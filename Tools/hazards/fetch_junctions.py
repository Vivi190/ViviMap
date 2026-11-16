# -*- coding: utf-8 -*-
"""Signalised junctions of Istanbul from the municipality's open data, bundled with the app beside the
OpenStreetMap traffic lights (fetch_signals.py), which miss about half of them.

    python -X utf8 Tools/hazards/fetch_junctions.py

Writes Packages/AtlasKit/Sources/RoadHazards/Resources/junctions-istanbul.json: one [lat, lon] per junction
(its centre), rounded to 1e-5 degrees. A file of its own: the app merges the two at load, so each keeps its
licence. Data: İstanbul Büyükşehir Belediyesi, "Sinyalize Kavşak Bilgileri Web Servisi", İBB Açık Veri Lisansı
(https://data.ibb.gov.tr/license).
"""
import json
import urllib.request
from datetime import date
from pathlib import Path

from fetch_hazards import BBOX

URL = "https://api.ibb.gov.tr/web/api/junction"
OUT = Path(__file__).resolve().parents[2] / "Packages/AtlasKit/Sources/RoadHazards/Resources/junctions-istanbul.json"


def main():
    s, w, n, e = BBOX
    request = urllib.request.Request(URL, headers={"User-Agent": "Atlas-iOS/1.0 (personal navigation app)"})
    with urllib.request.urlopen(request, timeout=60) as response:
        junctions = json.load(response)
    points = set()
    for junction in junctions:
        try:
            lat, lon = float(junction["YCoord"]), float(junction["XCoord"])
        except (KeyError, TypeError, ValueError):
            continue
        if s <= lat <= n and w <= lon <= e:
            points.add((round(lat, 5), round(lon, 5)))
    OUT.write_text(json.dumps({
        "source": "İstanbul Büyükşehir Belediyesi, Sinyalize Kavşak Bilgileri (İBB Açık Veri Lisansı)",
        "fetched": date.today().isoformat(),
        "count": len(points),
        "points": [list(p) for p in sorted(points)],
    }, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"{len(points)} of {len(junctions)} junctions -> {OUT}")


if __name__ == "__main__":
    main()
