# Faz 04.4 — Production Architecture Foundation

## Sonuç

Faz 04.3.5 sonrasında kod kırılgan bir prototip değildir; authoritative komut sınırı, streaming, pooling, fixed-step sürü simülasyonu ve yaşam döngüsü korumaları vardır. Buna rağmen önceki yapı gerçek AAA üretim çekirdeği olarak tamamlanmış değildi. Üç büyük orkestratör, veri sahipliği ile uygulama ayrıntılarını aynı dosyalarda tutuyor; tuning değerlerinin bir bölümü kod içine gömülü kalıyor; ağ snapshot'ı maç yaşam döngüsüyle karışıyor ve çalışma zamanı sorunları ancak kullanıcı videosundan sonra görülebiliyordu.

Bu faz davranışı yeniden yazmak yerine güvenli **seam**'ler oluşturur. Yeni servisler mevcut oyunu çalıştırır ve sonraki AI, multiplayer, replay, rendering ve cihaz ölçekleme fazlarının birbirine zarar vermeden eklenmesini sağlar.

## Uygulanan mimari

### 1. Composition root

`MatchController` artık algoritma deposu değil, maç composition root'u ve orkestratörüdür. Aşağıdaki scoped servisleri kurar ve sahne kapanırken kapatır:

- `MatchRules`
- `FixedStepClock`
- `ColonyUnitPool`
- `ProjectileSystem`
- `AuthoritativeCommandJournal`
- `NetworkSnapshotBuilder`
- `NetworkEntityRegistry`
- `RuntimeInvariantMonitor`
- `WorldStreamManager`

Global autoload sayısı artırılmadı. Maça ait servisler maç ömründen uzun yaşamaz ve başka maça state sızdıramaz.

### 2. Veri odaklı maç kuralları

`data/match/default_match_rules.tres`, maç süresi, koloni kapasitesi, server/projectile tick oranları, catch-up sınırları, sorgu aralıkları, havuz bütçeleri ve komut oran sınırını taşır. Resource yüklenince kopyalanır ve `sanitize()` edilir. Runtime kodu editörde yanlış girilmiş veya bozuk değerle başlamaz.

### 3. Sınırlandırılmış deterministik zaman

`FixedStepClock`:

- FPS'ten bağımsız tick üretir.
- Uzun karelerde sınırsız catch-up yapmaz.
- Kabul edilmeyen frame zamanı ve atılan backlog'u ölçer.
- Tick sayısını authoritative komut günlüğü ve snapshot cadence için tek kaynaktan verir.
- Render interpolation için 0–1 arası alpha sağlar.

Bu yapı tam lockstep iddiasında değildir. Ama server simulation cadence'i tek ve gözlemlenebilir hale getirir.

### 4. Projectile domain ayrımı

`ProjectileSystem`, görsel ve node oluşturmayan mantıksal asit mermilerini aynı servis içinde yönetir. Görsel bütçe dolduğunda hasar davranışı kaybolmaz; logical projectile yoluna geçer. Pool yaşam döngüsü, sabit zaman adımı, düşürülen projectile sayısı ve zaman borcu ayrı ölçülür.

### 5. Scoped unit pool

`ColonyUnitPool` yalnız maçın unit root'una bağlıdır. Oluşturulan, yeniden kullanılan ve havuz sınırı nedeniyle atılan nesne sayıları ölçülür. Pool state'i autoload'a taşınmadığı için restart ve yeni maçlarda kirli nesne sızıntısı oluşmaz.

### 6. AI seam

`ColonyBotBrain`, bot hedef seçimi, aktif karar cadence'i, DORMANT makro navigasyon ve makro ekonomiyi `ColonyController` yaşam döngüsünden ayırır. Envanter, üretim kuyruğu ve birlik sahipliği yine colony aggregate içinde kalır. Sonraki taktik AI fazında utility scoring, threat memory, influence map ve squad intent bu servis üzerinden eklenebilir.

### 7. Streaming domain ayrımı

`WorldStreamManager` yalnız orchestration ve planı uygulama sorumluluğunda kalır:

- `WorldResidencyPlanner`: interest anchor'lardan ACTIVE/WARM desired-state ve resident budget üretir.
- `WorldContentCatalog`: biyom prop/resource tablolarını taşır.
- `WorldObjectPool`: prop/resource havuzlarını ve texture cache'i yönetir.
- `WorldChunkBuildJob`: chunk kurulumunu kare bütçesine böler.

Planner sahne ağacını değiştirmez. Bu sayede streaming kararları ayrı test edilebilir ve ileride worker thread üzerinde yalnız veri planlama yapılabilir. SceneTree mutation ana thread'de kalır.

### 8. Network snapshot servisi

`NetworkSnapshotBuilder` şu işleri maç controller'ından devralır:

- izleyici relevance alanı,
- yakın/uzak entity cadence'i,
- commander önceliği,
- periyodik keyframe,
- relevance dışına çıkan entity despawn listesi,
- koloni özetleri,
- peer/team snapshot cache temizliği,
- entity retirement temizliği.

Taşıma katmanı henüz eklenmemiştir. Fakat ENet, snapshot buffer ve prediction/reconciliation eklenirken snapshot algoritması maç, UI veya savaş koduna dokunmadan değiştirilebilir.

### 9. Authoritative command journal

Başarılı ve başarısız doğrulanmış komutlar sınırlı ring buffer'da server tick, peer, team, command type ve payload ile tutulur. Bu temel:

- deterministik hata yeniden üretimi,
- replay metadata,
- desync analizi,
- hile/abuse incelemesi,
- automated soak test raporu

için kullanılabilir. Journal kapasitesi sınırlıdır; sonsuz bellek büyümesi oluşturmaz.

### 10. Runtime invariant monitor

Debug build veya `--runtime-audit` ile:

- duplicate team ID,
- duplicate network entity ID,
- aynı unit'in birden fazla koloni slotunda bulunması,
- stale/freed unit referansı,
- unit/team sahiplik uyuşmazlığı,
- commander ownership hatası,
- sonlu olmayan dünya konumu,
- resident chunk bütçe aşımı,
- server/projectile zaman borcu

periyodik denetlenir. Aynı hata log'u sürekli basmaz; raporlama throttle edilir ve sayaçlar dışarı okunabilir.

## Veri sahipliği kuralları

1. `MatchController`: maç zamanı, controller listesi, entity registry ve servis yaşam döngüsü.
2. `ColonyController`: tek koloninin inventory, progression, nest, commander, units ve command execution state'i.
3. `WorldStreamManager`: chunk state, residency uygulaması ve world query.
4. `NetworkSnapshotBuilder`: yalnız transient snapshot cache; gameplay state'in sahibi değildir.
5. HUD: yalnız input intent ve sunum.
6. AudioSystem: yalnız sunum; gameplay sonucuna karar vermez.
7. Pool servisleri: nesne belleği ve reuse; entity kimliğinin sahibi değildir.

## Mobil performans yaklaşımı

- Node callback sayısı yerine merkezi cadence servisleri.
- SceneTree dışında `RefCounted` planlama ve veri nesneleri.
- Üst sınırlı unit/projectile/prop/resource pool.
- Görsel projectile bütçesi ile logical projectile doğruluğunun ayrılması.
- Chunk planlama ve chunk uygulamasının ayrılması.
- FULL / REDUCED / DORMANT AI simülasyon katmanları.
- Runtime ölçümlerinde dropped time, pool reuse, logical/visual projectile ve snapshot cache sayıları.

## Gerçek AAA seviyesine kalan sistemler

Bu paket bir AAA oyunun bütün altyapısının tamamlandığı iddiasında değildir. Aşağıdaki katmanlar sonraki üretim fazlarıdır:

1. Gerçek ENet/relay transport, lobby, reconnect, timeout ve session migration.
2. Typed binary snapshot codec, bandwidth budget, delta compression, client interpolation buffer ve commander prediction/reconciliation.
3. Kayıtlı replay formatı, deterministic seed manifesti ve headless soak-test runner.
4. Utility AI + hierarchical state tree, threat memory, influence map, squad blackboard ve flow-field/path corridor navigasyon.
5. Çok büyük sürüler için hybrid presentation: yakın birimler Node2D, uzak birlikler MultiMesh/RenderingServer tabanlı impostor veya batch renderer.
6. Frame-budget governor ve cihaz profilleri: Redmi Note 8 Pro gibi hedef cihazlarda CPU/GPU/memory thermal tier düşürme.
7. Crash reporting, telemetry schema, performance marker'ları ve build/version correlation.
8. CI içinde gerçek Godot 4.6.3 parser, bütün headless testler, Android export smoke test ve uzun süreli bot maçı.
9. Save migration, config schema versioning, localization pipeline ve accessibility testleri.
10. Büyük controller'larda sonraki cohesive extraction: HUD presenter/input router, colony production service ve match peer-command gateway.

## Kabul kriterleri

- Hiçbir GDScript 1000 satırı aşmaz.
- Match snapshot cache'i `MatchController` içinde tutulmaz.
- Match tuning resource üzerinden gelir ve sanitize edilir.
- Server ve projectile cadence bounded fixed-step kullanır.
- Unit/projectile pool state'i maç ömrüyle sınırlıdır.
- World desired-state planı SceneTree mutation yapmayan ayrı servisten gelir.
- Bot karar katmanı colony aggregate yaşam döngüsünden ayrıdır.
- Runtime invariant sayıları dışarı okunabilir.
- Command journal en eski→en yeni sıralı ve üst sınırlıdır.
- Mevcut `res://` referanslarında eksik dosya bulunmaz.
- Bütün GDScript dosyaları `gdlint` kontrolünden geçer.

## Motor testi

```bash
godot --headless --path . \
  --script res://tests/production_architecture_foundation_test.gd
```

Tam regresyon:

```bash
for test in tests/*_test.gd; do
  godot --headless --path . --script "res://$test" || exit 1
done
```
