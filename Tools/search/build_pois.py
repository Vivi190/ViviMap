# -*- coding: utf-8 -*-
"""Business search index for Istanbul: the shops, restaurants, offices and other places of the Overture Maps
places theme, in the schema of the OSM index (build_index.py) so the app searches both the same way.

    pip install overturemaps
    overturemaps download --bbox=28.0,40.75,29.95,41.6 -f geojsonseq --type=place -o overture-places.geojsonseq
    python3 Tools/search/build_pois.py overture-places.geojsonseq pois.sqlite [Tools/search/chargers-istanbul.json]

A file of its own, not rows in the OSM index: the two sources carry different licences, and nothing here is
derived from OpenStreetMap. Data © Overture Maps Foundation and its sources (Meta, Microsoft, Foursquare,
AllThePlaces and others); each record is under CDLA-Permissive-2.0, Apache-2.0 or CC0-1.0.

The optional third file adds Istanbul's public charging stations from the energy regulator's register
(fetch_chargers.py; İBB Açık Veri Lisansı). Overture has 85 chargers for the city, the register 2 029.
"""
import json
import os
import re
import sqlite3
import sys

# The one fold() the app's TurkishFold mirrors, wherever this is run from.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_index import fold  # noqa: E402

# Overture's estimate that the place exists. Measured on the 2026-10-21 release for the Istanbul box: 458 000
# places, 393 000 at 0.4 and above. Below it the sample was mostly pages without an address or a kind.
MIN_CONFIDENCE = 0.4
CLOSED = {"permanently_closed", "temporarily_closed"}
# A title with a phone number in it is an advertisement, not a name.
PHONE = re.compile(r"\d[\d ()-]{8,}\d")
NOT_AN_ADDRESS = {"turkiye", "turkey", "istanbul", "istanbul turkiye", "istanbul turkey"}

# Overture's taxonomy (most specific first) to the OSM tag the app's icons, kind words and "nearest of a kind"
# searches already use. What is not listed is tried by its basic category, then by the rules in category().
SPECIFIC = {
    "fast_food_restaurant": "amenity=fast_food",
    "cafe": "amenity=cafe", "coffee_shop": "amenity=cafe", "tea_room": "amenity=cafe", "dessert_shop": "amenity=cafe",
    "ice_cream_shop": "amenity=cafe", "bagel_shop": "amenity=cafe",
    "bar": "amenity=bar", "pub": "amenity=bar", "lounge": "amenity=bar", "hookah_bar": "amenity=bar", "dance_club": "amenity=bar",
    "bakery": "shop=bakery", "butcher_shop": "shop=butcher", "produce_store": "shop=greengrocer",
    "grocery_store": "shop=supermarket", "organic_grocery_store": "shop=supermarket", "superstore": "shop=supermarket",
    "warehouse_club_store": "shop=supermarket", "convenience_store": "shop=convenience",
    "department_store": "shop=department_store", "shopping_mall": "shop=mall",
    "pharmacy": "amenity=pharmacy", "atm": "amenity=atm", "bank": "amenity=bank", "bank_or_credit_union": "amenity=bank",
    "gas_station": "amenity=fuel", "parking": "amenity=parking", "ev_charging_station": "amenity=charging_station",
    "post_office": "amenity=post_office", "currency_exchange": "amenity=bureau_de_change", "notary_public": "office=notary",
    "towing_service": "shop=car_repair", "auto_glass_service": "shop=car_repair", "car_inspection": "amenity=vehicle_inspection",
    "car_wash": "amenity=car_wash", "auto_detailing": "amenity=car_wash",
    "automotive_repair": "shop=car_repair", "auto_body_shop": "shop=car_repair", "automotive_service": "shop=car_repair",
    "tire_dealer_and_repair": "shop=tyres", "tire_shop": "shop=tyres",
    "auto_parts_store": "shop=car_parts", "auto_dealer": "shop=car", "motorcycle_dealer": "shop=motorcycle",
    "car_rental_service": "amenity=car_rental", "taxi_service": "amenity=taxi",
    "hair_salon": "shop=hairdresser", "barber": "shop=hairdresser",
    "beauty_salon": "shop=beauty", "nail_salon": "shop=beauty",
    "hotel": "tourism=hotel", "lodging": "tourism=hotel",
    "hospital": "amenity=hospital", "dental_clinic": "amenity=dentist", "doctors_office": "amenity=doctors",
    "veterinarian": "amenity=veterinary",
    "elementary_school": "amenity=school", "middle_school": "amenity=school", "high_school": "amenity=school",
    "school": "amenity=school", "private_school": "amenity=school", "preschool": "amenity=kindergarten",
    "college_university": "amenity=university", "campus_building": "amenity=university",
    "language_school": "amenity=language_school", "driving_school": "amenity=driving_school",
    "music_school": "amenity=music_school",
    "muslim_place_of_worship": "amenity=place_of_worship", "christian_place_of_worship": "amenity=place_of_worship",
    "police_station": "amenity=police", "courthouse": "amenity=courthouse", "town_hall": "amenity=townhall",
    "library": "amenity=library", "movie_theater": "amenity=cinema", "theatre_venue": "amenity=theatre",
    "bus_station": "amenity=bus_station", "metro_station": "railway=station", "train_station": "railway=station",
    "park": "leisure=park", "public_plaza": "leisure=park", "garden": "leisure=park", "playground": "leisure=playground",
    "gym": "leisure=fitness_centre", "pilates_studio": "leisure=fitness_centre", "stadium_arena": "leisure=stadium",
    "swimming_pool": "leisure=sports_centre", "museum": "tourism=museum", "historic_site": "tourism=attraction",
    "clothing_store": "shop=clothes", "womens_clothing_store": "shop=clothes", "mens_clothing_store": "shop=clothes",
    "childrens_clothing_store": "shop=clothes", "fashion_boutique": "shop=clothes", "bridal_shop": "shop=clothes",
    "shoe_store": "shop=shoes", "jewelry_store": "shop=jewelry", "eyewear_store": "shop=optician",
    "furniture_store": "shop=furniture", "home_goods_store": "shop=houseware", "carpet_store": "shop=carpet",
    "electronics_store": "shop=electronics", "mobile_phone_store": "shop=mobile_phone", "appliance_store": "shop=appliance",
    "hardware_store": "shop=doityourself", "home_improvement_store": "shop=doityourself", "building_supply_store": "shop=doityourself",
    "flowers_and_gifts_store": "shop=florist", "bookstore": "shop=books", "office_supply_store": "shop=stationery",
    "pet_store": "shop=pet", "toy_store": "shop=toys", "sporting_goods_store": "shop=sports",
    "cosmetics_and_fragrance_store": "shop=cosmetics", "beauty_supply_store": "shop=cosmetics",
    "liquor_store": "shop=alcohol", "tobacco_shop": "shop=tobacco", "second_hand_store": "shop=second_hand",
}
BASIC = {
    "restaurant": "amenity=restaurant", "casual_eatery": "amenity=restaurant", "fast_food_restaurant": "amenity=fast_food",
    "cafe": "amenity=cafe", "coffee_shop": "amenity=cafe", "non_alcoholic_beverage_venue": "amenity=cafe", "bar": "amenity=bar",
    "pharmacy_and_drug_store": "amenity=pharmacy", "gas_station": "amenity=fuel", "fueling_station": "amenity=fuel",
    "hotel": "tourism=hotel", "lodging": "tourism=hotel", "hospital": "amenity=hospital", "emergency_department": "amenity=hospital",
    "outpatient_care_facility": "amenity=clinic", "diagnostics_imaging_or_lab_service": "amenity=clinic",
    "behavioral_or_mental_health_clinic": "amenity=clinic", "specialized_health_care": "amenity=clinic",
    "physical_medicine_and_rehabilitation": "amenity=clinic", "vision_or_eye_care_clinic": "amenity=clinic",
    "surgery": "amenity=clinic", "medical_service": "amenity=clinic", "health_care": "amenity=clinic",
    "specialty_school": "amenity=prep_school", "government_office": "office=government",
    "auto_dealer": "shop=car", "vehicle_dealer": "shop=car", "gym": "leisure=fitness_centre",
    "fitness_studio": "leisure=fitness_centre", "sport_or_fitness_facility": "leisure=fitness_centre",
    "shopping": "shop=yes", "shopping_mall": "shop=mall",
}


# What a name says its place is, for the places Overture's taxonomy leaves without a tag the app has a word
# for: services and offices, 149 000 of the 389 000 places of the 2026-10-21 release. These rules name 34 000
# of them. Each pattern reads the folded name; the first match wins, so the order is part of the rules:
# Turkish puts the head noun last ("… Camii Derneği" is an association, "… Hastanesi Durağı" a stop), and what
# must not be taken for a kind comes before the kinds it would be taken for. Kinds a wrong guess would make
# dangerous are left out (a "telefon hastanesi" repairs phones) or tied to the end of the name ("… Eczanesi").
NAMED = [
    (r"\btaksi\b", "amenity=taxi"),
    # No kind: a building site, an impound lot, a lorry park, a stop, a company under its legal name.
    (r"\bsantiye\w*|\byed+i ?emin\b|\btir parki\b|\bduragi?\b|\b(ltd|limited|sti|sirketi)\b|\ba\.s\.?(\s|$)", None),
    (r"^pudo\b|\beasy point\b|\bkargo\w*|\bkurye\w*", "office=courier"),
    (r"\bdernegi\b|\bdernek\b", "office=association"),
    (r"\bvakfi\b", "office=foundation"),
    (r"\b(oto|arac|araba) (yikama|kuafor\w*)\b|\boto ?yikama\b|\bcar ?wash\b", "amenity=car_wash"),
    (r"\bpet ?(kuafor\w*|otel\w*|hotel|shop|market|kres)\b|\b(kedi|kopek) (oteli?|pansiyonu?|kuafor\w*)\b", "shop=pet"),
    (r"\beczanesi$", "amenity=pharmacy"),
    (r"\bkuafor\w*|\bberber\w*|\bcoiffeur\b|\bhair (design|desing|studio|salon|style|stylist|artist|art)\b", "shop=hairdresser"),
    (r"\bguzellik\b|\bbeauty\b|\bepilasyon\b|\bnail\w*|\bcilt bakim\w*", "shop=beauty"),
    (r"\bdental\b|\bdentist\w*|\bagiz ve dis\b|\bdis (hekimi|hekimligi|klinigi|poliklinigi|sagligi|hastanesi)\b", "amenity=dentist"),
    (r"\bveteriner (klini\w*|hekim\w*|poliklini\w*|muayenehane\w*)|\bveteriner$", "amenity=veterinary"),
    (r"\bnoter\w*", "office=notary"),
    (r"\bptt\b", "amenity=post_office"),
    (r"\bemlak\w*|\bgayrimenkul\w*|\breal estate\b|\bremax\b|\bre/max\b|\bcoldwell\b|\bcentury ?21\b", "office=estate_agent"),
    (r"\bsigorta\w*", "office=insurance"),
    (r"\bhukuk\b|\bavukat\w*|\blaw (firm|office)\b", "office=lawyer"),
    (r"\bmali musavir\w*|\bmuhasebe\w*", "office=accountant"),
    (r"\bterzi(si)?\b", "shop=tailor"),
    (r"\bkuru ?temizleme\w*|\bdry clean\w*", "shop=dry_cleaning"),
    (r"\bcilingir\w*|\banahtarci\w*", "shop=locksmith"),
    (r"\bnakliyat\w*|\bevden eve\b", "office=moving_company"),
    (r"\bdugun (salonu|sarayi|salonlari)\b|\bdavet (salonu|evi)\b|\bkir dugunu\b", "amenity=events_venue"),
    (r"\bsurucu kursu\b", "amenity=driving_school"),
    (r"\banaokulu$|\bkresi?$", "amenity=kindergarten"),
    (r"\b(ilkokulu|ortaokulu|lisesi|koleji)$", "amenity=school"),
    (r"\buniversitesi$", "amenity=university"),
    (r"\b(camii?|camisi|mescidi?|mescit)$", "amenity=place_of_worship"),
    (r"\bmezarli[gk]\w*", "landuse=cemetery"),
    (r"\bpoliklini\w*|\btip merkezi\b|\bsaglik (ocagi|merkezi)\b|\baile sagligi\b", "amenity=clinic"),
    (r"\bdiyetisyen\w*", "healthcare=dietitian"),
    (r"\bspor salonu\b|\bfitness\b|\bgym\b|\bpilates\b|\bcrossfit\b", "leisure=fitness_centre"),
    (r"\boto lastik\w*|\blastikci\w*", "shop=tyres"),
    (r"\boto (servis\w*|tamir\w*|elektrik\w*|kaporta\w*|bakim|egzoz\w*|klima\w*)\b(?! (urunleri|ekipmanlari|malzemeleri))", "shop=car_repair"),
    (r"\brent ?a ?car\b|\b(arac|oto|araba) kiralama\b", "amenity=car_rental"),
    (r"\boto galeri\w*", "shop=car"),
    # A car park a driver can use: not the police's, not one for buses.
    (r"^(?!.*\b(emniyet|otobus)).*\botopark\w*$", "amenity=parking"),
    (r"\b(oteli?|hotel|pansiyonu?|hostel)$", "tourism=hotel"),
    # A municipality's "sosyal tesis" is its restaurant.
    (r"\bsosyal tesis\w*", "amenity=restaurant"),
    (r"\bcafe\b|\bkafe\b|\bkahve\w*|\bkiraathane\w*|\bcoffee\b|\bpastane\w*|\bcay (evi|bahcesi|ocagi)\b", "amenity=cafe"),
    (r"\brestoran\w*|\brestaurant\w*|\blokanta\w*|\bkahvalti\w*|\bkebap\w*|\bpide\w*|\bdoner(ci\w*)?\b(?! sermaye)|\bkofte\w*"
     r"|\bpizza\b|\bburger\b|\bocakbasi\b|\bbalik (restoran\w*|evi)\b", "amenity=restaurant"),
    (r"\bdovme\w*|\btattoo\b", "shop=tattoo"),
    (r"\bhali yikama\b", "shop=carpet_cleaning"),
    (r"\bseyahat acente\w*|\bturizm seyahat\b|\btravel\b", "shop=travel_agency"),
    (r"\bkursu$|\bkurs merkezi\b|\bdershane\w*|\betut merkezi\b", "amenity=prep_school"),
    (r"\bspor kulubu\b", "club=sport"),
    (r"\bmuhtarligi\b|\bkaymakamligi\b|\bbelediyesi$|\bvergi dairesi\b|\b(tapu|nufus|emniyet|mal|saglik|milli egitim) mudurlugu\b",
     "office=government"),
    (r"\bsanayi sitesi\b|\borganize sanayi\b|\bosb\b", "landuse=industrial"),
    (r"\bsitesi$|\bkonutlari$|\bevleri$|\bkonaklari$|\brezidans\w*$|\bresidence$", "landuse=residential"),
    (r"\bplaza$|\bis merkezi$|\bis ?hani$", "building=office"),
    (r"\bparki$", "leisure=park"),
]
NAMED = [(re.compile(pattern), tag) for pattern, tag in NAMED]


def named(name):
    """The tag a name alone gives its place, or None."""
    folded = fold(name).strip()
    for pattern, tag in NAMED:
        if pattern.search(folded):
            return tag
    return None


def category(specific, basic, name=""):
    """The OSM tag for a place of Overture's `taxonomy.primary` and `basic_category`, else the one its name
    gives it; None for places that are neither (most services, offices, factories), which show a plain dot."""
    if specific in SPECIFIC:
        return SPECIFIC[specific]
    if basic in BASIC and BASIC[basic] != "shop=yes":
        return BASIC[basic]
    if specific and specific.endswith("_restaurant"):
        return "amenity=restaurant"
    # A shop of no listed kind is still better told by its name ("… Halı Yıkama") than called a shop.
    if basic in BASIC or (specific and specific.endswith("_store")) or (basic and basic.endswith("_store")):
        return named(name) or "shop=yes"
    return named(name)


def clean(text):
    return " ".join((text or "").split())


def subtitle(address):
    """Street address and district as one line: "Ankara Cd. No:57, Kartal"."""
    street = clean(address.get("freeform"))
    district = clean(address.get("locality"))
    # Some pages give the country, the city or the district alone as their address.
    if fold(street).replace(",", " ").strip() in NOT_AN_ADDRESS or fold(street) == fold(district):
        street = ""
    if len(street) > 90:
        street = street[:90].rsplit(" ", 1)[0]
    if street and district and fold(district) not in fold(street):
        return f"{street}, {district}"
    return street or district


def contact(properties):
    """Phone number and website as the card offers them: "+902163066161", "https://example.com"."""
    phone = clean(((properties.get("phones") or [None])[0]))
    site = clean(((properties.get("websites") or [None])[0]))
    if not re.fullmatch(r"[+]?[\d ()-]{7,20}", phone):
        phone = ""
    if not site.lower().startswith(("http://", "https://")) or " " in site or len(site) > 200:
        site = ""
    return phone, site


def searchable(name):
    """The folded name as the index reads it. "McDonald's" is also "mcdonalds", the way it is typed: the
    tokenizer splits at the apostrophe, so the joined spelling is added beside it."""
    folded = fold(name)
    joined = folded.replace("'", "").replace("’", "")
    return folded if joined == folded else f"{folded} {joined}"


def wanted(properties):
    """A place worth a row: named, likely to exist, open, and not an advertisement posing as a name."""
    name = clean((properties.get("names") or {}).get("primary"))
    if not name or len(name) > 90 or PHONE.search(name):
        return None
    if (properties.get("confidence") or 0) < MIN_CONFIDENCE or properties.get("operating_status") in CLOSED:
        return None
    return name


def main(source, target, chargers=None):
    registered = []
    if chargers:
        with open(chargers, encoding="utf-8") as file:
            registered = [tuple(row) for row in json.load(file)["stations"]]
    # Where the register has a station, its record replaces Overture's: it says how fast and how many.
    charging = {(round(lat, 3) + dy / 1000, round(lon, 3) + dx / 1000)
                for _, _, lat, lon in registered for dy in (-1, 0, 1) for dx in (-1, 0, 1)}
    charging = {(round(lat, 3), round(lon, 3)) for lat, lon in charging}
    best = {}
    read = 0
    with open(source, encoding="utf-8") as lines:
        for line in lines:
            line = line.strip().lstrip("\x1e")
            if not line:
                continue
            feature = json.loads(line)
            read += 1
            properties = feature.get("properties") or {}
            geometry = feature.get("geometry") or {}
            name = wanted(properties)
            if name is None or geometry.get("type") != "Point":
                continue
            lon, lat = geometry["coordinates"][:2]
            addresses = properties.get("addresses") or [{}]
            taxonomy = properties.get("taxonomy") or {}
            row = (properties.get("confidence") or 0, name, subtitle(addresses[0] or {}),
                   category(taxonomy.get("primary"), properties.get("basic_category"), name), round(lat, 6), round(lon, 6),
                   *contact(properties))
            if row[3] == "amenity=charging_station" and (round(lat, 3), round(lon, 3)) in charging:
                continue
            # The same name within about 100 m is the same place listed twice: the likelier record stays.
            key = (fold(name), round(lat, 3), round(lon, 3))
            if key not in best or best[key][0] < row[0]:
                best[key] = row

    db = sqlite3.connect(target)
    db.executescript("""
        DROP TABLE IF EXISTS place; DROP TABLE IF EXISTS place_fts;
        -- weight: Overture's confidence in percent. The map shows the likeliest places of a view first.
        CREATE TABLE place (id INTEGER PRIMARY KEY, name TEXT NOT NULL, subtitle TEXT NOT NULL,
                            category TEXT, lat REAL NOT NULL, lon REAL NOT NULL, weight INTEGER NOT NULL);
        CREATE VIRTUAL TABLE place_fts USING fts4(folded, tokenize=unicode61);
        -- The words of the names with their counts: where the app looks up a misspelt word's nearest spelling.
        DROP TABLE IF EXISTS place_terms;
        CREATE VIRTUAL TABLE place_terms USING fts4aux(place_fts);
        -- Read for one place at a time, when its card opens; a table of its own keeps the searched one small.
        DROP TABLE IF EXISTS contact;
        CREATE TABLE contact (id INTEGER PRIMARY KEY, phone TEXT, website TEXT);
    """)
    # After Overture's places, so that those keep their row numbers from one build to the next.
    rows = list(best.values()) + [(0.9, name, line, "amenity=charging_station", lat, lon, "", "")
                                  for name, line, lat, lon in registered]
    for confidence, name, line, kind, lat, lon, phone, site in rows:
        cursor = db.execute("INSERT INTO place (name, subtitle, category, lat, lon, weight) VALUES (?, ?, ?, ?, ?, ?)",
                            (name, line, kind, lat, lon, round(confidence * 100)))
        db.execute("INSERT INTO place_fts (docid, folded) VALUES (?, ?)", (cursor.lastrowid, searchable(name)))
        if phone or site:
            db.execute("INSERT INTO contact (id, phone, website) VALUES (?, ?, ?)", (cursor.lastrowid, phone or None, site or None))
    # "Nearest of a kind" filters on the category before it sorts by distance.
    db.execute("CREATE INDEX place_category ON place (category)")
    # The places of a map view: a band of latitudes, then its longitudes.
    db.execute("CREATE INDEX place_lat ON place (lat)")
    db.execute("INSERT INTO place_fts (place_fts) VALUES ('optimize')")
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(f"{len(best)} of {read} places and {len(registered)} charging stations -> {target}")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        assert category("turkish_restaurant", "restaurant") == "amenity=restaurant"
        assert category("doner_kebab_restaurant", None) == "amenity=restaurant"
        assert category("grocery_store", "food_and_beverage_store") == "shop=supermarket"
        assert category("barber", "personal_or_beauty_service") == "shop=hairdresser"
        assert category("ev_charging_station", None) == "amenity=charging_station"
        assert category("lighting_store", "hardware_home_and_garden_store") == "shop=yes"
        assert category("real_estate_agent", "real_estate_service") is None
        assert category(None, None) is None
        for name, tag in [
            ("Beşiktaş 5. Noterliği", "office=notary"), ("Aras Kargo Alba Şubesi", "office=courier"),
            ("Kuaför Ümit", "shop=hairdresser"), ("Murat Oto Kuaför", "amenity=car_wash"), ("Patiş Pet Kuaför", "shop=pet"),
            ("Özay Eczanesi", "amenity=pharmacy"), ("Eczane Tabela Sistemleri", None), ("Rami Televizyon Hastanesi", None),
            ("Sarıyer Lisesi Mezunları Derneği", "office=association"), ("Devlet Hastanesi Durağı", None),
            ("Sinemköy Taksi Durağı", "amenity=taxi"), ("Topkapı Yediemin Otoparkı", None), ("Sedir Otopark", "amenity=parking"),
            ("Pendik İlçe Emniyet Trafik Otoparkı", None), ("Terzioğlu Toplu Konut", None), ("Terzi Fatma", "shop=tailor"),
            ("Lera Mimarlık Restoran İnşaat Sanayi Ticaret Limited Şirketi", None), ("Hatay Döner Künefe", "amenity=restaurant"),
            ("Döner Sermaye İşletme Müdürlüğü", None), ("Bahçeköy Veteriner Kliniği", "amenity=veterinary"),
            ("Veteriner Fakültesi Amfi", None), ("Bağdat Diş Polikliniği", "amenity=dentist"), ("Akın Dış Ticaret", None),
            ("Manolya Sitesi", "landuse=residential"), ("Beysan Sanayi Sitesi", "landuse=industrial"),
            ("Çakıroğlu İş Merkezi", "building=office"), ("Mega Tır Parkı", None), ("Mevlana Parkı", "leisure=park"),
            ("CHZ Oto Servis Ekipmanları", None), ("Burak Oto Servis", "shop=car_repair"), ("Dragos Sosyal Tesisleri", "amenity=restaurant"),
            ("Gürpınar Mahalle Muhtarlığı", "office=government"), ("AK Parti Tuzla İlçe Başkanlığı", None),
        ]:
            assert named(name) == tag, (name, named(name))
        assert category("real_estate_agent", "real_estate_service", "Ali Arslan Gayrimenkul") == "office=estate_agent"
        assert category("turkish_restaurant", "restaurant", "Emlak Lokantası") == "amenity=restaurant"
        assert category("lighting_store", "hardware_home_and_garden_store", "Güneş Halı Yıkama") == "shop=carpet_cleaning"
        assert subtitle({"freeform": "Ankara Cd.  No:57", "locality": "Kartal"}) == "Ankara Cd. No:57, Kartal"
        assert subtitle({"freeform": "Yukarı Mah. Kartal", "locality": "Kartal"}) == "Yukarı Mah. Kartal"
        assert subtitle({"freeform": "Türkiye", "locality": "Kartal"}) == "Kartal"
        assert subtitle({"freeform": None, "locality": None}) == ""
        place = {"names": {"primary": " Kıyı Pastanesi "}, "confidence": 0.99}
        assert wanted(place) == "Kıyı Pastanesi"
        assert wanted({**place, "confidence": 0.39}) is None
        assert wanted({**place, "operating_status": "permanently_closed"}) is None
        assert wanted({"names": {"primary": "Eski Eşya Alanlar 0537 427 48 48"}, "confidence": 0.9}) is None
        assert wanted({"names": {"primary": None}, "confidence": 0.9}) is None
        assert contact({"phones": ["+902163066161"], "websites": ["https://example.com/"]}) == ("+902163066161", "https://example.com/")
        assert contact({"phones": ["ara beni"], "websites": ["example.com"]}) == ("", "")
        assert contact({}) == ("", "")
        assert searchable("McDonald's Kartal") == "mcdonald's kartal mcdonalds kartal"
        assert searchable("Kıyı Pastanesi") == "kiyi pastanesi"
        print("self-test ok")
    else:
        main(*sys.argv[1:4])
