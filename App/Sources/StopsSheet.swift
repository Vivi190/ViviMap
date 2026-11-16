import AppCore
import DesignSystem
import NavigationEngine
import SearchEngine
import SwiftUI

/// "Yol üstünde ara" while guiding: places of one kind ahead on the route, the cheapest to turn into first, as
/// Yandex lists them on the way; a tap makes one the stop. One stop at a time: a new one takes the last one's place.
struct StopsSheet: View {
    let navigation: NavigationSession
    let onAdd: (Place) -> Void
    let onRemove: () -> Void
    @State private var kind: NearbyKind?
    /// nil while the indexes are read.
    @State private var found: [PlaceAhead]?

    /// Parking is for the destination: the bar offers it on arrival.
    private static let kinds = NearbyKind.allCases.filter { $0 != .parking }
    /// OpenStreetMap's first: where both have a place, its surveyed position is kept, as search keeps it.
    private static let indexes = [OfflinePlaceIndex.bundled, OfflinePlaceIndex.businesses].compactMap { $0 }

    var body: some View {
        List {
            if !navigation.stops.isEmpty {
                Section {
                    Button("Ara durağı kaldır", systemImage: "mappin.slash", role: .destructive, action: onRemove)
                }
            }
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.s), count: 4), spacing: Spacing.s) {
                    ForEach(Self.kinds, id: \.self) { option in
                        Button { kind = option } label: {
                            VStack(spacing: Spacing.xs) {
                                Image(systemName: option.systemImage)
                                    .font(.system(size: 17, weight: .semibold))
                                Text(option.title)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.bordered)
                        .tint(kind == nil || kind == option ? Color.atlasAccent : Color.secondary)
                        .accessibilityAddTraits(kind == option ? .isSelected : [])
                    }
                }
            }
            if let kind {
                Section("Rotanın önünde") {
                    if let found {
                        if found.isEmpty {
                            Text("Önünüzdeki 40 km'de rotaya yakın bir yer bulunamadı.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(found) { row($0, kind: kind) }
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Yol üstünde ara")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: kind) {
            guard let kind else { return }
            found = nil
            let places = await navigation.placesAhead(kind, in: Self.indexes)
            if !Task.isCancelled { found = places }
        }
    }

    /// "Shell", "Benzinlik · 3,2 km ileride · sağda", then the address.
    private func row(_ item: PlaceAhead, kind: NearbyKind) -> some View {
        Button { onAdd(item.place) } label: {
            HStack(spacing: Spacing.m) {
                Image(systemName: PlaceSymbol.name(for: item.place.category))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(PlaceSymbol.tint(for: item.place.category), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.place.name)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    let side: String? = item.side.map { $0 == .left ? "solda" : "sağda" }
                    Text([kind.title, "\(Formatting.distance(meters: item.ahead)) ileride", side].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !item.place.subtitle.isEmpty {
                        Text(item.place.subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.atlasAccent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Ara durak olarak ekler"))
    }
}
