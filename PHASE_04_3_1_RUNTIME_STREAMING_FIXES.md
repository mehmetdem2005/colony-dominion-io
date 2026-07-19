# Faz 04.3.1 — Runtime, görsel sıra ve uzak koloni düzeltmeleri

Hedef motor: Godot 4.6.3 Mobile renderer.

## 1. Viewport filtre hatası

`project.godot` içindeki Viewport varsayılan canvas filtresi `4` olarak kayıtlıydı. Bu alanın geçerli çalışma zamanı değerleri `0..3` aralığındadır; `4` enum sonu işaretidir. Proje ayarı `2` (`LINEAR_WITH_MIPMAPS`) yapıldı. Sahne Sprite2D düğümlerindeki `texture_filter = 4` değiştirilmedi; onlar farklı olan CanvasItem filtresi enum'unda geçerli `LINEAR_WITH_MIPMAPS` değeridir.

## 2. Camera2D interpolation uyarısı

`PlayerCamera` sahnede `process_callback = 0` ile Physics moduna sabitlendi. `PlayerCameraController._init()` da aynı değeri node SceneTree'ye girmeden önce uygular. Böylece fizik interpolasyonu kamerayı çalışma anında zorla başka callback'e geçirmek zorunda kalmaz.

## 3. Üst üste gelen karınca halkaları

Kök neden iki parçalıydı:

- Çok sayıda yarı saydam dolu daire üst üste geldiğinde alpha birikimi parlaklığı çizim sırasına bağımlı yapıyordu.
- Küçük separation düzeltmeleri karıncaları Z kovası sınırında ileri-geri geçirerek çizim sırasını değiştirebiliyordu.

Çözüm:

- Yarı saydam dolu takım diski kaldırıldı; koyu dış kontur ve tam opak takım halkası kullanılıyor.
- Z sırası 16 dünya birimlik kova, 4 birim histerezis ve `network_entity_id` tabanlı dört stable alt katman kullanıyor.
- Commander ve squad işaretleri de opak çiziliyor.

## 4. Yüklenmemiş chunk'lardaki NPC kolonileri

DORMANT koloniler artık yerel chunk node'larına, collision'a veya minyon physics callback'lerine ihtiyaç duymayan makro navigasyon katmanına sahiptir.

- Güncelleme frekansı: 2 Hz.
- Hız: komutan hızının yüzde 72'si.
- Bütün canlı koloni birimleri aynı translation ile taşınır; formasyon korunur.
- Grup bounding box'ı dünya sınırına birlikte clamp edilir.
- Güçlü koloniler yalnız 3000 birim içindeki düşman yuvasına makro saldırı yürüyüşü başlatır; aksi halde yuva çevresinde deterministik devriye hedefi seçer.
- Chunk yeniden resident olduğunda mevcut FULL/REDUCED sistemine normal pozisyonundan geri girer ve interpolation state sıfırlanır.

Bu katman uzak simülasyon için stratejik hareket sürekliliği sağlar. Engelli arazi makro grafiği, tehdit puanlama, savaş/geri çekilme utility sistemi ve uzak savaş çözümlemesi sonraki AI fazına bırakılmıştır.

## 5. Basit kaçış görünümü

Bot komutanının yakınında düşman varken düşük kuvvetli koloninin eski kaynak hedefine yürümeye devam etmesi durduruldu. Bot artık yakın tehdide karşı ilgisiz navigasyonu keser ve bulunduğu yerde mevcut otomatik saldırı sistemini kullanır. Beş veya daha fazla savaş birimi varsa hedefe commit eder. Bu değişiklik gelişmiş AI değildir; yalnızca yanlış davranışın deterministik olarak engellenmesidir.

## Regresyon komutu

```bash
godot --headless --path . --script res://tests/runtime_streaming_regression_test.gd
```

Test; Viewport filtre değerini, Camera2D physics callback'ini, DORMANT görünürlüğünü, chunk bağımsız hareketi ve grup translation bütünlüğünü doğrular.
