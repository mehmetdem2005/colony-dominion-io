# Colony Dominion.io

Godot 4.6.3 için hazırlanmış, Android yatay ekrana odaklı, 90 derece yukarıdan bakışlı 2D karınca kolonisi io-strateji oyunu.

## Bu pakette çalışan oyun döngüsü

- Oyuncu altın taçlı karınca komutanını sanal joystick ile yönetir.
- İşçi, asker, muhafız, izci ve asit karıncası üretilebilir.
- İşçiler tohum, nektar, protein, yaprak ve taş kaynaklarını otomatik toplar.
- Üretim yuva kuyruğu üzerinden süreli gerçekleşir; kaynaklar anında birime dönüşmez.
- Birlikler rollerine göre dinamik formasyon kurar ve birbirlerinden ayrışma kuvvetiyle üst üste binmez.
- SALDIR emri en yakın düşmana hücum ettirir; TOPLA emri orduyu tekrar komutanın çevresine çeker.
- BÖLÜN komutu minyonları iki ayrı savaş koluna ayırır; BİRLEŞ komutu tekrar tek formasyona toplar.
- Yuva seviyeleri ordu kapasitesini, işçi toplama verimini ve üretim hızını artırır.
- Her koloninin birlik çemberi kendi rengindedir ve komutanların üstünde oyuncu adı görünür.
- Beş yapay zekâ kolonisi kaynak toplar, ordu üretir, rakipleri ve yuvaları hedefler.
- Sıralama sabit değildir; birlik, kaynak, yuva sağlığı ve öldürme skoruna göre canlı güncellenir.
- Komutan ölürse yuva ayaktaysa 5 saniye sonra doğar. Yuva yokken komutanın ölmesi koloniyi eler.
- Maç 20 dakika sürer; son kalan koloni veya süre sonunda en yüksek skorlu koloni kazanır.

## Çalıştırma

> **Önemli:** Önceki sürümün üzerine çıkarmayın. Eski proje klasörünü ve `.godot` önbelleğini silip bu paketi yeni klasöre çıkarın.


1. ZIP dosyasını çıkarın.
2. Godot 4.6.3 Android editöründe `project.godot` dosyasını içe aktarın.
3. Projeyi çalıştırın.
4. APK almak için Godot export template'lerini kurup hazır `Android` export preset'ini kullanın.

Yerel Android Google girişi için üretim imzası ve OAuth eşleştirme adımları:
[`docs/ANDROID_NATIVE_GOOGLE_SIGN_IN.md`](docs/ANDROID_NATIVE_GOOGLE_SIGN_IN.md).

Android kimlik eklentisi ve bağımlılıkları Gradle tarafından otomatik paketlenir;
Godot editörüne ayrıca eklenti kurmak gerekmez.

## Mobil kontroller

- Sol sanal joystick: komutan hareketi
- SALDIR: en yakın geçerli düşmana toplu saldırı emri
- TOPLAN: saldırıyı kesip formasyona dönme
- BÖLÜN: orduyu iki savaş koluna ayırma
- BİRLEŞ: savaş kollarını tek formasyonda toplama
- YÜKSELT: yuva seviyesi ve ordu kapasitesi geliştirme
- Alt görsel üretim kartları: birim resmi ve kaynak ikonları üzerinden minyon üretme
- İki parmak: kamera yakınlaştırma/uzaklaştırma

Masaüstü testinde WASD/ok tuşları, Space, R, Q ve E kullanılabilir.

## Ana sahne ağacı

```text
GameRoot (Node2D) [MatchController]
├── World (Node2D)
│   ├── Ground (Node2D)
│   ├── Decorations (Node2D, Y-sort)
│   ├── Resources (Node2D, Y-sort)
│   ├── Structures (Node2D, Y-sort)
│   ├── Units (Node2D, explicit quantized Z order)
│   └── Projectiles (Node2D, centralized simulation)
├── PlayerCamera (Camera2D) [PlayerCameraController]
└── HUD (CanvasLayer) [ColonyHUD]
```

## Üretim mimarisi

- `autoload/`: olay hattı, oturum ve veri kataloğu
- `data/units/`: koddan ayrılmış birim tanımları ve denge değerleri
- `gameplay/colony/`: koloni otoritesi, envanter, yuva ve üretim kuyruğu
- `gameplay/units/`: hareket, formasyon, toplama, savaş ve düşük frekanslı simülasyon için görsel interpolasyon
- `gameplay/world/`: 100× alan, deterministik chunk streaming, düğüm havuzları ve kaynak durum kalıcılığı
- `gameplay/match/`: maç yaşam döngüsü, skor ve zafer koşulları
- `gameplay/network/`: stable entity kimliği ve sunucu komut doğrulaması
- `ui/`: çoklu dokunmaya uygun joystick ve komut arayüzü

Mevcut teslim tam oynanabilir çevrimdışı bot maçıdır. Komutlar artık doğrudan HUD'dan oyun durumuna yazılmaz; sequence, sahiplik, oran ve payload doğrulamasından geçen otorite kapısına gider. Stable entity ID, 20 Hz server tick, çoklu interest alanı ve kademeli delta snapshot üretimi hazırdır. İnternet bağlantı/lobi/hesap servisi bu pakette etkin değildir.

## Phase 01 controls

- Joystick: move commander
- SALDIR: focus the nearest enemy
- KAYNAK: send workers to available resource nodes
- TOPLAN: recall units and stop worker gathering
- BÖL: split the army into two balanced wings
- DAĞIT / SIKILAŞ: toggle loose or compact formation spacing
- BİRLEŞ: merge split wings


## Faz 02: 100× açık dünya

- Dünya ölçüsü 36.000 × 24.000 birime çıkarıldı.
- 600 mantıksal chunk bulunur; yalnızca oyuncu çevresindeki chunklar oluşturulur.
- Kesintisiz tek UV zemini sayesinde chunk birleşim çizgileri yoktur.
- Prop ve kaynaklar object pool üzerinden yeniden kullanılır.
- Uzak bot kolonileri üç kademeli simülasyon ile mobil işlemci yükünü azaltır.
- Ayrıntılı teknik kapsam `PHASE_02_WORLD_STREAMING.md` dosyasındadır.


## Phase 03: minimap and performance

- Lightweight 5 Hz minimap without a second viewport.
- Spatial-hash target and separation queries.
- Cached formation slots instead of per-frame colony scans.
- Category-based collision layers; minion separation is handled by the spatial grid without unit-to-unit physics pairs.
- Pooled acid projectiles and reduced UI/event churn.
- Mobile streaming budget reduced for large-army battles.

See `PHASE_03_MINIMAP_PERFORMANCE.md` for the root-cause analysis.

## Faz 4: Komutan merkezli sürü

İşçiler artık haritada bağımsız otomatik görev yapmaz. Oyuncu kaynağın yanına gider, `HASAT` komutunu kullanır ve kraliçenin yakınında kalarak toplama sürecini yönetir. Bütün birlikler Lordz.io benzeri biçimde komutanın çevresindeki taktik formasyon slotlarını takip eder. Ayrıntılar `PHASE_04_COMMANDER_SWARM_ACTIVE_HARVEST.md` dosyasındadır.

## Faz 04.1: savaş kararlılığı ve streaming yükseltmesi

- Ölen hedeflerin spatial hash içinde kısa süre kalmasından doğan `Trying to cast a freed object` çöküşü, doğrudan referansları güvenli instance-id kayıtlarına çevirerek kökten giderildi.
- Mermi hedefi ve saldırganı da aynı yaşam döngüsü güvenliğiyle izlenir.
- Chunklar tek karede kurulmak yerine zaman bütçeli build job üzerinden parça parça hazırlanır.
- ACTIVE/WARM residency, yön tahminli önden yükleme, resident sınırı ve havuz üst sınırları eklendi.
- WARM dünya içeriği görünmez olmanın yanında fizik, collision ve resource processing yükü de oluşturmaz.
- Kaynak sorguları yalnızca ilgili chunkları tarar.

Ayrıntılı teknik kapsam ve kabul ölçütleri `PHASE_04_1_STABILITY_ADVANCED_STREAMING.md` dosyasındadır.

## Faz 04.2: kalabalık sürü ve network-ready temel

- Minyonlar 60 Hz bağımsız fizik callback'lerinden çıkarıldı; üç kovaya bölünmüş merkezi 20 Hz sürü simülasyonu kullanır.
- Karınca-karınca fizik çarpışması kaldırıldı; dost ayrışması takım kovaları kullanan spatial grid üzerinden devam eder.
- Birimler ve asit mermileri üst sınırlı havuzlardan tekrar kullanılır.
- En fazla 120 görsel mermi çizilir; fazlası aynı uçuş ve hasar davranışıyla node oluşturmadan simüle edilir.
- Hasat envanter olayları 5 Hz toplu işleme çevrildi.
- Chunk streaming birden fazla insan oyuncunun ACTIVE/WARM alanlarının birleşimini yönetir.
- Menü arka planı 1280 × 720 sürüme taşındı; bu fazdaki kalıcı gameplay-asset küçültmesi Faz 04.3'te kalite regresyonu nedeniyle geri alındı.
- Stable network entity ID, server tick, doğrulanmış komut DTO'ları, rate limit ve ilgi alanı kademeli snapshot üretimi eklendi.

Ayrıntılar `PHASE_04_2_CROWD_NETWORK_READY.md` dosyasındadır.

## Faz 04.3: görsel kalite ve titremesiz sürü

- Faz 04.2'de küçültülen karınca, kaynak, prop ve yuva çizimleri orijinal çözünürlüklerine birebir döndürüldü.
- Nearest örnekleme yerine non-pixel-art için smooth filtre kullanılır; takım halkaları ve sprite aynı `VisualRoot` altında yumuşatılır.
- Üç kovalı minyon zamanlayıcısı ekran FPS'inden bağımsız sabit 20 Hz ve sınırlandırılmış catch-up kullanır.
- Godot fizik interpolasyonu açıldı; spawn/pool/chunk teleportlarında interpolation state sıfırlanır.
- Birim Z sırası 16 dünya birimlik histerezisli kovalar ve stable entity alt katmanlarıyla kararlı hale getirildi.
- Boş node havuzları SceneTree'den ayrılır; yeniden kullanımda bağlanır, sahne kapanırken güvenli biçimde serbest bırakılır.
- İstemci yalnız yerel chunk interest alanını, dedicated server ise bütün aktif kolonilerin authoritative birleşimini kullanır.
- Predicted WARM chunk'lar ACTIVE alanları koruyan dinamik resident limitine göre önceliklendirilir; çok oyunculu sunucuda plansız chunk büyümesi engellenir.
- Snapshot cache yaşam döngüsü, remote-human hareketi, mermi kill attribution ve Android internet izni sertleştirildi.

Ayrıntılı kök neden, trade-off ve cihaz kabul planı `PHASE_04_3_VISUAL_SMOOTHING_PRODUCTION_HARDENING.md` dosyasındadır.

## Faz 04.3.1: çalışma zamanı ve uzak koloni düzeltmeleri

- Geçersiz Viewport canvas filtre değeri kaldırıldı; proje varsayılanı Godot 4.6.3 için geçerli smooth mipmap filtresine çekildi.
- `PlayerCamera` fizik işlem callback'ine sahne yüklenmeden önce sabitlendi; interpolation override uyarısı kaldırıldı.
- Üst üste gelen karıncalardaki yarı saydam dolgu birikimi kaldırıldı; opak halkalar, stable entity alt katmanı ve Z-histerezisi kullanılır.
- DORMANT bot kolonileri artık resident chunk gerektirmeyen 2 Hz makro navigasyonla grup halinde ilerler; formasyon dünya sınırında korunur.
- Yakın tehdidi bulunan zayıf botun ilgisiz kaynak hedefine yürüyerek savaştan kaçıyor görünmesi durduruldu. Gelişmiş taktik karar sistemi bu fazın kapsamı dışındadır.

Ayrıntılar `PHASE_04_3_1_RUNTIME_STREAMING_FIXES.md` dosyasındadır.

Yaşam döngüsü regresyon testi:

```bash
godot --headless --path . --script res://tests/spatial_index_lifecycle_test.gd
godot --headless --path . --script res://tests/network_entity_registry_test.gd
godot --headless --path . --script res://tests/network_command_validator_test.gd
godot --headless --path . --script res://tests/swarm_scheduler_cadence_test.gd
godot --headless --path . --script res://tests/visual_quality_regression_test.gd
godot --headless --path . --script res://tests/runtime_streaming_regression_test.gd
godot --headless --path . --script res://tests/swarm_crowd_stress_test.gd
```

## Faz 04.3.2 güncellemesi

NPC kolonileri kaynak yokken yuva üzerinde beklemek yerine süreli devriye hedefleri kullanır. DORMANT koloniler 4 Hz makro hareket eder. Aktif birimlere üç ışınlı yerel taş/engel kaçınma, sıkışma kurtarma ve çarpışma sonrası teğetsel kayma eklenmiştir. Kaynak paneli ve minimap sol üstte tek kompakt küme halinde; üretim kartları daha büyük maliyet ikonlarıyla mobil dokunma boyutuna geçirilmiştir.

## Faz 04.3.3: production ses ve dinamik müzik

Merkezi `AudioSystem` autoload'u, sekiz bus'lı miks topolojisi, limiter, 22 kanallı dünya SFX havuzu, 6 kanallı UI havuzu ve oyuncu komutanını izleyen `AudioListener2D` eklendi. Toplam 27 veri odaklı ses olayı; saldırı, hasar, ölüm, kaynak toplama, üretim, yuva, komut ve maç sonucu akışlarına bağlandı. Aynı zaman tabanındaki müzik stem'leri sakin koloni, büyüme, tehdit, küçük/büyük savaş ve kraliçe tehlikesi arasında kesintisiz geçiş yapar. Biyom ambiyansı ve yoğunluğa göre sürü katmanı bulunur. HUD'daki `SES` paneli kategori seviyelerini, titreşimi ve arka plan susturmayı kalıcı olarak yönetir.

Teknik mimari `PHASE_04_3_3_PRODUCTION_AUDIO_SYSTEM.md`, doğrulama sonucu `PHASE_04_3_3_AUDIO_VALIDATION.json` dosyasındadır.

```bash
godot --headless --path . --script res://tests/audio_system_regression_test.gd
```

## Faz 04.3.4: kamera, UI ve sürü görünürlüğü sertleştirmesi

Videolarda görülen iki ayrı kök neden giderildi. Kamera artık hareket yönünde komutanı ekranın uygun tarafında tutarak arkadan gelen sürüye alan bırakır ve alt üretim panelinin karıncaları örtmesine izin vermez. Normal karıncaların iki tam anti-aliased çemberi, yoğun örtüşmede alfa birikimi oluşturmayan dört opak segmente dönüştürüldü. Minimap pulse/alpha geçişleri sabitlendi, keşfedilmiş chunklar bellekte tutuldu ve kamera dikdörtgeni gerçek render merkezini kullanır. HUD Android/iOS safe area ve farklı landscape oranlarına göre yeniden yerleşir. Modal paneller joystick ve komut girişlerini atomik olarak kilitler.

Teknik rapor: `PHASE_04_3_4_UI_CAMERA_VISIBILITY_HARDENING.md`

```bash
godot --headless --path . --script res://tests/ui_camera_visibility_regression_test.gd
```

## Faz 04.3.5: derin çalışma zamanı sertleştirmesi

Ses, ağ otoritesi, nesne havuzları, üretim kuyruğu, chunk streaming, kamera hedef yaşam döngüsü ve mobil dokunma koordinatları birlikte denetlendi. Geçersiz/sonlu olmayan sayılar artık hareket, hasar, mermi, snapshot, kaynak ve ses akışlarına giremiyor. Chunk içeriği tamamen hazırlanıp residency atomik uygulanana kadar görünmez ve çarpışmasız kalır. Üretim kapasite yarışında kaynak kaybetmez; komutan havuzdan yeniden doğduğunda kamera güvenli biçimde yeni komutana döner. Ağ entity ID çakışmaları canlı nesneleri ezemez ve kayıtlı olmayan peer'ler oran sınırlama belleğini büyütemez.

Teknik rapor: `PHASE_04_3_5_DEEP_RUNTIME_HARDENING.md`

```bash
godot --headless --path . --script res://tests/deep_runtime_hardening_regression_test.gd
```

## Faz 04.4: production architecture foundation

Maç composition root'u veri odaklı `MatchRules`, bounded `FixedStepClock`, scoped unit/projectile servisleri, authoritative command journal, bağımsız network snapshot builder ve runtime invariant monitor ile ayrıştırıldı. Koloni AI kararları `ColonyBotBrain` servisinde; dünya katalog, residency planlama ve object pool sorumlulukları ayrı world servislerindedir. Böylece sonraki multiplayer, replay, utility AI ve hybrid swarm rendering fazları mevcut savaş/üretim koduna çapraz bağımlılık eklemeden geliştirilebilir.

Teknik rapor: `PHASE_04_4_PRODUCTION_ARCHITECTURE_FOUNDATION.md`

```bash
godot --headless --path . --script res://tests/production_architecture_foundation_test.gd
```

## Faz 04.5: AAA boundary architecture

Faz 04.4 yapısı doğrudan spagetti değildi, fakat dört yüksek merkezlilikli controller nedeniyle modülerleştirilmiş monolit durumundaydı. Ağ komut kapısı, local input, maç event yaşam döngüsü, sürü scheduler'ı, hasat workflow'u, streaming read-model/collision guard ve responsive HUD policy ayrı servislere taşındı. Global match EventBus kaldırıldı. Gameplay çekirdeği artık somut `ColonyHUD` veya `ColonyMinimap` sınıflarını tanımıyor; `MatchPresentationAdapter` portuna bağlıdır.

Statik class dependency çevrimi 1'den 0'a, 900 satır üzeri script sayısı 3'ten 0'a indirildi. Bu sürüm spagetti değildir ve AAA-ready production modular monolith temelidir; gerçek ENet transport, prediction/reconciliation, replay, telemetry, cihaz profillemesi ve motor çalışan CI tamamlanmadan “tam AAA altyapısı bitti” denmez.

Teknik rapor: `PHASE_04_5_AAA_BOUNDARY_ARCHITECTURE.md`

```bash
godot --headless --path . --script res://tests/architecture_boundaries_test.gd
```
