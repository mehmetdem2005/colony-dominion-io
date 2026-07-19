# Faz 04.3.2 — Aktif NPC hareketi, mobil HUD ve yerel engel kaçınma

Hedef motor: Godot 4.6.3 Mobile renderer.

## NPC kolonilerinin hareket sürekliliği

Aktif botlar kaynak bulamadığında eski davranışta doğrudan yuva konumunu hedefliyordu. Komutan yuvaya ulaştıktan sonra bütün koloni formasyonu uzun süre hareketsiz kalıyordu.

Bu fazda:

- Aktif bot karar aralığı 0.34–0.56 saniyeye indirildi.
- Kaynak bulunamadığında 420–1450 dünya birimi yarıçapında süreli devriye hedefi seçiliyor.
- Devriye hedefleri 3.5–7.5 saniye korunuyor; her AI kararında rastgele değiştirilmediği için yön titreşmesi oluşmuyor.
- Kaynak hedefi doğrudan kaynak konumuna sabitleniyor; sürekli rastgele ofset üretilmiyor.
- DORMANT makro hareket 2 Hz'den 4 Hz'e çıkarıldı ve hız katsayısı 0.72'den 0.88'e yükseltildi.
- FULL simülasyon ilgi mesafesi 2200, REDUCED ilgi mesafesi 4600 dünya birimine çıkarıldı.
- Gelişmiş tehdit puanlama, geri çekilme ve taktik saldırı seçimi bu fazın kapsamına alınmadı.

## Taş ve katı çevre engelleri

`move_and_collide()` tek başına çarpışma sonrası rota üretmediği için karıncalar taş yüzeyine basılı kalabiliyordu.

Yeni `UnitLocalObstacleAvoidance` bileşeni:

- Merkez, sol ve sağ olmak üzere üç ileri ray örnekler.
- Ray sorgularını her frame değil, birim başına 0.10–0.16 saniye aralıklarla yeniler.
- Engelin normalinden teğet yön üretir.
- Seçilen kaçış tarafını 0.72 saniye koruyarak sağ-sol titreşmesini önler.
- İstenen hız varken gerçek yer değiştirme düşük kalırsa sıkışma kurtarma kuvvetini artırır.
- Minyonlarda ilk çarpışmadan kalan hareketi yüzey boyunca kaydırır.
- Commander FULL simülasyonda `move_and_slide()`, diğer tier ve minyonlarda kontrollü `move_and_collide()` yolu kullanır.

Bu sistem lokal ve dinamik bir kaçınmadır; tam NavigationServer2D rota grafiği değildir. Chunk dışı makro hareket için engel grafiği sonraki dünya-AI fazında ayrıca kurulacaktır.

## Mobil HUD

### Kaynak alanı

- Panel genişliği 190'dan 142 piksele düşürüldü.
- Kaynak simgeleri ayrı 42×38 rozetlere alındı.
- Görsel alan 38×34, miktar yazısı 22 punto yapıldı.
- Beş kaynak satırı 224 piksel yükseklik içinde tutuldu.

### Minimap

- Sağ üstten kaldırıldı ve kaynak panelinin hemen sağına, sol üst kümeye taşındı.
- 224×224 dış panel ve 204×204 harita alanı kullanılıyor.
- Biome renkli resident chunk katmanı, aktif kaynak noktaları, yuva elmasları, yön gösteren commander okları, oyuncu pulse halkası ve kamera görüş dikdörtgeni eklendi.
- Yenileme aralığı 0.20 saniyeden 0.12 saniyeye indirildi.

### Üretim alanı

- Beş kartın toplam genişliği sağ komut alanına taşmadan 662 piksel dış panel içinde tutuldu.
- Kart dokunma alanı 122×108 piksel yapıldı.
- Birim görseli, isim ve rol alanları büyütüldü.
- Maliyetler 20×20 kaynak ikonlu ayrı rozetlerde gösteriliyor.
- Alt panel toplam dikey bütçesi 156 piksel olarak sınırlandı.

## Regresyon testleri

```bash
godot --headless --path . --script res://tests/runtime_streaming_regression_test.gd
godot --headless --path . --script res://tests/ai_navigation_ui_regression_test.gd
```

İkinci test; yerel kaçınmanın taş önünde teğetsel yön üretmesini, kaynak paneli genişliğini, minimap yerleşimini ve üretim panelinin mobil dikey bütçesini doğrular.
