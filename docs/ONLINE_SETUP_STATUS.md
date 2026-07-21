# Online Kurulum Durumu

Bu belge oyunun çevrim içi altyapısının güncel durumunu ve tam gerçek zamanlı
çok oyunculu için kalan tek adımı özetler. Yalnızca **Supabase** ve **Rivet**
kullanılır; Oracle Cloud / harici allocator / bağımsız VM **kullanılmaz** ve
`tools/validate_online_release.py` bunların varlığını CI'da yasaklar.

## Şu an bağlı ve çalışıyor (Supabase)

`config/backend_config.json` gerçek Colony.io Supabase projesine bağlandı:

- `supabase_url` → proje REST/Auth ucu
- `supabase_publishable_key` → istemci-güvenli yayınlanabilir anahtar (RLS ile
  korunur, gizli/`service_role` anahtar **değildir**)

Bununla birlikte şunlar canlı çalışır:

- Hesap oluşturma / giriş (Supabase Auth)
- Profil, tercihler, puan/lig geçmişi okuma (RLS ile yalnızca kendi verisi)
- Yasal kapı (KVKK/Gizlilik/Kullanım Koşulları/Topluluk Kuralları) yükleme ve
  kabul kaydı
- Devam eden maça yeniden bağlanma oturumu

### Güvenlik (veritabanı açık bırakılmadı)

Canlı veritabanında **tüm public tablolarda RLS açık**. Politikalar erişimi
`auth.uid() = user_id` ile kullanıcının kendi verisiyle sınırlar; maç ve puan
tabloları istemciden yazılamaz (yetkili-sunucu tasarımı). Anonim istemci yalnızca
yayınlanmış/aktif yasal belgeleri okuyabilir. Yayınlanabilir anahtarın istemcide
bulunması bu RLS zorlaması sayesinde güvenlidir.

## Tam gerçek zamanlı çok oyunculu için kalan tek adım (Rivet)

Rivet kontrol düzlemi `colonyio-3bo7` projesinin `staging-4x4s` alanına deploy
edilmiş durumda, ancak iki parça henüz tamamlanmadı:

- **Public REST ingress** — kontrol düzlemine dışarıdan erişilebilir HTTPS
  ucu (`public_rest_ingress_ready: false`)
- **Adanmış oyun sunucusu tahsisi** — `game_server_allocator_ready: false`

Bu ikisi tamamlanmadan gerçek zamanlı eşleştirme yapılamaz. İstemci bu durumu
zarifçe ele alır: `rivet_control_base_url` boşken "ÇOK OYUNCULU OYNA" akışı
"Online için RIVET_CONTROL_BASE_URL gerekli" uyarısı verir, oyun çökmez.

### Gateway hazır olunca etkinleştirme (kod değişikliği gerekmez)

Rivet public gateway URL'si yayınlandığında yalnızca yapılandırmaya yazın:

```bash
python3 tools/configure_online.py \
  --supabase-url https://mlwsxeqorlfgmxqxnfoo.supabase.co \
  --supabase-publishable-key "<publishable_key>" \
  --rivet-control-url https://<public-gateway-host>
```

`configure_online.py` yalnızca istemci-güvenli anahtarları kabul eder; gizli
anahtar yazılmasını reddeder.

## Sırların yönetimi

- Rivet cloud token ve Supabase Personal Access Token **repoda tutulmaz**.
  `validate_online_release.py` `cloud_api_…`, `sbp_…`, `sb_secret_…`
  desenlerini tarar ve bulursa sürümü reddeder.
- Deploy sırlarını yalnızca CI/deploy ortamının gizli değişkenlerinde saklayın.
