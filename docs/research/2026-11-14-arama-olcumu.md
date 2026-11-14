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

Yerel kontrolde beş sorgunun hepsinde ilk sonuç doğru türdeki doğru yer çıktı (Kartal ve Tavşantepe istasyonları, Kadıköy iskelesi, Akasya AVM, Kartal Metro durağı). Bunun resmî ölçümü 2. ölçümdür.

### 1. ölçümün tam tablosu

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
