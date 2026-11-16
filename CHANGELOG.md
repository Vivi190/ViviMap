# Changelog

TestFlight builds of ATLAS 1.0. Dates are upload dates (UTC).

## Build 31 — 2026-11-16

- **Businesses in search:** shops, restaurants, offices and other businesses by name, nearest first, also without a connection. They come from an on-device index of 389 000 places for Istanbul, built from the open places data of Overture Maps; OpenStreetMap, which search relied on, has about a tenth of them.
- The answers of both sources are one list: districts and streets first, then the matching names nearest first. A business both know is listed once.
- More kinds of place can be asked for by their word: "kuaför", "veteriner", "oto servis", "çiçekçi", "kasap", "spor salonu", "sinema".
- The place card names more kinds of place ("Kuaför", "Oto servis", "Diş kliniği").
- Known limit: a business record is a page its owner made, so a position can be a building off and a closed shop can still be listed. Reviews, photos and opening hours are not in open data.

## Build 30 — 2026-11-16

- A tap on a place badge of the map (a shop, a pharmacy, a station) opens that place's card: its name at once, its address a moment later.
- In landscape, speed and limit sit top right, as upright, instead of over the road ahead.

## Build 29 — 2026-11-16

Based on a side-by-side study of Yandex Navigator and Yandex Maps (same roads, same minute) and three code audits. Build 28 is the same code: a delayed CI run uploaded it after 29.

**Traffic**
- Roads are coloured per HERE sub-segment, so a colour changes where the traffic does: a 12 km stretch was one colour end to end.
- Colour bands calibrated against Yandex on the same roads: yellow from jam factor 2, red from 8, dark red from 9.5. The old bands showed 92 % green where Yandex showed 58 %.
- Thin lines per direction with a pixel offset and a rim, in Yandex's palette, drawn straight on the map style (no longer rebuilt on every map update).
- The traffic layer stays on during guidance, fed by the route's own traffic request (no extra requests).
- Area score on Yandex's scale (travel time over free-flow time on main roads) with its Turkish wording.
- Values that are not live (historical) are no longer drawn as live; closures are road events, not a colour.
- An answer is reused for 2 minutes and covers at least 3 km around the screen, so a map following the car no longer asks once per kilometre; stale lines are removed.

**Guidance screen**, laid out as drivers know it from Yandex Navigator
- A compact blue turn panel top left (arrow, distance, road), speed and limit as two discs top right, one slim trip row at the bottom (distance, arrival, time left) with the overview and end buttons.
- A large two-tone arrow for the car instead of the map library's small puck.
- The route is drawn in traffic colours once it has live traffic (green where it flows); a slimmer line.
- Side buttons appear after a tap on the map; "Rotaya devam et" returns to the car, also when the map was moved while driving.
- The speed display stays at a stop ("0") and without a fix ("–"); a GPS chip shows weak or lost signal.
- 24-hour clock; distances step by 50 m when far and drop ",0".

**Voice and turn logic**
- Formal Turkish, as navigation apps speak ("300 metre sonra sağa dönün").
- Fewer prompts: no repeats seconds apart, none for road-name changes; the at-turn prompt interrupts instead of queueing, and muting stops the sentence in progress.
- Roundabout exits by number, U-turns at roundabouts, a turn that stays on the same road said as a turn, ferry boarding, "Hedefe 400 metre kaldı".
- The turn panel and its prompt no longer move on to the next maneuver up to 25 m before the turn.
- Leaving the route is said and shown ("Rotadan çıktınız"), then "Rota yeniden oluşturuldu"; a failed reroute is announced once.
- Valhalla's fallback sentence is no longer read out as a road name.
- Speed-camera direction filter corrected (it dropped cameras facing the driver); a camera is announced even with a speed bump before it, and a run of bumps counts once.
- Rerouting asks the on-device router first; a failing route server falls back to it for any error except "no route".

**Route choice**
- Options as tiles with label, time and distance (the chosen one filled blue); callouts with tails on the map: time and distance on the chosen route, "+2 dk" on the others.
- Tiles keep their order when traffic times arrive; the selection only moves by itself for a gain of a minute or more, and never after a manual choice.

**Map style**
- Neutral grey-blue main roads instead of yellow (which read as slow traffic), buildings from zoom 15, more street names (abbreviated "Cd.", "Sk.", "Blv."), places from zoom 14, a navy night palette.

**Fixes**
- After arrival the arrow follows the car again and GPS and the screen lock are released.
- The time no longer drops to the free-flow estimate at "Başlat", after a reroute or after taking a faster route; a traffic time that can no longer be refreshed is cleared.
- Changing "Ücretli yollardan kaçın" re-plans the routes on screen; an on-device route is no longer scored as if it had live traffic.

## Build 27 — 2026-11-15

- Map chrome (search bar, buttons, chips, road name, speed) uses the same opaque surface as the cards instead of glass.
- Speed shown as a rounded tile with the speed-limit sign above it and a red rim when over the limit.
- During guidance, a "Rotaya dön" button appears while the map is not following the car.
- Fix: the route overview during guidance framed half the city instead of the remaining route.

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
