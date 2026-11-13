# ATLAS — Geliştirme Planı

Her faz bir öncekinin **doğrulanmasından** sonra başlar. "Doğrulama" sütunu, o fazın bitti sayılması için neyin kanıtlanması gerektiğini söyler. Kod yazılmış olması bu kanıt yerine geçmez.

| Faz | İçerik | Doğrulama | Durum |
|---|---|---|---|
| 0 — Araştırma | Depolar, lisanslar, trafik, offline, arama, CarPlay, CI | Rapor + mimari kararlar | ✅ |
| 1 — Temel | Proje yapısı, tasarım sistemi, harita, konum, hız rozeti, CI, TestFlight akışı | CI yeşil; simülatör ekran görüntüleri; **senin iPhone'unda TestFlight kurulumu** | 🟡 CI yeşil (testler + ekran görüntüleri), ilk build TestFlight'a yüklendi (13.11.2026); cihaz testi bekliyor |
| 2 — Navigasyon MVP | Arama (Photon), favoriler, rota (Valhalla: önce FOSSGIS), Ferrostar, Türkçe ses, rotadan sapma, arka plan | 50 adreslik İstanbul arama testi; simüle sürüş testleri; Pendik → Kartal gerçek sürüş (araç dururken etkileşim) | 🟡 Arama ✅, rota önizleme ✅ (CI'da canlı Photon + FOSSGIS Valhalla testi, 3 alternatif); Ev/İş ✅; navigasyon + Türkçe ses + arka plan kodlandı, CI'da |
| 3 — Trafik zekâsı | HERE, aday üretimi + puanlama, trafik katmanı, histerezisli rota değiştirme | Aynı sürüşte önerilen ve gerçekleşen süre kaydı; sık sık rota değiştirmenin önlendiğinin testi | ⏳ HERE hesabı ve anahtarı gerekiyor |
| 4 — Offline | PMTiles bölgeleri, Valhalla cihaz içi, FTS5 arama, indirme/devam ettirme, online ↔ offline geçiş | Uçak modunda baştan sona sürüş; bağlantı kesilince navigasyonun devam etmesi | ⏳ |
| 5 — Sürüş zekâsı | Hız sınırı (bilinmiyor/varsayılan ayrımıyla), kasis/tehlike/kamera uyarıları, kullanıcı işaretleri, şerit (veri varsa) | Uyarı zamanlaması testi; karşı yön filtresi; aynı uyarının tekrarlanmaması | ⏳ |
| 6 — Premium deneyim | 3D navigasyon kamerası, hıza göre zoom, rota kartları, yatay mod, takip modunda yakınlaştırma | Ekran görüntüsü incelemesi; 60 FPS ölçümü (Instruments, cihazda) | ⏳ |
| 7 — İleri özellikler | Live Activity / Dynamic Island, CarPlay (yetki gelirse), sürüş geçmişi, kişisel süre kalibrasyonu | Sürüş verisiyle kalibrasyon raporu | ⏳ |
| 8 — Doğrulama | Pil, bellek sızıntısı, uzun sürüş, trafik doğruluğu, arayüz incelemesi | Ölçüm raporu; Google/Yandex karşılaştırması yalnızca ölçülmüş verilerle | ⏳ |

## Faz 1 — çalışan özellikler ve eksikler

### Kodda hazır olanlar (CI ile doğrulanacak)

- **Harita:**
  - Tam ekran MapLibre haritası; özgün gündüz ve gece stilleri; Türkçe etiketler.
  - 2D/3D geçişi (3D binalarla).
  - Pusula: harita döndürülünce görünür, dokununca kuzeyi yukarı alır.
  - Atıf sayfası.
- **Konum takibi:**
  - Konum noktası ve yön göstergesi.
  - Takip modları: serbest → takip → yön takibi. Hızın 15 km/sa'nin altında veya üstünde olmasına göre pusula yönü ya da GPS rotası kullanılıyor.
- **Hız göstergesi:**
  - Hafif yumuşatma.
  - Dururken titremeyi önleyen histerezis.
  - Düşük doğrulukta soluk gösterim.
  - GPS kesilirse 4 saniye sonra "–" gösterimi.
- **Durum çipleri:** konum izni kapalı; yaklaşık konum; GPS zayıf/yok.
- **GPS tanılama ekranı:** doğruluk, hız doğruluğu, güncelleme aralığı, konum yaşı.
- **Gece/gündüz:** "Otomatik" modu bulunduğun yerde güneşin konumuna göre geçiş yapar; gündüz ve gece sabitlenebilir.
- **Birim testleri:** hız tahmini, GPS kalitesi, güneş hesabı (güneş hesabı Python'a birebir aktarılarak ayrıca doğrulandı).
- **CI'da UI testi:** simülatörde Kartal'da gündüz ve gece ekran görüntüsü.

### Bilinçli olarak eksik bırakılanlar

Hiçbiri arayüzde gösterilmiyor.

- Arama, rota ve ses (Faz 2).
- Arka planda konum: Faz 1 uygulama arka plana geçince GPS'i kapatıyor.
- Hız sınırı (veri Faz 5'te).
- Harita jestinin kamera takibini bırakması: swiftui-dsl'in mevcut davranışı, Faz 6'da iyileştirilecek.
- Yatay mod.

### Cihazda doğrulaman gerekenler

Bunları ben ölçemiyorum.

1. Uygulama açılıyor mu, harita yükleniyor mu?
2. Konum noktası doğru yerde mi? Yön oku doğru dönüyor mu?
3. Araçta yolcuyken: hız rozeti aracın hızıyla tutarlı mı, dururken 0'da sabit kalıyor mu?
4. Tünelde (örneğin Kartal–Pendik arası tüneller) "–" ve "GPS sinyali yok" görünüyor mu?
5. Akşam gün batımından sonra harita kendiliğinden gece moduna geçiyor mu?
