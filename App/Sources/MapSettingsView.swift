import AppCore
import DesignSystem
import RoadHazards
import SwiftUI
import TripHistory

/// Guided drives with predicted vs actual time, and how far off the estimates run for this driver.
struct TripsView: View {
    @Environment(TripLog.self) private var log

    var body: some View {
        List {
            calibration(withTraffic: true, title: "Trafikli tahminler")
            calibration(withTraffic: false, title: "Trafiksiz tahminler")
            Section {
                ForEach(log.trips) { trip in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(trip.destination).font(.headline).lineLimit(1)
                            Spacer(minLength: Spacing.s)
                            Text(trip.startedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: Spacing.s) {
                            Text("Tahmin \(Formatting.duration(seconds: trip.predicted)) · Gerçek \(Formatting.duration(seconds: trip.actual))")
                                .monospacedDigit()
                            if trip.arrived {
                                let difference = trip.actual - trip.predicted
                                Text("\(difference >= 0 ? "+" : "−")\(Formatting.duration(seconds: abs(difference)))")
                                    .monospacedDigit()
                                    .foregroundStyle(difference > 120 ? Color.atlasWarning : Color.secondary)
                            } else {
                                Text("yarıda bitti").foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline)
                        Text("\(Formatting.distance(meters: trip.distance)) · \(trip.predictedWithTraffic ? "trafikli tahmin" : "trafiksiz tahmin")")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { log.remove(atOffsets: $0) }
            } footer: {
                if !log.trips.isEmpty { Text("Sürüşler yalnızca bu telefonda tutulur.") }
            }
        }
        .overlay {
            if log.trips.isEmpty {
                ContentUnavailableView(
                    "Henüz sürüş yok",
                    systemImage: "car",
                    description: Text("Navigasyonla yaptığın her sürüşte, başta söylenen süre ile gerçekleşen süre burada karşılaştırılır. Simülasyonlar kaydedilmez.")
                )
            }
        }
        .navigationTitle("Sürüşlerim")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func calibration(withTraffic: Bool, title: String) -> some View {
        if let result = log.calibration(withTraffic: withTraffic) {
            let percent = Int((abs(result.ratio - 1) * 100).rounded())
            Section {
                Text(percent == 0
                    ? "\(title) senin sürüşlerinde tuttu."
                    : "\(title) senin sürüşlerinde ortalama %\(percent) \(result.ratio > 1 ? "daha uzun" : "daha kısa") sürdü.")
            } footer: {
                Text("\(result.drives) tamamlanmış sürüşün ortancası; 5 dakikadan kısa sürüşler sayılmaz.")
            }
        }
    }
}

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
    @Environment(TripLog.self) private var trips
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
                NavigationLink {
                    TripsView()
                } label: {
                    LabeledContent("Sürüşlerim", value: "\(trips.trips.count)")
                }
            } footer: {
                Text("Varış tahminlerinin senin sürüşlerinde ne kadar tuttuğu.")
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
