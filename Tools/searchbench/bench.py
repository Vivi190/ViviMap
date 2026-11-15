# -*- coding: utf-8 -*-
"""Search benchmark: does the app's first result point at the place the driver meant?

For each query the intended place is looked up in OSM (Overpass, by tag + name) and the query is sent to
Photon with the app's parameters; the app's re-ranking (PlaceRanking in PhotonSearchProvider.swift) is
replicated here. A hit is a result within `radius` metres of the intended OSM geometry.

This measures ranking and recall on OSM data, not whether OSM itself is right.

    python -X utf8 Tools/searchbench/bench.py > docs/research/search-bench.md
    # Targets from a local extract instead of Overpass (.github/workflows/search-bench.yml):
    python3 Tools/searchbench/bench.py --osm-file named.geojsonseq > search-bench.md
"""
import argparse
import json
import math
import os
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

UA = "Atlas-iOS/1.0 (personal navigation app; search benchmark)"
PHOTON = "https://photon.komoot.io/api/"
PHOTON_REVERSE = "https://photon.komoot.io/reverse"
# Public instances take turns being overloaded (502); another one can be set with OVERPASS_URL.
OVERPASS = os.environ.get("OVERPASS_URL", "https://overpass-api.de/api/interpreter")
TURKEY_BBOX = "25.6,35.8,44.9,42.2"
ISTANBUL = "(40.75,28.0,41.6,29.95)"  # south, west, north, east
KARTAL = (40.8890, 29.1905)  # the app biases results towards the user; benchmark user stands here

# Mirrors PlaceRanking in PhotonSearchProvider.swift.
BOOSTS = [
    (["belediye"], {"amenity=townhall"}),
    (["istasyon", "marmaray", "metro", "tren", "gar"], {"railway=station", "railway=halt", "public_transport=station"}),
    (["hastane"], {"amenity=hospital"}),
    (["havalimanı", "havaalanı"], {"aeroway=aerodrome"}),
    (["adliye"], {"amenity=courthouse"}),
]
STOPS = {"highway=bus_stop", "public_transport=platform", "public_transport=stop_position"}
# Mirrors PlaceRanking.focusRules: a query naming a kind of place also asks Photon for that kind alone.
FOCUS = [
    ({"durak", "durağı"}, ["highway:bus_stop", "public_transport:platform"]),
    ({"istasyon", "istasyonu", "metro", "metrosu", "marmaray", "tren", "gar", "garı"},
     ["railway:station", "railway:halt", "public_transport:station"]),
    ({"avm"}, ["shop:mall"]),
    ({"iskele", "iskelesi"}, ["amenity:ferry_terminal"]),
    ({"otopark", "otoparkı"}, ["amenity:parking"]),
]
# Mirrors PlaceRanking.kinds.
KINDS = {word: tags for words, tags in [
    (["benzinlik", "benzin istasyonu", "akaryakıt", "akaryakıt istasyonu", "petrol istasyonu"], ["amenity:fuel"]),
    (["eczane"], ["amenity:pharmacy"]),
    (["otopark", "park yeri"], ["amenity:parking"]),
    (["şarj", "şarj istasyonu", "şarj noktası"], ["amenity:charging_station"]),
    (["hastane"], ["amenity:hospital"]),
    (["market", "süpermarket"], ["shop:supermarket", "shop:convenience"]),
    (["atm", "bankamatik"], ["amenity:atm"]),
    (["banka"], ["amenity:bank"]),
    (["kafe", "cafe"], ["amenity:cafe"]),
    (["restoran", "restaurant", "lokanta"], ["amenity:restaurant"]),
    (["fırın"], ["shop:bakery"]),
    (["avm", "alışveriş merkezi"], ["shop:mall"]),
    (["polis", "karakol"], ["amenity:police"]),
    (["durak", "otobüs durağı"], ["highway:bus_stop"]),
    (["metro", "istasyon", "metro istasyonu", "tren istasyonu"], ["railway:station"]),
    (["iskele", "vapur iskelesi"], ["amenity:ferry_terminal"]),
    (["taksi", "taksi durağı"], ["amenity:taxi"]),
    (["oto yıkama", "otoyıkama"], ["amenity:car_wash"]),
    (["lastikçi"], ["shop:tyres"]),
    (["ptt", "postane"], ["amenity:post_office"]),
    (["tuvalet", "wc"], ["amenity:toilets"]),
    (["otel"], ["tourism:hotel"]),
] for word in words}
KIND_PREFIXES = ["en yakın ", "yakınımdaki ", "yakındaki ", "yakınımda ", "yakında "]
# Bare kinds measured apart: the target is "the right kind, close by", not one OSM object.
KIND_CASES = ["benzinlik", "eczane", "otopark", "hastane", "market", "en yakın atm", "şarj istasyonu", "kafe"]
KIND_RADIUS_KM = 3
# Mirrors PlaceRanking.lines.
LINES = {"railway=rail", "railway=subway", "railway=light_rail", "railway=tram", "railway=monorail", "railway=narrow_gauge",
         "railway=funicular", "railway=construction", "railway=proposed", "railway=abandoned", "railway=disused",
         "highway=construction", "highway=proposed"}
# Mirrors PlaceRanking.addressSteps / streetWord / numberAfterStreet.
ADDRESS_STEPS = [
    (r"(?<!\w)iç\s+kapı(?:\s+no)?\s*[\.:]?\s*\d+\w*", " "),
    (r"(?<!\w)dış\s+kapı(?!\w)", " "),
    (r"(?<!\w)(?:d|k)\s*[\.:]\s*\d+\w*", " "),
    (r"(?<!\w)(?:daire|kat)\s*[\.:]?\s*\d+\w*", " "),
    (r"(?<!\w)(?:no|numara|nu)\s*[\.:]?\s*(\d+[a-zçğıöşü]?)(?:\s*/\s*\d+)?(?!\w)", r" \1 "),
    (r"/", " "),
    (r"(?<!\w)(?:cad|cd)(?:\.|(?!\w))", " caddesi "),
    (r"(?<!\w)(?:sok|sk)(?:\.|(?!\w))", " sokak "),
    (r"(?<!\w)(?:mah|mh)(?:\.|(?!\w))", " mahallesi "),
    (r"(?<!\w)(?:blv|bulv)(?:\.|(?!\w))|(?<!\w)bul\.", " bulvarı "),
]
STREET_WORD = r"(?<!\w)(?:caddesi|cadde|sokak|sokağı|bulvarı|bulvar|yolu)(?!\w)"
NUMBER_AFTER_STREET = r"(?<!\w)(?:caddesi|cadde|sokak|sokağı|bulvarı|bulvar|yolu)\s+(\d+[a-zçğıöşü]?)(?!\w)"
SAME_STREET_WORD = {"sokağı": "sokak", "cadde": "caddesi", "bulvar": "bulvarı"}


def turkish_lower(text):
    return text.replace("I", "ı").replace("İ", "i").lower()


def words_of(text):
    """PlaceRanking.words: lowercased, "sokağı"/"sokak" alike, padded so a match is whole words."""
    return " " + " ".join(SAME_STREET_WORD.get(w, w) for w in turkish_lower(text).split()) + " "


def address(query):
    """PlaceRanking.address: the query in OSM's spelling and its house number; other queries unchanged."""
    lower = turkish_lower(query)
    text = lower
    for pattern, template in ADDRESS_STEPS:
        text = re.sub(pattern, template, text)
    text = " ".join(text.split())
    number = re.search(NUMBER_AFTER_STREET, text)
    return (text if text != " ".join(lower.split()) else query), (number.group(1) if number else None)


def app_rank(features, query):
    text = turkish_lower(address(query)[0])
    query_words = words_of(text)
    street = re.search(STREET_WORD, text) is not None
    focused = focus(query)
    if focused:
        boosted = {tag.replace(":", "=") for tag in focused[1]}
    elif street:
        boosted = set()
    else:
        boosted = set().union(*[cats for words, cats in BOOSTS if any(w in text for w in words)] or [set()])
    wants_stops = not street and ("durak" in text or "durağ" in text)

    def bucket(f):
        p = f["properties"]
        category = f"{p.get('osm_key')}={p.get('osm_value')}" if p.get("osm_key") else None
        if category is None:
            return 2
        if category in LINES:
            return 4
        if p.get("street") and p.get("housenumber") and words_of(f"{p['street']} {p['housenumber']}") in query_words:
            return 0
        if wants_stops:
            return 1 if category in STOPS else 2
        if category in boosted or (street and category.startswith("highway=") and category not in STOPS):
            return 1
        return 3 if category in STOPS else 2

    return [f for _, f in sorted(enumerate(features), key=lambda e: (bucket(e[1]), e[0]))]


def get_json(url, data=None, timeout=90):
    req = urllib.request.Request(url, data=data, headers={"User-Agent": UA})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.load(r)
        except Exception as error:  # rate limits / timeouts on public servers
            if attempt == 3:
                raise
            time.sleep(10 * (attempt + 1))


def photon(query, tags=()):
    params = {"q": query, "limit": "12", "bbox": TURKEY_BBOX, "lang": "default", "lat": KARTAL[0], "lon": KARTAL[1],
              "osm_tag": list(tags)}
    return get_json(PHOTON + "?" + urllib.parse.urlencode(params, doseq=True)).get("features", [])


def focus(query):
    text = turkish_lower(address(query)[0])
    if re.search(STREET_WORD, text):  # "istasyon caddesi": the kind word is part of the street's name
        return None
    words = text.split()
    for kind_words, tags in FOCUS:
        name = [w for w in words if w not in kind_words]
        if len(name) < len(words) and name:
            return " ".join(name), tags
    return None


def kind(query):
    """PlaceRanking.kind: the Photon tags of a bare kind of place ("benzinlik", "en yakın eczane"), else None."""
    text = " ".join(turkish_lower(query).split())
    prefix = next((p for p in KIND_PREFIXES if text.startswith(p)), "")
    text = text[len(prefix):]
    singular = text[:-3] if text.endswith(("ler", "lar")) else text
    return KINDS.get(text) or KINDS.get(singular)


def photon_nearest(tags):
    """PhotonSearchProvider.reverseRequest with tags: the nearest 12 of a kind within 15 km, nearest first."""
    params = {"lat": KARTAL[0], "lon": KARTAL[1], "limit": "12", "radius": "15", "lang": "default", "osm_tag": list(tags)}
    return get_json(PHOTON_REVERSE + "?" + urllib.parse.urlencode(params, doseq=True)).get("features", [])


def app_search(query):
    """PhotonSearchProvider.search: a bare kind lists the nearest; otherwise the focused hits first, then the
    general answer without repeats."""
    tags = kind(query)
    if tags:
        nearest = photon_nearest(tags)
        if nearest:
            return nearest
    query = address(query)[0]
    general = photon(query)
    focused = focus(query)
    if not focused:
        return app_rank(general, query)
    time.sleep(1.2)
    first = photon(*focused)
    ident = lambda f: f"{f['properties'].get('osm_type')}{f['properties'].get('osm_id')}"
    shown = {ident(f) for f in first}
    return app_rank(first + [f for f in general if ident(f) not in shown], query)


def overpass_targets(cases, chunk=8):
    """Targets in a few batched requests (the public servers throttle per request): each case's elements
    are followed by a synthetic `sep` element carrying the case number. A case with no `sep` was never
    answered (the server cut the batch short, see its `remark`), which is not the same as "not in OSM"."""
    targets = {}
    for start in range(0, len(cases), chunk):
        part = cases[start:start + chunk]
        query = "[out:json][timeout:180];" + "".join(
            f'nwr{case["osm"]}{case.get("bbox", ISTANBUL)};out geom;make sep case="{start + i}";out;'
            for i, case in enumerate(part)
        )
        body = get_json(OVERPASS, data=urllib.parse.urlencode({"data": query}).encode(), timeout=200)
        if body.get("remark"):
            print(f"overpass remark for cases {start}-{start + len(part) - 1}: {body['remark']}", file=sys.stderr)
        current = []
        for element in body.get("elements", []):
            if element.get("type") == "sep":
                targets[int(element["tags"]["case"])] = current
                current = []
            else:
                current.append(element)
        time.sleep(5)
    return targets


FILTER = re.compile(r'\["([^"]+)"(?:(=|~)"((?:[^"\\]|\\.)*)"(,i)?)?\]')


def parse_filter(text):
    """The Overpass tag filters queries.json uses: ["k"], ["k"="v"], ["k"~"regex"], ["k"~"regex",i]."""
    tests = []
    for key, op, value, ignore_case in FILTER.findall(text):
        if not op:
            tests.append(lambda tags, k=key: k in tags)
        elif op == "=":
            tests.append(lambda tags, k=key, v=value: tags.get(k) == v)
        else:
            pattern = re.compile(value, re.IGNORECASE if ignore_case else 0)
            tests.append(lambda tags, k=key, p=pattern: k in tags and p.search(tags[k]) is not None)
    return tests


def parse_bbox(text):
    south, west, north, east = (float(v) for v in text.strip("()").split(","))
    return south, west, north, east


def as_elements(geometry):
    """GeoJSON geometry → the Overpass element shapes distance_to() reads."""
    kind, coords = geometry["type"], geometry["coordinates"]
    line = lambda points: [{"lat": lat, "lon": lon} for lon, lat in points]
    if kind == "Point":
        return [{"type": "node", "lat": coords[1], "lon": coords[0]}]
    if kind == "LineString":
        return [{"type": "way", "geometry": line(coords)}]
    rings = coords if kind in ("MultiLineString", "Polygon") else [ring for polygon in coords for ring in polygon]
    return [{"type": "relation", "members": [{"geometry": line(ring)} for ring in rings]}]


def file_targets(cases, path):
    """Targets from an `osmium export` geojsonseq of named objects: the same OSM data, no public server."""
    tests = [parse_filter(case["osm"]) for case in cases]
    boxes = [parse_bbox(case.get("bbox", ISTANBUL)) for case in cases]
    targets = {number: [] for number in range(len(cases))}
    with open(path, encoding="utf-8") as source:
        for line in source:
            line = line.strip().lstrip("\x1e")
            if not line:
                continue
            feature = json.loads(line)
            tags = feature.get("properties") or {}
            matching = [n for n, case_tests in enumerate(tests) if all(test(tags) for test in case_tests)]
            if not matching or feature.get("geometry") is None:
                continue
            elements = as_elements(feature["geometry"])
            points = [(e["lat"], e["lon"]) for e in elements if e["type"] == "node"] + [
                (c["lat"], c["lon"]) for e in elements for g in [e.get("geometry")] + [m["geometry"] for m in e.get("members", [])] if g for c in g
            ]
            for number in matching:
                south, west, north, east = boxes[number]
                if any(south <= lat <= north and west <= lon <= east for lat, lon in points):
                    targets[number].extend(elements)
    return targets


def inside(point, ring):
    """Ray casting on a closed ring of (lat, lon)."""
    y, x = point
    hit = False
    for (y1, x1), (y2, x2) in zip(ring, ring[1:]):
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            hit = not hit
    return hit


def metres(a, b):
    lat = math.radians((a[0] + b[0]) / 2)
    dx = (b[1] - a[1]) * 111_320 * math.cos(lat)
    dy = (b[0] - a[0]) * 110_540
    return math.hypot(dx, dy)


def to_segment(p, a, b):
    """Distance from p to segment ab in metres (local flat projection)."""
    lat = math.radians(p[0])
    ax, ay = (a[1] - p[1]) * 111_320 * math.cos(lat), (a[0] - p[0]) * 110_540
    bx, by = (b[1] - p[1]) * 111_320 * math.cos(lat), (b[0] - p[0]) * 110_540
    dx, dy = bx - ax, by - ay
    t = 0.0 if dx == dy == 0 else max(0.0, min(1.0, -(ax * dx + ay * dy) / (dx * dx + dy * dy)))
    return math.hypot(ax + t * dx, ay + t * dy)


def distance_to(elements, point):
    best = math.inf
    for e in elements:
        if e["type"] == "node":
            best = min(best, metres(point, (e["lat"], e["lon"])))
        lines = [e.get("geometry")] if e.get("geometry") else [m.get("geometry") for m in e.get("members", [])]
        for line in filter(None, lines):
            coords = [(c["lat"], c["lon"]) for c in line if c]
            # Inside an area (campus, airport, mall) counts as on target.
            if len(coords) > 3 and coords[0] == coords[-1] and inside(point, coords):
                return 0.0
            for a, b in zip(coords, coords[1:]):
                best = min(best, to_segment(point, a, b))
            if len(coords) == 1:
                best = min(best, metres(point, coords[0]))
    return best


def self_test():
    tags = {"amenity": "hospital", "name": "T.C. Sağlık Bakanlığı Pendik Devlet Hastanesi"}
    assert all(t(tags) for t in parse_filter('["amenity"="hospital"]["name"~"Pendik Devlet Hastanesi"]'))
    assert not all(t(tags) for t in parse_filter('["amenity"="hospital"]["name"~"^Pendik"]'))
    assert all(t({"shop": "mall", "name": "VIAPORT"}) for t in parse_filter('["shop"="mall"]["name"~"Viaport",i]'))
    assert all(t({"highway": "primary", "name": "Canakkale Caddesi"}) for t in parse_filter('["highway"]["name"~"^[ÇC]anakkale Caddesi$"]'))
    assert not parse_filter('["highway"]')[0]({"name": "x"})
    assert parse_bbox("(40.86,29.14,40.94,29.25)") == (40.86, 29.14, 40.94, 29.25)
    assert address("Yakacık Mah. Atatürk Cad. No:12 D:5 Kartal/İstanbul") == ("yakacık mahallesi atatürk caddesi 12 kartal istanbul", "12")
    assert address("ATATÜRK CAD. DIŞ KAPI NO: 12 İÇ KAPI NO: 3 KARTAL") == ("atatürk caddesi 12 kartal", "12")
    assert address("Doğa Sk. No:5/2") == ("doğa sokak 5", "5")
    assert address("Ankara Caddesi 5 Kartal") == ("Ankara Caddesi 5 Kartal", "5")
    assert address("Kartal 5 Nolu Aile Sağlığı Merkezi") == ("Kartal 5 Nolu Aile Sağlığı Merkezi", None)
    assert focus("istasyon caddesi tuzla") is None and focus("istanbul havalimanı otopark") == ("istanbul havalimanı", ["amenity:parking"])
    assert kind("benzinlik") == ["amenity:fuel"] and kind("En yakın eczane") == ["amenity:pharmacy"]
    assert kind("marketler") == ["shop:supermarket", "shop:convenience"] and kind("yakındaki otoparklar") == ["amenity:parking"]
    assert kind("akasya avm") is None and kind("nöbetçi eczane") is None
    square = {"type": "Polygon", "coordinates": [[[29.0, 41.0], [29.01, 41.0], [29.01, 41.01], [29.0, 41.01], [29.0, 41.0]]]}
    assert distance_to(as_elements(square), (41.005, 29.005)) == 0.0  # inside an area
    assert 100 < distance_to(as_elements(square), (41.005, 29.0115)) < 200  # ~126 m east of it
    print("self-test ok")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--osm-file", help="geojsonseq of named OSM objects (osmium export) instead of Overpass")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    cases = json.loads(Path(__file__).with_name("queries.json").read_text(encoding="utf-8"))
    rows, hits1, hits3, scored = [], 0, 0, 0
    all_targets = file_targets(cases, args.osm_file) if args.osm_file else overpass_targets(cases)
    for number, case in enumerate(cases):
        if number not in all_targets:
            rows.append((case["query"], "—", "Overpass yanıt vermedi (ölçülmedi)", ""))
            continue
        targets = all_targets[number]
        if not targets:
            rows.append((case["query"], "—", "hedef OSM'de bulunamadı (ölçüm dışı)", ""))
            continue
        ranked = app_search(case["query"])
        time.sleep(1.2)
        radius = case.get("radius", 150)
        distances = [distance_to(targets, (f["geometry"]["coordinates"][1], f["geometry"]["coordinates"][0])) for f in ranked]
        rank = next((i + 1 for i, d in enumerate(distances) if d <= radius), None)
        scored += 1
        hits1 += rank == 1
        hits3 += rank is not None and rank <= 3
        first = ranked[0]["properties"].get("name") or ranked[0]["properties"].get("street") or "?" if ranked else "(sonuç yok)"
        verdict = "✅ 1." if rank == 1 else (f"🟡 {rank}." if rank and rank <= 3 else (f"❌ {rank}." if rank else "❌ yok"))
        rows.append((case["query"], verdict, first, f"{distances[0]:.0f} m" if distances else ""))
        print(f"{case['query']}: {verdict}", file=sys.stderr)

    print(f"# Arama ölçümü — {time.strftime('%d.%m.%Y')}\n")
    print("Photon (uygulamanın parametreleri, Kartal'dan konum önceliği) + uygulamanın yeniden sıralaması.")
    source = "İstanbul OSM kesiti (Geofabrik, osmium)" if args.osm_file else "Overpass"
    print(f"Hedef: OSM'deki nesne ({source}). İsabet: sonuç hedef geometriye yarıçap içinde (varsayılan 150 m).\n")
    print(f"**İlk sonuç doğru: {hits1}/{scored}** · ilk 3'te: {hits3}/{scored}\n")
    print("| Sorgu | Sonuç | Uygulamanın ilk sonucu | İlk sonucun hedefe uzaklığı |")
    print("|---|---|---|---|")
    for query, verdict, first, distance in rows:
        print(f"| {query} | {verdict} | {first} | {distance} |")
    measure_kinds()


def measure_kinds():
    """Bare kinds: is the first result of that kind and within KIND_RADIUS_KM of the user? The text search the
    app used before 2026-11-14 next to the nearest-of-kind search it uses now."""
    def verdict(features, wanted):
        if not features:
            return False, "(sonuç yok)"
        p, (lon, lat) = features[0]["properties"], features[0]["geometry"]["coordinates"][:2]
        category = f"{p.get('osm_key')}={p.get('osm_value')}"
        km = metres(KARTAL, (lat, lon)) / 1000
        return category in wanted and km <= KIND_RADIUS_KM, f"{p.get('name') or '?'} ({category}, {km:.1f} km)"

    rows, before, after = [], 0, 0
    for query in KIND_CASES:
        wanted = {tag.replace(":", "=") for tag in kind(query)}
        old_ok, old = verdict(app_rank(photon(query), query), wanted)
        time.sleep(1.2)
        new_ok, new = verdict(app_search(query), wanted)
        time.sleep(1.2)
        before, after = before + old_ok, after + new_ok
        rows.append((query, ("✅ " if old_ok else "❌ ") + old, ("✅ " if new_ok else "❌ ") + new))
        print(f"{query}: {old_ok} → {new_ok}", file=sys.stderr)
    print("\n## Yalnızca tür yazılan sorgular\n")
    print(f"İsabet: ilk sonuç o türden ve kullanıcıya {KIND_RADIUS_KM} km'den yakın. "
          f"**Metin araması: {before}/{len(KIND_CASES)} · en yakınlar: {after}/{len(KIND_CASES)}**\n")
    print("| Sorgu | Metin araması (eski) | En yakınlar (şimdi) |")
    print("|---|---|---|")
    for query, old, new in rows:
        print(f"| {query} | {old} | {new} |")


if __name__ == "__main__":
    if "--kinds-only" in sys.argv:  # live Photon only, no OSM targets needed
        measure_kinds()
    else:
        main()
