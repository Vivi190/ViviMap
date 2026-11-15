# Changelog

TestFlight builds of ATLAS 1.0. Dates are upload dates (UTC).

## Build 26 — 2026-11-15

- Road events (closures, accidents, road works) on the route stay visible during guidance, from the last traffic refresh before the drive; no extra requests.
- Fix: a long press on the map during guidance no longer selects a new place and replaces the destination.

## Build 25 — 2026-11-15

- **Guidance screen redesign:** an opaque turn card with the maneuver on a blue tile, a large distance and the street name; the remaining time set large in the bottom bar; the route line starts under the car and the driven part disappears.
- **Route choice:** each option's time in a bubble on the map (tap to choose), options side by side with the time difference to the fastest, a red destination pin.
- Routes are requested as soon as a place is selected, so the route card opens without waiting.
- The place card shows the kind of place ("Adliye · 3,0 km").
- Reading panels (place, route, guidance) use an opaque surface instead of glass.
- Road events on the map: closures (dashed red with a no-entry sign), accidents and road works.
- A traffic strip in the guidance bar shows slow stretches on the rest of the route.
- The city traffic layer skips residential streets, keeping the map responsive.
- Fixes: a route still loading for a previous place no longer lands on the new place's card; cancelled requests no longer fall back to on-device routing or search.

## Build 24 — 2026-11-15

- Apple Maps–style place badges and a livelier day palette.
- Traffic layer on by default, flowing roads in green, and an area traffic score.
- Speed bumps, cameras and traffic lights drawn on the map; "Işıklarda sağa dön" for turns at traffic lights.
- Road numbers in shields (D-100 blue, O-4 green).

## Build 23 — 2026-11-14

- District + kind and district + brand queries ("esentepe eczane", "kurtköy migros") search around that district.

## Build 22 — 2026-11-14

- A "Otopark" button on arrival, a voice sample in settings, "Nereye?" in the search bar.

## Build 21 — 2026-11-14

- Search starts fresh after a place is done; the roundabout arrow runs to the exit; one-tap Home and Work shortcuts under the search bar.

## Build 20 — 2026-11-14

- Addresses as written in messages, nearest places for a bare kind ("benzinlik", offline too), car parks near a destination.
- Position snapped to the road, a turn arrow on the route, the current road name, automatic return to the car after looking around.
- Offline street + district search; search falls back to the bundled index when Photon is down; accurate search error messages.

## Build 19 — 2026-11-14

- Redesigned route card and guidance bar; routes to airports, hospitals and malls end on the road in front; best installed Turkish voice; smooth guidance zoom.

## Build 18 — 2026-11-14

- Avoid tolls, share arrival, Siri and Shortcuts ("eve git", "işe git"), spoken speed-limit warning, "Yakında" quick searches.

## Build 17 — 2026-11-14

- City traffic layer; search fix for queries with a kind word.

## Builds 1–14 — 2026-11-13

- Foundation (map, location, speedometer, day and night styles), Photon search, Valhalla routing, Ferrostar guidance with Turkish voice, background guidance, live traffic times (HERE), offline Istanbul map, routing and search, Live Activity.
