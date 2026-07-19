# Faz 04.5 — AAA Boundary Architecture

## Net hüküm

Faz 04.4 sürümü doğrudan spagetti değildi; fakat dört yüksek merkezlilikli dosya nedeniyle **modülerleştirilmiş monolit** durumundaydı. `MatchController`, `ColonyController`, `WorldStreamManager` ve `ColonyHUD` kendi gerçek sorumluluklarına ek olarak giriş, ağ oturumu, zamanlama, sorgu, çarpışma koruması, olay dağıtımı ve responsive yerleşim ayrıntılarını taşıyordu.

Bu fazdan sonra proje **AAA-ready production modular monolith** seviyesindedir:

- Spagetti değildir.
- Bağımlılık yönleri belirgindir.
- Maç kapsamlı state global autoload'lara sızmaz.
- Ağ, giriş, koloni iş akışları, streaming read-model ve UI yerleşimi ayrı servislerdir.
- Somut HUD sınıfı gameplay çekirdeğinin derleme bağımlılığı değildir.
- Buna rağmen gerçek transport, prediction/reconciliation, replay, telemetry, cihaz profillemesi ve CI içi motor testleri tamamlanmadığı için “tam AAA altyapısı bitti” denmez.

## Uygulanan plan

### 1. Maç composition root'unu inceltme

`MatchController` artık raw input veya peer/rate-limit tabloları taşımaz.

Yeni sınırlar:

- `AuthoritativeCommandRouter`: peer sahipliği, sequence doğrulama akışı, rate limit, command dispatch, disconnect temizliği ve snapshot delegasyonu.
- `LocalCommandInputSource`: klavye/joystick polling, hareket cadence'i, modal/odak kaybında input reset.
- `MatchEventHub`: maç ömürlü event dağıtımı.
- `MatchPresentationAdapter`: gameplay tarafının bildiği soyut sunum portu.

`MatchController`, somut `ColonyHUD` veya `ColonyMinimap` sınıflarını artık tanımaz.

### 2. Global EventBus kaldırılması

Global maç EventBus'ı yeni maç, restart ve paralel test örnekleri arasında state/sinyal sızıntısı oluşturabilecek bir servis-locator davranışıydı. Autoload kaldırıldı. Her maç kendi `MatchEventHub` nesnesini oluşturur ve yok eder.

Sonuç:

- Yeni maç eski HUD bağlantılarını devralmaz.
- Headless server sunum sinyallerini global alana yaymaz.
- Paralel test sahneleri birbirinin olaylarını alamaz.
- Olay yaşam döngüsü maç yaşam döngüsüyle aynıdır.

### 3. Koloni aggregate sınırı

`ColonyController` artık merkezi sürü kovalarını ve aktif hasat komutu state'ini doğrudan taşımaz.

Yeni servisler:

- `SwarmSimulationScheduler`: üç kovalı 20 Hz bounded simulation cadence, dropped-time ve backlog metriği.
- `ColonyGatherService`: hedef generation doğrulaması, komut süresi, worker assignment, iptal ve state yayımı.

Koloni aggregate hâlâ inventory, progression, nest, commander, owned units ve authoritative colony command sonucunun sahibidir. Ayrılan servisler bu state'in sahibi değil, belirli use-case'lerin yürütücüsüdür.

### 4. Streaming orchestration sınırı

`WorldStreamManager` içindeki salt-okunur sorgular ve collision-activation güvenliği ayrıldı:

- `WorldStreamReadModel`: en yakın kaynak, aktif chunk sayısı, deterministik sıralı chunk DTO'ları ve minimap resource DTO'ları.
- `WorldCollisionActivationGuard`: ACTIVE collision açılmadan önce interest anchor ve fizik overlap güvenliği.

Collision guard doğrudan genel `Node` üzerinden dünya aramaz; gerçek bir `Node2D` physics context alır. Bu, dinamik metod çağrısına ve yanlış SceneTree bağlamına dayanan gizli runtime hatasını kaldırır.

### 5. HUD view ile layout policy ayrımı

`ColonyHUD` responsive koordinat hesaplarının sahibi değildir.

- `HudLayoutContext`: layout servisinin kullanacağı typed view referansları.
- `HudResponsiveLayout`: safe-area dönüşümü, ölçek, panel ve mobil kontrol yerleşimi.
- `HudEventBinder`: maç event hub bağlantılarının atomik bind/unbind yaşam döngüsü.

Yeni ekran oranı veya safe-area davranışı eklemek; üretim komutlarını, ses panelini veya oyun event callback'lerini değiştirmeyi gerektirmez.

### 6. Somut UI bağımlılık çevriminin kaldırılması

Önceki graph:

```text
MatchController → ColonyHUD → ColonyMinimap → MatchController
```

Yeni graph:

```text
MatchController → MatchPresentationAdapter
ColonyHUD → MatchPresentationAdapter
ColonyHUD / ColonyMinimap → MatchController read/command API
```

Gameplay katmanı artık UI implementasyonunu tanımaz. Composition scene, gerçek HUD'ı presentation portuna bağlar. Statik class graph taramasında strongly-connected component kalmamıştır.

## Güncel composition

```text
MatchController
├─ MatchRules
├─ FixedStepClock
├─ MatchEventHub
├─ MatchPresentationAdapter (client port)
├─ LocalCommandInputSource
├─ AuthoritativeCommandRouter
│  ├─ NetworkCommandValidator
│  ├─ AuthoritativeCommandJournal
│  └─ NetworkSnapshotBuilder
├─ NetworkEntityRegistry
├─ ColonyUnitPool
├─ ProjectileSystem
├─ RuntimeInvariantMonitor
├─ WorldStreamManager
│  ├─ WorldResidencyPlanner
│  ├─ WorldContentCatalog
│  ├─ WorldObjectPool
│  ├─ WorldChunkBuildJob
│  ├─ WorldStreamReadModel
│  └─ WorldCollisionActivationGuard
└─ ColonyController[]
   ├─ ColonyInventory
   ├─ ColonyProgression
   ├─ ColonySquadManager
   ├─ SwarmFormationManager
   ├─ SwarmSimulationScheduler
   ├─ ColonyGatherService
   └─ ColonyBotBrain

ColonyHUD
├─ HudEventBinder
├─ HudLayoutContext
├─ HudResponsiveLayout
└─ ColonyMinimap
```

## Bağımlılık kuralları

1. Domain/gameplay katmanı `res://ui/` implementasyonlarını preload etmez.
2. Maç state'i global autoload içinde tutulmaz.
3. UI authoritative state yazmaz; yalnız command intent gönderir.
4. Network router komut sonucuna karar vermez; doğrulanmış komutu ilgili colony aggregate'e iletir.
5. Snapshot builder gameplay state'in sahibi değildir.
6. Streaming read-model SceneTree mutation yapmaz.
7. Collision guard yalnız physics context ve salt okunur interest provider kullanır.
8. Pool nesne belleğine; registry entity kimliğine sahiptir. Bu sahiplikler birleşmez.
9. RefCounted servisler bağımsız `_process()` kullanmaz; composition root tarafından ilerletilir.
10. Yeni cross-system davranış global singleton yerine açık constructor/configure bağımlılığı veya maç scoped event hub kullanır.

## Ölçülebilir sonuç

Faz 04.4 → Faz 04.5:

- GDScript: 63 → 74
- Class dependency cycle: 1 → 0
- 900 satır üzeri script: 3 → 0
- `MatchController`: 863 → 776 satır
- `ColonyController`: 1000 → 863 satır
- `WorldStreamManager`: 985 → 888 satır
- `ColonyHUD`: 999 → 862 satır
- Global match EventBus: kaldırıldı
- Gameplay → concrete HUD dependency: kaldırıldı
- Raw input polling in MatchController: kaldırıldı
- Peer/rate-limit state in MatchController: kaldırıldı

Satır sayısı tek başına kalite metriği değildir. Buradaki düşüş, cohesive sorumlulukların bağımsız servis ve portlara taşınmasının yan sonucudur.

## Kalan gerçek AAA üretim fazları

### Faz 04.6 — AI command architecture

- Utility scorer
- Threat/perception memory
- Colony blackboard
- Squad intent ve tactical roles
- Influence grid
- Hierarchical path corridor / flow field
- Stuck telemetry ve route invalidation

### Faz 04.7 — Hybrid swarm presentation

- Yakın birimler: tam Node2D ve animasyon
- Orta mesafe: azaltılmış presentation proxy
- Uzak sürüler: MultiMesh/RenderingServer batch
- Görsel entity ↔ authoritative entity ayrımı
- Frame-budget governor ve device quality tiers

### Faz 04.8 — Production multiplayer

- ENet/relay transport adapter
- Session authentication ve reconnect
- Typed binary snapshot codec
- Delta compression ve bandwidth budget
- Client interpolation buffer
- Commander prediction/reconciliation
- Desync hash ve replay journal persistence

### Faz 04.9 — Operasyon ve kalite kapısı

- Resmî Godot 4.6.3 CI parser/headless suite
- Android export smoke test
- Uzun bot soak testleri
- Crash/ANR telemetry
- CPU/GPU/memory/thermal budget raporları
- Save/config schema migration
- Build/version correlation

## Kabul kriterleri

- Gameplay kaynaklarında `ColonyHUD` veya `ColonyMinimap` concrete dependency bulunmaz.
- `project.godot` içinde global match EventBus autoload bulunmaz.
- MatchController raw input polling veya peer session tablosu taşımaz.
- ColonyController swarm bucket veya aktif gather workflow state'i taşımaz.
- Class dependency graph strongly-connected component üretmez.
- Hiçbir GDScript 900 satırı aşmaz.
- Bütün literal `res://` yolları mevcut dosyaya çözümlenir.
- Bütün GDScript dosyaları `gdlint` kontrolünden geçer.
- Architecture boundary testi server composition root üzerinde yeni servisleri doğrular.

## Motor testi

```bash
godot --headless --path . \
  --script res://tests/architecture_boundaries_test.gd
```

Tam regresyon:

```bash
for test in tests/*_test.gd; do
  godot --headless --path . --script "res://$test" || exit 1
done
```
