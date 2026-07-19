# Faz 04.3.3 — Production Audio System

## Amaç

Bu faz, oyuna dağınık `AudioStreamPlayer` düğümleri eklemek yerine mobil cihaz, yoğun sürü savaşı ve gelecekteki çok oyunculu sunucu mimarisiyle uyumlu merkezi bir ses altyapısı kurar. Oynanış kodu ses dosyalarını doğrudan yönetmez; yalnızca anlamlı ses olayları üretir.

## Çalışma zamanı düğüm ağacı

```text
/root
└── AudioSystem (Autoload, Node)
    ├── SFXPool2D (22 × AudioStreamPlayer2D)
    ├── UISFXPool (6 × AudioStreamPlayer)
    ├── WorldAudioListener2D (AudioListener2D)
    ├── MusicDirector
    │   ├── Music_base
    │   ├── Music_growth
    │   ├── Music_tension
    │   ├── Music_combat
    │   ├── Music_critical
    │   └── Music_Menu
    ├── AmbientDirector
    │   ├── Ambient_meadow
    │   ├── Ambient_forest
    │   ├── Ambient_rocky
    │   ├── Ambient_dry
    │   └── Ambient_Swarm
    └── AudioSnapshotController
```

`WorldAudioListener2D`, 4 Hz oynanış bağlamı güncellemesinde oyuncu komutanının dünya konumuna taşınır. Böylece 2D efektlerin pan, mesafe zayıflaması ve duyulabilirlik merkezi gerçek oyuncu konumuyla aynıdır.

## Audio bus topolojisi

```text
Master [Limiter]
├── Music
├── Ambient
├── SFX
│   ├── Units
│   ├── Combat
│   ├── Environment
│   └── Colony
└── UI
```

Bus'lar çalışma zamanında idempotent biçimde oluşturulur. `Master` üzerinde limiter bulunur. Müzik ve çevre bus'larına yüksek öncelikli savaş/sonuç olaylarında snapshot ducking uygulanır. Alt bus'lar `SFX` seviyesini miras alır; UI sesi efekt seviyesinden bağımsızdır.

## Veri odaklı ses olayları

Her olay `AudioEventDefinition` kaynağıdır ve aşağıdaki verileri koddan ayırır:

- varyasyon dosyaları,
- bus,
- positional/non-positional çalışma,
- ses ve pitch aralığı,
- global ve emitter bazlı cooldown,
- maksimum eşzamanlı instance,
- duyulma mesafesi,
- öncelik,
- müzik/ambiyans ducking miktarı ve süresi.

Toplam 27 olay tanımlıdır. Karınca, yuva, mermi ve HUD scriptleri yalnızca olay kimliği gönderir. Yeni bir varyasyon eklemek için oyun mantığını değiştirmek gerekmez.

## Havuzlama ve ses bütçesi

- Dünya efektleri: 22 kanallı sabit `AudioStreamPlayer2D` havuzu.
- UI efektleri: 6 kanallı sabit `AudioStreamPlayer` havuzu.
- Havuz dolduğunda yalnızca daha yüksek öncelikli olay düşük öncelikli kanalı devralabilir.
- Kamera/oyuncu duyma yarıçapı dışındaki positional olaylar stream başlatılmadan reddedilir.
- Aynı olayın ve aynı emitter'ın hızlı tekrarları birleştirilir.
- Aynı anda yüzlerce karınca saldırsa bile her saldırı için yeni node oluşturulmaz.
- Dedicated server ve headless çalışmada bütün ses sistemi devre dışıdır.

## Dinamik müzik direktörü

Aynı uzunlukta ve aynı zaman tabanında beş senkron stem kullanılır:

```text
colony_base.ogg
colony_growth.ogg
colony_tension.ogg
colony_combat.ogg
colony_critical.ogg
```

Durumlar:

```text
MENU
COLONY_CALM
RESOURCE_EXPANSION
THREAT
COMBAT_SMALL
COMBAT_LARGE
QUEEN_DANGER
RESULT
```

Müzik durumu yakın düşman yoğunluğu, aktif çatışan birim sayısı, üretim/hasat büyümesi ve komutan sağlığıyla belirlenir. Düşük duruma geçişlerde hold süreleri kullanılır; tek bir kısa olay müziği sürekli ileri-geri değiştirmez. Stem'ler aynı anda başlatıldığı için durum geçişleri parça ortasında kesme yerine seviye çapraz geçişiyle gerçekleşir.

## Çevre ve sürü katmanları

`AmbientDirector`, oyuncu konumundaki chunk biyomunu `WorldStreamManager.get_biome_at()` üzerinden alır ve şu döngüler arasında yumuşak geçiş yapar:

- meadow,
- forest,
- rocky,
- dry.

Yakındaki hareketli dost karınca sayısı ayrıca tekil ayak sesi yağmuru üretmez. Yoğunluğa göre açılan birleşik `ant_swarm_loop` katmanı kullanılır.

## Oynanış bağlantıları

Ses olayları aşağıdaki authoritative oynanış noktalarına bağlanmıştır:

- menü ve maç geçişi,
- saldırı, hasar ve ölüm,
- asit fırlatma ve çarpma,
- beş kaynak türünün toplanması,
- üretim kuyruğu başlangıcı ve tamamlanması,
- yuva yükseltme, hasar ve yıkım,
- saldır, hasat, geri çağır, böl, dağıt ve birleştir komutları,
- geçersiz işlem,
- kraliçe/komutan kritik sağlık uyarısı,
- zafer ve yenilgi.

## Mobil ayarlar

HUD'daki `SES` düğmesi kompakt ayar panelini açar:

- Ana ses,
- Müzik,
- Efekt,
- Çevre,
- Arayüz,
- Titreşim,
- Arka planda sesi kapat.

Değerler `user://audio_settings.cfg` içinde `ConfigFile` ile kalıcıdır. Uygulama odağı kaybedildiğinde, seçenek açıksa Master bus susturulur; odağa dönüldüğünde önceki kategori seviyeleri geri yüklenir. Android export presetine `VIBRATE` izni eklenmiştir.

## Ses varlıkları

Bu fazda 62 özgün/prosedürel ses varlığı üretildi:

- 6 stereo OGG müzik dosyası,
- 5 stereo OGG çevre/sürü döngüsü,
- 51 mono PCM WAV efekt.

Bütün dosyalar 44.1 kHz'dir. Hiçbir üçüncü taraf müzik veya efekt paketi kullanılmadı. SFX mono tutulduğu için 2D konumlandırma motor tarafından yapılır; uzun katmanlar depolama ve streaming verimliliği için OGG'dir.

## Dosya yapısı

```text
res://audio/
├── music/
├── ambience/
├── sfx/
│   ├── ui/
│   ├── combat/
│   ├── units/
│   ├── colony/
│   └── resources/
├── events/
└── scripts/
```

## Regresyon testi

```bash
godot --headless --path . --script res://tests/audio_system_regression_test.gd
```

Test; 27 olay kaynağını, olayların bütün stream referanslarını, müzik stem'lerini, ambiyans döngülerini ve temel event bütçelerini doğrular.

## Kabul kriterleri

- Positional ses merkezi oyuncu komutanını takip eder.
- Yoğun savaşta runtime audio node oluşturma/silme yapılmaz.
- Önemsiz uzak sesler çalınmadan elenir.
- Aynı ses mekanik biçimde her kare tekrar etmez.
- Sakinlik, büyüme, tehdit ve savaş arasında ani müzik kesilmesi yoktur.
- Biyom değişiminde çevre döngüsü çapraz geçiş yapar.
- Sonuç ve kraliçe tehlikesi yüksek öncelikle duyulur.
- Kategori ses seviyeleri ve titreşim tercihi cihazda saklanır.
- Uygulama arka plana geçtiğinde ses tercihe göre kapanır.
- Dedicated server ses kaynaklarını çalıştırmaz.
