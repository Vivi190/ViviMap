# -*- coding: utf-8 -*-
"""Traffic lights in Istanbul from OpenStreetMap, bundled with the app for the map (works offline).

    python -X utf8 Tools/hazards/fetch_signals.py

Writes Packages/AtlasKit/Sources/RoadHazards/Resources/signals-istanbul.json: one [lat, lon] per OSM
highway=traffic_signals node, rounded to 1e-5 degrees (about 1 m). Data © OpenStreetMap contributors, ODbL.
"""
import json
from datetime import date
from pathlib import Path

from fetch_hazards import BBOX, fetch

OUT = Path(__file__).resolve().parents[2] / "Packages/AtlasKit/Sources/RoadHazards/Resources/signals-istanbul.json"


def main():
    s, w, n, e = BBOX
    elements, server = fetch(f'[out:json][timeout:180];node["highway"="traffic_signals"]({s},{w},{n},{e});out skel;')
    points = sorted({(round(x["lat"], 5), round(x["lon"], 5)) for x in elements if "lat" in x})
    OUT.write_text(json.dumps({
        "source": "© OpenStreetMap contributors (ODbL)",
        "fetched": date.today().isoformat(),
        "count": len(points),
        "points": [list(p) for p in points],
    }, separators=(",", ":")), encoding="utf-8")
    print(f"{server}: {len(points)} traffic lights -> {OUT}")


if __name__ == "__main__":
    main()
