# Faz 4 — Komutan Merkezli Sürü ve Aktif Hasat

Bu faz, oyuncunun işçileri uzak görevlere gönderip beklediği RTS davranışını kaldırır. Oyun artık hareketli kraliçe/komutan merkezli bir `.io` sürü yapısı kullanır.

## Oynanış değişiklikleri

- İşçiler kendi başlarına haritanın uzak noktalarına gitmez.
- Oyuncu kaynağın yakınına gelmeden hasat başlatamaz.
- `HASAT` komutu yalnızca kraliçenin 310 piksel çevresindeki kaynağı hedefler.
- Hasat 7 saniyelik aktif bir çalışma penceresidir.
- Kraliçe kaynaktan 360 pikselden fazla uzaklaşırsa hasat iptal edilir.
- Hasat bitince veya `GERİ ÇAĞIR` kullanıldığında işçiler formasyona döner.
- Daha fazla işçi, aynı aktif hasat penceresinde daha yüksek toplama hızı sağlar.
- Hedeflenen kaynağın çevresinde takım renginde nabız atan hasat çemberi görünür.

## Sürü davranışı

- Yeni `SwarmFormationManager`, bütün karıncalara benzersiz formasyon slotları atar.
- Muhafız ve askerler öne; işçiler ve menzilli birimler arkaya; izciler kanatlara yerleşir.
- Slotlar yalnızca birlik eklendiğinde, öldüğünde veya formasyon komutu değiştiğinde yeniden kurulur.
- Karıncalar düşmanı sınırsız takip etmez; kraliçenin çevresindeki savaş menzilinde kalır.
- Çok geride kalan karıncalar hız bonusu alarak sürüye geri yetişir.
- Yavaş birimler, kraliçenin hareket hızına göre otomatik takip hız çarpanı kazanır.
- Yuvada üretilen yeni birlik, kraliçe uzaktaysa doğrudan sürünün yakınına katılır.

## Komutlar

- `HASAT`: Yakındaki kaynağı kısa süreli aktif olarak toplatır.
- `GERİ ÇAĞIR`: Hasadı ve saldırı hedefini iptal eder, bütün sürüyü kraliçeye toplar.
- `SALDIR`: Kraliçenin çevresindeki erişilebilir düşmana sürü saldırısı verir.
- `BÖL`: Sürüyü kraliçenin iki yanında iki savaş kanadına ayırır.
- `BİRLEŞ`: İki kanadı tek sürüye döndürür.
- `DAĞIT / SIKILAŞ`: Slotlar arasındaki mesafeyi değiştirir.

## Teknik mimari

- `gameplay/colony/swarm_formation_manager.gd`: taktik rol sıralaması ve halka slot üretimi.
- `gameplay/colony/colony_controller.gd`: aktif hasat oturumu, komutan merkezli hedef sınırı ve takviye katılımı.
- `gameplay/units/unit.gd`: sert geri çağırma, takip hız eşitleme ve yerel hasat davranışı.
- `gameplay/economy/resource_node.gd`: aktif hedef görseli.
- `ui/hud.gd`: `HASAT` geri sayımı ve `GERİ ÇAĞIR` komutu.
