import AppCore
import SwiftUI

struct MapSettingsView: View {
    @Environment(AppSettings.self) private var settings
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
            } footer: {
                Text("Arama, rota ve sesli yönlendirme sonraki fazda eklenecek.")
            }
        }
        .navigationTitle("Harita")
        .navigationBarTitleDisplayMode(.inline)
    }
}
