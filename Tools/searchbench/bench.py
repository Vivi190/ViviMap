# -*- coding: utf-8 -*-
"""Search benchmark: does the app's first result point at the place the driver meant?

For each query the intended place is looked up in OSM (Overpass, by tag + name) and the query is sent to
Photon with the app's parameters; the app's re-ranking (PlaceRanking in PhotonSearchProvider.swift) is
replicated here. A hit is a result within `radius` metres of the intended OSM geometry.

This measures ranking and recall on OSM data, not whether OSM itself is right.

    python -X utf8 Tools/searchbench/bench.py > docs/research/search-bench.md
"""
import json
import math
import os
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

UA = "Atlas-iOS/1.0 (personal navigation app; search benchmark)"
PHOTON = "https://photon.komoot.io/api/"
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


def turkish_lower(text):
    return text.replace("I", "ı").replace("İ", "i").lower()


def app_rank(features, query):
    text = turkish_lower(query)
    boosted = set().union(*[cats for words, cats in BOOSTS if any(w in text for w in words)] or [set()])
    wants_stops = "durak" in text or "durağ" in text

    def bucket(f):
        p = f["properties"]
        category = f"{p.get('osm_key')}={p.get('osm_value')}" if p.get("osm_key") else None
        if category is None:
            return 1
        if wants_stops:
            return 0 if category in STOPS else 1
        if category in boosted:
            return 0
        return 2 if category in STOPS else 1

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


def photon(query):
    params = {"q": query, "limit": "12", "bbox": TURKEY_BBOX, "lang": "default", "lat": KARTAL[0], "lon": KARTAL[1]}
    return get_json(PHOTON + "?" + urllib.parse.urlencode(params)).get("features", [])


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


def main():
    cases = json.loads(Path(__file__).with_name("queries.json").read_text(encoding="utf-8"))
    rows, hits1, hits3, scored = [], 0, 0, 0
    all_targets = overpass_targets(cases)
    for number, case in enumerate(cases):
        if number not in all_targets:
            rows.append((case["query"], "—", "Overpass yanıt vermedi (ölçülmedi)", ""))
            continue
        targets = all_targets[number]
        if not targets:
            rows.append((case["query"], "—", "hedef OSM'de bulunamadı (ölçüm dışı)", ""))
            continue
        ranked = app_rank(photon(case["query"]), case["query"])
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
    print("Hedef: OSM'deki nesne (Overpass). İsabet: sonuç hedef geometriye yarıçap içinde (varsayılan 150 m).\n")
    print(f"**İlk sonuç doğru: {hits1}/{scored}** · ilk 3'te: {hits3}/{scored}\n")
    print("| Sorgu | Sonuç | Uygulamanın ilk sonucu | İlk sonucun hedefe uzaklığı |")
    print("|---|---|---|---|")
    for query, verdict, first, distance in rows:
        print(f"| {query} | {verdict} | {first} | {distance} |")


if __name__ == "__main__":
    main()
