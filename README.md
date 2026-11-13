# ATLAS

İstanbul odaklı, kişisel kullanım için iOS navigasyon uygulaması. Geçici adı ATLAS.
Yığın: native SwiftUI + MapLibre; Ferrostar/Valhalla tabanlı rota motoru (Faz 2+); offline-first.

**Durum:** Faz 2 (navigasyon MVP) kodlandı ve CI'da uçtan uca test edildi:
- Arama (Photon) ve haritadan seçme
- Ev/İş kısayolları
- Rota (Valhalla, alternatiflerle)
- Ferrostar ile adım adım navigasyon, Türkçe sesli yönlendirme ve ekran kilitliyken devam

Sırada cihazda sürüş testi var. Canlı trafik, offline ve yol uyarıları sonraki fazlarda.
Ayrıntılar: [docs/development-plan.md](docs/development-plan.md).

## Dokümanlar

- [Faz 0 araştırma raporu](docs/research/2026-11-13-faz0-arastirma.md)
- [Mimari kararlar ve modül haritası](docs/architecture.md)
- [Geliştirme planı](docs/development-plan.md)
- [TestFlight kurulumu (Windows)](docs/setup-testflight.md)

## Yapı

```
App/                    iOS uygulama hedefi (ekranlar, varlıklar, UI testleri)
Packages/AtlasKit/      Modüller: AppCore, DesignSystem, LocationEngine, MapEngine, Diagnostics
Tools/mapstyle/         Gündüz/gece harita stillerini üreten betik
Tools/appicon/          Uygulama ikonunu üreten betik
project.yml             XcodeGen tanımı (.xcodeproj üretilir, depoya girmez)
.github/workflows/      ci.yml (her push), testflight.yml (elle)
```

## Derleme

Mac gerekmez; derlemeyi GitHub Actions yapar:

- `main`'e her push'ta derleme, birim testleri ve simülatörde gündüz/gece ekran görüntüleri üretilir. Görüntüler **Actions → çalıştırma → Artifacts** altındadır.
- TestFlight: `gh workflow run testflight.yml` (önce [kurulum](docs/setup-testflight.md)).

Stil ya da ikonu değiştirdikten sonra şunları çalıştır:

```bash
python Tools/mapstyle/build_styles.py
python Tools/appicon/make_icon.py
```

## Atıf

Harita verisi © OpenStreetMap katkıcıları (ODbL), © OpenMapTiles; karolar OpenFreeMap.
