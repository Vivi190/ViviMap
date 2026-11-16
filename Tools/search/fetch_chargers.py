# -*- coding: utf-8 -*-
"""Istanbul's public charging stations from the energy regulator's register, as the municipality republishes
it: the rows build_pois.py adds to the business index. Overture has 85 chargers for the city, the register
2 029 public ones.

    python -X utf8 Tools/search/fetch_chargers.py

Writes Tools/search/chargers-istanbul.json: [name, subtitle, lat, lon] per station, e.g. ["ZES Kartal Sahil
Migros", "AC 22 kW · 2 soket · Kartal", 40.8889, 29.1885]. Kept in the repository, like the hazard files, so
that building the index needs no connection to the municipality's servers. Data: İstanbul Büyükşehir
Belediyesi, "Elektrikli Araç Şarj İstasyonları Verisi" and "… Soket Verileri" (EPDK's register, published
2025-05-13), İBB Açık Veri Lisansı (https://data.ibb.gov.tr/license). Stations opened since are missing.
"""
import collections
import csv
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import date
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_index import fold  # noqa: E402

PORTAL = "https://data.ibb.gov.tr/dataset/"
STATIONS = PORTAL + "79b0e26e-e923-498b-a675-453382274178/resource/726e9d82-37f7-4142-8fa0-4f70a5530188/download/sarj_istasyonlari.geojson"
SOCKETS = PORTAL + "17f75354-1553-4a74-a90f-3a79680343c9/resource/ff424a4c-6478-455c-9bd5-b597a7df7df1/download/sarj_istasyon_soket.csv"
OUT = Path(__file__).resolve().parent / "chargers-istanbul.json"


def clean(text):
    return " ".join((text or "").split())


def proper(text):
    """A register entry as a name is written: words in capitals get one capital ("ÜMRANİYE ZIRHLI" becomes
    "Ümraniye Zırhlı"); words of up to three letters (AVM, OHT) and words with small letters in them ("60kW",
    "Trugo") are left as they are. So is a word with an I in a text without Turkish letters: "KISIM" wants
    "Kısım" and "CHARGING" "Charging", and nothing there says which language it is."""
    turkish = any(c in "ÇĞİÖŞÜçğıöşü" for c in text)

    def one(part):
        letters = [c for c in part if c.isalpha()]
        if len(letters) <= 3 or not all(c.isupper() for c in letters) or ("I" in part and not turkish):
            return part
        lower, vowel = "", ""
        for c in part:
            # Vowel harmony: an ı follows a, ı, o or u; after e, i, ö or ü the I is an i ("CHARGEINN").
            lower += ("i" if vowel in ("E", "İ", "Ö", "Ü") else "ı") if c == "I" else "i" if c == "İ" else c.lower()
            vowel = c if c in "AEIİOÖUÜ" else vowel
        return {"i": "İ", "ı": "I"}.get(lower[0], lower[0].upper()) + lower[1:]
    # "TOGER-RÜYA EVLERİ": the parts of a hyphenated word one by one.
    return " ".join("-".join(one(part) for part in word.split("-")) for word in text.split())


def brand_name(text):
    """A brand near enough to how its owner writes it, whatever the register did: "zes" is ZES, "eşarj"
    Eşarj, "VOLTRUN" Voltrun."""
    return proper(" ".join(word.replace("i", "İ").replace("ı", "I").upper() if word.islower() else word
                           for word in text.split()))


# "DC-1", "- AC 2", a closing "- DC": the units of a station. Not "AC 44 kW".
UNIT = re.compile(r"\s*[-–]?\s*\b(?:AC|DC)\s*[-–]?\s*\d+\b(?!\s*kw)|\s*[-–]\s*(?:AC|DC)\s*$", re.IGNORECASE)


def station_name(text):
    """One name for an entry that lists its units: "Kuyumcukent AC-1, Kuyumcukent AC-2" is "Kuyumcukent",
    "Viaport Marina 1, Viaport Marina 2" is "Viaport Marina". A place after a comma stays ("Şahsuvaroğlu, Pendik")."""
    parts = [part for part in (clean(UNIT.sub("", part)) for part in text.split(",")) if part]
    bare = [re.sub(r"\s*\d+$", "", part) for part in parts]
    if len(parts) > 1 and len({fold(part) for part in bare}) == 1:
        parts = bare
    return ", ".join(dict.fromkeys(parts))


def power(kilowatts):
    """22.0 -> "22", 7.4 -> "7,4"."""
    return f"{kilowatts:g}".replace(".", ",")


def chargers(stations, sockets):
    """The public charging stations of the register as rows of the index: (name, subtitle, lat, lon).

    "ZES Kartal Sahil Migros", "AC 22 kW · 2 soket · Kartal": the operator's brand leads the name, since that is
    what a driver looks for; the subtitle says how fast and how many. The units one operator registered at one
    spot are one station. Stations for an owner's own use (HIZMET_SEKLI "OZEL") are left out.
    """
    plugs = collections.defaultdict(list)
    with open(sockets, encoding="utf-8-sig", newline="") as lines:
        for row in csv.DictReader(lines):
            try:
                plugs[row["ISTASYON_NO"]].append((float(row["SOKET_GUCU"]), row["SOKET_TIPI"]))
            except (KeyError, ValueError):
                continue
    with open(stations, encoding="utf-8") as file:
        features = json.load(file)["features"]
    merged = {}
    for feature in features:
        properties = feature.get("properties") or {}
        geometry = feature.get("geometry") or {}
        if properties.get("HIZMET_SEKLI") != "HALKA_ACIK" or geometry.get("type") != "Point":
            continue
        lon, lat = geometry["coordinates"][:2]
        name = clean(properties.get("AD"))
        if not name or not (40.5 <= lat <= 41.7 and 27.9 <= lon <= 30.0):
            continue
        brand = clean(properties.get("MARKA_TESCIL_BELGESI"))
        station = merged.setdefault((fold(brand), round(lat, 4), round(lon, 4)), {
            "name": name, "brand": brand, "lat": lat, "lon": lon, "plugs": [],
            # "… No:3 Kartal / İSTANBUL": the district is the word before the city.
            "district": clean(properties.get("ADRES")).rsplit("/", 1)[0].split()[-1:],
        })
        station["plugs"] += plugs.get(properties.get("ISTASYON_NO"), [])
    rows = []
    for station in merged.values():
        name = proper(station_name(station["name"]))
        brand = brand_name(station["brand"])
        # A legal name in the brand field ("… SAN. ve TİC. LTD. ŞTİ.") is no brand to lead with.
        if brand and len(brand.split()) <= 3 and fold(station["brand"]) not in fold(name):
            name = f"{brand} {name}"
        parts = []
        if station["plugs"]:
            # The fastest current decides: a station with one DC plug is where a driver in a hurry goes.
            current = "DC" if any(kind == "DC" for _, kind in station["plugs"]) else "AC"
            fastest = max(kilowatts for kilowatts, kind in station["plugs"] if kind == current)
            parts += [f"{current} {power(fastest)} kW", f"{len(station['plugs'])} soket"]
        parts += [proper(word) for word in station["district"]]
        rows.append((name[:90], " · ".join(parts), round(station["lat"], 6), round(station["lon"], 6)))
    return rows


def download(url, target):
    # curl, not urllib: the portal's server leaves out its intermediate certificate, which the system's TLS
    # fetches by itself and Python's does not.
    subprocess.run(["curl", "-fsSL", "--retry", "3", "-A", "Atlas-iOS/1.0 (personal navigation app)", "-o", target, url],
                   check=True)


def main():
    with tempfile.TemporaryDirectory() as folder:
        stations, sockets = os.path.join(folder, "stations.geojson"), os.path.join(folder, "sockets.csv")
        download(STATIONS, stations)
        download(SOCKETS, sockets)
        rows = sorted(chargers(stations, sockets), key=lambda row: (row[2], row[3], row[0]))
    OUT.write_text(json.dumps({
        "source": "EPDK şarj istasyonu kayıtları, İstanbul Büyükşehir Belediyesi Açık Veri Portalı (İBB Açık Veri Lisansı)",
        "published": "2025-05-13",
        "fetched": date.today().isoformat(),
        "count": len(rows),
        "stations": [list(row) for row in rows],
    }, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"{len(rows)} public charging stations -> {OUT}")


def self_test():
    assert proper("ÜMRANİYE ZIRHLI") == "Ümraniye Zırhlı"
    assert proper("CAROUSEL AVM") == "Carousel AVM"
    assert proper("İÇERENKÖY 60kW") == "İçerenköy 60kW"
    assert proper("Kartal Sahil Migros") == "Kartal Sahil Migros"
    assert proper("IŞIKLAR") == "Işıklar"
    assert proper("MINUS ENERGY") == "MINUS Energy"
    assert proper("CHARGEINN PENDİK KİRAZLI") == "Chargeinn Pendik Kirazlı"
    assert proper("TOGER-RÜYA EVLERİ 2") == "Toger-Rüya Evleri 2"
    assert [brand_name(b) for b in ("zes", "eşarj", "wat mobilite", "VOLTRUN", "Trugo")] == \
        ["ZES", "Eşarj", "WAT Mobilite", "Voltrun", "Trugo"]
    assert station_name("Kuyumcukent AC-1, Kuyumcukent AC-2, Kuyumcukent AC-3") == "Kuyumcukent"
    assert station_name("Viaport Marina Tuzla 1, Viaport Marina Tuzla 2") == "Viaport Marina Tuzla"
    assert station_name("Vizyon Park, Kartal - DC -1, DC - 2, AC - 1") == "Vizyon Park, Kartal"
    assert station_name("Şahsuvaroğlu, Pendik") == "Şahsuvaroğlu, Pendik"
    assert station_name("Eon, Sultanbeyli - DC, AC - 1, AC - 2") == "Eon, Sultanbeyli"
    assert station_name("İstanbul Evleri Han 7 / AC 44 kW") == "İstanbul Evleri Han 7 / AC 44 kW"
    assert station_name("Firuze Sitesi 2") == "Firuze Sitesi 2"
    assert power(22.0) == "22" and power(7.4) == "7,4"
    with tempfile.TemporaryDirectory() as folder:
        stations, sockets = os.path.join(folder, "stations.geojson"), os.path.join(folder, "sockets.csv")

        def station(number, name, brand, lon, lat, service="HALKA_ACIK", address="Kordonboyu Mahallesi  No:3 Kartal / İSTANBUL"):
            return {"type": "Feature", "geometry": {"type": "Point", "coordinates": [lon, lat]},
                    "properties": {"ISTASYON_NO": number, "AD": name, "ADRES": address, "HIZMET_SEKLI": service,
                                   "MARKA_TESCIL_BELGESI": brand}}
        with open(stations, "w", encoding="utf-8") as file:
            json.dump({"features": [
                station("ŞRJ/1", "Kartal Sahil Migros", "zes", 29.19, 40.889),
                station("ŞRJ/2", "ÖRNEK AVM", "eşarj", 29.20, 40.890), station("ŞRJ/3", "ÖRNEK AVM 2", "eşarj", 29.20, 40.890),
                station("ŞRJ/4", "Site Yönetimi", "zes", 29.21, 40.891, service="OZEL"),
                station("ŞRJ/5", "TOGER - ÖRNEK BELEDİYESİ", "TOGER", 29.22, 40.892, address=""),
            ]}, file)
        with open(sockets, "w", encoding="utf-8-sig", newline="") as file:
            file.write("ISTASYON_NO,SOKET_GUCU,SOKET_NO,SOKET_TIPI,SOKET_TURU\n"
                       "ŞRJ/1,22,SKT/1,AC,AC_TYPE2\nŞRJ/1,7.4,SKT/2,AC,AC_TYPE2\n"
                       "ŞRJ/2,180,SKT/3,DC,DC_CCS\nŞRJ/2,22,SKT/4,AC,AC_TYPE2\nŞRJ/3,120,SKT/5,DC,DC_CCS\n")
        assert chargers(stations, sockets) == [
            ("ZES Kartal Sahil Migros", "AC 22 kW · 2 soket · Kartal", 40.889, 29.19),
            # Two units of one operator at one spot: one station, its sockets together.
            ("Eşarj Örnek AVM", "DC 180 kW · 3 soket · Kartal", 40.89, 29.2),
            # No sockets on record, no address; the brand is in the name already.
            ("Toger - Örnek Belediyesi", "", 40.892, 29.22),
        ], chargers(stations, sockets)
    print("self-test ok")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
    else:
        main()
