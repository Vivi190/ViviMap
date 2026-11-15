#!/usr/bin/env python3
"""Generate Atlas day/night MapLibre styles (OpenMapTiles schema) from one layer definition.

Run:  python Tools/mapstyle/build_styles.py
Out:  Packages/AtlasKit/Sources/MapEngine/Styles/atlas-{day,night}.json

Both styles share every layer; only the palette differs, so the two can never drift apart.
"""
import json
import pathlib

OUT_DIR = pathlib.Path(__file__).resolve().parents[2] / "Packages/AtlasKit/Sources/MapEngine/Styles"

TILES_URL = "https://tiles.openfreemap.org/planet"
GLYPHS_URL = "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf"
# OpenFreeMap serves single fonts only; combined stacks ("A,B") return 404.
FONT_REGULAR = ["Noto Sans Regular"]
FONT_BOLD = ["Noto Sans Bold"]
FONT_ITALIC = ["Noto Sans Italic"]

PALETTES = {
    # Day leans to Apple Maps: warm off-white land, clear greens and a bright sea (15.11.2026: the greyer first
    # palette read as dull next to it).
    "day": {
        "background": "#F6F3EC",
        "residential": "#F0EDE6",
        "industrial": "#E8E6E3",
        "institutional": "#F0E9E1",
        "park": "#C8E8BC",
        "wood": "#BCDDAC",
        "sand": "#F4EAD0",
        "water": "#9CCFF0",
        "waterway": "#92C8EC",
        "building": "#E7E2D9",
        "building_outline": "#D9D2C6",
        "building_3d": "#E1DDD5",
        "building_opacity": 0.92,
        "aeroway": "#E0DED9",
        "motorway": "#F6BF62",
        "motorway_casing": "#DD9A35",
        "trunk": "#F9D488",
        "trunk_casing": "#E2AE55",
        "major": "#FFFFFF",
        "major_casing": "#D2CCC1",
        "minor": "#FFFFFF",
        "minor_casing": "#DAD5CC",
        "service": "#FBFAF7",
        "path": "#D6D1C8",
        "tunnel": "#EEEBE6",
        "rail": "#BDB8B0",
        "ferry": "#7FA9CF",
        "boundary": "#B8AEC4",
        "label": "#2C2C2E",
        "label_secondary": "#6C6C71",
        "label_road": "#3A3A3D",
        "label_halo": "#FFFFFF",
        "label_water": "#4C789F",
        "label_house": "#8F8A83",
    },
    "night": {
        "background": "#14171C",
        "residential": "#171A20",
        "industrial": "#191B20",
        "institutional": "#1A1B22",
        "park": "#16231C",
        "wood": "#15211A",
        "sand": "#1E1D1A",
        "water": "#0F2436",
        "waterway": "#13304A",
        "building": "#1D2026",
        "building_outline": "#262A31",
        "building_3d": "#282C33",
        "building_opacity": 0.95,
        "aeroway": "#22252B",
        "motorway": "#9A7533",
        "motorway_casing": "#5E4720",
        "trunk": "#7E6838",
        "trunk_casing": "#4D3F24",
        "major": "#3C414A",
        "major_casing": "#24272D",
        "minor": "#31353C",
        "minor_casing": "#1F2227",
        "service": "#2A2D33",
        "path": "#2C3036",
        "tunnel": "#24272D",
        "rail": "#3A3E45",
        "ferry": "#2F5677",
        "boundary": "#4C4558",
        "label": "#E8EAED",
        "label_secondary": "#9CA2AA",
        "label_road": "#C8CCD2",
        "label_halo": "#14171C",
        "label_water": "#6F95B8",
        "label_house": "#7D838B",
    },
}

NAME = ["coalesce", ["get", "name:tr"], ["get", "name"]]


def width(*stops):
    """Exponential zoom curve: width(z0, w0, z1, w1, ...)."""
    return ["interpolate", ["exponential", 1.5], ["zoom"], *stops]


RAMP = ["case", ["==", ["get", "ramp"], 1], 0.7, 1]

# Places shown as Apple Maps-style badges: OpenMapTiles poi classes by group, with the label colour for day and
# night. The badges themselves (a white SF Symbol on a circle in the group colour) are drawn by the app and
# registered as "poi-<class>" (MapEngine/POIIcons.swift); keep the two lists in step. Bus stops stay off: Istanbul
# has so many that they buried everything else.
POI_GROUPS = [
    (["restaurant", "fast_food", "cafe", "bar", "beer", "ice_cream"], "#B85B00", "#FFB25E"),  # food
    (["shop", "grocery", "clothing_store"], "#946C00", "#F2C94C"),  # shopping
    (["hospital", "pharmacy", "doctors", "dentist"], "#C62F2F", "#FF8A80"),  # health
    (["school", "college", "library"], "#7E5C36", "#D9B98C"),  # education
    (["railway", "harbor", "ferry_terminal", "fuel", "parking", "aerialway"], "#1E66C4", "#82B6FF"),  # transport
    (["park", "zoo", "campsite", "golf", "playground"], "#277A40", "#7FD49A"),  # nature
    (["place_of_worship"], "#5E5E64", "#B8B8BE"),  # worship
    (["attraction", "art_gallery", "castle", "museum", "theatre", "cinema"], "#93398E", "#E39BE0"),  # culture
    (["lodging"], "#4B49C2", "#A5A4FF"),  # lodging
    (["town_hall", "post", "police", "fire_station", "bank", "atm"], "#4E5D75", "#A9B6CC"),  # services
    (["stadium", "swimming", "sports_centre"], "#17808F", "#7FD3E0"),  # sports
]
POI_CLASSES = [c for classes, _, _ in POI_GROUPS for c in classes]


def poi_layers(name, p):
    """Important places from z15, all from z16.5; the more important (lower rank) win when labels collide."""
    column = 1 if name == "day" else 2
    color = ["match", ["get", "class"]]
    for group in POI_GROUPS:
        color += [group[0], group[column]]
    color.append(p["label_secondary"])
    layout = {
        "icon-image": ["concat", "poi-", ["get", "class"]],
        "text-field": NAME, "text-font": FONT_REGULAR,
        "text-size": ["interpolate", ["linear"], ["zoom"], 15, 10.5, 18, 12.5],
        "text-anchor": "top", "text-offset": [0, 1.0], "text-max-width": 8,
        # Badge and name together or not at all: lone badges cluttered the first CI screenshot (15.11.2026).
        "symbol-sort-key": ["coalesce", ["get", "rank"], 99],
    }
    paint = {"text-color": color, "text-halo-color": p["label_halo"], "text-halo-width": 1.3}
    known = ["match", ["get", "class"], POI_CLASSES, True, False]
    # Shops and clothing only from z16.5: there are too many; supermarkets stay, they are landmarks here.
    major = ["match", ["get", "class"], [c for c in POI_CLASSES if c not in ("shop", "clothing_store")], True, False]
    return [
        {"id": "poi-major", "type": "symbol", "source": "openmaptiles", "source-layer": "poi",
         "minzoom": 15, "maxzoom": 16.5, "filter": ["all", major, ["has", "name"], ["<=", ["coalesce", ["get", "rank"], 99], 20]],
         "layout": layout, "paint": paint},
        {"id": "poi-all", "type": "symbol", "source": "openmaptiles", "source-layer": "poi",
         "minzoom": 16.5, "filter": ["all", known, ["has", "name"]], "layout": layout, "paint": paint},
    ]


def road_width(curve, extra=0.0):
    """Apply the ramp factor (and casing extra) inside each stop.

    A ["zoom"] expression must be the input of the top-level interpolate, so the data-driven
    parts have to live in the stop outputs rather than wrap the curve.
    """
    head, stops = curve[:3], curve[3:]
    out = list(head)
    for z, w in zip(stops[0::2], stops[1::2]):
        value = ["*", w, RAMP]
        out += [z, ["+", value, extra] if extra else value]
    return out


def classes(*names):
    return ["match", ["get", "class"], list(names), True, False]


def not_brunnel(*kinds):
    return ["!", ["match", ["coalesce", ["get", "brunnel"], ""], list(kinds), True, False]]


# Road hierarchy: (id, class filter, fill key, casing key, min zoom, fill width curve, casing extra px)
ROADS = [
    ("service", classes("service", "track"), "service", "minor_casing", 14.5,
     width(14.5, 0.8, 16, 3, 18, 9), 0.8),
    ("minor", classes("minor"), "minor", "minor_casing", 12.5,
     width(12.5, 0.6, 14, 2.2, 16, 7, 18, 20), 1.0),
    ("tertiary", classes("tertiary"), "major", "major_casing", 11,
     width(11, 0.8, 13, 2.5, 16, 9, 18, 24), 1.2),
    ("secondary", classes("secondary"), "major", "major_casing", 9,
     width(9, 0.8, 12, 2.4, 14, 5, 16, 11, 18, 28), 1.3),
    ("primary", classes("primary"), "major", "major_casing", 8,
     width(8, 0.8, 12, 3, 14, 6, 16, 13, 18, 32), 1.4),
    ("trunk", classes("trunk"), "trunk", "trunk_casing", 6,
     width(6, 0.8, 10, 2.2, 13, 5, 16, 14, 18, 34), 1.5),
    ("motorway", classes("motorway"), "motorway", "motorway_casing", 5,
     width(5, 0.6, 9, 1.8, 13, 5.5, 16, 15, 18, 36), 1.6),
]


def road_layers(p, brunnel):
    """Casing pass then fill pass so junctions merge cleanly. brunnel: None | 'tunnel' | 'bridge'."""
    if brunnel is None:
        base = not_brunnel("bridge", "tunnel")
    else:
        base = ["==", ["get", "brunnel"], brunnel]
    casings, fills = [], []
    for rid, cls, fill_key, casing_key, minzoom, w, extra in ROADS:
        flt = ["all", base, cls]
        lid = f"road-{rid}" if brunnel is None else f"{brunnel}-{rid}"
        # Links (ramps) are drawn a little thinner than their parent class.
        line_width = road_width(w)
        casing_paint = {
            "line-color": p[casing_key],
            "line-width": road_width(w, extra * (1.6 if brunnel == "bridge" else 1)),
        }
        if brunnel == "tunnel":
            casing_paint["line-dasharray"] = [0.6, 0.4]
        casings.append({
            "id": f"{lid}-casing", "type": "line", "source": "openmaptiles",
            "source-layer": "transportation", "minzoom": minzoom,
            "filter": flt,
            "layout": {"line-cap": "butt" if brunnel == "tunnel" else "round", "line-join": "round"},
            "paint": casing_paint,
        })
        fills.append({
            "id": lid, "type": "line", "source": "openmaptiles",
            "source-layer": "transportation", "minzoom": minzoom, "filter": flt,
            "layout": {"line-cap": "round", "line-join": "round"},
            "paint": {
                "line-color": p["tunnel"] if brunnel == "tunnel" else p[fill_key],
                "line-width": line_width,
                **({"line-opacity": 0.75} if brunnel == "tunnel" else {}),
            },
        })
    return casings + fills


def build(name, p):
    layers = [
        {"id": "background", "type": "background", "paint": {"background-color": p["background"]}},
        {"id": "landuse-residential", "type": "fill", "source": "openmaptiles", "source-layer": "landuse",
         "filter": classes("residential", "suburb", "neighbourhood"),
         "paint": {"fill-color": p["residential"], "fill-opacity": ["interpolate", ["linear"], ["zoom"], 9, 0.8, 15, 0.4]}},
        {"id": "landuse-industrial", "type": "fill", "source": "openmaptiles", "source-layer": "landuse",
         "minzoom": 11, "filter": classes("industrial", "commercial", "retail", "railway", "garages"),
         "paint": {"fill-color": p["industrial"]}},
        {"id": "landuse-institutional", "type": "fill", "source": "openmaptiles", "source-layer": "landuse",
         "minzoom": 12, "filter": classes("hospital", "school", "college", "university", "kindergarten"),
         "paint": {"fill-color": p["institutional"]}},
        {"id": "landcover-wood", "type": "fill", "source": "openmaptiles", "source-layer": "landcover",
         "filter": classes("wood", "forest"), "paint": {"fill-color": p["wood"], "fill-antialias": False}},
        {"id": "landcover-grass", "type": "fill", "source": "openmaptiles", "source-layer": "landcover",
         "filter": classes("grass", "farmland", "wetland"),
         "paint": {"fill-color": p["park"], "fill-opacity": 0.7, "fill-antialias": False}},
        {"id": "landcover-sand", "type": "fill", "source": "openmaptiles", "source-layer": "landcover",
         "minzoom": 10, "filter": classes("sand", "beach"), "paint": {"fill-color": p["sand"]}},
        {"id": "landuse-green", "type": "fill", "source": "openmaptiles", "source-layer": "landuse",
         "minzoom": 11, "filter": classes("cemetery", "stadium", "pitch", "playground"),
         "paint": {"fill-color": p["park"]}},
        {"id": "park", "type": "fill", "source": "openmaptiles", "source-layer": "park",
         "paint": {"fill-color": p["park"], "fill-opacity": 0.85}},
        {"id": "water", "type": "fill", "source": "openmaptiles", "source-layer": "water",
         "filter": ["!=", ["get", "brunnel"], "tunnel"], "paint": {"fill-color": p["water"]}},
        {"id": "waterway", "type": "line", "source": "openmaptiles", "source-layer": "waterway",
         "minzoom": 11, "filter": not_brunnel("tunnel"),
         "paint": {"line-color": p["waterway"], "line-width": width(11, 0.6, 16, 3, 18, 6)}},
        {"id": "aeroway", "type": "line", "source": "openmaptiles", "source-layer": "aeroway",
         "minzoom": 11, "filter": classes("runway", "taxiway"),
         "paint": {"line-color": p["aeroway"], "line-width": width(11, 1, 14, 6, 17, 40)}},
        {"id": "boundary-state", "type": "line", "source": "openmaptiles", "source-layer": "boundary",
         "filter": ["all", ["<=", ["get", "admin_level"], 4], ["!=", ["get", "maritime"], 1]],
         "paint": {"line-color": p["boundary"], "line-width": width(4, 0.6, 12, 1.4),
                   "line-dasharray": [2, 1.5]}},
    ]

    layers += [
        {"id": "building", "type": "fill", "source": "openmaptiles", "source-layer": "building",
         "minzoom": 13,
         "paint": {"fill-color": p["building"], "fill-outline-color": p["building_outline"],
                   "fill-opacity": ["interpolate", ["linear"], ["zoom"], 13, 0, 14, 1]}},
    ]
    layers += road_layers(p, "tunnel")
    layers += [
        {"id": "road-path", "type": "line", "source": "openmaptiles", "source-layer": "transportation",
         "minzoom": 15.5, "filter": ["all", not_brunnel("tunnel"), classes("path")],
         "paint": {"line-color": p["path"], "line-width": width(15.5, 0.6, 18, 2), "line-dasharray": [2, 1.4]}},
        {"id": "rail", "type": "line", "source": "openmaptiles", "source-layer": "transportation",
         "minzoom": 11, "filter": ["all", not_brunnel("tunnel"), classes("rail", "transit")],
         "paint": {"line-color": p["rail"], "line-width": width(11, 0.6, 16, 2, 18, 3)}},
        {"id": "ferry", "type": "line", "source": "openmaptiles", "source-layer": "transportation",
         "minzoom": 9, "filter": classes("ferry"),
         "paint": {"line-color": p["ferry"], "line-width": width(9, 0.6, 16, 1.6), "line-dasharray": [3, 2]}},
    ]
    layers += road_layers(p, None)
    layers += road_layers(p, "bridge")
    layers += [
        # Hidden by default: even at pitch 0 the perspective camera shows extrusion walls, which turns dense
        # districts into noise. The app makes this visible only in 3D mode (MapEngine: BUILDINGS_3D_LAYER).
        {"id": "building-3d", "type": "fill-extrusion", "source": "openmaptiles", "source-layer": "building",
         "minzoom": 15, "filter": ["!=", ["get", "hide_3d"], True], "layout": {"visibility": "none"},
         "paint": {
             "fill-extrusion-color": p["building_3d"],
             "fill-extrusion-opacity": p["building_opacity"],
             "fill-extrusion-height": ["interpolate", ["linear"], ["zoom"], 15, 0, 16,
                                       ["coalesce", ["get", "render_height"], 6]],
             "fill-extrusion-base": ["interpolate", ["linear"], ["zoom"], 15, 0, 16,
                                     ["coalesce", ["get", "render_min_height"], 0]],
         }},
        {"id": "label-water", "type": "symbol", "source": "openmaptiles", "source-layer": "water_name",
         "filter": ["==", ["geometry-type"], "Point"],
         "layout": {"text-field": NAME, "text-font": FONT_ITALIC,
                    "text-size": ["interpolate", ["linear"], ["zoom"], 6, 11, 14, 15],
                    "text-letter-spacing": 0.08, "text-max-width": 7},
         "paint": {"text-color": p["label_water"], "text-halo-color": p["label_halo"], "text-halo-width": 1}},
        {"id": "label-road-minor", "type": "symbol", "source": "openmaptiles", "source-layer": "transportation_name",
         "minzoom": 14.5, "filter": classes("minor", "service"),
         "layout": {"symbol-placement": "line", "text-field": NAME, "text-font": FONT_REGULAR,
                    "text-size": ["interpolate", ["linear"], ["zoom"], 14.5, 10, 18, 14],
                    "text-max-angle": 30, "symbol-spacing": 280, "text-padding": 2},
         "paint": {"text-color": p["label_road"], "text-halo-color": p["label_halo"], "text-halo-width": 1.4}},
        {"id": "label-road-major", "type": "symbol", "source": "openmaptiles", "source-layer": "transportation_name",
         "minzoom": 12, "filter": classes("primary", "secondary", "tertiary", "trunk", "motorway"),
         "layout": {"symbol-placement": "line", "text-field": NAME, "text-font": FONT_REGULAR,
                    "text-size": ["interpolate", ["linear"], ["zoom"], 12, 10.5, 16, 13.5, 18, 16],
                    "text-max-angle": 28, "symbol-spacing": 320, "text-padding": 2},
         "paint": {"text-color": p["label_road"], "text-halo-color": p["label_halo"], "text-halo-width": 1.6}},
        # Road numbers (D-100, O-4 …) on sign-like shields, green for motorways and blue for the rest, as on
        # Turkish signs; the stretchable shields are drawn by the app (MapEngine/RoadShields.swift).
        {"id": "label-road-ref", "type": "symbol", "source": "openmaptiles", "source-layer": "transportation_name",
         "minzoom": 9, "filter": ["all", classes("motorway", "trunk", "primary"), ["has", "ref"]],
         "layout": {"symbol-placement": "line", "text-field": ["get", "ref"], "text-font": FONT_BOLD,
                    "text-size": ["interpolate", ["linear"], ["zoom"], 9, 9.5, 14, 11],
                    "icon-image": ["case", ["==", ["get", "class"], "motorway"], "shield-motorway", "shield-road"],
                    "icon-text-fit": "both", "icon-text-fit-padding": [2, 4, 2, 4],
                    "icon-rotation-alignment": "viewport",
                    "symbol-spacing": 700, "text-rotation-alignment": "viewport", "text-padding": 6},
         "paint": {"text-color": "#FFFFFF"}},
        {"id": "label-housenumber", "type": "symbol", "source": "openmaptiles", "source-layer": "housenumber",
         "minzoom": 17,
         "layout": {"text-field": ["get", "housenumber"], "text-font": FONT_REGULAR, "text-size": 10,
                    "text-padding": 3},
         "paint": {"text-color": p["label_house"], "text-halo-color": p["label_halo"], "text-halo-width": 1}},
        # Above road names and house numbers, below place names (higher layers place their labels first).
        *poi_layers(name, p),
        {"id": "label-neighbourhood", "type": "symbol", "source": "openmaptiles", "source-layer": "place",
         "minzoom": 13, "filter": classes("neighbourhood", "quarter"),
         "layout": {"text-field": NAME, "text-font": FONT_REGULAR,
                    "text-size": ["interpolate", ["linear"], ["zoom"], 13, 10.5, 17, 13],
                    "text-letter-spacing": 0.04, "text-max-width": 8},
         "paint": {"text-color": p["label_secondary"], "text-halo-color": p["label_halo"], "text-halo-width": 1.2}},
        {"id": "label-suburb", "type": "symbol", "source": "openmaptiles", "source-layer": "place",
         "minzoom": 10.5, "maxzoom": 16, "filter": classes("suburb", "village"),
         "layout": {"text-field": NAME, "text-font": FONT_BOLD,
                    "text-size": ["interpolate", ["linear"], ["zoom"], 10.5, 11, 15, 14],
                    "text-letter-spacing": 0.03, "text-max-width": 8},
         "paint": {"text-color": p["label_secondary"], "text-halo-color": p["label_halo"], "text-halo-width": 1.4}},
        {"id": "label-town", "type": "symbol", "source": "openmaptiles", "source-layer": "place",
         "minzoom": 7, "maxzoom": 15, "filter": classes("town"),
         "layout": {"text-field": NAME, "text-font": FONT_BOLD,
                    "text-size": ["interpolate", ["linear"], ["zoom"], 7, 11, 13, 16], "text-max-width": 8},
         "paint": {"text-color": p["label"], "text-halo-color": p["label_halo"], "text-halo-width": 1.5}},
        {"id": "label-city", "type": "symbol", "source": "openmaptiles", "source-layer": "place",
         "minzoom": 4, "maxzoom": 13, "filter": classes("city"),
         "layout": {"text-field": NAME, "text-font": FONT_BOLD,
                    "text-size": ["interpolate", ["linear"], ["zoom"], 4, 12, 10, 20], "text-max-width": 8},
         "paint": {"text-color": p["label"], "text-halo-color": p["label_halo"], "text-halo-width": 1.6}},
    ]
    return {
        "version": 8,
        "name": f"Atlas {name.title()}",
        "metadata": {"atlas:appearance": name},
        "sources": {"openmaptiles": {"type": "vector", "url": TILES_URL}},
        "glyphs": GLYPHS_URL,
        "layers": layers,
    }


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, palette in PALETTES.items():
        style = build(name, palette)
        ids = [layer["id"] for layer in style["layers"]]
        assert len(ids) == len(set(ids)), "duplicate layer id"
        path = OUT_DIR / f"atlas-{name}.json"
        path.write_text(json.dumps(style, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print(f"wrote {path.relative_to(OUT_DIR.parents[3])} ({len(ids)} layers)")


if __name__ == "__main__":
    main()
