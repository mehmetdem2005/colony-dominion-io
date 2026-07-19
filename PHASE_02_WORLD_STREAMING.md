# Faz 02 — 100× dünya alanı ve mobil chunk streaming

Hedef motor: Godot 4.6.3 stable / Mobile renderer

## Dünya ölçeği

Önceki dünya 3600 × 2400 birimdi. Bu fazda genişlik ve yükseklik 10'ar kat artırıldı:

- Dünya: 36.000 × 24.000 birim
- Toplam oynanabilir alan: önceki alanın 100 katı
- Chunk ölçüsü: 1200 × 1200
- Toplam mantıksal chunk: 30 × 20 = 600
- Oyuncu çevresinde aktif alan: 5 × 5 chunk
- Bellekte tutulan koruma halkası: 7 × 7 chunk üst sınırı

## Üretim mimarisi

```text
GameRoot (MatchController)
├── World
│   ├── Ground
│   │   ├── WorldUnderlay
│   │   └── StreamingGround (tek quad, tekrarlanan kesintisiz UV)
│   ├── Decorations
│   │   └── Pooled StreamedWorldProp düğümleri
│   ├── Resources
│   │   └── Pooled WorldResourceNode düğümleri
│   ├── Structures
│   ├── Units
│   └── Projectiles
├── WorldStreamManager
├── ColonyController × 6
├── PlayerCamera
└── HUD
```

## Streaming kuralları

- Chunk içeriği global seed ve chunk koordinatından deterministik üretilir.
- Aynı koordinata geri dönüldüğünde dekor yerleşimi değişmez.
- Prop ve kaynak düğümleri silinmez; havuza dönüp yeniden kullanılır.
- Tüketilmiş kaynakların miktarı ve yeniden doğma süresi chunk kapatıldığında saklanır.
- Chunk yükleme kare başına bütçelidir; tek karede bütün dünya oluşturulmaz.
- Zemin 36.000 × 24.000 görsel olarak belleğe alınmaz. Tek Polygon2D üzerinde tam eşleşen, tekrarlanabilir 1024 px zemin dokusu kullanılır.
- Zemin chunklara bölünmediği için birleşim çizgisi oluşmaz.

## Uzak yapay zekâ katmanları

- FULL: Oyuncuya 2200 birimden yakın koloniler tam fizik ve savaş simülasyonu kullanır.
- REDUCED: 2200–3500 aralığında birlikler 8 Hz civarında güncellenir.
- DORMANT: Daha uzaktaki kolonilerde minyon fiziği kapatılır; ekonomi ve üretim koloni düzeyinde düşük frekanslı simüle edilir.
- Oyuncu yaklaştığında birlikler aynı sağlık, sayı ve üretim durumu korunarak yeniden tam simülasyona geçer.

## Kabul kriterleri

- Oyuncu dünya sınırları boyunca 36.000 × 24.000 alan içinde hareket edebilir.
- Harita alanı eski sürümün tam 100 katıdır.
- Zemin tekrarlarında açık birleşim çizgisi görünmez.
- Başlangıçta yalnızca yakın chunklar yüklenir.
- Uzak chunklar kapatılır ve aynı düğümler havuzdan yeniden kullanılır.
- Kaynak tüketimi chunk kapatıp açarak sıfırlanmaz.
- Beş uzak bot, oyuncudan uzaktayken yüzlerce CharacterBody2D fizik adımı çalıştırmaz.
