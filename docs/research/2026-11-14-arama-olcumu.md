# Arama ölçümü (Faz 2)

**Soru:** Sürücünün yazdığı sorguda uygulamanın ilk sonucu kastettiği yer mi?

**Yöntem** (`Tools/searchbench/bench.py`, iş akışı *Search benchmark*):
- 51 gerçek sorgu: hastane, havalimanı, istasyon, iskele, belediye, AVM, üniversite, Kartal/Pendik/Tuzla sokakları, semt, simge yapı.
- Sorgu, uygulamanın parametreleriyle canlı Photon'a gider ve uygulamanın yeniden sıralamasından geçer. Kullanıcı Kartal'da varsayılır.
- Hedef, OSM'deki nesnenin kendisidir: İstanbul OSM kesitinden (Geofabrik, osmium) etiket ve adla bulunur.
- Sonuç, hedef geometriye belirtilen yarıçap içindeyse isabettir (varsayılan 150 m; alan içindeyse 0 m).
- Ölçülen şey sıralama ve bulmadır, OSM'nin kendisinin doğruluğu değildir. Hedefi OSM'de bulunamayan sorgu ölçüm dışıdır.

Halka açık Overpass sunucuları 14.11.2026'da zaman aşımı ve 504 verdiği için hedefler yerel kesitten çıkarılır.

## 1. ölçüm — 14.11.2026, düzeltmeden önce

**İlk sonuç doğru: 44/49 · ilk 3'te: 46/49** (2 sorgu ölçüm dışı: hedef OSM'de yok)

Hatalar ve nedenleri:

| Sorgu | Sonuç | Neden |
|---|---|---|
| kartal metro istasyonu | yok | İstasyonun OSM adı yalnızca "Kartal". Tam sorgu önce "… İstasyonu" adlı başka yerleri buluyor (şarj istasyonu, itfaiye). |
| akasya avm | yok | OSM adı "Akasya Alışveriş Merkezi"; "avm" kısaltması eşleşmiyor. |
| tavşantepe metro | 3. | İlk sıralarda "Tavşantepe Metro" adlı otobüs durakları ve metro hattının kendisi var; istasyon hiç gelmiyor. |
| kartal metro durağı | 4. | Durak türü öne alınıyor, ama duraklar arasında "Kartal Metro" adlı olan 4. sırada. |
| kadıköy iskelesi | 2. | İlk sonuç "Beşiktaş - Kadıköy İskelesi" (1 km öteki başka bir iskele). |

**Düzeltme** (`PlaceRanking.focus`): sorguda bir yer türü kelimesi varsa (durak, istasyon/metro/marmaray/tren/gar, AVM, iskele), uygulama eşzamanlı ikinci bir istek atar. Bu istekte o kelime çıkarılır ve Photon'un `osm_tag` filtresi kullanılır ("kartal" + `railway:station`, "akasya" + `shop:mall`). Gelen sonuçlar başa konur. Durak kuralı istasyon kuralından önce gelir: "kartal metro durağı" bir istasyon değil, "Kartal Metro" adlı bir duraktır.

Yerel kontrolde beş sorgunun hepsinde ilk sonuç doğru türdeki doğru yer çıktı (Kartal ve Tavşantepe istasyonları, Kadıköy iskelesi, Akasya AVM, Kartal Metro durağı).

## 2. ölçüm — 14.11.2026, düzeltmeden sonra (aynı 51 sorgu)

**İlk sonuç doğru: 49/49 · ilk 3'te: 49/49.**

Düzeltme bu sorgulardan çıkarıldığı için bu sonuç kısmen kendi verisine uyum olabilir. Bu yüzden 3. ölçüm yapıldı.

## 3. ölçüm — 14.11.2026, bakılmamış 9 sorgu eklendi (toplam 60)

Düzeltmeyi tasarlarken hiç bakılmamış istasyon, iskele, AVM ve durak sorguları eklendi: Maltepe, Bostancı, Kozyatağı, Üsküdar istasyonları; Kartal ve Üsküdar iskeleleri; Optimum ve Capitol AVM; Pendik Metro durağı.

**İlk sonuç doğru: 57/57 · ilk 3'te: 57/57.** Bakılmamış 8 ölçülebilir sorgunun 8'i doğru. Ölçüm dışı kalan 3 sorgunun hedefi OSM'de yok: Kartal Koşuyolu Hastanesi, Viaport ve Capitol AVM (`shop=mall` olarak işli değil).

Ölçüm dışı kalanlarda uygulamanın gerçekte gösterdiği (elle kontrol, 14.11.2026):

- **kartal koşuyolu hastanesi:** ilk sonuç "Kartal Koşuyolu Kalp Hastanesi", yani doğru. OSM'de `building=hospital` olarak işli, ölçüm `amenity=hospital` arıyordu.
- **capitol avm:** ilk sonuç "Capitol Alışveriş Merkezi" (`shop=mall`, Altunizade), yani doğru. Ölçüm aracı kesitte hedefi bulamadı; bu aracın sınırı.
- **viaport:** ilk sonuç "Viaport Houses & Suites" (konut sitesi), yani yanlış. Viaport AVM OSM'de alışveriş merkezi olarak işli değil; bu bir veri eksiği, sıralamayla düzelmez.

Sınır: bu ölçüm sıralamayı ve bulmayı ölçer. Kapı numaralı adres araması OSM'deki numara verisine bağlıdır ve burada ölçülmedi.

## 4. ölçüm — 14.11.2026, adresler mesajda yazıldığı gibi (toplam 68 sorgu)

Adresler insanların mesajda yazdığı biçimde eklendi ("Sanayi Cad. No:1 Kartal", "Yakacık Mah. Atatürk Cad. No:12 D:5 Kartal/İstanbul", "ihlas sk. kartal"), yanında iki gerçekçi sorgu daha ("cevizli tugay yolu", "istanbul havalimanı otopark").

Eski kurallarla ölçülebilir 7 sorgunun yalnızca 1'i doğruydu ("ihlas sk. kartal"):

| Sorgu | Eski ilk sonuç | Neden |
|---|---|---|
| Sanayi Cad. No:1 Kartal | lastik bayisi ("İnönü Cad. D: 15") | Photon "Cad." ve "D:"yi kelime gibi eşledi |
| Hatboyu Cad. No 17 Tuzla | Cafe North ("Başkomutan Cad. 17", Aydınlı) | aynı |
| Ankara Cad. No:5 Kartal | Kartal 37. Noterliği (Ankara Caddesi 488, Pendik) | "No 5", adında numara geçen yerlerle eşleşti |
| Yakacık Mah. Atatürk Cad. No:12 D:5 Kartal/İstanbul | Kartal 24. Noter (Kartal Caddesi 12) | 12 numara, ama başka sokakta |
| cevizli tugay yolu | "Tugay Yolu", yapım aşamasındaki metro hattı | hatlar sıralamada ayrılmıyordu |
| istanbul havalimanı otopark | Turkish Technic Otopark (Sabiha Gökçen) | otopark türü aranmıyordu; "havalimanı" kelimesi havalimanlarını öne alıyordu |

**Düzeltme** (`PlaceRanking`):
- `address`: adres kısaltmaları OSM'in yazımına çevrilir. Cad. → Caddesi, Sk. → Sokak, Mah. → Mahallesi, Blv. → Bulvarı, "No:12" → 12. Daire, kat ve iç kapı numarası atılır, "/" boşluk olur. Bunlardan hiçbiri yoksa sorgu olduğu gibi gider.
- Adres sorgusunda önce sokağı ve numarası birlikte tutan yer gelir, sonra o sokak.
- Sorguda sokak kelimesi varsa (caddesi, sokağı, bulvarı, yolu), sorgudaki tür kelimeleri sokağın adının parçası sayılır ("istasyon caddesi") ve sokaklar öne gelir.
- "… otopark" sorgusu otoparkı arar. Sorulan tür, adın çağrıştırdığı türün önüne geçer.
- Raylı hatlar, yapım aşamasındaki ve planlanan yollar sona iner.

**İlk sonuç doğru: 64/64 · ilk 3'te: 64/64.** Yeni 7 sorgunun 7'si doğru, önceki 57'de gerileme yok. "Bağdat Cd. No:300 Kadıköy" ölçüm dışı kaldı: o adresteki yerler kesitte adres etiketleriyle bulunamadı. Elle kontrolde ilk sonuç Bağdat Caddesi 300'deki bir mağaza, yani doğru.

**Yalnızca tür yazılan sorgular** ("benzinlik", "eczane") ölçüm aracının dışındadır, çünkü hedef sabit bir yer değil, en yakını. Elle kontrol, Kartal'dan:
- Photon'un metin araması "benzinlik"e 148 km öteden, "otopark"a 25 km öteden, "market"e 26 km öteden sonuç verdi. "hastane"de ilk sonuç bir inşaat alanıydı.
- Photon'un ters araması `osm_tag` filtresiyle en yakınları mesafe sırasıyla verdi: BP 190 m, Nurdan Eczanesi 150 m, BİM 130 m, Kartal Kızılay Hastanesi 740 m.

Uygulama artık "benzinlik", "en yakın eczane", "marketler" gibi sorguları ters aramayla arar. Çevrimdışıyken en yakınları cihazdaki dizinden verir; dizin her adlı yerin türünü tuttuğu için bu bütün türlerde çalışır. "Nöbetçi eczane" bilerek bu yola girmez, çünkü OSM'de nöbet çizelgesi yok.

Ölçüm aracında artık bunun için ayrı bir bölüm var (`bench.py --kinds-only`). İsabet ölçütü: ilk sonuç o türden ve Kartal'daki kullanıcıya 3 km'den yakın.

**Metin araması (eski): 0/8 · en yakınlar (şimdi): 7/8.**

| Sorgu | Metin araması (eski) | En yakınlar (şimdi) |
|---|---|---|
| benzinlik | ❌ Benzinlik (amenity=fuel, 148,1 km) | ✅ BP (amenity=fuel, 0,2 km) |
| eczane | ❌ Eczane. (amenity=pharmacy, 18,9 km) | ✅ Nurdan Eczanesi (amenity=pharmacy, 0,2 km) |
| otopark | ❌ otopark (amenity=parking, 24,8 km) | ✅ İspark (amenity=parking, 0,1 km) |
| hastane | ❌ Hastane (landuse=construction, 1,3 km) | ✅ Kartal Kızılay Hastanesi (amenity=hospital, 0,7 km) |
| market | ❌ Market (shop=convenience, 25,9 km) | ✅ Evrim Tekel (shop=convenience, 0,1 km) |
| en yakın atm | ❌ En yakın lastikci (shop=car_repair, 10,7 km) | ✅ Türkiye İş Bankası (amenity=atm, 1,3 km) |
| şarj istasyonu | ❌ Tekerlekli Sandalye Şarj istasyonu (amenity=charging_station, 3,5 km) | ❌ Asf Otomotiv (amenity=charging_station, 3,3 km) |
| kafe | ❌ Kafe (amenity=cafe, 77,6 km) | ✅ Dozze Coffee Kartal (amenity=cafe, 0,1 km) |

"Şarj istasyonu" ölçütü geçemedi, çünkü Kartal kıyısına en yakın şarj noktası 3,3 km uzakta: bölgede OSM'de çok az şarj noktası var (cihazdaki dizinde İstanbul'un tamamında 87). Sıralama doğru, ölçütün 3 km sınırı burada sıkı. Eski metin araması bu sorguda bir tekerlekli sandalye şarj noktası buluyordu; Photon'un tür filtresi araç ve tekerlekli sandalye şarjını ayıramaz.

**"Semt + tür" ve "semt + marka"** (elle kontrol, Kartal'dan, 14.11.2026). Photon bu biçimdeki sorguların çoğunu buluyor, çünkü semt adı adres alanlarında geçiyor: "kartal bim", "soğanlık a101", "yakacık şok", "tuzla migros", "kurtköy eczane" doğru. Bulamadıkları:

| Sorgu | Photon'un metin araması | Neden |
|---|---|---|
| kurtköy migros | sonuç yok (iki sırada da) | Kurtköy'deki mağazaların adres alanlarında "Kurtköy" geçmiyor |
| aydınlı benzinlik | sonuç yok | "benzinlik" adlarda geçmiyor |
| esentepe eczane | Şişli'deki Esentepe'den ve Sakarya'dan eczane | İstanbul'da iki Esentepe var; konum önceliği yetmiyor |

Semti Photon'un yer aramasıyla bulmak da güvenilir değildi (`osm_tag=place`, Kartal'dan): Esentepe ve Yakacık doğru çıktı, ama Kurtköy için önce Yalova'daki Kurtköy geldi, Soğanlık'ta ilgisiz sonuçlar geldi, Aydınlı hiç bulunamadı.

**Düzeltme:** semt cihazdaki İstanbul dizininden bulunur (`place=*`, aynı adlılar arasından kullanıcıya en yakını). "Semt + tür" sorgusunda türün en yakınları o semtin çevresinde listelenir. "Semt + marka" sorgusu boş dönerse marka o semtin çevresinde yeniden aranır. Bu yollar dizinin bulunduğu TestFlight build'lerinde çalışır; ölçüm aracının OSM hedefleri bu sorguları kapsamıyor.

### 3. ölçümün tam tablosu

| Sorgu | Sonuç | Uygulamanın ilk sonucu | İlk sonucun hedefe uzaklığı |
|---|---|---|---|
| pendik devlet hastanesi | ✅ 1. | Pendik Devlet Hastanesi | 0 m |
| lütfi kırdar şehir hastanesi | ✅ 1. | Dr. Lütfi Kırdar Şehir Hastanesi | 0 m |
| kartal koşuyolu hastanesi | — | hedef OSM'de bulunamadı (ölçüm dışı) |  |
| tuzla devlet hastanesi | ✅ 1. | Tuzla Devlet Hastanesi | 0 m |
| marmara üniversitesi pendik hastanesi | ✅ 1. | Marmara Üniversitesi Pendik Eğitim ve Araştırma Hastanesi | 0 m |
| siyami ersek hastanesi | ✅ 1. | Dr. Siyami Ersek Göğüs Kalp ve Damar Cerrahisi Eğitim ve Araştırma Hastanesi | 0 m |
| sabiha gökçen havalimanı | ✅ 1. | Sabiha Gökçen Havalimanı (SAW) | 0 m |
| istanbul havalimanı | ✅ 1. | İstanbul Havalimanı | 0 m |
| pendik tren garı | ✅ 1. | Pendik | 0 m |
| kartal metro istasyonu | ✅ 1. | Kartal | 0 m |
| tavşantepe metro | ✅ 1. | Tavşantepe | 0 m |
| bostancı iskelesi | ✅ 1. | Bostancı | 0 m |
| kadıköy iskelesi | ✅ 1. | Kadıköy | 0 m |
| harem otogarı | ✅ 1. | Harem Otogarı | 0 m |
| kartal belediyesi | ✅ 1. | Kartal Belediyesi | 0 m |
| pendik belediyesi | ✅ 1. | Pendik Belediyesi | 0 m |
| tuzla belediyesi | ✅ 1. | Tuzla Belediyesi | 0 m |
| maltepe belediyesi | ✅ 1. | Maltepe Belediyesi | 0 m |
| kartal adliyesi | ✅ 1. | İstanbul Anadolu Adalet Sarayı | 0 m |
| viaport | — | hedef OSM'de bulunamadı (ölçüm dışı) |  |
| hilltown avm | ✅ 1. | Hilltown AVM | 0 m |
| pendorya avm | ✅ 1. | Pendorya AVM | 0 m |
| neomarin avm | ✅ 1. | Neomarin | 0 m |
| akasya avm | ✅ 1. | Akasya Alışveriş Merkezi | 0 m |
| emaar square | ✅ 1. | Emaar Square AVM | 11 m |
| sabancı üniversitesi | ✅ 1. | Sabancı Üniversitesi | 0 m |
| yeditepe üniversitesi | ✅ 1. | Yeditepe Üniversitesi | 0 m |
| boğaziçi üniversitesi | ✅ 1. | Boğaziçi Üniversitesi Güney Yerleşkesi | 0 m |
| ankara caddesi kartal | ✅ 1. | Ankara Caddesi | 0 m |
| bağdat caddesi | ✅ 1. | Bağdat Caddesi | 0 m |
| çanakkale caddesi kartal | ✅ 1. | Çanakkale Caddesi | 0 m |
| turgut özal bulvarı kartal | ✅ 1. | Turgut Özal Bulvarı | 0 m |
| ihlas sokağı kartal | ✅ 1. | İhlas Sokağı | 0 m |
| şehzade caddesi kartal | ✅ 1. | Şehzade Caddesi | 0 m |
| meşeli ayazma caddesi | ✅ 1. | Meşeli Ayazma Caddesi | 0 m |
| hürriyet caddesi kartal | ✅ 1. | Hürriyet Caddesi | 0 m |
| atatürk caddesi pendik | ✅ 1. | Atatürk Caddesi | 0 m |
| istasyon caddesi tuzla | ✅ 1. | İstasyon Caddesi | 0 m |
| esentepe kartal | ✅ 1. | Esentepe | 0 m |
| soğanlık | ✅ 1. | Soğanlık | 486 m |
| yakacık | ✅ 1. | Yakacık | 0 m |
| kurtköy | ✅ 1. | Kurtköy | 563 m |
| aydınlı tuzla | ✅ 1. | Aydınlı | 0 m |
| velibaba pendik | ✅ 1. | Velibaba | 0 m |
| gümüşpınar kartal | ✅ 1. | Gümüşpınar | 0 m |
| taksim meydanı | ✅ 1. | Taksim Meydanı | 0 m |
| galata kulesi | ✅ 1. | Galata Kulesi | 0 m |
| ayasofya | ✅ 1. | Ayasofya | 0 m |
| kız kulesi | ✅ 1. | Kız Kulesi | 0 m |
| çamlıca camii | ✅ 1. | Çamlıca Camii Zemin Altı Otoparkı | 33 m |
| kartal metro durağı | ✅ 1. | Kartal Metro | 0 m |
| maltepe metro istasyonu | ✅ 1. | Maltepe | 0 m |
| bostancı marmaray | ✅ 1. | Bostancı | 0 m |
| kozyatağı metro | ✅ 1. | Kozyatağı | 0 m |
| üsküdar marmaray | ✅ 1. | Üsküdar | 0 m |
| kartal iskelesi | ✅ 1. | İDO Kartal Terminali | 0 m |
| üsküdar iskelesi | ✅ 1. | Üsküdar | 0 m |
| optimum avm | ✅ 1. | Optimum Premium Outlet | 0 m |
| capitol avm | — | hedef OSM'de bulunamadı (ölçüm dışı) |  |
| pendik metro durağı | ✅ 1. | Pendik Metro Minibüs Durağı | 0 m |

### 1. ölçümün tam tablosu (düzeltmeden önce)

| Sorgu | Sonuç | Uygulamanın ilk sonucu | İlk sonucun hedefe uzaklığı |
|---|---|---|---|
| pendik devlet hastanesi | ✅ 1. | Pendik Devlet Hastanesi | 0 m |
| lütfi kırdar şehir hastanesi | ✅ 1. | Dr. Lütfi Kırdar Şehir Hastanesi | 0 m |
| kartal koşuyolu hastanesi | — | hedef OSM'de bulunamadı (ölçüm dışı) |  |
| tuzla devlet hastanesi | ✅ 1. | Tuzla Devlet Hastanesi | 0 m |
| marmara üniversitesi pendik hastanesi | ✅ 1. | Marmara Üniversitesi Pendik Eğitim ve Araştırma Hastanesi | 0 m |
| siyami ersek hastanesi | ✅ 1. | Dr. Siyami Ersek Göğüs Kalp ve Damar Cerrahisi Eğitim ve Araştırma Hastanesi | 0 m |
| sabiha gökçen havalimanı | ✅ 1. | Sabiha Gökçen Havalimanı (SAW) | 0 m |
| istanbul havalimanı | ✅ 1. | İstanbul Havalimanı | 0 m |
| pendik tren garı | ✅ 1. | Pendik Garı | 48 m |
| kartal metro istasyonu | ❌ yok | Tekerlekli Sandalye Şarj istasyonu | 1540 m |
| tavşantepe metro | 🟡 3. | M4B Tavşantepe - Tuzla Metro Hattı | 3195 m |
| bostancı iskelesi | ✅ 1. | Bostancı İskelesi | 0 m |
| kadıköy iskelesi | 🟡 2. | Beşiktaş - Kadıköy İskelesi | 1072 m |
| harem otogarı | ✅ 1. | Harem Otogarı | 0 m |
| kartal belediyesi | ✅ 1. | Kartal Belediyesi | 0 m |
| pendik belediyesi | ✅ 1. | Pendik Belediyesi | 0 m |
| tuzla belediyesi | ✅ 1. | Tuzla Belediyesi | 0 m |
| maltepe belediyesi | ✅ 1. | Maltepe Belediyesi | 0 m |
| kartal adliyesi | ✅ 1. | İstanbul Anadolu Adalet Sarayı | 0 m |
| viaport | — | hedef OSM'de bulunamadı (ölçüm dışı) |  |
| hilltown avm | ✅ 1. | Hilltown AVM | 0 m |
| pendorya avm | ✅ 1. | Pendorya AVM | 0 m |
| neomarin avm | ✅ 1. | Neomarin AVM | 28 m |
| akasya avm | ❌ yok | Akasyalı Sokak | 80755 m |
| emaar square | ✅ 1. | Emaar Square AVM | 11 m |
| sabancı üniversitesi | ✅ 1. | Sabancı Üniversitesi | 0 m |
| yeditepe üniversitesi | ✅ 1. | Yeditepe Üniversitesi | 0 m |
| boğaziçi üniversitesi | ✅ 1. | Boğaziçi Üniversitesi Güney Yerleşkesi | 0 m |
| ankara caddesi kartal | ✅ 1. | Ankara Caddesi | 0 m |
| bağdat caddesi | ✅ 1. | Bağdat Caddesi | 0 m |
| çanakkale caddesi kartal | ✅ 1. | Çanakkale Caddesi | 0 m |
| turgut özal bulvarı kartal | ✅ 1. | Turgut Özal Bulvarı | 0 m |
| ihlas sokağı kartal | ✅ 1. | İhlas Sokağı | 0 m |
| şehzade caddesi kartal | ✅ 1. | Şehzade Caddesi | 0 m |
| meşeli ayazma caddesi | ✅ 1. | Meşeli Ayazma Caddesi | 0 m |
| hürriyet caddesi kartal | ✅ 1. | Hürriyet Caddesi | 0 m |
| atatürk caddesi pendik | ✅ 1. | Atatürk Caddesi | 0 m |
| istasyon caddesi tuzla | ✅ 1. | İstasyon Caddesi | 0 m |
| esentepe kartal | ✅ 1. | Esentepe | 0 m |
| soğanlık | ✅ 1. | Soğanlık | 486 m |
| yakacık | ✅ 1. | Yakacık | 0 m |
| kurtköy | ✅ 1. | Kurtköy | 563 m |
| aydınlı tuzla | ✅ 1. | Aydınlı | 0 m |
| velibaba pendik | ✅ 1. | Velibaba | 0 m |
| gümüşpınar kartal | ✅ 1. | Gümüşpınar | 0 m |
| taksim meydanı | ✅ 1. | Taksim Meydanı | 0 m |
| galata kulesi | ✅ 1. | Galata Kulesi | 0 m |
| ayasofya | ✅ 1. | Ayasofya | 0 m |
| kız kulesi | ✅ 1. | Kız Kulesi | 0 m |
| çamlıca camii | ✅ 1. | Çamlıca Camii Zemin Altı Otoparkı | 33 m |
| kartal metro durağı | ❌ 4. | Topselvi - Pendik Minibüs Durağı | 1030 m |
