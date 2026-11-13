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

struct MapSettingsView: View {
    @Environment(AppSettings.self) private var settings
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
