import AppCore
import DesignSystem
import LocationEngine
import RoadHazards
import RoutingEngine
import SearchEngine
import SwiftUI
import TrafficEngine

/// The search pill at the top of the map; opens the search screen.
struct SearchBarButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Ara")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.l)
            .frame(height: Metrics.controlWidth)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .atlasFloatingSurface(in: Capsule())
        .accessibilityLabel(Text("Ara"))
        .accessibilityIdentifier("search.open")
    }
}

/// "Ev" / "İş" under the search pill once saved: one tap to the route card, as Google Maps offers.
struct ShortcutChips: View {
    let hasHome: Bool
    let hasWork: Bool
    let onTap: (SearchController.Slot) -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            if hasHome { chip("Ev", "house.fill", .home) }
            if hasWork { chip("İş", "briefcase.fill", .work) }
        }
    }

    private func chip(_ title: String, _ symbol: String, _ slot: SearchController.Slot) -> some View {
        Button { onTap(slot) } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: symbol)
                    .foregroundStyle(Color.atlasAccent)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .atlasFloatingSurface(in: Capsule())
        .accessibilityLabel(Text("\(title): rota"))
        .accessibilityIdentifier("shortcut.\(slot.rawValue)")
    }
}

struct SearchSheet: View {
    @Bindable var search: SearchController
    let onSelect: (Place) -> Void
    /// Home / work: one tap goes straight to the route.
    let onShortcut: (Place) -> Void
    @Environment(LocationProvider.self) private var location
    @State private var isSearchPresented = true

    private var hasQuery: Bool {
        search.query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    var body: some View {
        List {
            if hasQuery {
                if let center = search.nearbyCenter {
                    Section("\(center.name) yakınında") {
                        ForEach(search.results) { place in row(place) }
                    }
                } else {
                    ForEach(search.results) { place in row(place) }
                }
            } else {
                if search.canShowNearby {
                    Section("Yakında") { nearbyButtons }
                }
                if search.home != nil || search.work != nil {
                    Section("Kısayollar") {
                        if let home = search.home { shortcut("Ev", "house.fill", home) }
                        if let work = search.work { shortcut("İş", "briefcase.fill", work) }
                    }
                }
                if !search.recents.isEmpty {
                    recentsSection
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay { emptyState }
        .navigationTitle("Ara")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $search.query,
            isPresented: $isSearchPresented,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Adres, yer veya koordinat"
        )
        .autocorrectionDisabled()
    }

    private func shortcut(_ title: String, _ symbol: String, _ place: Place) -> some View {
        Button { onShortcut(place) } label: {
            HStack(spacing: Spacing.m) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.atlasAccent, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(place.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .foregroundStyle(Color.atlasAccent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(title): rota"))
    }

    /// Nearest fuel, parking, pharmacy, charger from the shipped Istanbul index: instant, and offline too.
    /// Bordered buttons, so each one takes its own tap inside the shared list row.
    private var nearbyButtons: some View {
        HStack(spacing: Spacing.s) {
            ForEach(NearbyKind.allCases, id: \.self) { kind in
                Button { search.showNearby(kind) } label: {
                    VStack(spacing: Spacing.xs) {
                        Image(systemName: kind.systemImage)
                            .font(.system(size: 17, weight: .semibold))
                        Text(kind.title)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .tint(Color.atlasAccent)
            }
        }
    }

    private var recentsSection: some View {
        Section {
            ForEach(search.recents) { place in row(place) }
        } header: {
            Text("Son aramalar")
        } footer: {
            Button("Geçmişi temizle", role: .destructive) { search.clearRecents() }
                .font(.footnote)
        }
    }

    @ViewBuilder private var emptyState: some View {
        if hasQuery {
            if search.isSearching, search.results.isEmpty {
                ProgressView()
            } else if let message = search.errorMessage {
                ContentUnavailableView("Arama yapılamadı", systemImage: "wifi.exclamationmark", description: Text(message))
            } else if search.results.isEmpty {
                if search.query.lowercased(with: Locale(identifier: "tr")).contains("nöbetçi") {
                    // Searched often, and OSM has no duty roster: say so instead of a bare "no results".
                    ContentUnavailableView(
                        "Nöbet bilgisi yok",
                        systemImage: "cross.case",
                        description: Text("Haritada eczanelerin nöbet çizelgesi yok. En yakın eczaneler için \"eczane\" yaz; açık olup olmadığını gitmeden önce kontrol et.")
                    )
                } else {
                    ContentUnavailableView.search(text: search.query)
                }
            }
        } else if search.recents.isEmpty, search.home == nil, search.work == nil {
            ContentUnavailableView(
                "Nereye gidiyoruz?",
                systemImage: "magnifyingglass",
                description: Text("Adres, mahalle, işletme, koordinat ya da benzinlik gibi bir tür yaz.")
            )
        }
    }

    private func row(_ place: Place) -> some View {
        Button { onSelect(place) } label: {
            HStack(spacing: Spacing.m) {
                Image(systemName: PlaceSymbol.name(for: place.category))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(PlaceSymbol.tint(for: place.category), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if !place.subtitle.isEmpty {
                        Text(place.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let distance = distanceText(to: place) {
                    Text(distance)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("search.result")
    }

    /// From the user, or from the place the list is around ("Yakındaki otoparklar").
    private func distanceText(to place: Place) -> String? {
        guard let from = search.nearbyCenter?.point ?? location.lastLocation.map({ GeoPoint($0.coordinate) }) else { return nil }
        return Formatting.distance(meters: from.distance(to: place.point))
    }
}

/// Bottom card for the selected place: details, route request, home/work shortcut.
struct PlaceCard: View {
    @Environment(LocationProvider.self) private var location
    let place: Place
    let isPlanning: Bool
    let error: String?
    let onRoute: () -> Void
    let onSave: (SearchController.Slot) -> Void
    /// Marks a camera or bump at this place (OSM barely maps cameras around Pendik/Kartal/Tuzla).
    let onMark: (Hazard.Kind) -> Void
    /// Car parks around this place, from the shipped index; nil in builds without it (the item is hidden).
    let onParking: (() -> Void)?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            details
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.atlasWarning)
            }
            HStack(spacing: Spacing.s) {
                Button(action: onRoute) {
                    HStack(spacing: Spacing.s) {
                        if isPlanning {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        }
                        Text(isPlanning ? "Rota hesaplanıyor" : "Rota")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(isPlanning)
                .accessibilityIdentifier("place.route")

                Menu {
                    if let onParking {
                        Button("Yakındaki otoparklar", systemImage: "parkingsign", action: onParking)
                    }
                    Button("Ev olarak kaydet", systemImage: "house.fill") { onSave(.home) }
                    Button("İş olarak kaydet", systemImage: "briefcase.fill") { onSave(.work) }
                    Section("Uyarı noktası") {
                        Button("Kamera işaretle", systemImage: "camera.fill") { onMark(.camera) }
                        Button("Kasis işaretle", systemImage: "exclamationmark.triangle.fill") { onMark(.bump) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel(Text("Diğer seçenekler"))
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .atlasFloatingSurface(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("place.card")
    }

    private var details: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: PlaceSymbol.name(for: place.category))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(PlaceSymbol.tint(for: place.category), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.headline)
                    .lineLimit(2)
                if !place.subtitle.isEmpty {
                    Text(place.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let here = location.lastLocation?.coordinate {
                    Text(Formatting.distance(meters: GeoPoint(here).distance(to: place.point)) + " uzaklıkta")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Kapat"))
        }
    }
}

/// Route preview: time first (what a driver decides on), then distance, arrival, main roads, alternatives.
struct RouteCard: View {
    enum TrafficStatus {
        /// No HERE key in this build.
        case unavailable
        case loading
        /// Every alternative measured with live traffic.
        case ready
        case failed
    }

    let place: Place
    let routes: [RouteOption]
    let traffic: [Int: TrafficEstimate]
    let trafficStatus: TrafficStatus
    /// The "Ücretli yollardan kaçın" setting these routes were planned with.
    let avoidsTolls: Bool
    @Binding var selection: Int
    /// nil when navigation could not be set up; the button is hidden rather than shown broken.
    let onStart: (() -> Void)?
    /// Test drive; nil unless enabled in the map settings.
    let onSimulate: (() -> Void)?
    let onClose: () -> Void

    /// Tolls and ferries before the driver commits to a route, and whether the setting shaped it.
    static func notes(_ notes: RouteNotes, avoidsTolls: Bool) -> String? {
        var parts: [String] = []
        if notes.hasToll { parts.append("Ücretli geçiş var") }
        if notes.hasFerry { parts.append("Feribotla geçiş") }
        if avoidsTolls, !notes.hasToll { parts.append("Ücretli yollardan kaçınıldı") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Live-traffic time when every alternative was measured, otherwise Valhalla's free-flow estimate.
    private func duration(_ option: RouteOption) -> TimeInterval {
        trafficStatus == .ready ? traffic[option.index]?.duration ?? option.duration : option.duration
    }

    var body: some View {
        let route = routes[min(selection, routes.count - 1)]
        let fastest = routes.map(duration).min() ?? 0
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .font(.headline)
                        .lineLimit(1)
                    if !place.subtitle.isEmpty {
                        Text(place.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 26))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Rotayı kapat"))
            }
            VStack(spacing: Spacing.xs) {
                // Fastest first, by the same time the rows show (selection follows `index`, not the row).
                ForEach(routes.sorted { duration($0) < duration($1) }) { option in
                    routeRow(option, isSelected: option.index == route.index, fastest: fastest)
                }
            }
            if route.isOffline {
                // No connection: computed on the phone from the shipped Istanbul tiles, so no traffic either.
                Label("Çevrimdışı rota · cihazdaki İstanbul verisiyle, trafiksiz", systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                trafficSource
            }
            if let onStart {
                HStack(spacing: Spacing.s) {
                    Button(action: onStart) {
                        Label("Başlat", systemImage: "location.north.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .accessibilityIdentifier("route.start")
                    if let onSimulate {
                        Button(action: onSimulate) {
                            Label("Simüle et", systemImage: "play.fill")
                                .font(.headline)
                                .padding(.horizontal, Spacing.s)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .accessibilityIdentifier("route.simulate")
                    }
                }
                .padding(.top, Spacing.xs)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .atlasFloatingSurface(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route.card")
        .animation(.snappy(duration: 0.25), value: selection)
        .animation(.snappy(duration: 0.25), value: trafficStatus)
    }

    /// One candidate: time and how much slower than the fastest, distance and arrival. The chosen one also
    /// shows its main roads, the traffic delay and tolls or ferries; the others stay one line high, so three
    /// of them leave the map its room.
    private func routeRow(_ option: RouteOption, isSelected: Bool, fastest: TimeInterval) -> some View {
        let time = duration(option)
        let extra = time - fastest
        let arrival = Date.now.addingTimeInterval(time).formatted(date: .omitted, time: .shortened)
        let estimate = trafficStatus == .ready ? traffic[option.index] : nil
        let choosable = routes.count > 1
        return Button { selection = option.index } label: {
            HStack(alignment: .top, spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                        Text(Formatting.duration(seconds: time))
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        if choosable, extra >= 60 {
                            Text("+\(Formatting.duration(seconds: extra))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else if choosable {
                            Text("En hızlı")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.atlasAccent)
                        }
                    }
                    Text("\(Formatting.distance(meters: option.distance)) · Varış \(arrival)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                    if isSelected {
                        if let estimate {
                            TrafficDelayLabel(estimate: estimate)
                        }
                        if !option.mainRoads.isEmpty {
                            Label(option.mainRoads.joined(separator: " → "), systemImage: "road.lanes")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let notes = Self.notes(option.notes, avoidsTolls: avoidsTolls) {
                            Label(notes, systemImage: option.notes.hasFerry ? "ferry" : "turkishlirasign.circle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
                if choosable {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.atlasAccent : Color.secondary.opacity(0.5))
                }
            }
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (isSelected && choosable ? Color.atlasAccent.opacity(0.12) : Color.primary.opacity(0.04)),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(Formatting.duration(seconds: time)), \(Formatting.distance(meters: option.distance)), varış \(arrival)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Always says where the time comes from; HERE's terms require the attribution where its data shows.
    @ViewBuilder private var trafficSource: some View {
        switch trafficStatus {
        case .unavailable:
            Label("Trafik dahil değil — trafiksiz tahmini süre", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .loading:
            HStack(spacing: Spacing.s) {
                ProgressView().controlSize(.small)
                Text("Canlı trafik alınıyor…")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .failed:
            Label("Trafik alınamadı — trafiksiz tahmini süre", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .ready:
            Label("Canlı trafikle · © HERE", systemImage: "dot.radiowaves.up.forward")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// "Trafik 6 dk ekliyor", coloured by how much slower than free flow (HERE's own baseline, same scale).
struct TrafficDelayLabel: View {
    let estimate: TrafficEstimate

    var body: some View {
        let share = estimate.baseDuration > 0 ? estimate.delay / estimate.baseDuration : 0
        let text = estimate.delay >= 60 ? "Trafik \(Formatting.duration(seconds: estimate.delay)) ekliyor" : "Trafik akıcı"
        Label(text, systemImage: "car.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(share >= 0.25 ? Color.atlasCritical : share >= 0.1 ? Color.atlasWarning : Color.green)
    }
}

/// SF Symbol and tint per OSM category, so lists scan by shape before text.
enum PlaceSymbol {
    static func name(for category: String?) -> String {
        guard let category else { return "mappin" }
        let value = category.split(separator: "=").last.map(String.init) ?? ""
        switch category.split(separator: "=").first.map(String.init) ?? "" {
        case "highway":
            return value == "bus_stop" ? "bus" : "road.lanes"
        case "railway", "public_transport": return "tram.fill"
        case "aeroway": return "airplane"
        case "leisure": return value == "park" ? "leaf.fill" : "figure.run"
        case "shop": return "bag.fill"
        case "building", "place": return "building.2.fill"
        case "amenity":
            switch value {
            case "hospital", "clinic", "doctors", "pharmacy": return "cross.case.fill"
            case "restaurant", "cafe", "fast_food": return "fork.knife"
            case "fuel": return "fuelpump.fill"
            case "parking": return "parkingsign"
            case "school", "university", "college", "kindergarten": return "graduationcap.fill"
            case "townhall", "courthouse": return "building.columns.fill"
            default: return "mappin"
            }
        default: return "mappin"
        }
    }

    static func tint(for category: String?) -> Color {
        switch category?.split(separator: "=").first.map(String.init) {
        case "highway": .gray
        case "railway", "public_transport", "aeroway": .blue
        case "leisure": .green
        case "shop": .orange
        case "amenity": category?.hasSuffix("=fuel") == true ? .indigo : .pink
        default: .atlasCritical
        }
    }
}
