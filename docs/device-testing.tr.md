# Cihaz testleri

TestFlight build'lerinin iPhone'da nasıl deneneceği. Neyin hangi build'de geldiği: [CHANGELOG.md](../CHANGELOG.md).

Sürüş testleri yolcuyken yapılmalı; sürücüyken uygulamayla yalnızca araç dururken etkileşime girilmeli.

## Hazırlık: sürüş simülasyonu

Harita ayarları → Test → **Sürüş simülasyonu** açılınca rota kartında **Simüle et** düğmesi çıkar. Konum GPS yerine rota boyunca, Valhalla'nın o rota için varsaydığı ortalama hızla ilerler. Talimat kartı, sesli uyarılar ve kamera araç kullanmadan denenebilir. Simülasyon sürerken ekranda **Simülasyon** etiketi durur.

## Arama ve yer seçme

1. Arama alanına yer, adres ya da koordinat yazın ("Kartal Adliyesi", "40.889, 29.19"). Sonuçlar Türkçe adlı ve mesafeli olmalı.
2. Mesajda yazıldığı gibi adres yapıştırın ("Yakacık Mah. Atatürk Cad. No:12 D:5 Kartal/İstanbul"). İlk sonuç o adresteki yer, kapı numarası OSM'de yoksa o sokak olmalı.
3. Yalnızca tür yazın ("benzinlik", "eczane", "otopark", "en yakın ATM"). En yakınlar mesafeleriyle listelenmeli.
4. Semt + tür ya da marka yazın ("esentepe eczane", "kurtköy migros"). Sonuçlar o semtin çevresinden gelmeli.
5. Yazmadan önce "Yakında" altındaki Benzinlik, Otopark, Eczane ve Şarj düğmeleri en yakınları listelemeli; uçak modunda da.
6. Bir sonuç seçin. Haritada kırmızı iğne, kartta adı, türü ve mesafesi ("Adliye · 3,0 km") ve adresi görünmeli.
7. Haritada bir noktaya uzun basın: kartta adres çıkmalı. Kartın "…" menüsünden **Ev olarak kaydet** seçilince arama çubuğunun altında "Ev" kapsülü çıkmalı; dokununca doğrudan rota kartı açılmalı.
8. Kartın "…" menüsündeki "Yakındaki otoparklar" o yerin çevresindeki otoparkları, o yere uzaklıklarıyla listelemeli.

## Rota seçimi

1. Bir yer seçip birkaç saniye sonra **Rota**'ya basın: rota kartı beklemeden açılmalı.
2. Her rotanın süresi haritada, yalnız o rotanın geçtiği yerde bir baloncukta görünmeli; seçili olan mavi.
3. Kartta rotalar yan yana kutular olarak sıralanır: süre ve "En hızlı" ya da "+N dk". Bir kutuya ya da haritadaki baloncuğa dokununca seçim değişmeli.
4. Seçili rotanın altında büyük süre, mesafe · varış saati, ana yollar ve varsa ücretli geçiş ya da feribot uyarısı görünmeli.
5. Canlı trafikte kart önce "Canlı trafik alınıyor…" der, sonra trafikli süreyi ve "Trafik X dk ekliyor" satırını gösterir; altta "Canlı trafikle · © HERE" yazar. Yoğun saatte rotanın yavaş kısımları turuncu, kırmızı ya da koyu kırmızı olur.
6. Havalimanı, hastane ya da AVM'ye rota alanın ortasında değil, önündeki yolda bitmeli.
7. Harita ayarları → Rota → "Ücretli yollardan kaçın" açıkken Kadıköy → Beşiktaş rotası araba vapuruyla gitmeli ve kartta "Feribotla geçiş · Ücretli yollardan kaçınıldı" yazmalı.

## Navigasyon

1. **Başlat**'a basın. Üstte açık renkli (gece koyu) bir kart çıkmalı: mavi kutuda dönüş oku, büyük mesafe, gidilecek yolun adı ve "Sağa dön" gibi talimat. Ardışık manevrada "Sonra" etiketi görünür.
2. Mavi rota çizgisi konum okunun altından başlamalı; geçilen kısım silinir. Bir sonraki dönüş rotanın üstünde beyaz bir okla gösterilir.
3. Altta kalan süre büyük, yanında varış saati ve kalan mesafe; alt çubuğun üstünde o an üzerinde bulunulan yolun adı. Sağdaki küçük kırmızı ✕ navigasyonu bitirir.
4. Sesli uyarılar şehirde yaklaşık 400 m, 120 m ve dönüşte, hızlı yolda daha erken gelmeli. Trafik ışıklı kavşakta "Işıklarda sağa dön" denmeli.
5. Rotadan çıkınca "Yeni rota hesaplanıyor" denip yeni rota çizilmeli.
6. Harita elle kaydırılınca ya da "Rotanın tamamı"na dokununca görünüm 12 saniye sonra kendiliğinden araca dönmeli.
7. Navigasyon sürerken ekran kararmamalı. Yan tuşla kilitlenince sesli yönlendirme sürmeli; kilit ekranında ve Dynamic Island'da sonraki manevra, mesafe ve varış görünmeli.
8. Varışta alt çubukta "Vardın" ve "Otopark" düğmesi çıkmalı; dokununca hedefin çevresindeki otoparklar listelenmeli.
9. Navigasyonda sağdaki paylaş düğmesi tahmini varış saati, hedef ve harita bağlantısı içeren bir mesaj hazırlamalı.
10. Önce bir yer Ev olarak kaydedilip "Hey Siri, Atlas ile eve git" denince uygulama açılmalı ve eve rota kartı gelmeli.

## Trafik

1. Uygulama açılınca trafik katmanı açık olmalı: akan yollar yeşil, yavaşlar turuncu, yoğunlar kırmızı, duranlar koyu kırmızı; arama çubuğunun altında "Trafik 3/10 · akıcı" gibi bölge puanı. Sağdaki arabalı düğme katmanı kapatır.
2. Kapalı yollar kırmızı kesikli çizgi ve girilmez işaretiyle, kazalar ve yol çalışmaları kendi işaretleriyle görünmeli. Navigasyonda rotanın üstündekiler görünmeye devam eder.
3. Canlı trafikle navigasyonda alt çubukta ince bir şerit kalan yolu gösterir: yavaş kesimler turuncu, yoğunlar kırmızı. Alt çubuk 3 dakikada bir trafikli varış saatine geçer.
4. Belirgin bir kazanç (en az 3 dk ve %15) olursa "Daha hızlı rota" bandı çıkar; 20 saniye içinde dokunulmazsa mevcut rota kalır.

## Sürüş uyarıları ve harita

1. Sokak düzeyinde trafik ışıkları, kasis levhaları ve kamera rozetleri haritada görünmeli; yer rozetleri (restoran, eczane, okul…) renkli simgelerle görünür ve navigasyonda gizlenir.
2. Navigasyonda "Kasis · 80 m" ya da "Hız kamerası · 300 m" etiketi çıkmalı ve uyarı bir kez seslendirilmeli. Ayarlar → Uyarılar'dan açılıp kapanır.
3. Bölgede OSM'de neredeyse kamera yok; bilinen kameralar ve kasisler uzun basıp "…" menüsünden işaretlenebilir. İşaretler Ayarlar → Uyarılar → İşaretlerim'den silinir.
4. Hız sınırı işli bir yolda sınırın belirgin üstünde (50'lik yolda 57 ve üstü) 3 saniye kalınca "Hız sınırı 50." denmeli.
5. Sol alttaki hız göstergesi araçla tutarlı olmalı; tünelde "–" ve "GPS sinyali yok" görünmeli.
6. Gün batımından sonra harita kendiliğinden gece moduna geçmeli.

## Çevrimdışı

Uçak modu açıkken uygulama açılınca üstte "İnternet yok · İstanbul çevrimdışı" yazmalı ve harita cihazdaki İstanbul paketinden gelmeli. Arama cihazdaki dizinden sonuç vermeli, rota kartında "Çevrimdışı rota" yazmalı ve rotadan çıkınca yeni rota yine cihazda hesaplanmalı.

## Ses

Harita ayarları → Sesli yönlendirme kullanılan Türkçe sesi gösterir; "Örnek dinle" bir talimatı navigasyondaki gibi okur. Ayarlar → Erişilebilirlik → Seslendirilen İçerik → Sesler → Türkçe yolundan "Geliştirilmiş" ses indirilirse Atlas onu kullanır.

Bilinen sınırlar: [development-plan.md](development-plan.md#known-limitations).
