# Changelog

TestFlight builds of ATLAS 1.0. Dates are upload dates (UTC).

## Build 34 — 2026-11-17

- **Stops on the way:** while guiding, a tap on the map shows "Yol üstünde ara". It lists fuel stations, chargers, markets, pharmacies, ATMs, cafés and restaurants ahead on the route, from the indexes on the device, the cheapest to turn into first, with how far ahead each is and on which side. A tap makes one a stop without ending guidance ("Ara durak eklendi."): an orange pin, its own prompts ("Ara durağa 400 metre kaldı.", "Ara durak sağda"), then guidance goes on to the destination. Reroutes and traffic rounds keep the stop; "Ara durağı kaldır" drops it. One stop at a time.
- **Search results on the map:** "12 sonucu haritada göster" above a list of results puts them on the map as blue pins with their names, all in view, as Yandex and Apple Maps show a search. A tap on a pin opens its card; a chip under the search bar opens the list again or takes the pins off.
- **Home and Work with their times:** the "Ev" and "İş" chips under the search bar show the drive there now with live traffic ("Ev · 24 dk"), as Yandex's start screen does; measured again every ten minutes while the map is open, and after about a kilometre of driving. One route request and one traffic request per place, only while the app is in front.
- **İSPARK fees:** an İSPARK car park's card shows what it costs and its free minutes ("1 sa 110 TL · 2 sa 140 TL · Tam gün 370 TL · İlk 15 dk ücretsiz"), from the municipality's open data.
- **Warnings without a route:** with the map open, speed bumps and cameras ahead on the road are said without a destination too, as Yandex's navigator mode does ("80 metre sonra kasis."). The road ahead is judged by the course, so a bend or a road alongside can mislead; a switch in the settings turns it off.
- **Guidance settings:** "Dönüşleri seslendir" off leaves only the warnings spoken (cameras, bumps, speed, road events), for a driver who knows the way; the speed warning's threshold ("Otomatik", +5, +10 or +20 km/h); and "Navigasyonda kuzey yukarıda" for a flat map with north up instead of one turning with the car.
- **Tunnels:** when the GPS goes silent for 3 seconds while the car was moving on its route, guidance moves it along the route at its last speed, as the other map apps do, so the turn after a tunnel is announced in time; it stops 40 m before the next maneuver and waits for the real position there. Up to two minutes.
- The settings sheets are opaque at half height.

## Build 33 — 2026-11-16

- **Route settings:** "Feribotlardan kaçın" beside "Ücretli yollardan kaçın". With both on there is no way across the Bosphorus, and the card says so instead of offering the router's way round the Black Sea.
- **Shared locations:** a short link from the Google Maps app ("maps.app.goo.gl/…") opens as a place. It carries no coordinates, so Google is asked once where it leads; only the link is sent.
- **Traffic budget:** the monthly caps are nine tenths of HERE's free tier instead of half, now that one phone uses the key: about twice the hours of live traffic before "Bu ayın trafik sorgu sınırı doldu."
- The list of a route's turns opens on an opaque sheet.

## Build 32 — 2026-11-16

**Guidance**
- The speed limit shows on nearly every road of a route. Where OpenStreetMap has none, nine roads in ten around Kartal, Pendik and Tuzla, the limit HERE gives for that stretch is used; it comes with the route's traffic time, at no extra request. Without a connection the limit is OpenStreetMap's alone.
- Road events on the rest of the route (a closed road, an accident, road works) are renewed with every traffic round and said once, about a kilometre ahead ("1 kilometre sonra yol çalışması.").
- A route no longer runs through a stretch that live traffic reports as closed when there is another way: on the route card the candidate is replaced by a way round it before its time is measured; while driving, the route changes and says so ("Yol kapalı. Rota değiştirildi.").
- Every plan also asks for a route that prefers local streets, for when the main roads are jammed; the card offers the three routes that differ most.
- Roundabouts are "döner kavşak" in the prompts ("Döner kavşakta ikinci çıkıştan çıkın"), the destination's side "Hedefiniz solda".

**Places on the map and their cards**
- At street zoom the businesses of the search index show as badges on the map, in the look of the base map's own place badges; a tap opens the business's card. The base map alone showed about a tenth of a street's shops.
- Hairdressers, offices, car services, vets, bakeries, butchers, dry cleaners and chargers have badges of their own; the base map's places of these kinds, which were not drawn at all, show too. A business whose kind is unknown is a plain dot, drawn where the others leave room.
- The place card has a row of actions: call (285 000 businesses carry a phone number), website, star, share. Its route button shows the driving time once the routes asked for in advance are in ("Rota · 12 dk").
- Starred places are listed in the search sheet under "Kaydedilenler". A star stays with its place when the index is rebuilt.
- Reviews, photos and opening hours are not in open data and Google's may not be shown beside another map: the card's menu opens the place in Google Maps or Yandex Maps instead.
- A tapped badge of the base map shows its kind ("İstasyon").
- One-way streets carry an arrow at street zoom.

**Search**
- Forgiving spelling: "mediamarket" finds MediaMarkt, "kebabçı uzunlar" Kebapcı Uzunlar, "mcdonalds" McDonald's.
- "Yakında" offers eight kinds (market, ATM, restaurant and cafe are new) from both indexes; a kind next to a district ("kartal kuaför") lists that district's.
- A result row says what a place is before where it is ("Kafe · Ankara Caddesi 54, Kartal").
- 34 000 businesses that open data lists without a kind get it from their name ("Beşiktaş 5. Noterliği", "Aras Kargo", "Kuaför Ümit", "Manolya Sitesi"). Forty more kinds have a word on the card, and many can be asked for by it: "kargo", "terzi", "çilingir", "kuru temizleme", "emlakçı", "avukat", "nakliyat", "düğün salonu", "sürücü kursu", "noter", "postane".
- A location pasted as a link is opened as a place: what Google Maps, Apple Maps, Yandex Maps and WhatsApp share when the link carries its coordinates, and "geo:" addresses. Short links (maps.app.goo.gl) carry none and are not understood.

**Istanbul's open data**
- Charging stations: the 1 807 public stations of the energy regulator's register, with their fastest current and their sockets ("ZES Kartal Sahil Migros · AC 22 kW · 2 soket"), found under "Şarj", by operator ("zes", "trugo") and on the map. There were 87. The register is a snapshot of May 2025: stations opened since are missing.
- Car park lists add İSPARK's car parks with the spaces free at that moment ("83 boş yer · 100 araçlık · 08:00-19:00"). A car park reporting no free space is listed without a count, not as full: the service reports zero for car parks it does not count. Car parks for coaches are left out.
- Traffic lights: the municipality's list of signalised junctions fills in the half OpenStreetMap lacks, 1 274 junctions (320 of the 479 around Kartal, Pendik and Tuzla had no light on the map). They show on the map and in "Işıklarda sağa dönün".

**Route card**
- A list of the route's turns, in the words and arrows guidance uses, behind a button beside "Başlat".

**Wording**
- One form of address ("siz") in messages and settings, as in the spoken prompts. The faster-route offer is answered with "Değiştir" or "Hayır". One wording for a time without traffic ("Trafiksiz tahmini süre").
- The traffic score beside the map has words of the app's own ("4 puan · Yer yer yoğun"). Error messages no longer show a server's status code.

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
