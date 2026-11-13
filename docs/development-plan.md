# ATLAS — Geliştirme Planı

Her faz bir öncekinin **doğrulanmasından** sonra başlar. "Doğrulama" sütunu, o fazın bitti sayılması için neyin kanıtlanması gerektiğini söyler. Kod yazılmış olması bu kanıt yerine geçmez.

| Faz | İçerik | Doğrulama | Durum |
|---|---|---|---|
| 0 — Araştırma | Depolar, lisanslar, trafik, offline, arama, CarPlay, CI | Rapor + mimari kararlar | ✅ |
| 1 — Temel | Proje yapısı, tasarım sistemi, harita, konum, hız rozeti, CI, TestFlight akışı | CI yeşil; simülatör ekran görüntüleri; **senin iPhone'unda TestFlight kurulumu** | 🟡 CI yeşil (testler + ekran görüntüleri), ilk build TestFlight'a yüklendi (13.11.2026); cihaz testi bekliyor |
| 2 — Navigasyon MVP | Arama (Photon), favoriler, rota (Valhalla: önce FOSSGIS), Ferrostar, Türkçe ses, rotadan sapma, arka plan | 50 adreslik İstanbul arama testi; simüle sürüş testleri; Pendik → Kartal gerçek sürüş (araç dururken etkileşim) | 🟡 Kod + CI tamam: arama, rota, navigasyon, Türkçe ses, arka plan, haritadan seçme, sürüş simülasyonu. Simüle sürüş testleri CI'da geçiyor: gerçek bir Kartal rotasında varış ✅, rotadan sapınca yeniden rota ✅. TestFlight 1.0 (7). Eksik: 50 adreslik arama ölçümü (şimdilik yalnızca Türkçe karakterler ve birkaç tipik sorgu için ön kontrol var) ve **cihazda gerçek sürüş** |
| 3 — Trafik zekâsı | HERE, aday üretimi + puanlama, trafik katmanı, histerezisli rota değiştirme | Aynı sürüşte önerilen ve gerçekleşen süre kaydı; sık sık rota değiştirmenin önlendiğinin testi | 🟡 HERE anahtarı alındı (14.11.2026) ve canlı doğrulandı: gerçek bir Kartal rotası `/v8/import` ile eşleşti (5.169 m; trafikli 480 sn, trafiksiz 458 sn, tipik 453 sn). Kodlananlar: rota kartında trafikli süre ve adayların trafikle sıralanması; navigasyonda 3 dakikada bir trafikli varış ve histerezisli "Daha hızlı rota" önerisi; rota çizgisinin trafiğe göre renklenmesi (koridor akışı); aylık kota bekçisi. **Cihazda yoğun saatte denenmesi gerekiyor** |
| 4 — Offline | PMTiles bölgeleri, Valhalla cihaz içi, FTS5 arama, indirme/devam ettirme, online ↔ offline geçiş | Uçak modunda baştan sona sürüş; bağlantı kesilince navigasyonun devam etmesi | ⏳ |
| 5 — Sürüş zekâsı | Hız sınırı (bilinmiyor/varsayılan ayrımıyla), kasis/tehlike/kamera uyarıları, kullanıcı işaretleri, şerit (veri varsa) | Uyarı zamanlaması testi; karşı yön filtresi; aynı uyarının tekrarlanmaması | 🟡 Kasis ve kamera uyarıları kodlandı: OSM verisi uygulamayla geliyor (İstanbul: 208 kamera, 2.558 kasis; 14.11.2026), internetsiz çalışır. Rota üzerindeki noktalar bulunur (kasis 10 m, kamera 20 m); yönü işli kameralarda ters yön elenir; her nokta bir kez, hıza göre erken söylenir; bantta çip, ayarlarda aç/kapa. Birim testleri: zamanlama, karşı yön, tekrar yok. Kullanıcı işaretleri ✅ (kendi kamera/kasis noktaların; cihazda kalır). Hız sınırı tabelası ✅: yalnızca OSM'de `maxspeed` varsa (Valhalla anotasyonu; Kartal örneğinde 180 segmentin 92'sinde), bilinmiyorsa tabela yok; 5 km/s üstünde hız kırmızı. Şerit: veri yok, çizilmiyor |
| 6 — Premium deneyim | 3D navigasyon kamerası, hıza göre zoom, rota kartları, yatay mod, takip modunda yakınlaştırma | Ekran görüntüsü incelemesi; 60 FPS ölçümü (Instruments, cihazda) | 🟡 3D eğik navigasyon kamerası ✅, konum oku ekranın altında ✅, hıza göre yakınlık ✅ (otoyolda uzak, dönüşte yakın, histerezisli), rotanın tamamını gösterme ✅, ardışık manevra ("Sonra") ✅. Eksik: yatay mod, cihazda 60 FPS ölçümü |
| 7 — İleri özellikler | Live Activity / Dynamic Island, CarPlay (yetki gelirse), sürüş geçmişi, kişisel süre kalibrasyonu | Sürüş verisiyle kalibrasyon raporu | 🟡 Sürüş geçmişi ve kişisel süre kalibrasyonu ✅ (her navigasyonda başlangıçta söylenen ve gerçekleşen süre; trafikli/trafiksiz ayrı ortanca; cihazda kalır). Live Activity / CarPlay: senin kararını bekliyor |
| 8 — Doğrulama | Pil, bellek sızıntısı, uzun sürüş, trafik doğruluğu, arayüz incelemesi | Ölçüm raporu; Google/Yandex karşılaştırması yalnızca ölçülmüş verilerle | ⏳ |

## Faz 2 — TestFlight'ta ne denenecek

Sürüş testlerini **yolcuyken** yap, ya da uygulamayla yalnızca araç dururken etkileşime gir.

0. **Evde deneme (simülasyon):** Harita ayarları → Test → **Sürüş simülasyonu**'nu aç. Bundan sonra rota kartında **Simüle et** düğmesi çıkar:
   - Konum, GPS yerine rota boyunca ilerler. Hız, Valhalla'nın o rota için varsaydığı ortalama hızdır.
   - Talimat bandını, sesli uyarıları ve kamerayı araç kullanmadan görür ve duyarsın.
   - Ekranda her zaman **Simülasyon** etiketi durur.
1. **Arama:** "Ara" alanına bir yer, adres ya da koordinat yaz (örneğin "Kartal Adliyesi", "40.889, 29.19"). Sonuçlar mesafeli ve Türkçe adlı mı?
2. **Haritadan seçme:** haritada bir noktaya uzun bas. Kartta adres çıkıyor mu? "…" menüsünden **Ev olarak kaydet**'e dokun. Sonra "Ara" sayfasında **Kısayollar → Ev**'e tek dokunuş doğrudan rota açmalı.
3. **Rota:** kartta süre, mesafe, varış saati, ana yollar ve varsa alternatifler görünmeli. Canlı trafik (build 10+):
   - Kart önce "Canlı trafik alınıyor…" der, sonra trafikli süreyi ve "Trafik X dk ekliyor" satırını gösterir. Altta "Canlı trafikle · © HERE" yazar.
   - Alternatiflerin süreleri de trafikli olur ve en hızlısı seçili gelir.
   - Yoğun saatte rota çizgisinin yavaş kısımları turuncu, kırmızı ya da koyu kırmızı olur. Gece her şey akıcı olduğu için renk görmezsin; bu doğru davranış.
4. **Navigasyon:** "Başlat"a bas. Şunları kontrol et:
   - Mavi bantta Türkçe talimat ("300 m · Sola dön · Ankara Caddesi") görünüyor mu?
   - Sesli uyarılar zamanında geliyor mu? Şehirde yaklaşık 400 m, 120 m ve dönüşte; hızlı yolda daha erken.
   - Rotadan çıkınca "Yeni rota hesaplanıyor" denip yeni rota çiziliyor mu?
   - Alt çubuk 3 dakikada bir trafikli varış saatine geçer ("Canlı trafikle · © HERE").
   - Belirgin bir kazanç (en az 3 dk ve en az %15) varsa "Daha hızlı rota" bandı çıkar: Geç ya da Kalsın. 20 sn içinde dokunmazsan mevcut rota kalır.
5. **Ekran:** navigasyon sürerken ekran kendiliğinden kararmamalı. Yan tuşla elle kilitlediğinde sesli yönlendirme devam etmeli ve üstte mavi konum göstergesi görünmeli.
6. **Konum oku:** navigasyonda ekranın alt bölümünde durmalı; böylece ilerideki yol görünür. Varışta alt çubukta "Vardın" yazmalı.
7. **Hız göstergesi:** sol altta, araçla tutarlı mı?
8. **Kasis ve kamera uyarıları:** bantta "Kasis · 80 m" ya da "Hız kamerası · 300 m" çipi çıkmalı ve uyarı bir kez seslendirilmeli. Ayarlar → Uyarılar'dan açılıp kapanır.
   - Bölgende OSM'de neredeyse kamera yok (Pendik, Kartal ve Tuzla'da 2 tane). Bildiğin kameraları ve kasisleri kendin işaretle: haritada uzun bas, "…" menüsünden "Kamera işaretle" ya da "Kasis işaretle"yi seç. İşaretler haritada nokta olarak görünür, Ayarlar → Uyarılar → İşaretlerim'den silinir.

**Bilinen sınırlar:**

- Canlı trafik HERE'in ücretsiz kotasıyla sınırlı. Uygulama cihaz başına aylık sınırın altında kalır; sınır dolarsa kart "Trafik alınamadı" der.
- Rota sunucusu FOSSGIS'in ortak sunucusu; arada yavaşlayabilir.
- Şerit bilgisi çoğu yolda yok (OSM'de veri yok; sahte şerit çizilmiyor).
- Adres aramada kapı numarası çoğu yerde bulunmuyor (OSM'de numara verisi az): sokak bulunur. Tam nokta için haritada uzun bas. Türkçe karakterli ve karaktersiz yazım ("çanakkale" / "canakkale") aynı sonucu veriyor (14.11.2026 ölçümü).
- Hız sınırı tabelası yalnızca OSM'de sınırı işli yollarda çıkar (Pendik/Kartal/Tuzla'da yolların %9–16'sı); bilinmeyen yerde tabela gösterilmez.
- Offline çalışmıyor (Faz 4).
- Ses kalitesi cihazdaki Türkçe sese bağlı. Ayarlar → Erişilebilirlik → Seslendirilen İçerik → Sesler → Türkçe yolundan "Geliştirilmiş" sesi indirirsen daha doğal okunur.

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
