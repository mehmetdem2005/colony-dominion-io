# Faz 04.1 — Savaş Kararlılığı ve Gelişmiş Streaming

Bu ara teslim yeni bir oynanış fazı değildir. Faz 04 savaş döngüsünü kararlı hâle getirir ve sonraki fazlardan önce dünya altyapısını üretim seviyesine taşır.

## Çöküşün kök nedeni

`UnitSpatialIndex` hücre dizilerinde doğrudan `Node2D` referansı tutuyordu. Bir birlik öldüğünde `queue_free()` ile siliniyor, fakat indeks bir sonraki 0,12 saniyelik rebuild'e kadar eski referansı koruyordu. `candidate_variant as Node2D` ifadesi geçerlilik kontrolünden önce çalıştığı için Godot, serbest bırakılmış nesneyi çevirmeye çalışıyor ve saldırı sırasında oyunu durduruyordu.

## Kalıcı yaşam döngüsü düzeltmesi

- Spatial hash artık nesne referansı değil yalnızca 64 bit `instance_id` saklar.
- Her sorgu `is_instance_id_valid()` ve `instance_from_id()` üzerinden canlı nesneyi çözer.
- Silinme kuyruğundaki veya sahne ağacından çıkmış hedefler hasar verilebilir kabul edilmez.
- Aynı güvenlik modeli asit mermisinin saldırgan ve hedef kayıtlarında da kullanılır.
- `tests/spatial_index_lifecycle_test.gd`, canlı hedefi bulduktan sonra hedefi anında siler ve aynı hücre sorgusunun güvenli biçimde `null` döndürdüğünü doğrular.

## Chunk yaşam döngüsü

Her chunk aşağıdaki üretim durumlarından geçer:

1. `UNLOADED`: Yalnızca kalıcı kaynak durumu saklanır.
2. `BUILDING`: Prop ve kaynaklar tek karede kurulmaz; kare başına zaman ve iş adımı bütçesiyle hazırlanır.
3. `ACTIVE`: Görsel, engel çarpışması, kaynak sorgusu ve gerekli respawn simülasyonu açıktır.
4. `WARM`: Düğümler hızlı geri dönüş için bellekte kalır; çizim, çarpışma, Area2D monitoring ve fizik işlemi tamamen kapalıdır.

`WorldChunkRuntime` yüklü chunk verisini ve residency durumunu, `WorldChunkBuildJob` ise çok kareli kurulum işini taşır. `WorldStreamManager` otorite, kuyruk önceliği, bütçe ve havuz sınırlarını yönetir.

## Mobil streaming bütçeleri

- Chunk boyutu: `1200 × 1200`
- Aktif alan: oyuncu çevresinde en fazla `3 × 3`
- Toplam resident sınırı: `18` chunk
- Kare başına streaming CPU bütçesi: `1400 µs`
- Kare başına en fazla `5` prop/kaynak kurulum adımı
- Kare başına en fazla `1` chunk boşaltma
- Prop havuzu üst sınırı: `260`
- Kaynak havuzu üst sınırı: `120`

Yön ve hız filtresi, oyuncunun yaklaşık `0,85` saniye sonra ulaşacağı chunkları önceden WARM olarak hazırlar. Aktif chunklar her zaman önceliklidir; eski kuyruk işleri rota değiştiğinde iptal edilir.

## Ek performans düzeltmeleri

- Kaynak araması bütün aktif kaynak dizisini taramak yerine yalnızca sorgu yarıçapının kestiği chunklarda çalışır.
- Dolu ve odak animasyonu olmayan kaynaklar artık her fizik karesinde işlem yapmaz.
- WARM kaynakların respawn süresi düğüm çalıştırmadan zaman damgası üzerinden ilerletilir.
- WARM prop ve kaynaklar çizim ve physics broadphase yükü oluşturmaz.
- Havuzlar sınırsız büyümez; üst sınır üzerindeki düğümler güvenli biçimde bırakılır.
- Chunk üretimi koordinat ve global seed üzerinden deterministiktir.
- Oyuncunun tam üzerinde kurulan katı prop geçici olarak çarpışmasız başlar; oyuncu uzaklaşınca gerçek çarpışması bir kez etkinleşir.
- `MatchController.get_stream_stats()` aktif/WARM chunk, kuyruk, streaming süresi, havuz ve spatial hash telemetrisini sağlar.

## Kabul ölçütleri

- Ölen hedef aynı spatial rebuild aralığında sorgulansa bile freed-object cast oluşmaz.
- Mermi hedefi veya saldırganı uçuş sırasında silinirse mermi güvenli biçimde havuza döner.
- Oyun başlarken yalnızca merkez chunk senkron kurulur; komşular karelere bölünerek yüklenir.
- WARM chunk içindeki Sprite2D, collision ve kaynak physics process kapalıdır.
- Resident chunk sayısı normal akışta `18` sınırını geçmez.
- GDScript proje analizi sıfır parse/type hatası ve sıfır uyarı verir.

