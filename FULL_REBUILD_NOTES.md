# Tam Yeniden Yapım — Godot 4.6.3

Bu sürüm eski hotfix zincirinin üzerine yama uygulanarak değil, son tam paketten temiz klasöre çıkarılıp sorunlu sistemler yeniden yazılarak oluşturuldu.

## Kökten değiştirilen sistemler

- Joystick artık `Control` tabanlı, ekran köşesine anchor ile bağlı ve çoklu dokunmayı parmak kimliğiyle izliyor.
- `SALDIR`, `TOPLA` ve üretim kartları özel mobil giriş alanları kullanıyor; dokunma ile fare emülasyonu kapatıldığı için çift tetikleme oluşmuyor.
- Mobil kontroller doğrudan `HUDRoot` altında ve `CanvasLayer.layer = 100` üzerinde; editör içi gömülü oyun penceresinde de ekran dışında kalmıyor.
- Özel UI çizimlerinde kullanılan tüm `queue_redraw()` çağrıları kaldırıldı. UI, standart `Panel`, `Label` ve `TextureRect` düğümleriyle oluşturuluyor.
- Sıralama güncellemesindeki `queue_free()` tabanlı sonsuz `while` döngüsü kaldırıldı. Bu hata maç başladıktan kısa süre sonra ana iş parçacığını kilitleyebiliyordu.
- Dekorların sahne ağacına eklenmeden `global_position` alması kaldırıldı.
- Zemin, parçalardan veya shader ile kayan katmanlardan oluşmuyor. Harita ile aynı ölçüde 3600×2400 tek ve benzersiz doku kullanıyor.
- Zeminde mipmap filtresi kaldırıldı; standart lineer filtre ve 1.0 başlangıç kamera yakınlaştırması kullanılıyor.

## Kontrol edilenler

- Bütün GDScript dosyaları gdtoolkit ayrıştırma, biçim ve lint kontrolünden geçti.
- Bütün PNG dosyaları tamamen açılarak doğrulandı.
- Bütün `res://` dosya başvuruları kontrol edildi.
- Proje ZIP'i oluşturulduktan sonra CRC bütünlük testi yapıldı.

## Temiz kurulum

Eski proje klasörünün üzerine yazmayın. Eski klasörü ve içindeki `.godot` önbelleğini silin; bu paketi yeni klasöre çıkarıp `project.godot` dosyasını yeniden içe aktarın.
