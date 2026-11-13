# TestFlight kurulumu (Windows, tek seferlik)

Bu adımları **sen** yapmalısın. Sertifikalar, anahtarlar ve parolalar yalnızca senin bilgisayarında ve GitHub Secrets'ta durur; depoya asla girmez (`.gitignore` bunları engelliyor).
Komutlar **Git Bash** içindir. Dosyaları depo klasörünün dışında, örneğin `~/atlas-signing` altında tut.

## 1. Dağıtım sertifikası (Apple Distribution)

```bash
mkdir -p ~/atlas-signing && cd ~/atlas-signing
# Git Bash "/CN=..." ifadesini dosya yolu sanmasın diye MSYS_NO_PATHCONV kullanılıyor
MSYS_NO_PATHCONV=1 openssl req -new -newkey rsa:2048 -nodes \
  -keyout dist.key -out dist.csr -subj "/CN=Atlas Distribution/C=TR"
```

1. https://developer.apple.com/account/resources/certificates/add adresine git ve **Apple Distribution**'ı seç.
2. `dist.csr` dosyasını yükle ve `distribution.cer` dosyasını indir.
3. Sertifikayı .p12'ye çevir. Eski (3DES/SHA1) algoritmalar şart; OpenSSL 3'ün varsayılan formatını macOS keychain reddedebiliyor:

```bash
openssl x509 -inform DER -in distribution.cer -out dist.pem
openssl pkcs12 -export -inkey dist.key -in dist.pem -out dist.p12 \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
# Burada bir parola belirle; bu parola DIST_P12_PASSWORD olacak.
```

## 2. App ID ve profil

1. **Identifiers → +** yolunu izle, **App IDs → App** seç. Bundle ID'yi **Explicit** olarak gir, örneğin `com.vivimap.atlas`. İstersen kendi ID'ni seç; iş akışı ID'yi profilden okur.
   Faz 1 için ek bir capability gerekmiyor; konum ayarları Info.plist üzerinden yapılıyor.
2. **Profiles → +** yolunu izle, **App Store Connect** seç. Bu App ID'yi ve 1. adımdaki sertifikayı seç, profili `Atlas AppStore` adıyla indir.

## 3. App Store Connect

1. Gerekirse **Agreements** sayfasında güncel sözleşmeleri kabul et.
2. **Apps → +** ile **New App** oluştur: platform iOS, ad (ör. "Atlas Nav"; mağaza adı benzersiz olmalı), dil Türkçe, aynı Bundle ID, SKU olarak herhangi bir değer.
3. **Users and Access → Integrations → App Store Connect API** yolunu izle. **Team Key** oluştur, rolü **App Manager** olsun.
   `.p8` dosyasını indir (yalnızca bir kez indirilebilir). Key ID ve Issuer ID'yi not et.
4. **TestFlight → Internal Testing** altında bir grup oluştur ve kendini ekle.

## 4. GitHub Secrets

Depo klasöründe `gh` ile çalıştır. Değerler doğrudan şifreli olarak yüklenir, ekranda görünmez:

```bash
cd ~/atlas-signing
base64 -w0 dist.p12 | gh secret set DIST_P12_BASE64 -R Vivi190/ViviMap
gh secret set DIST_P12_PASSWORD -R Vivi190/ViviMap          # parolayı yaz, Enter
base64 -w0 "Atlas_AppStore.mobileprovision" | gh secret set PROFILE_BASE64 -R Vivi190/ViviMap
base64 -w0 AuthKey_XXXXXXXXXX.p8 | gh secret set ASC_KEY_P8_BASE64 -R Vivi190/ViviMap
gh secret set ASC_KEY_ID -R Vivi190/ViviMap                 # Key ID
gh secret set ASC_ISSUER_ID -R Vivi190/ViviMap              # Issuer ID
```

## 5. Build gönderme

```bash
gh workflow run testflight.yml -R Vivi190/ViviMap
gh run watch -R Vivi190/ViviMap
```

Apple build'i işledikten sonra TestFlight uygulamasında görünür; işlem genellikle dakikalar sürer. Dahili test için Beta App Review gerekmez.

## Bakım

- Dağıtım sertifikası **1 yıl** geçerli. Süresi dolunca 1. ve 2. adımları tekrarla.
- TestFlight build'leri **90 gün** geçerli.
- `~/atlas-signing` klasörünü yedekle; özellikle `dist.key` ve `.p8` kaybolursa yeniden üretmek gerekir.
