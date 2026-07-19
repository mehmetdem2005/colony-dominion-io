# Teknik Mimari

## Faz 04.5 AAA boundary architecture

Proje artık raw input, network session, swarm scheduling, gather workflow, streaming read-model, collision activation ve responsive HUD policy işlerini büyük controller dosyalarında birleştirmez. Maç scoped `MatchEventHub`, authoritative command router, local input adapter, presentation port ve ayrı use-case servisleri üzerinden açık bağımlılıklarla çalışır.

```text
Client presentation
ColonyHUD -> MatchPresentationAdapter <- MatchController
ColonyHUD -> HudEventBinder / HudResponsiveLayout / ColonyMinimap

Application boundary
MatchController -> LocalCommandInputSource
MatchController -> AuthoritativeCommandRouter
AuthoritativeCommandRouter -> Validator / Journal / SnapshotBuilder

Domain aggregates
MatchController -> ColonyController[]
ColonyController -> Inventory / Progression / Squads / Formation
ColonyController -> SwarmSimulationScheduler / ColonyGatherService / ColonyBotBrain

Infrastructure
MatchController -> WorldStreamManager / Pools / Registry / RuntimeInvariantMonitor
WorldStreamManager -> Planner / Catalog / BuildJob / ObjectPool / ReadModel / CollisionGuard
```

Maç state'i global EventBus'ta tutulmaz. Somut UI sınıfları gameplay katmanından referans edilmez. Statik class dependency graph'ta çevrim yoktur. Bu sürüm tam AAA ürün altyapısının bittiği anlamına gelmez; fakat spagetti değil, sonraki network/AI/render/telemetry katmanlarını kontrollü taşıyabilecek production modular monolith temelidir. Ayrıntılar `PHASE_04_5_AAA_BOUNDARY_ARCHITECTURE.md` içindedir.

## Faz 04.4 production architecture foundation

Maç sahnesi bir **composition root** olarak kalır; fakat yüksek maliyetli veya ayrı yaşam döngüsü bulunan işler artık `MatchController` içinde uygulanmaz. Controller servisleri kurar, sahiplenir ve kapatır. Kurallar `MatchRules` kaynağından gelir; sabit adımlı zaman, unit havuzu, projectile simülasyonu, network snapshot üretimi, authoritative command journal ve runtime invariant denetimi ayrı servislerdir.

```text
MatchController (composition root / orchestration)
├─ MatchRules (data-driven Resource)
├─ FixedStepClock (bounded deterministic server time)
├─ NetworkEntityRegistry (stable identity ownership)
├─ NetworkCommandValidator (untrusted input boundary)
├─ AuthoritativeCommandJournal (bounded replay/debug history)
├─ NetworkSnapshotBuilder (relevance, cadence, keyframe, despawn)
├─ ColonyUnitPool (scoped lifetime + metrics)
├─ ProjectileSystem (visual/logical projectile simulation)
├─ RuntimeInvariantMonitor (debug observability)
└─ WorldStreamManager (stream orchestration)
   ├─ WorldResidencyPlanner (pure desired-state planning)
   ├─ WorldContentCatalog (deterministic content data)
   ├─ WorldObjectPool (prop/resource lifetime + texture cache)
   └─ WorldChunkBuildJob (frame-budgeted construction)

ColonyController (colony aggregate root)
├─ ColonyInventory
├─ ColonyProgression
├─ ColonySquadManager
├─ SwarmFormationManager
└─ ColonyBotBrain (AI decision seam)
```

Veri sahipliği tek yönlüdür: `MatchController` maç ve entity yaşam döngüsüne, `ColonyController` yalnız kendi koloni agregasına, `WorldStreamManager` chunk durumuna sahiptir. HUD ve ses sistemi authoritative gameplay state yazmaz. Ağ snapshot servisi gameplay state üretmez; yalnız server state'ini salt okunur biçimde paketler.

Sahne ağacı dışındaki planlama, katalog, günlük ve havuz mantığı `RefCounted` servislerle tutulur. SceneTree'e yalnız gerçekten işlem, çizim, fizik veya sinyal yaşam döngüsü gereken nesneler eklenir. Bu, binlerce mantıksal öğeyi gereksiz Node callback'lerine dönüştürmeyi engeller.

## Otorite sınırı

`MatchController` maç zamanı, entity registry, server tick, doğrulanmış komut kapısı, dünya streaming yöneticisi, hedef sorguları, skor ve galibiyet kararlarının tek otoritesidir. HUD yalnızca komut DTO'su üretir. `NetworkCommandValidator` sequence, peer sahipliği, komut türü, hareket aralığı ve üretim payload'ını doğruladıktan sonra `ColonyController.execute_authoritative_command()` çağrılır. `ColonyController` yalnızca kendi kolonisinin envanteri, üretim kuyruğu, komutanı ve minyonları üzerinde karar verir.

## Veri odaklı birimler

Her sınıf `data/units/*.tres` içindeki `UnitDefinition` kaynağıyla tanımlanır. Sağlık, hız, saldırı aralığı, üretim süresi, maliyet ve görsel doku koddan ayrıdır.

## Dünya streaming

`WorldStreamManager`, 36.000 × 24.000 dünyayı 1200 × 1200 mantıksal chunklara böler. Chunklar global seed ve koordinattan deterministik üretilir. İstemcide yalnız yerel komutan, dedicated server modunda ise bütün aktif koloniler aynı authoritative residency planına katılır. Böylece uzak network oyuncuları istemci chunk belleğini büyütmez, server da bot/oyuncu kolonilerinden hiçbirinin kaynak ve engel alanını boş bırakmaz. ACTIVE alanlar her zaman korunur; predicted WARM adayları yakınlık önceliğiyle dinamik resident limitine budanır. `WorldChunkBuildJob` içeriği 1400 µs kare bütçesi altında parça parça kurar; tek karede tam chunk üretimi yapılmaz. `WorldChunkRuntime` yüklü içeriği ACTIVE veya WARM residency durumunda tutar. WARM chunk bellekte hazır kalırken çizim, çarpışma ve fizik işlemi üretmez.

Görsel prop ve kaynak nesneleri sınırlı `StreamedWorldProp` ve `WorldResourceNode` havuzlarından alınır. Kaynak miktarı ve yeniden doğma süresi chunk durumunda saklanır. Kaynak araması, sorgu alanının kestiği chunklarla sınırlandırılır.

Zemin tek `Polygon2D` üzerinden, tekrarlanabilir ve kenarları birebir eşleştirilmiş bir doku ile çizilir. Bu nedenle dev bir bitmap belleğe alınmaz ve chunk sınırlarında dikiş oluşmaz.

## Mobil performans

- Mobile renderer
- Her interest anchor çevresinde 3 × 3 ACTIVE chunk
- Tek istemcide 18, altı server anchor'ında dinamik olarak 78 ve mutlak 84 sınırı olan ACTIVE/WARM residency
- Yöne bağlı önden yükleme ve 1400 µs kare başına streaming bütçesi
- Sınırlı dekor ve kaynak düğümü havuzları
- Uzak yapay zekâ için FULL / REDUCED / DORMANT simülasyon katmanları; DORMANT koloniler resident chunk veya birim fiziğine bağlı olmayan 2 Hz grup makro navigasyonu kullanır
- Yalnız dünya engellerine karşı minyon fiziği; birim-birim physics pair bulunmaz
- Takım kovalarına ayrılmış freed-object güvenli spatial hash
- FPS'ten bağımsız sabit adımlı, üç kovalı merkezi 20 Hz minyon simülasyonu ve kare başına altı adımlık catch-up sınırı
- Minyon gövde simülasyonundan ayrı `VisualRoot` konum/dönüş yumuşatması; bağımsız minyon callback'i yoktur
- Yarı saydam birim dolgu katmanı yoktur; üst üste binmede alpha birikimi oluşturmayan opak takım halkaları kullanılır
- 60 Hz komutan fiziği ve global Godot physics interpolation
- 16 dünya birimlik histerezisli explicit Z kovaları ve stable entity alt katmanları; global unit Y-sort yoktur
- Üst sınırlı unit/projectile havuzları ve 120 görsel mermi sınırı
- Boş unit/projectile/prop/resource havuzlarının SceneTree dışında tutulması
- 5 Hz toplu hasat envanter işlemleri
- Chunk yöneticisinde merkezi 4 Hz resource respawn/focus simülasyonu
- Hedef ve ayrışma taramaları her fizik karesinde değil, 0.12–0.48 saniye aralıklarla
- Basit dairesel dünya engeli çarpışmaları
- Veri odaklı koloni başı birlik kapasitesi

## Ağ temeli

Hazır olan parçalar:

1. Maç boyunca yeniden kullanılmayan stable `network_entity_id` ve freed/pool-reuse güvenli registry.
2. 20 Hz server tick, peer→team sahipliği ve saniyelik komut oran sınırı.
3. Yakın minyonlarda 10 Hz, uzak ilgili minyonlarda 4 Hz, komutanda 20 Hz delta snapshot cadence.
4. İki saniyelik keyframe, relevance dışına çıkan entity despawn listesi ve 1 Hz koloni özeti.
5. İstemcide yalnız yerel, dedicated server'da bütün aktif kolonileri kapsayan chunk interest ayrımı.
6. `dedicated_server`/`--server` algısı, görselsiz dünya kurulum yolu ve Linux dedicated export preset'i.
7. Entity retirement ve peer disconnect sırasında temizlenen snapshot cadence/relevance cache'i.
8. Saldırgan node'u mermi uçuşunda ölse de korunan takım tabanlı kill attribution.

Sonraki gerçek multiplayer fazında ENet taşıma, lobby/matchmaking, istemci snapshot buffer/interpolation ve komutan prediction/reconciliation bu sınırların üzerine eklenir; gameplay state istemciden doğrudan değiştirilemez.
