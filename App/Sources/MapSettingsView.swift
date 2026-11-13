import AppCore
import SwiftUI

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
