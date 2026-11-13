import AppCore
import RoadHazards
import SwiftUI

/// Age of the shipped camera/bump data, read once.
enum HazardData {
    static let fetched: String = {
        guard let date = HazardCatalog.bundled()?.fetched else { return "tarih bilinmiyor" }
        return date.split(separator: "-").reversed().joined(separator: ".") // 2026-11-14 → 14.11.2026
    }()
}

/// The driver's own camera / bump marks; swipe to delete.
struct MarkedHazardsView: View {
    @Environment(UserHazardStore.self) private var store

    var body: some View {
        List {
            ForEach(Array(store.hazards.enumerated()), id: \.offset) { _, hazard in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hazard.kind == .camera ? "Hız kamerası" : "Kasis")
                        Text(String(format: "%.5f, %.5f", hazard.latitude, hazard.longitude))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: hazard.kind == .camera ? "camera.fill" : "exclamationmark.triangle.fill")
                }
            }
            .onDelete { store.remove(atOffsets: $0) }
        }
        .overlay {
            if store.hazards.isEmpty {
                ContentUnavailableView(
                    "İşaret yok",
                    systemImage: "mappin.slash",
                    description: Text("Haritada bir noktaya uzun bas, kartın menüsünden \"Kamera işaretle\" ya da \"Kasis işaretle\" seç.")
                )
            }
        }
        .navigationTitle("İşaretlerim")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MapSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(UserHazardStore.self) private var userHazards
    @Environment(\.dismiss) private var dismiss
    let showDiagnostics: () -> Void

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Harita görünümü", selection: $settings.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Görünüm")
            } footer: {
                Text("Otomatik: bulunduğun yerde gün batımından gün doğumuna kadar gece haritası.")
            }

            Section {
                Toggle("Hız kamerası uyarıları", isOn: $settings.warnsCameras)
                Toggle("Kasis uyarıları", isOn: $settings.warnsBumps)
                NavigationLink {
                    MarkedHazardsView()
                } label: {
                    LabeledContent("İşaretlerim", value: "\(userHazards.hazards.count)")
                }
            } header: {
                Text("Uyarılar")
            } footer: {
                Text("Veri: OpenStreetMap, \(HazardData.fetched). Her kamera ve kasis haritada işli değil; Pendik, Kartal ve Tuzla'da kamera verisi çok az.")
            }

            Section {
                Button("GPS tanılama", systemImage: "antenna.radiowaves.left.and.right", action: showDiagnostics)
                Toggle("Sürüş simülasyonu", isOn: $settings.showsDriveSimulation)
            } header: {
                Text("Test")
            } footer: {
                Text("Rota kartına \"Simüle et\" ekler: konum, GPS yerine rota boyunca ilerler. Sesli yönlendirmeyi araç kullanmadan denemek için.")
            }
        }
        .navigationTitle("Harita")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Bitti") { dismiss() }
            }
        }
    }
}
