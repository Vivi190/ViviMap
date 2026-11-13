# -*- coding: utf-8 -*-
"""Speed cameras and speed bumps in Istanbul from OpenStreetMap, bundled with the app (works offline).

    python -X utf8 Tools/hazards/fetch_hazards.py

Writes Packages/AtlasKit/Sources/RoadHazards/Resources/hazards-istanbul.json. Re-run to refresh; the file
records when it was fetched so the app can say how old the data is. Data © OpenStreetMap contributors, ODbL.
"""
import json
import time
import urllib.parse
import urllib.request
from datetime import date
from pathlib import Path

BBOX = (40.75, 28.0, 41.6, 29.95)  # south, west, north, east: greater Istanbul
SERVERS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
]
# traffic_calming values a driver feels as a bump ("kasis"); chicanes, islands and rumble strips are not.
BUMPS = {"bump", "hump", "table", "cushion", "mini_bumps", "yes"}
CARDINAL = {"N": 0, "NNE": 22.5, "NE": 45, "ENE": 67.5, "E": 90, "ESE": 112.5, "SE": 135, "SSE": 157.5,
            "S": 180, "SSW": 202.5, "SW": 225, "WSW": 247.5, "W": 270, "WNW": 292.5, "NW": 315, "NNW": 337.5}
OUT = Path(__file__).resolve().parents[2] / "Packages/AtlasKit/Sources/RoadHazards/Resources/hazards-istanbul.json"


def query():
    s, w, n, e = BBOX
    return f"""[out:json][timeout:180];
(
  node["highway"="speed_camera"]({s},{w},{n},{e});
  node["traffic_calming"]({s},{w},{n},{e});
);
out body;"""


def fetch():
    data = urllib.parse.urlencode({"data": query()}).encode()
    for server in SERVERS:
        for attempt in range(2):
            try:
                req = urllib.request.Request(server, data=data, headers={"User-Agent": "Atlas-iOS/1.0 (personal navigation app; hazard data)"})
                with urllib.request.urlopen(req, timeout=240) as r:
                    return json.load(r)["elements"], server
            except Exception as error:  # public servers are often busy; try the next one
                print(f"{server}: {error}")
                time.sleep(15)
    raise SystemExit("no Overpass server answered")


def direction(tags):
    """Numeric bearing a camera watches, when tagged as degrees or a compass point; else None."""
    raw = (tags.get("direction") or "").strip().upper()
    if raw in CARDINAL:
        return CARDINAL[raw]
    try:
        return float(raw) % 360
    except ValueError:
        return None  # "forward"/"backward" depend on the way's direction, which a lone node lacks


def speed(tags):
    raw = (tags.get("maxspeed") or "").strip()
    return int(raw) if raw.isdigit() else None


def main():
    elements, server = fetch()
    hazards = []
    for e in elements:
        tags = e.get("tags", {})
        if tags.get("highway") == "speed_camera":
            item = {"k": "camera", "lat": round(e["lat"], 6), "lon": round(e["lon"], 6)}
            if (limit := speed(tags)) is not None:
                item["maxspeed"] = limit
            if (bearing := direction(tags)) is not None:
                item["dir"] = bearing
            hazards.append(item)
        elif tags.get("traffic_calming") in BUMPS:
            hazards.append({"k": "bump", "lat": round(e["lat"], 6), "lon": round(e["lon"], 6)})
    hazards.sort(key=lambda h: (h["k"], h["lat"], h["lon"]))
    counts = {kind: sum(h["k"] == kind for h in hazards) for kind in ("camera", "bump")}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({
        "source": "© OpenStreetMap contributors (ODbL)",
        "fetched": date.today().isoformat(),
        "bbox": list(BBOX),
        "counts": counts,
        "hazards": hazards,
    }, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"{server}: {counts} -> {OUT}")


if __name__ == "__main__":
    main()
