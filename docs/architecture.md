# ATLAS — Mimari Kararlar

Gerekçelerin ve kaynakların ayrıntısı: [research/2026-11-13-faz0-arastirma.md](research/2026-11-13-faz0-arastirma.md).
**Durum** sütunundaki "Onay bekliyor" ibaresi, karar ücretli servis, hesap açma ya da lisans riski içerdiği için senin onayını gerektirdiğini gösterir.

## Karar özeti

| # | Karar | Durum |
|---|---|---|
| ADR-1 | Native Swift 6 + SwiftUI, iOS 17+, yalnızca iPhone | Kabul |
| ADR-2 | Harita: MapLibre Native 7 + swiftui-dsl; karolar OpenFreeMap → kendi PMTiles | Kabul |
| ADR-3 | Navigasyon çekirdeği: Ferrostar; arayüz bizim | Kabul (Faz 2'de uyumluluk testi) |
| ADR-4 | Routing: Valhalla, online ve cihaz içi | Kabul. Önce FOSSGIS, sonra kendi sunucu (onaylandı 13.11.2026) |
| ADR-5 | Rota zekâsı: aday üret → trafikle puanla → histerezisli karar | Kabul. Trafik: HERE (onaylandı 13.11.2026) |
| ADR-6 | Arama: Photon + offline FTS5; Apple araması yok | Kabul |
| ADR-7 | Veri cihazda kalır; analytics yok; anahtarlar kodda değil | Kabul |
| ADR-8 | Derleme: XcodeGen + GitHub Actions; imzalama Windows'ta üretilen .p12 ile | Kabul |
| ADR-9 | Hız kamerası uyarısı | Kabul: uyarılar olacak (senin kararın, 13.11.2026) |

---

## ADR-1 — Native SwiftUI

- **Bağlam:** Mac yok, hedef yalnızca iPhone. CarPlay, Live Activities, CoreLocation ve AVSpeech native API'ler.
- **Karar:**
  - Swift 6 dil modu (tam eşzamanlılık denetimi) ve SwiftUI. Minimum iOS 17; `@Observable`, `CLBackgroundActivitySession` ve `sensoryFeedback` için gerekli.
  - iOS 26'da yüzen harita kontrolleri Liquid Glass kullanıyor, daha eski sürümlerde ince bir materyal.
- **Elenen alternatif:** React Native. Getirdiği Android desteği bu projede bir hedef değil; buna karşılık her native API için köprü yazmak gerekirdi.

## ADR-2 — Harita motoru

- **Karar:**
  - MapLibre Native iOS 7.0 (BSD-2) ve `maplibre/swiftui-dsl` 0.27.0 (BSD-3, tam sürüme sabit).
  - Stiller `Tools/mapstyle/build_styles.py` ile üretiliyor: tek katman tanımı, iki palet (gündüz/gece), OpenMapTiles şeması.
  - Online karo kaynağı OpenFreeMap. Offline için Planetiler aynı şemada PMTiles üretecek (Faz 4), böylece tek stil seti iki kaynakta da çalışacak.
- **Elenen alternatif — Apple MapKit:**
  - Offline harita yok, özel stil yok.
  - DPLA Ek 6 §2.4 Apple verisini yalnızca Apple haritasında gösterme şartı koyuyor.
  - Kendi routing motorumuzla birleştirilemiyor.
- **Sonuçları:**
  - Etiket fontları Noto Sans; harita üzerinde SF Pro kullanmak lisans açısından riskli.
  - 3D binalar varsayılan olarak gizli, 3D modunda açılıyor.

## ADR-3 — Navigasyon çekirdeği: Ferrostar

- **Karar:**
  - Ferrostar Core (rota takibi, adım ilerletme, sapma tespiti, rotaya yapıştırma) kullanılacak.
  - Talimat kartları, hız göstergesi ve kamera davranışı bizim SwiftUI bileşenlerimiz olacak.
  - Türkçe sesli talimat metni manevra verisinden **bizim** tarafımızda üretilecek; Valhalla'nın `tr-TR` çevirisi eksik.
- **Risk:** Ferrostar 0.59 swiftui-dsl 0.26.1 ile test edilmiş; biz 0.27.0 kullanıyoruz. Faz 2'nin ilk adımı CI'da bu ikisinin birlikte derlendiğini doğrulamak; derlenmezse 0.26.1'e sabitlenecek.
- **Elenen alternatif:** Mapbox Navigation SDK. Tescilli; ToS §2.9.1 MapLibre ile kullanımı yasaklıyor.

## ADR-4 — Routing: Valhalla

- **Karar:**
  - Online: Valhalla 3.9.x. Geliştirmede FOSSGIS ya da Stadia'nın ücretsiz planı; kalıcı çözümde kendi sunucumuz.
  - Offline: `valhalla-mobile` (MIT, SwiftPM), Ferrostar'ın `CustomRouteProvider` arayüzü üzerinden.
  - İki taraf da aynı karo build'ini kullanacak; böylece offline'a geçişte rotalar tutarlı kalır.
- **Elenen alternatifler:**
  - OSRM: sesli ve banner talimat üretmiyor.
  - GraphHopper: iOS'ta offline desteklenmiyor.
  - Organic Maps: SDK yok, kütüphane olarak kullanılamaz.

## ADR-5 — Rota zekâsı (projenin farkı)

```
                ┌───────────── RoutingEngine ─────────────┐
 Başla/Bitir ──►│ Aday üretimi (Valhalla, trafiksiz):     │
                │  • varsayılan + 2 alternatif            │
                │  • "Yerel sokaklar" (use_highways↓)     │
                │  • D-100/E-5 koridorundan kaçınma       │
                │    (linear_cost_factors)                │
                │ Tekilleştirme: geometrik örtüşme > %85  │
                │  ise aynı rota sayılır                  │
                └────────────────┬────────────────────────┘
                                 ▼
                ┌───────────── TrafficEngine ─────────────┐
                │ Tüm adaylar TEK sağlayıcıyla puanlanır  │
                │ (HERE import / ara-nokta) → aynı ölçek  │
                │ duration, typicalDuration, baseDuration │
                └────────────────┬────────────────────────┘
                                 ▼
                ┌───────────── Karar katmanı ─────────────┐
                │ skor = süre + belirsizlik payı          │
                │  + dönüş/kavşak/ışık cezası             │
                │ Navigasyonda: kazanç ≥ max(3 dk, %15)   │
                │  ve cooldown ≥ 3 dk; manevraya < 300 m  │
                │  kalmışsa rota değiştirme önerilmez     │
                └─────────────────────────────────────────┘
```

- **Farklı sağlayıcıların süreleri birbiriyle karşılaştırılmaz.** Bütün adaylar aynı trafik sağlayıcısıyla ölçülür.
- **Trafik verisi olmayan ara sokakların hızı uydurulmaz.** Yol sınıfı, ışık ve dönüş sayısı belirsizlik payı olarak skora eklenir.
- Eşik değerleri (3 dk, %15, 300 m) **başlangıç tahminleri**. Faz 8'de gerçek sürüşlerle ayarlanacak.
- "Google veya Yandex'ten daha iyi" iddiası ancak ölçümle yapılabilir. Faz 7, her sürüşte önerilen ve gerçekleşen süreyi kaydedecek.

## ADR-6 — Arama

- **Karar:**
  - Online arama Photon ile yapılır. Geliştirmede public sunucu kullanılır, sonra kendi sunucumuz.
  - Sorguda yer türü kelimesi varsa (durak, istasyon/metro/marmaray, AVM, iskele), kelimesi çıkarılmış ikinci bir istek Photon'un `osm_tag` filtresiyle eşzamanlı gönderilir. Ölçüm: [2026-11-14-arama-olcumu.md](research/2026-11-14-arama-olcumu.md).
  - Adresler mesajda yazıldığı gibi gelir ("Atatürk Cad. No:12 D:5 Kartal/İstanbul"); istekten önce OSM'in yazımına çevrilir (Caddesi, 12; daire/kat atılır). Sıralamada önce sokağı ve numarası tutan yer, sonra o sokak gelir.
  - Yalnızca tür yazılırsa ("benzinlik", "en yakın eczane") metin araması yapılmaz: Photon'un ters araması `osm_tag` filtresiyle en yakınları mesafe sırasıyla verir.
  - Raylı hatlar ve yapım aşamasındaki/planlanan yollar sonuçların sonuna iner.
  - Ters geocoding (haritadan seçme) de Photon ile yapılır; Nominatim kullanılmıyor.
  - Offline: CI'da üretilen SQLite FTS4 indeksi (İstanbul, Türkçe katlama: "çanakkale" = "canakkale"). Photon'a ulaşılamazsa ya da sunucu hata verirse (5xx, 429) devreye girer.
- **Neden Apple araması yok:** DPLA Ek 6 §2.4.
- **Bilinen sınır:** OSM'de kapı numarası kapsaması düşük. Bulunamazsa sokağa düşülür ve sonuç "yaklaşık" olarak gösterilir.

## ADR-7 — Gizlilik ve güvenlik

- Konum geçmişi ve kişisel istatistikler yalnızca cihazda tutulur. Analytics ya da üçüncü taraf takip SDK'sı yok.
- API anahtarları (HERE, Stadia) koda yazılmaz.
  - Derleme sırasında yapılandırmaya eklenir: `HERE_API_KEY` GitHub Secret'ı → derleme ayarı → Info.plist (`HEREAPIKey`).
  - Anahtar uygulama paketinin içinde düz metin olarak durur ve paketi açan biri okuyabilir. Kişisel TestFlight kullanımı için kabul edildi. Uygulama yaygınlaşırsa küçük bir vekil sunucuya taşınır; Keychain bu durumu değiştirmez.
  - Ücretli API'ler için aylık kota bekçisi (`RequestBudget`): her cihazda ücretsiz kotanın yarısının altında durur. Böylece iki telefon aynı anahtarı kullansa bile fatura çıkmaz.
- İmzalama malzemesi yalnızca GitHub Secrets'ta durur ve iş akışı sonunda runner'dan silinir. `.gitignore` bu dosyaları kesin olarak dışarıda tutar.
- Offline paketler (Faz 4) SHA-256 ile doğrulanır.

## ADR-8 — Derleme ve dağıtım

- **XcodeGen:** `project.yml` dosyasından `.xcodeproj` üretilir; `.xcodeproj` depoya girmez.
- **CI (`ci.yml`):** her push'ta derleme, birim testleri ve simülatörde gündüz/gece ekran görüntüsü. Görüntüler artifact olarak saklanır.
- **TestFlight (`testflight.yml`):** yalnızca elle tetiklenir. Manuel imzalama, `xcodebuild -exportArchive` ile `destination=upload`.

## ADR-9 — Hız kamerası uyarısı

- **Karar (13.11.2026):** Kamera uyarıları olacak.
- **Veri kaynakları:**
  - OSM `highway=speed_camera`: İstanbul'da 184 nokta, Pendik'te 1 nokta.
  - Resmi sabit EDS noktaları, makine tarafından okunabilir bir kaynak bulunursa.
  - Senin işaretlediğin noktalar.
- **Bilinen risk:** KTK md. 51 (7574 sayılı kanun) radar tespit/ikaz *cihazlarını* yasaklıyor; telefon uygulamasının bu kapsamda olup olmadığı tartışmalı. Kararı verdin; bu not yalnızca kayıt için.

---

## Modül haritası

Her modül `Packages/AtlasKit` içinde bir hedef olarak yaşar. Sağlayıcıya bağlı her şey bir protokolün arkasında durur; sağlayıcı değişirse yalnızca o adaptör değişir.

| Modül | Sorumluluk | Faz | Durum |
|---|---|---|---|
| AppCore | Ayarlar, güneş hesabı, ortak tipler | 1 | ✅ |
| DesignSystem | Renk/aralık token'ları, yüzen kontroller, hız rozeti | 1 | ✅ |
| MapEngine | MapLibre görünümü, stiller, kamera takibi, atıf | 1 | ✅ |
| LocationEngine | CoreLocation, hız tahmini, GPS kalitesi | 1 | ✅ (map matching Faz 2) |
| Diagnostics | Canlı GPS tanılama ekranı | 1 | ✅ |
| SearchEngine | Photon arama ve ters arama, tür kelimesi için filtreli ikinci istek, adres yazımı, tek başına tür için en yakınlar; çevrimdışı İstanbul dizini (FTS4) | 2 / 4 | ✅ ölçüm: ilk sonuç 64/64, mesajda yazıldığı gibi 7 adres dahil (14.11.2026) |
| RoutingEngine | Valhalla: FOSSGIS online, cihaz içi Valhalla 3.9.0 (çevrimdışı yedek), aday üretimi | 2 / 3 / 4 | ✅ |
| NavigationEngine | Ferrostar sarmalayıcı, rota takibi, yeniden rota, Türkçe talimat ve ses, kasis/kamera uyarıları, hız sınırı, hıza göre yakınlık, yola oturtulmuş konum oku, dönüş oku, şu anki yol | 2 / 3 / 5 / 6 | ✅ |
| VoiceGuidance | Türkçe talimat üretimi, AVSpeech, ses oturumu | 2 | ✅ NavigationEngine içinde (TurkishInstructions, VoiceGuide) |
| TrafficEngine | `TrafficProvider` (HERE): rota süreleri, rota boyunca akış (rota renkleri), alan akışı (şehir trafik katmanı), histerezisli öneri, ayrı aylık kotalar | 3 | ✅ |
| OfflineEngine | Bölge paketleri, indirme/devam ettirme, bütünlük | 4 | Ayrı modül yok: tek bölge build'e gömülü (OfflineRouter, OfflineMap, OfflinePlaceIndex) |
| RoadHazards | Kasis/kamera verisi, kullanıcı işaretleri, uyarı zamanlaması | 5 | ✅ |
| TripHistory | Sürüş kayıtları, süre kalibrasyonu | 6 / 7 | ✅ |
| NavigationActivity | Live Activity içeriği (uygulama ve widget uzantısı paylaşır) | 7 | ✅ |
| Settings | Ayarlar ekranları (AppCore + harita sayfası) | 2+ | ✅ görünüm, uyarılar, işaretler, sürüşler, test |
