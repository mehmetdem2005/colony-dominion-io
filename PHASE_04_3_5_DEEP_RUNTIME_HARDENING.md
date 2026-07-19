# Faz 04.3.5 — Derin Çalışma Zamanı Sertleştirmesi

Hedef: Godot 4.6.3 stable, Android landscape ve dedicated-server uyumlu aynı oyun kodu.

Bu faz yeni oynanış eklemez. Faz 04.3.4 üzerine yaşam döngüsü, veri doğrulama, nesne havuzlama, chunk residency, ağ otoritesi, ses havuzları, mobil giriş ve sabit-zaman simülasyonu için savunmacı üretim sertleştirmesi uygular.

## Düzeltilen kök nedenler

### 1. Havuzlanan nesneler ve kamera yaşam döngüsü

- Ölen komutanın nesnesi havuza döndüğünde kamera artık eski `ColonyUnit` referansını tutmaz.
- Kamera canlı komutanı, komutan yoksa canlı yuvayı takip eder; yeni komutan doğduğunda hedef atomik olarak geri değiştirilir.
- İlk komutan veya yeniden doğan komutan geçici bir entity/pool hatası nedeniyle oluşturulamazsa yeniden doğma işlemi tek seferde kaybolmaz; sınırlı gecikmeyle yeniden denenir.
- Orphan/dead birimler düzenli temizlikte entity registry, spatial index, swarm bucket ve pool katmanlarından birlikte çıkarılır.

### 2. Üretim kuyruğu atomikliği

- Üretim süresi dolduğu karede kapasite doluysa kayıt artık kuyruktan kaybolmaz.
- Doğum başarısız olursa aynı üretim kaydı kuyruğun başına geri alınır ve kısa gecikmeyle yeniden denenir.
- Başarısız doğumda tamamlanma sesi/olayı yayınlanmaz.
- Yıkılmış yuvada üretim ve yükseltme işlemleri reddedilir.

### 3. Chunk streaming ve fizik aktivasyonu

- Çok kareye yayılan build job sırasında prop ve kaynaklar tamamen dormant kalır.
- Görünürlük, işlem ve collision yalnızca chunk bütünüyle hazırlandıktan sonra residency ile atomik uygulanır.
- WARM→ACTIVE geçişinde taş çarpışması komutanın, yuvanın veya aktif minyonların altında açılmaz.
- Yakın birim ayrıldıktan sonra geçici collision suppression güvenli biçimde kaldırılır.
- Kaynak respawn simülasyonu sabit 0,25 saniyelik adımlara ve kare başına üst sınıra alınmıştır; uzun donmalarda tek karelik simülasyon sıçraması oluşmaz.

### 4. Ağ otoritesi ve snapshot güvenliği

- Kayıtlı olmayan peer komutları rate-limit tablosunda durum oluşturamaz.
- Aynı canlı network entity ID başka nesne tarafından ezilemez.
- `sequence`, `client_tick`, komut adı, payload, birim kimliği ve hareket vektörü tür/sınır kontrolünden geçer.
- `NaN` ve `Infinity` hareket, snapshot radius veya konum olarak authoritative akışa giremez.
- Elenmiş bir koloni yeni peer'e atanamaz.
- Peer ayrıldığında hareket girdisi, sıra numarası, rate-limit ve snapshot cache durumu temizlenir.
- Geçersiz viewer/anchor durumunda keyframe biçiminde güvenli boş snapshot ve önceki entity'ler için despawn listesi üretilir.

### 5. Sabit-zaman ve aşırı yük davranışı

- Server tick, projectile tick ve resource tick catch-up döngülerinin kare başına üst sınırı vardır.
- Fazla birikmiş zaman korunabilir küçük kalana indirgenir ve debug istatistiğinde dropped time olarak raporlanır.
- Görsel projectile ve logical projectile sayıları sabit bütçeyle sınırlıdır.

### 6. Birim fiziği ve sayısal doğrulama

- Eksik üç obstacle-recovery sabiti tanımlandı.
- Hareket, hasar, mermi hızı/hasarı, hedef konumu, dormant translation ve world query girdilerinde sonlu sayı kontrolü vardır.
- Taş çarpışmasında kalan hareket en fazla üç iterasyonla yüzey boyunca kaydırılır.
- DORMANT→ACTIVE dönüşünde birim bir engelin içinde kalmışsa deterministik halka taramasıyla güvenli konuma çıkarılır.

### 7. Mobil UI giriş bütünlüğü

- Joystick, aksiyon düğmeleri ve üretim kartları hit testlerini ölçeklenmiş Canvas koordinatından yerel koordinata ters dönüşümle yapar.
- Görsel UI küçültüldüğünde eski boyutta görünmez dokunma alanı kalmaz.
- Modal veya oyun sonu paneli açıldığında joystick, kamera pinch ve komut girişleri sıfırlanır.
- Uygulama odağı kaybolduğunda yakalanmış touch/mouse durumları serbest bırakılır.

### 8. Ses çalışma zamanı

- Başarısız ses çalma girişleri cooldown veya emitter geçmişi bırakmaz.
- SFX/UI havuzları tekrar configure edildiğinde eski player düğümleri temizlenir.
- Cooldown geçmişi süreli temizlenir; uzun maçta sözlükler sınırsız büyümez.
- Konum, listener ve intensity girdileri sonlu sayı kontrolünden geçer.
- Aynı event ID ikinci kez yüklenirse sessizce üzerine yazılmaz.
- `play_ui()` konumsal bir olayı yanlış havuza kabul etmez.
- Eski limiter kaldırıldı; Master zincirinde tek bir `AudioEffectHardLimiter` son efekt olarak tutulur.

## Eklenen regresyon kapsamı

`res://tests/deep_runtime_hardening_regression_test.gd` şunları denetler:

- entity ID çakışması ve yanlış-node unregister,
- serbest bırakılmış entity çözümleme,
- negatif maliyetle envanter kazanımı olmaması,
- geçersiz projectile ve kaynak girdileri,
- server sahnesinde canlı kolonilerin aktif kalması,
- birden fazla canlı koloni varken erken maç bitişi olmaması,
- elenmiş koloniye peer atanamaması,
- NaN joystick/hasar/snapshot girdileri,
- kamera, chunk, production retry, touch transform ve audio hardening kaynak sözleşmeleri.

Çalıştırma:

```bash
godot --headless --path . --script res://tests/deep_runtime_hardening_regression_test.gd
```

Tüm testleri çalıştırma:

```bash
for test in tests/*_test.gd; do
  godot --headless --path . --script "res://$test" || exit 1
done
```

## Kabul ölçütleri

- Godot parser/compile hatası olmamalı.
- Eksik `res://` referansı olmamalı.
- Canlı entity kimliği üzerine başka nesne yazılamamalı.
- Kapasite yarışı üretim kaydı veya harcanmış kaynak kaybı oluşturmamalı.
- Chunk kısmi hazırlanırken hiçbir prop/kaynak görünür veya çarpışmalı olmamalı.
- HUD ölçek değişiminde görünmez hitbox oluşmamalı.
- Komutan ölümü/havuzlanması sonrası kamera başka bir havuzlanmış minyonu izlememeli.
- Uzun frame stall sonrası simülasyon tek karede sınırsız catch-up yapmamalı.
- Dedicated server birden fazla canlı koloni varken maçı erken bitirmemeli.

## Bilinen sınır

Statik analiz ve kaynak regresyonları çalışma zamanı riskini önemli ölçüde azaltır; gerçek cihazdaki render/driver, Android yaşam döngüsü ve yoğun savaş zamanlaması yalnızca Godot 4.6.3 motor testi ve uzun süreli cihaz soak testiyle doğrulanabilir. Bu build ortamında Godot executable bulunmadığı için headless testler burada çalıştırılamadı.
