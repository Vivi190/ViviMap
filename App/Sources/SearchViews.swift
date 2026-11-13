import AppCore
import DesignSystem
import LocationEngine
import SearchEngine
import SwiftUI

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

struct SearchSheet: View {
    @Bindable var search: SearchController
    let onSelect: (Place) -> Void
    @Environment(LocationProvider.self) private var location
    @State private var isSearchPresented = true

    private var hasQuery: Bool {
        search.query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    var body: some View {
        List {
            if hasQuery {
                ForEach(search.results) { place in row(place) }
            } else if !search.recents.isEmpty {
                Section {
                    ForEach(search.recents) { place in row(place) }
                } header: {
                    Text("Son aramalar")
                } footer: {
                    Button("Geçmişi temizle", role: .destructive) { search.clearRecents() }
                        .font(.footnote)
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

    @ViewBuilder private var emptyState: some View {
        if hasQuery {
            if search.isSearching, search.results.isEmpty {
                ProgressView()
            } else if let message = search.errorMessage {
                ContentUnavailableView("Arama yapılamadı", systemImage: "wifi.exclamationmark", description: Text(message))
            } else if search.results.isEmpty {
                ContentUnavailableView.search(text: search.query)
            }
        } else if search.recents.isEmpty {
            ContentUnavailableView(
                "Nereye gidiyoruz?",
                systemImage: "magnifyingglass",
                description: Text("Adres, mahalle, işletme ya da koordinat yaz.")
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

    private func distanceText(to place: Place) -> String? {
        guard let here = location.lastLocation?.coordinate else { return nil }
        return Formatting.distance(meters: GeoPoint(here).distance(to: place.point))
    }
}

/// Bottom card for the selected place. Routing arrives in the next slice; until then the card only informs.
struct PlaceCard: View {
    @Environment(LocationProvider.self) private var location
    let place: Place
    let onClose: () -> Void

    var body: some View {
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
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .atlasFloatingSurface(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("place.card")
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
