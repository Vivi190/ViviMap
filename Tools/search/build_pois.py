# -*- coding: utf-8 -*-
"""Business search index for Istanbul: the shops, restaurants, offices and other places of the Overture Maps
places theme, in the schema of the OSM index (build_index.py) so the app searches both the same way.

    pip install overturemaps
    overturemaps download --bbox=28.0,40.75,29.95,41.6 -f geojsonseq --type=place -o overture-places.geojsonseq
    python3 Tools/search/build_pois.py overture-places.geojsonseq pois.sqlite

A file of its own, not rows in the OSM index: the two sources carry different licences, and nothing here is
derived from OpenStreetMap. Data © Overture Maps Foundation and its sources (Meta, Microsoft, Foursquare,
AllThePlaces and others); each record is under CDLA-Permissive-2.0, Apache-2.0 or CC0-1.0.
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
    "gas_station": "amenity=fuel", "parking": "amenity=parking",
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
    "language_school": "amenity=college", "driving_school": "amenity=driving_school", "music_school": "amenity=college",
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
    "specialty_school": "amenity=college", "government_office": "office=government",
    "auto_dealer": "shop=car", "vehicle_dealer": "shop=car", "gym": "leisure=fitness_centre",
    "fitness_studio": "leisure=fitness_centre", "sport_or_fitness_facility": "leisure=fitness_centre",
    "shopping": "shop=yes", "shopping_mall": "shop=mall",
}


def category(specific, basic):
    """The OSM tag for a place of Overture's `taxonomy.primary` and `basic_category`; None for kinds the app
    has no use for (services, offices, factories), which show a plain pin."""
    if specific in SPECIFIC:
        return SPECIFIC[specific]
    if basic in BASIC:
        return BASIC[basic]
    if specific and specific.endswith("_restaurant"):
        return "amenity=restaurant"
    if (specific and specific.endswith("_store")) or (basic and basic.endswith("_store")):
        return "shop=yes"
    return None


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


def wanted(properties):
    """A place worth a row: named, likely to exist, open, and not an advertisement posing as a name."""
    name = clean((properties.get("names") or {}).get("primary"))
    if not name or len(name) > 90 or PHONE.search(name):
        return None
    if (properties.get("confidence") or 0) < MIN_CONFIDENCE or properties.get("operating_status") in CLOSED:
        return None
    return name


def main(source, target):
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
                   category(taxonomy.get("primary"), properties.get("basic_category")), round(lat, 6), round(lon, 6),
                   *contact(properties))
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
        -- Read for one place at a time, when its card opens; a table of its own keeps the searched one small.
        DROP TABLE IF EXISTS contact;
        CREATE TABLE contact (id INTEGER PRIMARY KEY, phone TEXT, website TEXT);
    """)
    for confidence, name, line, kind, lat, lon, phone, site in best.values():
        cursor = db.execute("INSERT INTO place (name, subtitle, category, lat, lon, weight) VALUES (?, ?, ?, ?, ?, ?)",
                            (name, line, kind, lat, lon, round(confidence * 100)))
        db.execute("INSERT INTO place_fts (docid, folded) VALUES (?, ?)", (cursor.lastrowid, fold(name)))
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
    print(f"{len(best)} of {read} places -> {target}")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        assert category("turkish_restaurant", "restaurant") == "amenity=restaurant"
        assert category("doner_kebab_restaurant", None) == "amenity=restaurant"
        assert category("grocery_store", "food_and_beverage_store") == "shop=supermarket"
        assert category("barber", "personal_or_beauty_service") == "shop=hairdresser"
        assert category("lighting_store", "hardware_home_and_garden_store") == "shop=yes"
        assert category("real_estate_agent", "real_estate_service") is None
        assert category(None, None) is None
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
        print("self-test ok")
    else:
        main(sys.argv[1], sys.argv[2])
