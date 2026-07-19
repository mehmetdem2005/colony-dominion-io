# Faz 04.2 — Kalabalık Sürü Performansı ve Network-Ready Temel

Bu teslim yeni içerik fazı değildir. Faz 04.1 oynanışını korurken yoğun karınca savaşındaki CPU/GPU darboğazlarını kaldırır ve sonraki gerçek multiplayer fazının otorite sınırlarını hazırlar.

## Kalabalık sürü düzeltmesi

Önceki yapıda 6 koloni × 60 minyon + 6 komutan en kötü durumda 366 ayrı `_physics_process()` callback'i çalıştırıyordu. 60 Hz'de bu, yaklaşık 21.960 birim callback'i/saniye ve yoğun savaşta birim-birim physics pair maliyeti üretiyordu.

Yeni yapı:

- Yalnız komutanlar bağımsız 60 Hz fizik callback'i kullanır.
- Minyonlar koloni başına üç dengeli kovaya atanır ve merkezi olarak 20 Hz simüle edilir.
- 360 minyonda her kare yaklaşık 120 minyon adımı çalışır; minyon callback sayısı sıfırdır.
- Minyonların fizik maskesi yalnız dünya engellerini içerir. Karınca-karınca ayrışma, takım kovalarına ayrılmış spatial grid ile çözülür.
- Unit kökünde her kare Y-sort yerine 32 dünya biriminde nicemlenmiş Z sırası kullanılır.
- Minyon takım göstergesi dört ağır halka yerine iki basit dairesel çizim kullanır.

## Yaşam döngüsü ve pooling

- Ölen unit node'u silinmez; stable entity kaydı kaldırılır, bütün hedef/işlem durumu sıfırlanır ve 128 eleman sınırındaki havuza döner.
- Havuzdan çıkan aynı Godot node'u yeni bir `network_entity_id` alır. Eski hedef veya mermi kimliği yeni varlığa çözülemez.
- Spatial grid yerel instance ID'yi yalnız dahili canlılık çözümlemesi için kullanır; ağ veya formasyon sırası için kullanmaz.
- Komutan isim etiketi bütün minyon sahnelerinde bulunmaz; yalnız komutan için tembel oluşturulur.

## Mermi bütçesi

- Görsel AcidProjectile node'ları merkezi 30 Hz çalışır.
- Aynı anda en fazla 120 görsel mermi bulunur.
- Bu sınırın üzerindeki veya headless server'daki mermiler node oluşturmadan mantıksal uçuş durumunda tutulur; hedef, hız, ömür ve vuruş zamanı korunur.
- Boşta projectile havuzu 96 node ile sınırlıdır.

## Olay ve varlık maliyeti

- İşçi hasatları resource türüne göre 0,20 saniye boyunca biriktirilir ve envantere tek batch olarak uygulanır.
- Bir üretim/yükseltme isteğinden önce bekleyen hasat zorunlu flush edilir; ekonomi doğruluğu korunur.
- Kullanılmayan ResourceNode Area2D monitoring/collision broadphase'i tamamen kapatıldı.
- Depleted resource respawn ve odak süresi ayrı 60 Hz callback'ler yerine chunk yöneticisinde merkezi 4 Hz ilerler.
- Birim/kaynak dokuları en fazla 256 px; büyük prop ve yuva dokuları en fazla 384 px oldu.
- 3600 × 2400 menü arka planı yerine 1280 × 720 sürüm kullanılır. Büyük kaynak dosya Android export'undan çıkarılır.

## Çoklu-interest chunk sistemi

- Tek `interest_target` yerine instance-lifecycle güvenli çoklu anchor kaydı bulunur.
- Her insan komutanı, komutan yoksa yuvası, 3 × 3 ACTIVE alan oluşturur.
- Tahmini hareket yönündeki chunklar WARM hazırlanır.
- Tek istemci residency bütçesi 18'dir; server birleşimi anchor sayısına göre büyür ve 84 ile sınırlıdır.
- Headless mod görsel olmayan prop'ları kurmaz; katı engellerin deterministik RNG akışı ve authoritative çarpışması korunur.

## Network-ready otorite

- `NetworkEntityRegistry`: maç içinde yeniden kullanılmayan stable ID ve pool/freed güvenli çözümleme.
- `NetworkCommandValidator`: sequence, sahip peer, tür, hareket büyüklüğü ve üretim birimi doğrulaması.
- `MatchController.receive_authoritative_command()`: istemciden gelecek taşıma katmanının tek yazma kapısı.
- Peer başına 45 komut/saniye rate limit.
- 20 Hz server tick ve quantized position snapshotları.
- Komutan 20 Hz, yakın minyon 10 Hz, uzak ilgili minyon 4 Hz, yuva 2 Hz, uzak koloni özeti 1 Hz.
- İki saniyede bir keyframe ve relevance dışına çıkan varlıklar için despawn listesi.
- Headless algısı ve `Dedicated Server` Linux export preset'i.

Gerçek ENet bağlantı ekranı, lobby/matchmaking ve istemci prediction/interpolation bir sonraki multiplayer fazının kapsamıdır. Bu teslimde çevrimdışı oynanış aynı authoritative komut kapısını kullanır; böylece UI artık gameplay state'i doğrudan değiştirmez.

## Regresyon testleri

```bash
godot --headless --path . --script res://tests/spatial_index_lifecycle_test.gd
godot --headless --path . --script res://tests/network_entity_registry_test.gd
godot --headless --path . --script res://tests/network_command_validator_test.gd
godot --headless --path . --script res://tests/swarm_crowd_stress_test.gd
```

Crowd testi altı koloniyi 60'ar minyona doldurur, bütün minyonların bağımsız physics callback'inin kapalı olduğunu doğrular ve 180 physics frame boyunca telemetri toplar.
