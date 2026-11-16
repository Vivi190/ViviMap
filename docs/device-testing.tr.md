# Cihaz testleri

TestFlight build'lerinin iPhone'da nasıl deneneceği. Neyin hangi build'de geldiği: [CHANGELOG.md](../CHANGELOG.md).

Sürüş testleri yolcuyken yapılmalı; sürücüyken uygulamayla yalnızca araç dururken etkileşime girilmeli.

## Hazırlık: sürüş simülasyonu

Harita ayarları → Tanılama → **Sürüş simülasyonu** açılınca rota kartında, "Başlat"ın yanında bir oynatma düğmesi çıkar. Konum GPS yerine rota boyunca, Valhalla'nın o rota için varsaydığı ortalama hızla ilerler. Talimat kartı, sesli uyarılar ve kamera araç kullanmadan denenebilir. Simülasyon sürerken ekranda **Simülasyon** etiketi durur.

## Arama ve yer seçme

1. Arama alanına yer, adres ya da koordinat yazın ("Kartal Adliyesi", "40.889, 29.19"). Sonuçlar Türkçe adlı ve mesafeli olmalı.
2. Mesajda yazıldığı gibi adres yapıştırın ("Yakacık Mah. Atatürk Cad. No:12 D:5 Kartal/İstanbul"). İlk sonuç o adresteki yer, kapı numarası OSM'de yoksa o sokak olmalı.
3. Yalnızca tür yazın ("benzinlik", "eczane", "otopark", "en yakın ATM"). En yakınlar mesafeleriyle listelenmeli.
4. Semt + tür ya da marka yazın ("esentepe eczane", "kurtköy migros"). Sonuçlar o semtin çevresinden gelmeli.
5. İşletme adı yazın ("mediamarkt", "kıyı pastanesi", bildiğiniz bir restoran, kuaför ya da dükkân): en yakın şubeler adresleri ve mesafeleriyle listelenmeli; uçak modunda da. "kuaför", "veteriner", "oto servis", "çiçekçi" gibi tür sözcükleri en yakınları, "kartal kuaför" gibi semtle birlikte yazılınca o semttekileri listelemeli. Yanlış yazılan adlar da bulunmalı ("mediamarket", "kebabçı uzunlar", "mcdonalds"). Bulunamayan ya da yeri yanlış çıkan işletmeleri not edin.
6. Yazmadan önce "Yakında" altındaki sekiz düğme (Benzinlik, Otopark, Eczane, Şarj, Market, ATM, Restoran, Kafe) en yakınları listelemeli; uçak modunda da.
7. Bir sonuç seçin. Haritada kırmızı iğne, kartta adı, türü ve mesafesi ("Adliye · 3,0 km") ve adresi görünmeli.
8. Haritayı sokak düzeyine yaklaştırın: çevredeki işletmeler (restoran, market, banka, kuaför, ofis, oto servis, veteriner…) rozet olarak görünmeli; türü bilinmeyen işletmeler küçük gri bir nokta ve adlarıyla, diğerlerinden yer kaldıkça görünür. Bir rozete dokunun: o yerin kartı açılmalı; işletmelerde adres hemen, haritanın kendi rozetlerinde (istasyon, park…) bir an sonra gelir. Kartta bir eylem satırı görünmeli: veride varsa **Ara** (dokununca arama başlar) ve **Web sitesi**, her yerde **Kaydet** ve **Paylaş** (bir harita bağlantısı gönderir). **Rota** düğmesi birkaç saniye içinde yaklaşık sürüş süresini göstermeli ("Rota · 12 dk"). "…" menüsündeki "Google Haritalar'da aç" ve "Yandex Haritalar'da aç" yorumlar için o uygulamayı açmalı. Rozet olmayan bir noktaya uzun basın: kartta adres çıkmalı. Kartın "…" menüsünden **Ev olarak kaydet** seçilince arama çubuğunun altında "Ev" kapsülü çıkmalı; dokununca doğrudan rota kartı açılmalı.
9. Kartın "…" menüsündeki "Yakındaki otoparklar" o yerin çevresindeki otoparkları, o yere uzaklıklarıyla listelemeli. İSPARK otoparkları bir iki saniye içinde o anki boş yer sayısıyla görünmeli ("Otopark · 83 boş yer · 100 araçlık · 08:00-19:00 · İSPARK"). Boş yer bildirmeyen otoparkta sayı yazmaz; "dolu" denmez, çünkü servis saymadığı otoparklar için de sıfır bildiriyor.
10. Karttaki **Kaydet** ile bir yeri kaydedin: düğme "Kaydedildi" olmalı, yer arama ekranında "Kaydedilenler" altında görünmeli; düğmeye yeniden dokununca çıkmalı.
11. "şarj" yazın ya da "Yakında → Şarj"a dokunun: en yakın halka açık şarj istasyonları işletmecisi, akım türü, gücü ve soket sayısıyla listelenmeli ("ZES Kartal Sahil Migros", "Şarj istasyonu · AC 22 kW · 2 soket · Kartal"). "zes", "trugo" gibi işletmeci adı o işletmecinin istasyonlarını getirmeli. Bildiğiniz bir istasyon eksikse ya da kapanmışsa not edin: kayıt Mayıs 2025 tarihli.
12. Tür sözcükleri deneyin: "kargo", "terzi", "çilingir", "kuru temizleme", "noter", "emlakçı", "avukat", "düğün salonu". En yakınlar listelenmeli; kartlarında türleri yazmalı ("Kargo", "Noter", "Hukuk bürosu").
13. Birinin gönderdiği konumu yapıştırın: WhatsApp konumu (maps.google.com/?q=…), Google, Apple ya da Yandex Haritalar'dan kopyalanmış uzun bağlantı. Tek sonuç "Paylaşılan konum" olarak gelmeli ve doğru noktayı göstermeli. Google Haritalar uygulamasının "Paylaş" ile verdiği kısa bağlantı (maps.app.goo.gl/…) da açılmalı: Atlas bağlantının nereyi gösterdiğini bir kez Google'a sorar; yer adıyla birlikte "Paylaşılan konum" olarak gelir.
14. "eczane" ya da "kafe" yazın ve listenin üstündeki "… sonucu haritada göster"e dokunun: sonuçlar haritada adlarıyla mavi iğneler olarak, hepsi ekrana sığacak biçimde görünmeli. Bir iğneye dokunun: o yerin kartı açılmalı, kartı kapatınca iğneler yerinde kalmalı. Arama çubuğunun altındaki çipe dokununca liste yeniden açılmalı, ✕ iğneleri kaldırmalı.
15. Ev ve İş kayıtlıyken, ikisinden de 1 km'den uzaktayken, arama çubuğunun altındaki çiplerde birkaç saniye içinde trafikli süre görünmeli ("Ev · 24 dk"); Yandex'teki süreyle karşılaştırın. Uygulama arka plandayken süre yenilenmemeli.
16. Bir İSPARK otoparkını açın ("otopark" yazıp listeden İSPARK olanı seçin): kartta ücret satırı görünmeli ("1 sa 110 TL · 2 sa 140 TL · Tam gün 370 TL · İlk 15 dk ücretsiz"); otoparkın tabelasıyla karşılaştırın.

## Rota seçimi

1. Bir yer seçip birkaç saniye sonra **Rota**'ya basın: rota kartı beklemeden açılmalı.
2. Seçili rotanın süresi ve mesafesi haritada, yalnız o rotanın geçtiği yerde mavi bir baloncukta görünmeli. Diğer rotaların baloncuğunda seçili rotaya göre fark yazar: "+2 dk" kırmızı, "−3 dk" yeşil.
3. Kartta rotalar yan yana kutular olarak durur: "En hızlı", "+N dk" ya da "Benzer süre" etiketi, süre ve mesafe; seçili kutu mavi dolguludur. Trafikli süreler gelince kutuların sırası değişmemeli. Bir kutuya ya da haritadaki baloncuğa dokununca seçim değişmeli.
4. Kutuların altında varış saati (24 saat biçiminde), ana yollar ve varsa ücretli geçiş ya da feribot uyarısı görünmeli. Tek rota varsa süre ve mesafe de burada yazar.
5. Canlı trafikte kart önce "Canlı trafik alınıyor…" der, sonra trafikli süreyi ve "Trafik X dk ekliyor" satırını gösterir; altta "Canlı trafik · © HERE" yazar. Trafik gelince rota çizgisi maviden trafik renklerine döner: akan kısımlar yeşil, yavaşlar sarı, yoğunlar kırmızı, duranlar koyu kırmızı.
6. Havalimanı, hastane ya da AVM'ye rota alanın ortasında değil, önündeki yolda bitmeli.
7. Harita ayarları → Rota → "Ücretli yollardan kaçın" açıkken Kadıköy → Beşiktaş rotası araba vapuruyla gitmeli ve kartta "Feribotla geçiş · Ücretli yollardan kaçınıldı" yazmalı. "Feribotlardan kaçın" tek başına açıkken aynı rota köprüden gitmeli; ikisi birlikte açıkken rota bulunamamalı ve kart bunu açıkça söylemeli ("Ücretli yol ve feribot kullanmadan bu hedefe rota bulunamadı…").
8. Rota kartında "Başlat"ın yanındaki liste düğmesi rotanın dönüşlerini sırayla göstermeli: her satırda ok, kaç metre sonra olduğu, talimat ("Sağa dönün") ve girilecek yolun adı. Seçili rota değişince liste de değişmeli.

## Navigasyon

1. **Başlat**'a basın. Sol üstte küçük mavi bir panel çıkmalı: dönüş oku, büyük mesafe ve gidilecek yolun adı (ad yoksa "Sağa dönün" gibi talimat). Ardışık manevrada ikinci, küçük bir ok görünür. Sağ üstte iki daire durur: hız ve yolun hız sınırı. Araç dururken "0" yazar; sınır aşılınca hız kırmızıya döner ve tabela kırmızı dolar.
2. Rota çizgisi araç okunun altından başlamalı; geçilen kısım silinir. Araç büyük, iki tonlu mavi bir okla gösterilir. Bir sonraki dönüş rotanın üstünde beyaz bir okla gösterilir.
3. Altta tek satır durur: kalan mesafe, varış saati ve kalan süre; solunda rotanın tamamını gösteren düğme, sağında navigasyonu bitiren ✕. Satırın üstünde o an üzerinde bulunulan yolun adı yazar.
4. Sesli uyarılar "siz" diliyle gelir ("300 metre sonra sağa dönün"): şehirde yaklaşık 400 m, 120 m ve dönüşte; hızlı yolda daha erken ve iki kez. Yalnızca adı değişen yolda uyarı gelmez. Trafik ışıklı kavşakta "Işıklarda sağa dönün", döner kavşakta "Döner kavşakta ikinci çıkıştan çıkın", hedefe yaklaşırken "Hedefe 400 metre kaldı" denmeli.
5. Rotadan çıkınca "Rotadan çıktınız" denmeli ve panelde yazmalı; yeni rota çizilince "Rota yeniden oluşturuldu" denmeli.
6. Haritaya dokununca sağda ses ve paylaş düğmeleri 6 saniyeliğine çıkar. Harita elle kaydırılınca ya da "Rotanın tamamı" düğmesine dokununca alt satırın üstünde **Rotaya devam et** düğmesi çıkmalı; dokunulmazsa görünüm 12 saniye sonra kendiliğinden araca dönmeli.
7. Navigasyon sürerken ekran kararmamalı. Yan tuşla kilitlenince sesli yönlendirme sürmeli; kilit ekranında ve Dynamic Island'da sonraki manevra, mesafe ve varış görünmeli.
8. Varışta "Hedefinize ulaştınız" denmeli; alt satırda "Vardınız" ve "Otopark" düğmesi çıkmalı, dokununca hedefin çevresindeki otoparklar listelenmeli.
9. Navigasyonda haritaya dokununca çıkan paylaş düğmesi tahmini varış saati, hedef ve harita bağlantısı içeren bir mesaj hazırlamalı.
10. Önce bir yer Ev olarak kaydedilip "Hey Siri, Atlas ile eve git" denince uygulama açılmalı ve eve rota kartı gelmeli.

## Trafik

1. Uygulama açılınca trafik katmanı açık olmalı: yollar yön başına ince çizgilerle çizilir; akan yeşil, yavaş sarı, yoğun kırmızı, duran koyu kırmızı. Renk trafiğin değiştiği yerde değişmeli; uzun bir yol baştan sona tek renk olmamalı. Arama çubuğunun altında "4 puan · Yer yer yoğun" gibi bölge puanı yazar. Sağdaki arabalı düğme katmanı kapatır.
   Aynı anda Yandex Haritalar açılıp aynı yollar karşılaştırılmalı: renkler büyük ölçüde örtüşmeli.
2. Kapalı yollar kırmızı kesikli çizgi ve girilmez işaretiyle, kazalar ve yol çalışmaları kendi işaretleriyle görünmeli. Navigasyonda rotanın üstündekiler görünmeye devam eder. Rotanın üstünde bir olay varsa yaklaşık bir kilometre kala bir kez söylenmeli ("1 kilometre sonra yol çalışması.", "800 metre sonra kaza."); olaylar 3 dakikada bir yenilenir.
3. Navigasyonda trafik katmanı açık kalır: rotanın çevresindeki yollar da renkli görünür. Canlı trafikle rota çizgisi trafik renklerindedir ve alt satırdaki ince şerit kalan yolu gösterir. Varış saati 3 dakikada bir trafiğe göre yenilenir; altında "Canlı trafik · © HERE" yazar.
4. Belirgin bir kazanç (en az 3 dk ve %15) olursa "Daha hızlı rota" bandı çıkar ("Değiştir" yeni rotaya geçer, "Hayır" bandı kapatır); 20 saniye içinde dokunulmazsa mevcut rota kalır.
5. Kapalı bir yol: rota kartında hiçbir seçenek trafiğin kapalı bildirdiği bir kesimden geçmemeli (başka yol varken). Sürüş sırasında rotanın üstünde bir yol kapanırsa "Yol kapalı. Rota değiştirildi." denmeli ve rota kapalı kesimin etrafından dolaşmalı. Bilinen bir kapalı yol (yol çalışması, pazar kurulan sokak) varsa oraya rota isteyip deneyin.
6. Rota kartındaki seçeneklerden biri ana yollar yerine ara yolları kullanan bir rota olabilir; D-100 tıkalıyken bu seçeneğin süresine bakın.

## Sürüş uyarıları ve harita

1. Sokak düzeyinde trafik ışıkları, kasis levhaları ve kamera rozetleri haritada görünmeli. Bildiğiniz ışıklı kavşaklarda ışık simgesi olmalı (belediyenin sinyalize kavşak listesi eklendi; eksik kalan kavşakları not edin); yer rozetleri (restoran, eczane, okul…) renkli simgelerle görünür ve navigasyonda gizlenir.
   Tek yönlü sokaklarda yol boyunca küçük gri oklar görünmeli; bildiğiniz tek yönlü sokaklarda yönün doğru olduğunu kontrol edin.
2. Navigasyonda "Kasis · 80 m" ya da "Hız kamerası · 300 m" etiketi çıkmalı ve uyarı bir kez seslendirilmeli. Ayarlar → Uyarılar'dan açılıp kapanır.
3. Bölgede OSM'de neredeyse kamera yok; bilinen kameralar ve kasisler uzun basıp "…" menüsünden işaretlenebilir. İşaretler Ayarlar → Uyarılar → İşaretlerim'den silinir.
4. Canlı trafikli bir rotada hız sınırı neredeyse her yolda görünmeli (OpenStreetMap'te sınır olmayan yollarda HERE'nin sınırı kullanılır). Tabeladaki sınırla karşılaştırın; yanlış ya da eksik gördüğünüz yolları not edin. Uçak modunda sınır yalnızca OpenStreetMap'te olan yollarda görünür. Sınırın belirgin üstünde (50'lik yolda 57 ve üstü) 3 saniye kalınca "Hız sınırı 50." denmeli.
5. Rota başlatmadan, harita açıkken bildiğiniz bir kasise ya da kameraya doğru sürün: yaklaşık 80 m (kasis) ya da 300 m (kamera) kala bir kez "80 metre sonra kasis." denmeli. Paralel yoldaki ya da arkada kalan kasis için uyarı gelmemeli; virajda geç gelirse not edin. Ayarlar → Uyarılar → "Rota yokken de uyar" kapatılınca susmalı.
6. Sağ üstteki hız göstergesi araçla tutarlı olmalı; tünelde "–" ve sol üstte "GPS sinyali yok" görünmeli.
7. Gün batımından sonra harita kendiliğinden gece moduna geçmeli.

## Çevrimdışı

Uçak modu açıkken uygulama açılınca üstte "İnternet yok · çevrimdışı harita" yazmalı ve harita cihazdaki İstanbul paketinden gelmeli. Arama cihazdaki dizinden sonuç vermeli, rota kartında "Çevrimdışı rota" yazmalı ve rotadan çıkınca yeni rota yine cihazda hesaplanmalı.

## Ses

Harita ayarları → Sesli yönlendirme kullanılan Türkçe sesi gösterir; "Örnek dinle" bir talimatı navigasyondaki gibi okur. Ayarlar → Erişilebilirlik → Seslendirilen İçerik → Sesler → Türkçe yolundan "Geliştirilmiş" ses indirilirse Atlas onu kullanır.

Bilinen sınırlar: [development-plan.md](development-plan.md#known-limitations).
