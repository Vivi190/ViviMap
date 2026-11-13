# ATLAS — Mimari Kararlar

Gerekçelerin ve kaynakların ayrıntısı: [research/2026-11-13-faz0-arastirma.md](research/2026-11-13-faz0-arastirma.md).
**Durum** sütunundaki "Onay bekliyor" ibaresi, karar ücretli servis, hesap açma ya da lisans riski içerdiği için senin onayını gerektirdiğini gösterir.

## Karar özeti

| # | Karar | Durum |
|---|---|---|
| ADR-1 | Native Swift 6 + SwiftUI, iOS 17+, yalnızca iPhone | Kabul |
| ADR-2 | Harita: MapLibre Native 7 + swiftui-dsl; karolar OpenFreeMap → kendi PMTiles | Kabul |
| ADR-3 | Navigasyon çekirdeği: Ferrostar; arayüz bizim | Kabul (Faz 2'de uyumluluk testi) |
| ADR-4 | Routing: Valhalla, online ve cihaz içi | Kabul. Online barındırma **onay bekliyor** |
| ADR-5 | Rota zekâsı: aday üret → trafikle puanla → histerezisli karar | Kabul. Sağlayıcı (HERE) **onay bekliyor** |
| ADR-6 | Arama: Photon + offline FTS5; Apple araması yok | Kabul |
| ADR-7 | Veri cihazda kalır; analytics yok; anahtarlar kodda değil | Kabul |
| ADR-8 | Derleme: XcodeGen + GitHub Actions; imzalama Windows'ta üretilen .p12 ile | Kabul |
| ADR-9 | Hız kamerası uyarısı | **Onay bekliyor** (hukuki gri alan) |

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
  - Ters geocoding Nominatim ile yapılır; saniyede en fazla 1 istek, autocomplete yok.
  - Offline: CI'da üretilen SQLite FTS5 indeksi; Türkçe kısaltmalar eşanlamlı olarak eklenir.
- **Neden Apple araması yok:** DPLA Ek 6 §2.4.
- **Bilinen sınır:** OSM'de kapı numarası kapsaması düşük. Bulunamazsa sokağa düşülür ve sonuç "yaklaşık" olarak gösterilir.

## ADR-7 — Gizlilik ve güvenlik

- Konum geçmişi ve kişisel istatistikler yalnızca cihazda tutulur. Analytics ya da üçüncü taraf takip SDK'sı yok.
- API anahtarları (HERE, Stadia) koda yazılmaz.
  - Derleme sırasında yapılandırmaya eklenir, cihazda Keychain'de tutulur.
  - Mümkün olan yerlerde kendi küçük vekil sunucumuz kullanılır.
- İmzalama malzemesi yalnızca GitHub Secrets'ta durur ve iş akışı sonunda runner'dan silinir. `.gitignore` bu dosyaları kesin olarak dışarıda tutar.
- Offline paketler (Faz 4) SHA-256 ile doğrulanır.

## ADR-8 — Derleme ve dağıtım

- **XcodeGen:** `project.yml` dosyasından `.xcodeproj` üretilir; `.xcodeproj` depoya girmez.
- **CI (`ci.yml`):** her push'ta derleme, birim testleri ve simülatörde gündüz/gece ekran görüntüsü. Görüntüler artifact olarak saklanır.
- **TestFlight (`testflight.yml`):** yalnızca elle tetiklenir. Manuel imzalama, `xcodebuild -exportArchive` ile `destination=upload`.

## ADR-9 — Hız kamerası uyarısı (onay bekliyor)

- KTK md. 51, radar tespit/ikaz *cihazlarını* yasaklıyor; uygulamaların durumu belirsiz.
- Öneri: kasis ve tehlike uyarıları serbest. Kamera uyarısı yalnızca senin açık onayınla, yalnızca resmi sabit noktalar ve senin işaretlediğin noktalar için.

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
| SearchEngine | `SearchProvider`: Photon, Nominatim, FTS5 | 2 / 4 | — |
| RoutingEngine | `RouteProvider`: Valhalla online/offline, aday üretimi | 2 / 3 / 4 | — |
| NavigationEngine | Ferrostar sarmalayıcı, rota takibi, rota değiştirme kararı | 2 / 3 | — |
| VoiceGuidance | Türkçe talimat üretimi, AVSpeech, ses oturumu | 2 | — |
| TrafficEngine | `TrafficProvider`: HERE, trafik katmanı | 3 | — |
| OfflineEngine | Bölge paketleri, indirme/devam ettirme, bütünlük | 4 | — |
| RoadHazards | Kasis/kamera/tehlike verisi, kullanıcı işaretleri, uyarı zamanlaması | 5 | — |
| TripHistory | Sürüş kayıtları, süre kalibrasyonu | 6 / 7 | — |
| Settings | Ayarlar ekranları (şimdilik AppCore + harita sayfası) | 2+ | — |
