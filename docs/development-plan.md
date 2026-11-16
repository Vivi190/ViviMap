# Development plan

Each phase starts once the previous one is verified. A phase counts as done when its exit criteria are demonstrated; written code alone does not count. Release history: [CHANGELOG.md](../CHANGELOG.md). Step-by-step device tests (Turkish): [device-testing.tr.md](device-testing.tr.md).

| Phase | Scope | Exit criteria | Status |
|---|---|---|---|
| 0 — Research | Libraries, licences, traffic, offline, search, CarPlay, CI | Report and architecture decisions ([architecture.md](architecture.md)) | ✅ |
| 1 — Foundation | Project structure, design system, map, location, speedometer, CI, TestFlight pipeline | CI green; simulator screenshots; TestFlight install on a device | 🟡 Code and CI done; device check pending |
| 2 — Navigation MVP | Search (Photon), saved places, routing (Valhalla), Ferrostar guidance, Turkish voice, rerouting, background guidance | Istanbul search benchmark; simulated drives; a real drive Pendik → Kartal | 🟡 Simulated drives pass in CI on a real Kartal route (arrival, rerouting). Search benchmark: first result correct for 64 of 64 queries ([report](research/2026-11-14-arama-olcumu.md), Turkish). Pending: real drive |
| 3 — Traffic | HERE traffic, candidate scoring, traffic layer, rerouting with hysteresis | Predicted vs actual times on real drives; no route flapping | 🟡 Verified live on a Kartal route (5,169 m: 480 s with traffic, 458 s free flow). Route times and ranking with traffic, live arrival every 3 min, a hysteresis-guarded "faster route" offer, traffic-coloured route line, city traffic layer with an area score, road events, monthly request budget per device. Pending: rush-hour test on a device |
| 4 — Offline | Bundled map, on-device routing, offline search, online ↔ offline switching | An airplane-mode drive end to end | 🟡 On-device Valhalla 3.9.0 for planning and rerouting; Istanbul map (PMTiles, 50 MB) and routing tiles (108 MB) built in CI and bundled; offline search index (SQLite FTS4 with Turkish folding). Region downloads are out of scope by design: one bundled region, refreshed with each build. Pending: airplane-mode drive |
| 5 — Driver aids | Speed limits, bump and camera warnings, user marks, lanes | Warning timing; opposite-direction filter; no repeated warnings | 🟡 Bundled OpenStreetMap hazards (Istanbul: 208 cameras, 2,558 bumps, 4,118 traffic lights), unit-tested timing and direction filter, user marks, speed-limit sign where OSM has `maxspeed`, spoken over-speed warning. Lane data is nearly absent in OSM (one junction in about 280 on each of two test routes) |
| 6 — Premium experience | 3D guidance camera, speed-based zoom, route choice, landscape layout | Screenshot review; 60 FPS on a device | 🟡 3D camera, zoom by speed and next turn, route overview, follow-up maneuver, landscape layout for car mounts, route choice with time bubbles. Pending: 60 FPS measurement |
| 7 — Extras | Live Activity, CarPlay (entitlement), trip history, personal time calibration | Calibration report from real drives | 🟡 Trip history and calibration, Live Activity (lock screen, Dynamic Island, CarPlay dashboard on iOS 26), share arrival, Siri and Shortcuts. Full CarPlay navigation needs an Apple entitlement |
| 8 — Verification | Battery, memory, long drives, traffic accuracy, UI review | Measurement report; comparisons with other apps only from measured data | 🟡 UI reviewed from CI screenshots each build. Long simulated drive Pendik → Kadıköy (18 km): arrival, no reroute, peak memory growth under 8 MB. Pending on a device: battery, 60 FPS, arrival-time accuracy |

## Open items

**Needs a device** (cannot be measured in CI):

- Install, map loading, location dot and heading.
- Speedometer against the car; "–" and "GPS sinyali yok" in tunnels.
- Automatic switch to the night map after sunset.
- Guidance on the lock screen and in the Live Activity.
- A drive in airplane mode; a drive at rush hour with live traffic.
- Traffic colours against another traffic map on the same roads at the same time; the timing and wording of spoken prompts on a real drive.
- 60 FPS, battery use on a long drive, arrival-time accuracy (trip log calibration).

**Decisions for the project owner:**

- Whether to apply for Apple's CarPlay navigation entitlement.
- External TestFlight testing, which needs Beta App Review contact details.

## Known limitations

- Live traffic stays within HERE's free tier through a monthly request budget per device. When it runs out, route times fall back to free-flow estimates and the traffic layer says so.
- Routing uses the shared FOSSGIS Valhalla server, which can be slow at busy times.
- With tolls avoided, the Bosphorus is crossed by car ferry; sailing times and waiting at the pier are not in the estimate.
- Lanes, house numbers and speed limits appear only where OpenStreetMap has them (speed limits on 9–16 % of roads around Pendik, Kartal and Tuzla); nothing is invented.
- Offline mode covers the Istanbul area only, without traffic. Offline search finds places and streets, not house numbers.
- Voice quality depends on the Turkish voice installed on the device; an "Enhanced" voice reads more naturally.
- In a tunnel the position stops until the signal returns; there is no dead reckoning.
- Businesses come from open data (Overture Maps): far more of them than OpenStreetMap has, but a position can be a building off and a closed shop can still be listed.
