# ATLAS — Geliştirme Planı

Her faz bir öncekinin **doğrulanmasından** sonra başlar. "Doğrulama" sütunu, o fazın bitti sayılması için neyin kanıtlanması gerektiğini söyler. Kod yazılmış olması bu kanıt yerine geçmez.

| Faz | İçerik | Doğrulama | Durum |
|---|---|---|---|
| 0 — Araştırma | Depolar, lisanslar, trafik, offline, arama, CarPlay, CI | Rapor + mimari kararlar | ✅ |
| 1 — Temel | Proje yapısı, tasarım sistemi, harita, konum, hız rozeti, CI, TestFlight akışı | CI yeşil; simülatör ekran görüntüleri; **senin iPhone'unda TestFlight kurulumu** | 🟡 CI yeşil (testler + ekran görüntüleri), ilk build TestFlight'a yüklendi (13.11.2026); cihaz testi bekliyor |
| 2 — Navigasyon MVP | Arama (Photon), favoriler, rota (Valhalla: önce FOSSGIS), Ferrostar, Türkçe ses, rotadan sapma, arka plan | 50 adreslik İstanbul arama testi; simüle sürüş testleri; Pendik → Kartal gerçek sürüş (araç dururken etkileşim) | 🟡 Kod + CI tamam: arama, rota, navigasyon, Türkçe ses, arka plan, haritadan seçme, sürüş simülasyonu. Simüle sürüş testleri CI'da geçiyor: gerçek bir Kartal rotasında varış ✅, rotadan sapınca yeniden rota ✅. TestFlight 1.0 (7). Arama ölçümü ✅ ([rapor](research/2026-11-14-arama-olcumu.md)): önce ilk sonuç 49 sorgunun 44'ünde doğruydu. Kaçanlar istasyon, AVM, durak ve iskeleydi; bunlar için tür kelimesi artık ayrı, filtreli bir istekle aranıyor. Sonra 57/57 doğru; bunun içinde düzeltmeyi tasarlarken bakılmamış 8 sorgunun 8'i de var. Mesajda yazıldığı gibi adresler ("Sanayi Cad. No:1 Kartal") eski kurallarla 7'de 1 doğruydu, düzeltmeden sonra 7/7; toplam 64/64. Yalnızca tür yazılan sorgular ("benzinlik", "eczane") en yakınları listeler. Eksik: **cihazda gerçek sürüş** |
| 3 — Trafik zekâsı | HERE, aday üretimi + puanlama, trafik katmanı, histerezisli rota değiştirme | Aynı sürüşte önerilen ve gerçekleşen süre kaydı; sık sık rota değiştirmenin önlendiğinin testi | 🟡 HERE anahtarı alındı (14.11.2026) ve canlı doğrulandı: gerçek bir Kartal rotası `/v8/import` ile eşleşti (5.169 m; trafikli 480 sn, trafiksiz 458 sn, tipik 453 sn). Kodlananlar: rota kartında trafikli süre ve adayların trafikle sıralanması; navigasyonda 3 dakikada bir trafikli varış ve histerezisli "Daha hızlı rota" önerisi; rota çizgisinin trafiğe göre renklenmesi (koridor akışı); aylık kota bekçisi. Ücretli yollardan kaçınma (`next` dalı, derlenmedi): canlı ölçümde Kadıköy → Beşiktaş varsayılan rotası ücretli kesimden geçiyor; `exclude_tolls` ile Harem–Sirkeci araba vapuru. Kartta "Ücretli geçiş var" ve "Feribotla geçiş" uyarısı. Şehir trafik katmanı ✅ (haritadaki "Trafik" düğmesi): ekrandaki bölgede yavaş, yoğun ve duran yollar, her yön kendi şeridinde; harita durunca yüklenir, 3 dakikada bir tazelenir; geniş görünümde yalnızca ana yollar; ayrı aylık kota (600), rota trafiğinden yemez. Canlı ölçüm (14.11.2026): filtresiz 0,10° × 0,07° Kartal kutusu 1,7 MB, filtreyle 11 KB. **Cihazda yoğun saatte denenmesi gerekiyor** |
| 4 — Offline | PMTiles bölgeleri, Valhalla cihaz içi, FTS5 arama, indirme/devam ettirme, online ↔ offline geçiş | Uçak modunda baştan sona sürüş; bağlantı kesilince navigasyonun devam etmesi | 🟡 Rota: cihaz içi Valhalla 3.9.0 (Rallista/valhalla-mobile, MIT) bağlandı; internet yoksa ya da sunucu çökmüşse planlama ve navigasyon içi yeniden rota aynı isteği cihazda çözer, kart "Çevrimdışı rota" der. Veri: İstanbul kutusu, CI'da üretilip TestFlight build'ine gömülür (ölçüm 14.11.2026: rota tile'ları 108 MB, harita PMTiles 50 MB). Bölge indirme ve kaldığı yerden devam yok, bilinçli olarak: tek bölge var ve uygulama kurulduğu andan itibaren internetsiz çalışır; veri yeni build'le tazelenir. Harita: bağlantı yokken pakete gömülü İstanbul PMTiles + yerel fontlar ✅. Arama: Photon'a ulaşılamazsa cihazdaki İstanbul dizini (SQLite FTS4, Türkçe katlama) ✅. Kalan: **uçak modunda gerçek sürüş testi** (cihazda) |
| 5 — Sürüş zekâsı | Hız sınırı (bilinmiyor/varsayılan ayrımıyla), kasis/tehlike/kamera uyarıları, kullanıcı işaretleri, şerit (veri varsa) | Uyarı zamanlaması testi; karşı yön filtresi; aynı uyarının tekrarlanmaması | 🟡 Kasis ve kamera uyarıları kodlandı: OSM verisi uygulamayla geliyor (İstanbul: 208 kamera, 2.558 kasis; 14.11.2026), internetsiz çalışır. Rota üzerindeki noktalar bulunur (kasis 10 m, kamera 20 m); yönü işli kameralarda ters yön elenir; her nokta bir kez, hıza göre erken söylenir; bantta çip, ayarlarda aç/kapa. Birim testleri: zamanlama, karşı yön, tekrar yok. Kullanıcı işaretleri ✅ (kendi kamera/kasis noktaların; cihazda kalır). Hız sınırı tabelası ✅: yalnızca OSM'de `maxspeed` varsa (Valhalla anotasyonu; Kartal örneğinde 180 segmentin 92'sinde), bilinmiyorsa tabela yok; 5 km/s üstünde hız kırmızı. Sesli hız sınırı uyarısı (`next` dalı, derlenmedi): sınırın hem %10 hem 6 km/sa üstünde 3 sn kalınca "Hız sınırı 50.", en erken dakikada bir. Şerit: veri varsa bantta gösterilir, ama veri yok denecek kadar az (ölçüm 14.11.2026: Kartal → Kadıköy D-100 rotasında 288 kavşağın 1'inde, Pendik → Ataşehir TEM rotasında 271 kavşağın 1'inde şerit verisi var) |
| 6 — Premium deneyim | 3D navigasyon kamerası, hıza göre zoom, rota kartları, yatay mod, takip modunda yakınlaştırma | Ekran görüntüsü incelemesi; 60 FPS ölçümü (Instruments, cihazda) | 🟡 3D eğik navigasyon kamerası ✅ (binalar navigasyonda düz: yüksek 3D binalar dar sokakta rotayı örtüyordu, ekran görüntüsü incelemesi 14.11.2026), konum oku ekranın altında ✅, hıza göre yakınlık ✅ (otoyolda uzak, dönüşte yakın, histerezisli), rotanın tamamını gösterme ✅, ardışık manevra ("Sonra") ✅, yatay mod ✅ (araç tutucusu için paneller solda, harita sağda; CI'da ekran görüntüsü). Eksik: cihazda 60 FPS ölçümü |
| 7 — İleri özellikler | Live Activity / Dynamic Island, CarPlay (yetki gelirse), sürüş geçmişi, kişisel süre kalibrasyonu | Sürüş verisiyle kalibrasyon raporu | 🟡 Sürüş geçmişi ve kişisel süre kalibrasyonu ✅ (her navigasyonda başlangıçta söylenen ve gerçekleşen süre; trafikli/trafiksiz ayrı ortanca; cihazda kalır). Live Activity ✅ (kilit ekranı, Dynamic Island; iOS 26'da CarPlay ana ekranında da görünür, CarPlay navigasyon yetkisi gerekmez): sonraki manevra, mesafe, yol, varış; ayrı bundle ID `com.vivimap.atlas.widgets` + profil (API ile). Güncellemeler doğrudan navigasyon motorundan gelir, ekran kilitliyken arayüzün yenilenmesini beklemez; varış saati de motordan alınır, kilitliyken varılınca sürüş süresi uzamaz. Tam CarPlay navigasyonu Apple yetkisi ister (kişisel uygulamaya verilme ihtimali düşük). `next` dalında kodlandı, henüz derlenip test edilmedi (CI kotası): varışımı paylaş, Siri ve Kestirmeler'den "eve git" / "işe git" |
| 8 — Doğrulama | Pil, bellek sızıntısı, uzun sürüş, trafik doğruluğu, arayüz incelemesi | Ölçüm raporu; Google/Yandex karşılaştırması yalnızca ölçülmüş verilerle | 🟡 Arayüz incelemesi CI ekran görüntüleriyle (14.11.2026; gündüz, gece, yatay, ayarlar, Sürüşlerim): 5 kusur bulundu ve düzeltildi. (1) Navigasyonda rota 3D binaların arkasında kalabiliyordu, binalar artık düz. (2) Yatayda konum oku sol panelin altına düşüyordu. (3) Navigasyon başında kamera önizleme merkezinde kalıyordu. (4) Alternatif rotalar haritada yoktu. (5) OSM'deki 'Canakkale' yazımı karta yansıyordu. Aynı gün ikinci inceleme (arama sayfası, dönüş oku, rota kartı): 3 kusur daha düzeltildi. (6) Sürüşten sonra arama eski sorguyla açılıyordu, son aramalar görünmüyordu. (7) Göbekte dönüş okunun ucu göbeğin içini gösteriyordu, artık çıkış yolunu gösteriyor. (8) Rota kartında alternatifler süreye göre sıralı değildi. Uzun sürüş CI testi: Pendik → Kadıköy (18 km+), varış ✅, yeniden rota yok ✅, ikinci yarıda tepe bellek büyümesi < 8 MB ✅. Cihazda kalan: pil, 60 FPS, gerçek trafikte süre doğruluğu (Sürüşlerim'deki kalibrasyon) |

## TestFlight'ta ne denenecek

**Son yüklenen: build 23 (14.11.2026, işlendi).** Depo herkese açık olduğu için GitHub Actions dakikaları artık ücretsiz ([setup-testflight.md](setup-testflight.md#github-actions-ve-açık-depo)).
- Build 17: trafik katmanı, tür kelimeli arama düzeltmesi.
- Build 18: ücretli yollardan kaçınma, varışımı paylaş, Siri kısayolu, hız sınırı uyarısı, "Yakında" düğmeleri.
- Build 19: yenilenen rota kartı ve navigasyon alt çubuğu, havalimanı/hastane/AVM rotalarının alanın önündeki yolda bitmesi, telefondaki en kaliteli Türkçe ses, navigasyonda yumuşak yakınlaşma.
- Build 20: mesajda yazıldığı gibi adres arama, yalnızca tür yazınca en yakınlar ("benzinlik", çevrimdışı da), "… otopark" araması, rota kartında alternatiflerin süreye göre sıralanması, navigasyonda yola oturtulmuş konum oku, rota üzerinde dönüş oku, alt çubuğun üstünde şu anki yolun adı, haritaya bakıldıktan sonra görünümün kendiliğinden araca dönmesi, hedefin yakınındaki otoparklar, çevrimdışı "sokak + ilçe" araması, Photon sunucusu çökünce aramanın cihazdaki dizine geçmesi, arama hatasında nedenin doğru söylenmesi.
- Build 21: yerle işi bitince aramanın baştan (son aramalar, kısayollar, "Yakında") açılması, göbekte dönüş okunun çıkış yoluna kadar uzaması, kayıtlıysa "Ev" ve "İş"in arama çubuğunun altında tek dokunuşla rota açması.
- Build 22: varışta alt çubukta "Otopark" düğmesi, ayarlarda sesli yönlendirme için "Örnek dinle", arama çubuğunda "Nereye?".
- Build 23: "semt + tür" ("esentepe eczane") ve "semt + marka" ("kurtköy migros") aramalarının o semtin çevresinde yapılması.

Sıradaki build'de gelecekler: şimdilik yok (main'deki her şey build 23'te).

"Sıradaki build" yazan maddeler o build'le gelir.

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
9. **Trafik katmanı (build 17+):** sağdaki düğmelerden arabalı simgeye (Trafik) dokun. Harita durunca bir saniye içinde yavaş yollar turuncu, yoğunlar kırmızı, duranlar koyu kırmızı çizilir. Gece neredeyse hiç renk çıkmaz; bu doğru. Sağ altta "© OpenStreetMap · HERE" yazar.
10. **Çevrimdışı (build 12+):** uçak modunu aç, uygulamayı aç.
   - Üstte "İnternet yok · İstanbul çevrimdışı" çipi çıkmalı ve harita cihazdaki İstanbul paketinden gelmeli.
   - Arama cihazdaki dizinden sonuç vermeli.
   - Rota kartında "Çevrimdışı rota · cihazdaki İstanbul verisiyle, trafiksiz" yazmalı.
   - Navigasyonda rotadan çıkınca yeni rota yine cihazda hesaplanmalı.
11. **Kilit ekranı (build 14+):** navigasyonu başlatıp telefonu kilitle. Kilit ekranında sonraki manevra, mesafe ve varış saati görünmeli; Dynamic Island'lı iPhone'da üstte de görünür. iOS 26'da CarPlay'e bağlıysan CarPlay ana ekranında da çıkar. Görünmüyorsa Ayarlar → Atlas → Canlı Etkinlikler açık olmalı.
12. **Ücretli yollardan kaçınma (build 18+):** Harita ayarları → Rota → "Ücretli yollardan kaçın". Kadıköy'den Beşiktaş'a rota iste: araba vapuruyla (Harem–Sirkeci) gitmeli, kartta "Feribotla geçiş · Ücretli yollardan kaçınıldı" yazmalı. Ayar kapalıyken köprülü rotada "Ücretli geçiş var" yazmalı.
13. **Varışımı paylaş (build 18+):** navigasyonda sağdaki düğmelerin en altındaki paylaş simgesi. Mesajda tahmini varış saati, hedef ve harita bağlantısı olmalı.
14. **Siri (build 18+):** önce bir yeri Ev olarak kaydet. Sonra "Hey Siri, Atlas ile eve git" de: uygulama açılmalı ve eve rota kartı gelmeli. Kestirmeler uygulamasında da "Eve git" ve "İşe git" çıkar.
15. **Hız sınırı uyarısı (build 18+):** tabelası işli bir yolda sınırın belirgin üstüne çıkarsan (50'lik yolda 57+) 3 saniye sonra "Hız sınırı 50." denmeli, sonra en erken bir dakika sonra yine. Ayarlar → Uyarılar'dan kapanır. Bunu yolcuyken ya da simülasyonla dene.
16. **Yakında (build 18+):** Ara sayfasında, yazmadan önce "Yakında" altında Benzinlik, Otopark, Eczane ve Şarj düğmeleri çıkar. Birine dokun: en yakın olanlar mesafeleriyle listelenmeli. Uçak modunda da çalışmalı.
17. **Büyük alanlar (build 19+):** "Sabiha Gökçen Havalimanı", bir hastane ya da AVM'ye rota iste. Rota alanın ortasında değil, önündeki yolda bitmeli.
18. **Ses (build 19+):** Harita ayarları → Sesli yönlendirme, kullanılan Türkçe sesi ve kalitesini gösterir. "Geliştirilmiş" bir ses indirirsen Atlas kendiliğinden onu kullanır. Build 22'den itibaren aynı yerde "Örnek dinle" var: bir talimatı navigasyondaki gibi okur.
19. **Adres (build 20+):** bir adresi mesajda yazıldığı gibi yapıştır, örneğin "Sanayi Cad. No:1 Kartal" ya da "Yakacık Mah. Atatürk Cad. No:12 D:5 Kartal/İstanbul". İlk sonuç o adresteki yer olmalı; numarası OSM'de yoksa o sokak.
20. **En yakınlar (build 20+):** yalnızca "benzinlik", "eczane", "market", "hastane", "otopark" ya da "en yakın ATM" yaz. En yakınlar mesafeleriyle listelenmeli.
21. **Konum oku, dönüş oku, yol adı (build 20+):** navigasyonda konum oku binaların arasında da mavi çizginin üstünde kalmalı; rotadan gerçekten çıkınca çizgiden ayrılır ve yeni rota hesaplanır. Bir sonraki dönüş, rotanın üstünde beyaz bir okla görünmeli; göbekte ok çıkışa kadar uzanır. Alt çubuğun hemen üstünde, o an üzerinde olduğun yolun adı yazmalı. Haritayı elle kaydırır ya da "Rotanın tamamı"na dokunursan, 12 saniye sonra görünüm kendiliğinden araca dönmeli.
22. **Hedefin yakınındaki otoparklar (build 20+):** bir yeri seç, kartın "…" menüsünden "Yakındaki otoparklar"a dokun. O yerin çevresindeki otoparklar, o yere uzaklıklarıyla listelenmeli; birini seçip oraya rota alabilirsin. Uçak modunda da çalışır.
23. **Ev / İş kısayolu (build 21+):** bir yeri kartın "…" menüsünden Ev ya da İş olarak kaydet. Ana ekranda arama çubuğunun altında "Ev" / "İş" kapsülü çıkmalı; dokununca doğrudan o yere rota kartı açılmalı.
24. **Varışta otopark (build 22+):** navigasyonla bir yere var. Alt çubukta "Vardın"ın yanında "Otopark" düğmesi çıkmalı; dokununca navigasyon biter ve hedefin çevresindeki otoparklar, hedefe uzaklıklarıyla listelenir.
25. **Semt + tür / marka (build 23+):** "esentepe eczane", "aydınlı benzinlik", "kurtköy migros" yaz. Sonuçlar o semtin çevresinden gelmeli (Esentepe için Kartal'daki, Şişli'deki değil).

**Bilinen sınırlar:**

- Canlı trafik HERE'in ücretsiz kotasıyla sınırlı. Uygulama cihaz başına aylık sınırın altında kalır; sınır dolarsa kart "Trafik alınamadı" der. Trafik katmanının kendi sınırı vardır; dolarsa haritada "Bu ayın trafik sorgu sınırı doldu." yazar.
- Rota sunucusu FOSSGIS'in ortak sunucusu; arada yavaşlayabilir.
- Ücretli yollardan kaçınma açıkken Boğaz araba vapuruyla geçilir. Vapur sefer saatleri ve iskelede bekleme süreye dahil değildir; gerçek süre karttakinden uzun olabilir.
- Şerit bilgisi çoğu yolda yok (OSM'de veri yok; sahte şerit çizilmiyor).
- Adres aramada kapı numarası çoğu yerde bulunmuyor (OSM'de numara verisi az): sokak bulunur. Tam nokta için haritada uzun bas. Türkçe karakterli ve karaktersiz yazım ("çanakkale" / "canakkale") aynı sonucu veriyor (14.11.2026 ölçümü).
- Hız sınırı tabelası yalnızca OSM'de sınırı işli yollarda çıkar (Pendik/Kartal/Tuzla'da yolların %9–16'sı); bilinmeyen yerde tabela gösterilmez.
- Çevrimdışı mod (build 12+) yalnızca İstanbul kutusunda çalışır. Çevrimdışı rotada trafik yoktur. Çevrimdışı arama yer ve sokak adlarını bulur ("ankara caddesi kartal" gibi sokak + ilçe dahil), kapı numarası bulmaz.
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

### Faz 1'de eksik bırakılanlar (sonra tamamlandı)

- Arama, rota ve ses: Faz 2'de geldi.
- Arka planda konum: navigasyon sürerken arka planda da çalışır (Faz 2).
- Hız sınırı: OSM'de işli yollarda gösterilir (Faz 5).
- Harita jestinin kamera takibini bırakması: navigasyonda harita elle kaydırılınca ya da rotanın tamamına bakılınca, son dokunuştan 12 sn sonra görünüm kendiliğinden araca döner (sıradaki build).
- Yatay mod: Faz 6'da geldi.

### Cihazda doğrulaman gerekenler

Bunları ben ölçemiyorum.

1. Uygulama açılıyor mu, harita yükleniyor mu?
2. Konum noktası doğru yerde mi? Yön oku doğru dönüyor mu?
3. Araçta yolcuyken: hız rozeti aracın hızıyla tutarlı mı, dururken 0'da sabit kalıyor mu?
4. Tünelde (örneğin Kartal–Pendik arası tüneller) "–" ve "GPS sinyali yok" görünüyor mu?
5. Akşam gün batımından sonra harita kendiliğinden gece moduna geçiyor mu?
