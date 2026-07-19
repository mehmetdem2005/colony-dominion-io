# Faz 04.3 — Görsel Düzeltme, Akıcı Sürü ve Üretim Sertleştirmesi

Bu teslim yeni içerik fazı değildir. Faz 04.2'de oluşan görsel ve hareket regresyonlarını geri alır, kalabalık sürünün düşük FPS davranışını sabitler ve ilerideki gerçek multiplayer taşıma katmanı için yaşam döngüsü açıklarını kapatır.

## Bulunan regresyonlar

1. Üç kovalı sürü zamanlayıcısı her fizik karesinde yalnız bir kova çalıştırıyordu. Bu nedenle minyon başına hedeflenen 20 Hz yalnız 60 FPS'te sağlanıyor, 30 FPS'te yaklaşık 10 Hz'e düşüyordu.
2. Minyon gövdesi doğrudan 20 Hz adımlarla taşınıyor, ayrı bir görsel interpolasyon uygulanmıyordu. Sonuç, oyun 60 FPS üretse bile görülebilen adımlı hareket ve dönüş titremesiydi.
3. Orijinal 512 px karınca çizimleri 256 px'e, prop/yapı çizimleri 384 px'e kalıcı olarak küçültülmüştü. İllüstrasyon tarzı görseller ayrıca nearest filtre ile örnekleniyordu.
4. Birim derinliği 32 dünya birimlik Z basamaklarına yuvarlanıyordu. Yakın karıncalar birbirinin önüne geçerken görünür sıçrama oluşabiliyordu.
5. Havuzdaki ölü birim, mermi, prop ve kaynak düğümleri işlem kapalı olsa da SceneTree içinde kalıyordu.
6. Chunk interest seçimi istemci ve dedicated server görevlerini karıştırıyordu: gelecekte istemci bütün uzak insan oyuncular için chunk yükleyebilir, boş bir dedicated bot maçında ise yalnız ilk koloni çevresi authoritative olarak yüklenebilirdi.

## Akıcı ve sabit sürü simülasyonu

- Minyon mantığı sabit `0,05 s` adımla, kova başına gerçek 20 Hz çalışır.
- Zamanlayıcı 30 FPS'te kare başına ortalama iki kovayı yakalar; simülasyon hızı artık ekran FPS'ine bölünmez.
- Ani uzun karelerde en fazla altı kova adımı yakalanır ve en fazla `0,15 s` backlog tutulur. Bu sınır, bir donma sonrasında catch-up ölüm döngüsünü önler.
- Fizik gövdesi authoritative konumda kalırken `VisualRoot`, iki simülasyon örneği arasında konum ve dönüşü yumuşatır. Her minyona bağımsız `_process()` veya `_physics_process()` eklenmemiştir.
- Godot fizik interpolasyonu etkinleştirildi. Spawn, pool reuse ve streamed obje yerleşimlerinde `reset_physics_interpolation()` çağrılır.
- Z sırası 32 yerine 8 dünya biriminde nicemlenir; global Y-sort maliyeti geri getirilmeden örtüşme sıçraması azaltılır.

## Görsel kalite geri yüklemesi

- Karınca, kaynak, prop ve yuva PNG'leri yüklenen Faz 04 paketindeki orijinal çözünürlüklerine birebir geri döndürüldü.
- Non-pixel-art CanvasItem'lar `LINEAR_WITH_MIPMAPS` filtre moduna geçirildi. Kaynak PNG'ler kayıpsız kalır; VRAM compression artefaktı eklenmedi.
- Takım çemberlerinin önceki ayrıntılı görünümü ayrı `VisualRoot` çizimine taşındı. Böylece çember, sağlık çubuğu ve karınca resmi aynı yumuşatılmış görsel konumu izler.
- 1280 × 720 menü arka planı korunur; 3600 × 2400 menü belleği regresyonu geri getirilmemiştir.

Görsel kaynakların geri alınması seçili birim/prop/kaynak/yapı dokularında yaklaşık 10 MiB ek decode belleği kullanır. Bu, tek kopya halinde paylaşılan doku belleğidir; karınca sayısıyla çarpılmaz. Kaliteyi bozan kalıcı küçültme yerine bu kontrollü maliyet seçildi.

## SceneTree ve havuz maliyeti

- Boş unit/projectile/prop/resource havuzları artık sahne ağacından ayrılır.
- Yeniden kullanımda aynı node tekrar doğru köke bağlanır, state ve stable entity kimliği baştan kurulur.
- Sahne kapanırken ayrılmış havuz düğümleri açıkça serbest bırakılır; reload sırasında detached-node sızıntısı oluşmaz.
- Pooled unit ve resource nesneleri aktif gruplardan çıkarılır; gelecekteki grup sorguları hayalet nesne görmez.

## Multiplayer ve uzun maç sertleştirmesi

- Dedicated server authoritative chunk planına bütün aktif kolonileri ekler; istemci yalnız yerel oyuncu anchor'ını yükler.
- Tahmini sıcak chunk'lar aktif authoritative alanlara dokunmadan önceliklendirilir ve dinamik resident limitine sert biçimde uyar; altı uzak oyuncu aynı anda hareket ederken plansız chunk büyümesi oluşmaz.
- Remote human komutan artık bot hareket koduna düşmez; authoritative hareket girdisini kullanır.
- Entity despawn/pool sırasında viewer snapshot zaman damgaları ve bilinen entity cache'i temizlenir.
- Peer ayrılma/yeniden bağlanma sırasında ilgili snapshot cache'i sıfırlanır.
- Mermi uçarken saldırgan ölse bile saldırgan takım kimliği korunur ve kill attribution kaybolmaz.
- Mantıksal mermi listesine 2048 güvenlik üst sınırı ve taşma telemetrisi eklendi.
- Android export preset'inde `INTERNET` izni etkinleştirildi.

Bu paket hâlâ gerçek online oyun değildir. ENet client/server başlatma, bağlantı ekranı, lobby, kimlik doğrulama, snapshot alma hattı, istemci buffer/interpolation, prediction/reconciliation ve packet-loss testleri sonraki multiplayer fazında uygulanmalıdır.

## Regresyon testleri

```bash
godot --headless --path . --script res://tests/spatial_index_lifecycle_test.gd
godot --headless --path . --script res://tests/network_entity_registry_test.gd
godot --headless --path . --script res://tests/network_command_validator_test.gd
godot --headless --path . --script res://tests/swarm_scheduler_cadence_test.gd
godot --headless --path . --script res://tests/visual_quality_regression_test.gd
godot --headless --path . --script res://tests/swarm_crowd_stress_test.gd
```

Cadence testi 30 FPS delta akışında 20 Hz kova hızının korunduğunu ve uzun kare yakalamasının sınırlandığını doğrular. Görsel test orijinal asset çözünürlüklerini, smooth filtreyi ve fizik interpolasyon ayarını kilitler. Crowd testi altı dedicated-server anchor'ı ile 360 minyonu örnekler.

## Üretime çıkmadan önce kalan zorunlu ölçümler

- En az bir düşük/orta sınıf gerçek Android cihazda 60, 45 ve 30 FPS frame-time kaydı
- Godot Profiler'da script, physics ve rendering sürelerinin ayrı ölçümü
- 360 minyon yakın savaşında yüzde 1 düşük FPS ve termal throttling testi
- ENet fazından sonra 80–150 ms gecikme, yüzde 1–5 packet loss ve yeniden bağlanma testi
- 20 dakikalık soak testinde entity/snapshot/pool sayılarının sabit kaldığının doğrulanması

Statik doğrulama bu ortamda yapılır; Godot 4.6.3 çalıştırılabilir dosyası bulunmadığı için gerçek runtime ve Android cihaz ölçümü kullanıcı ortamında tamamlanmalıdır.
