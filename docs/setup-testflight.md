# TestFlight kurulumu (Mac olmadan)

**Durum:** 13.11.2026'da kuruldu.

| Kayıt | Değer |
|---|---|
| Bundle ID | `com.vivimap.atlas` |
| App Store Connect uygulaması | "Atlas Navigasyon" |
| Dağıtım sertifikası | 13.11.2027'ye kadar geçerli |
| TestFlight dahili grubu | "Ben" |

İmza dosyaları yalnızca bilgisayarında, `C:\Users\Vivi\atlas-signing` klasöründe ve GitHub Secrets'ta durur; depoya asla girmez (`.gitignore` bunları engelliyor). **Bu klasörü yedekle.**

## Build gönderme

```bash
gh workflow run testflight.yml -R Vivi190/ViviMap
gh run watch -R Vivi190/ViviMap
```

Apple build'i işledikten sonra (genellikle birkaç dakika) iPhone'daki TestFlight uygulamasında görünür. Dahili test için Beta App Review gerekmez.

## GitHub Actions ve açık depo

Depo 14.11.2026'dan beri herkese açık. Önceden özelken macOS dakikaları 10 kat sayılıyordu ve GitHub Free'nin aylık 2.000 dakikası bir gecede doldu. Açık depoda standart runner'lar ücretsiz.

| İş | Süre |
|---|---|
| CI (derleme, birim ve UI testleri) | ~8 dk |
| TestFlight yüklemesi | ~3 dk |

Açık depoda üç kural geçerli:

- **Log'lar herkese açık.** İş akışları gizli bilgi, gizli bilginin uzunluğunu ya da özetini, imza kimliğini (geliştiricinin adı) yazdırmaz. Açılmadan önce eski TestFlight log'ları silindi.
- **Gizli bilgi kodda ya da geçmişte yok.** Anahtarlar ve sertifikalar GitHub Secrets'ta durur. Açmadan önce bütün geçmiş tarandı; commit'lerde yalnızca GitHub'ın noreply e-postası var.
- **HERE verisi depoya konmaz.** Koşulları içeriğini dağıtmayı kısıtlıyor. Test örnekleri sentetik; kaydedilmiş iki HERE yanıtı geçmişten çıkarıldı. OSM verisi ODbL atfıyla serbest.

Geçmişin yeniden yazılmasından önceki commit'ler, eski kimliklerini bilen birine eski Actions koşu sayfalarından ve PR #1'in zaman çizelgesinden bir süre daha görünebilir. Tamamen silinmeleri için GitHub desteğinden önbellek temizliği istenebilir.

## Nasıl kuruldu

Apple'ın web arayüzünde yalnızca iki şey elle yapıldı; geri kalan her şey App Store Connect API üzerinden çalışan [Tools/appstore/provision.mjs](../Tools/appstore/provision.mjs) betiğiyle yapıldı.

1. Anahtar ve CSR bu bilgisayarda üretildi:
   ```bash
   MSYS_NO_PATHCONV=1 openssl req -new -newkey rsa:2048 -nodes -keyout dist.key -out dist.csr -subj "/CN=Atlas Distribution/C=TR"
   ```
2. App Store Connect'te **Users and Access → Integrations → Team Keys** altında "Atlas CI" adında, **Admin** rollü bir API anahtarı oluşturuldu. `.p8` dosyası `atlas-signing` klasörüne kaydedildi.
3. Betik Bundle ID'yi, sertifikayı (CSR'den) ve App Store profilini oluşturdu:
   ```bash
   node Tools/appstore/provision.mjs --key ~/atlas-signing/AuthKey_<KEYID>.p8 --issuer <ISSUER_ID> \
     --csr ~/atlas-signing/dist.csr --out ~/atlas-signing --steps bundle,cert,profile
   ```
4. Web arayüzünde **Apps → New App** ile uygulama kaydı oluşturuldu. Apple bu işlemi API'ye açmıyor.
5. Betik `--steps testflight` ile dahili grubu kurdu ve hesap sahibini gruba ekledi.
6. Sertifika eski algoritmalarla .p12'ye çevrildi ve 6 secret yüklendi:
   - `DIST_P12_BASE64`, `DIST_P12_PASSWORD`
   - `PROFILE_BASE64`
   - `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`

## Canlı trafik anahtarı (isteğe bağlı)

HERE anahtarı yoksa build trafiksiz çıkar ve rota kartı "Trafik dahil değil" der. Anahtarı eklemek için:

1. https://platform.here.com → **Access Manager → Apps → Register new app** → **Credentials → API Keys → Create API key**.
2. Anahtarı GitHub Secret olarak kaydet: `gh secret set HERE_API_KEY -R Vivi190/ViviMap` (komut değeri sorar; koda ve depoya yazılmaz).
3. Yeni bir TestFlight build'i gönder. Anahtar derlemede Info.plist'e girer.

Kota: uygulama her cihazda ayda en fazla 1.200 rota içe aktarma ve 2.400 trafik akışı isteği yapar (HERE'in ücretsiz kotasının yarısından az).

## Yıllık yenileme (sertifika süresi dolunca)

3. adımı ve 6. adımı tekrarla. Yeni bir CSR gerekmez; aynı `dist.csr` kullanılabilir.

## Tuzaklar

- **Windows'taki OpenSSL çıktısı CRLF ile biter.** Parola üretirken `tr -d '\r\n'` kullan. Sondaki görünmez `\r`, .p12'yi şifrelerken parolanın içinde kalıyor; `gh secret set` ise yüklerken onu kırpıyor. Sonuç: CI'da "passphrase not correct" hatası.
- Git Bash'te OpenSSL'e `file:/c/...` biçiminde yol verilemez. Parolayı `env:` veya `stdin` ile geçir.
- Depo herkese açık olduğundan iş akışı log'ları da açıktır. Bu yüzden "Check secrets" adımı yalnızca eksik secret'ları söyler; uzunluk ve özet yazdırmaz. İmza kimliği de, geliştiricinin adını taşıdığı için log'a yazılmaz. Bir secret'tan şüphelenirsen yerelde karşılaştır, log'a yazdırma.
