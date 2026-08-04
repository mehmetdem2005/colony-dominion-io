# Edgegap Kurulumu — Profesyonel + "Oyuncu Yokken Çalışmaz" Garantili

Bu rehber çok oyunculu için Edgegap'i (oyun sunucusu barındırma) baştan sona
kurar. Mimari: **istemci → Supabase eşleştirme fonksiyonu (Edgegap token'ını gizli
tutar) → Edgegap (maç başına adanmış sunucu açar)**. Oyun sırasında trafik
doğrudan Edgegap sunucusuna gider; Supabase aradan çıkar.

> Maliyet modeli: Edgegap **sadece sunucu çalışırken** (maç anında) ücret alır.
> Aşağıdaki üç mekanizma bir sunucunun oyuncu yokken açık kalmasını imkânsız
> kılar — yani boşta fatura oluşmaz.

---

## 0) "Oyuncu yokken çalışmaz" garantisi (kodda hazır)

Sunucu üç ayrı yoldan kendini kapatır; container çıkınca Edgegap deployment biter
ve **faturalama durur**:

1. **Maç öncesi**: 90 sn içinde kimse katılmazsa sunucu kapanır
   (`SERVER_JOIN_TIMEOUT_SECONDS`).
2. **Herkes ayrılırsa**: maç başladıktan sonra bağlı **insan kalmazsa**, yeniden
   bağlanma penceresinden ~15 sn sonra (toplam ~75 sn) sunucu kapanır
   (`EMPTY_SHUTDOWN_GRACE_SECONDS`, `game_transport.gd`).
3. **Sert üst sınır**: sunucu her hâlükârda `MAX_MATCH_MINUTES` (varsayılan 25 dk)
   dolunca kapanır — takılan/kaçak bir container bile sonsuza dek çalışamaz.

Ek olarak istemci maçtan düzgün çıkınca Supabase fonksiyonu Edgegap'e
`DELETE /stop` gönderip deployment'ı anında durdurur.

> **Belt-and-suspenders:** Edgegap panelinde uygulama sürümüne ayrıca bir
> "max deployment duration" (örn. 60 dk) koy. Kod zaten 25 dk'da kapanır; bu
> panel ayarı son güvenlik ağıdır.

---

## 1) Gereksinimler

- Edgegap hesabı (ücretsiz): https://app.edgegap.com
- Docker kurulu bir makine (imajı derleyip yüklemek için)
- Mevcut Supabase projen (giriş + DB için zaten kullanılıyor)

## 2) Oyun sunucusu imajını derle

```bash
# repo kökünde
IMAGE_TAG="colony-dominion-server:latest" ./tools/build_game_server_image.sh
```

Bu, Godot dedicated server'ı (`--headless --server`) içeren Docker imajını üretir.

## 3) İmajı Edgegap'e yükle ve uygulama sürümü oluştur

Edgegap panelinde:

1. **Create Application** → ad: `colony-dominion` (bu `EDGEGAP_APP_NAME` olacak).
2. **Create Version** → ad: örn. `v1` (bu `EDGEGAP_APP_VERSION` olacak).
   - **Container image**: imajı Edgegap'in registry'sine pushla (panel sana
     `registry.edgegap.com/...` hedefi ve `docker push` komutunu verir) veya kendi
     public registry'ni bağla.
   - **Port** (çok önemli — birebir böyle):
     - Ad: `game`
     - Port: `20000`
     - Protokol: **UDP**
     - (Eşleştirme fonksiyonu container'a `GAME_PORT=20000` enjekte eder ve dış
       portu `game` adlı eşlemeden okur.)
   - İstersen ikinci port: ad `control`, `7001`, TCP (sağlık kontrolü için;
     zorunlu değil).
   - **Resources**: küçük başla (örn. 1 vCPU / 1 GB) — maliyet buna göre.
3. Sürümü **deploy edilebilir** duruma getir (validate/publish).

## 4) Edgegap API token'ını al

Panel → **API Tokens** → yeni token oluştur. Bu token **sadece Supabase
fonksiyonunda** duracak, istemciye **asla** konmayacak.

## 5) Supabase eşleştirme fonksiyonunu ayarla ve deploy et

Fonksiyon: `backend/supabase/functions/matchmaking/index.ts`

Gerekli ortam sırlarını (function secrets) gir:

```bash
supabase secrets set \
  EDGEGAP_API_TOKEN="<panelden aldığın token>" \
  EDGEGAP_APP_NAME="colony-dominion" \
  EDGEGAP_APP_VERSION="v1" \
  GAME_MAX_PLAYERS="10" \
  GAME_MAX_MATCH_MINUTES="25"

supabase functions deploy matchmaking
```

> `GAME_MAX_MATCH_MINUTES` sunucuya enjekte edilir ve sert üst sınırı belirler
> (5–180 arası). Varsayılan 15; istersen değiştir.

Doğrulama:
```bash
curl -s https://<PROJE>.supabase.co/functions/v1/matchmaking/health
# {"ok":true,"service":"colony-edgegap-matchmaking","configured":true}
```
`configured:true` görüyorsan token + app adı tanımlı demektir.

## 6) İstemci tarafı

İstemci zaten Supabase üzerinden eşleştirmeye gidiyor; ekstra ayar gerekmez.
`config/backend_config.json` içindeki `supabase_url` ve `supabase_publishable_key`
doğru projeyi gösterdiği sürece "ÇOK OYUNCULU" bu akışı kullanır.

## 7) Test

1. APK'de Google ile giriş yap, yasal onayı geç.
2. "ÇOK OYUNCULU"ya bas → birkaç saniye içinde en yakın Edgegap node'unda sunucu
   açılır ve bağlanırsın.
3. Edgegap panelinde **Deployments** altında sunucunun açıldığını, maç bitince /
   herkes çıkınca **kendiliğinden kapandığını** gör.

### Maliyet doğrulaması
- Kimse oynamıyorken **Deployments listesi boş** olmalı → 0 maliyet.
- Bir maç açıp herkes çıkınca deployment ~75 sn içinde kaybolmalı.
- Hiçbir deployment 25 dk'yı geçmemeli.

---

## Sık sorunlar

| Hata | Sebep | Çözüm |
|---|---|---|
| `matchmaking_not_configured` | Fonksiyonda `EDGEGAP_API_TOKEN`/`EDGEGAP_APP_NAME` yok | 5. adımdaki secrets'ı gir, fonksiyonu yeniden deploy et |
| `deploy_failed` | App sürümü/registry hatalı, ücretsiz katman eşzamanlı limit, port adı yanlış | Sürümün publish olduğunu, port adının tam `game`/UDP/20000 olduğunu doğrula; önceki deployment'ları durdur |
| `deploy_no_request_id` | Edgegap beklenmeyen yanıt döndü | Panelden sürümün geçerli olduğunu kontrol et |
| Bağlanıyor ama kopuyor | Port/protokol UDP değil ya da dış port eşlemesi `game` değil | Port ayarını düzelt |
