# -*- coding: utf-8 -*-
"""Offline place search index for Istanbul: SQLite with an FTS4 table over Turkish-folded names.

    osmium tags-filter istanbul.osm.pbf nwr/name -o named.osm.pbf
    osmium export named.osm.pbf -f geojsonseq -o named.geojsonseq
    python3 Tools/search/build_index.py named.geojsonseq places.sqlite

The app searches it when Photon cannot be reached (SearchEngine.OfflinePlaceIndex), folding queries the
same way (fold() here == TurkishFold.fold in Swift). Data © OpenStreetMap contributors, ODbL.
"""
import json
import sqlite3
import sys

# Same "key=value" categories Photon reports, so PlaceSymbol picks the same icons.
CATEGORY_KEYS = ["amenity", "shop", "tourism", "leisure", "office", "railway", "public_transport", "aeroway",
                 "healthcare", "place", "highway", "building", "landuse", "natural"]
# Named things a driver searches for; everything else (e.g. named trees, benches) is noise.
SKIP = {("highway", "bus_stop_platform"), ("natural", "tree"), ("amenity", "bench"), ("amenity", "waste_basket")}
FOLD = str.maketrans({"ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u", "â": "a", "î": "i", "û": "u"})


def fold(text):
    """Lowercase with Turkish rules (İ → i, I → ı), then drop the marks: 'Çanakkale' → 'canakkale'."""
    return text.replace("İ", "i").replace("I", "ı").lower().translate(FOLD)


def point(geometry):
    """A representative point: the point itself, a line's middle vertex, a polygon ring's average."""
    kind, coords = geometry["type"], geometry["coordinates"]
    if kind == "Point":
        return coords
    if kind == "LineString":
        return coords[len(coords) // 2]
    if kind == "MultiLineString":
        line = max(coords, key=len)
        return line[len(line) // 2]
    ring = coords[0] if kind == "Polygon" else max((polygon[0] for polygon in coords), key=len)
    return [sum(c[0] for c in ring) / len(ring), sum(c[1] for c in ring) / len(ring)]


def category(tags):
    for key in CATEGORY_KEYS:
        if key in tags:
            return f"{key}={tags[key]}"
    return None


def main(source, target):
    db = sqlite3.connect(target)
    db.executescript("""
        DROP TABLE IF EXISTS place; DROP TABLE IF EXISTS place_fts;
        CREATE TABLE place (id INTEGER PRIMARY KEY, name TEXT NOT NULL, subtitle TEXT NOT NULL,
                            category TEXT, lat REAL NOT NULL, lon REAL NOT NULL);
        CREATE VIRTUAL TABLE place_fts USING fts4(folded, tokenize=unicode61);
        -- OpenStreetMap's opening_hours as mapped, read for one place at a time when its card opens.
        DROP TABLE IF EXISTS hours;
        CREATE TABLE hours (id INTEGER PRIMARY KEY, opening_hours TEXT NOT NULL);
    """)
    seen_streets = set()
    rows = 0
    with_hours = 0
    with open(source, encoding="utf-8") as lines:
        for line in lines:
            line = line.strip().lstrip("\x1e")
            if not line:
                continue
            feature = json.loads(line)
            tags = feature.get("properties") or {}
            name = (tags.get("name") or "").strip()
            if not name or feature.get("geometry") is None:
                continue
            cat = category(tags)
            if cat and tuple(cat.split("=", 1)) in SKIP:
                continue
            lon, lat = point(feature["geometry"])
            if cat and cat.startswith("highway="):
                # A street is many ways with one name; keep one per ~1 km cell.
                key = (fold(name), round(lat, 2), round(lon, 2))
                if key in seen_streets:
                    continue
                seen_streets.add(key)
            street = tags.get("addr:street", "")
            number = tags.get("addr:housenumber", "")
            subtitle = " ".join(part for part in (street, number) if part) or tags.get("addr:district") or tags.get("addr:suburb") or ""
            cursor = db.execute("INSERT INTO place (name, subtitle, category, lat, lon) VALUES (?, ?, ?, ?, ?)",
                                (name, subtitle, cat, round(lat, 6), round(lon, 6)))
            db.execute("INSERT INTO place_fts (docid, folded) VALUES (?, ?)", (cursor.lastrowid, fold(name)))
            hours = (tags.get("opening_hours") or "").strip()
            if hours and len(hours) <= 255:
                db.execute("INSERT INTO hours (id, opening_hours) VALUES (?, ?)", (cursor.lastrowid, hours))
                with_hours += 1
            rows += 1
    db.execute("INSERT INTO place_fts (place_fts) VALUES ('optimize')")
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(f"{rows} places, {with_hours} with opening hours -> {target}")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        assert fold("İstanbul Çanakkale Iğdır Şişli Gümüşpınar") == "istanbul canakkale igdir sisli gumuspinar"
        assert point({"type": "LineString", "coordinates": [[1, 1], [2, 2], [3, 3]]}) == [2, 2]
        assert point({"type": "Polygon", "coordinates": [[[0, 0], [2, 0], [2, 2], [0, 2]]]}) == [1, 1]
        assert category({"amenity": "hospital", "building": "yes"}) == "amenity=hospital"
        print("self-test ok")
    else:
        main(sys.argv[1], sys.argv[2])
