import AVFoundation
import AppCore
import DesignSystem
import MapEngine
import NavigationEngine
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
                    description: Text("Navigasyonla yaptığınız her sürüşte, başta söylenen süre ile gerçekleşen süre burada karşılaştırılır. Simülasyonlar kaydedilmez.")
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
                    ? "\(title) sürüşlerinizde tuttu."
                    : "\(title) sürüşlerinizde ortalama %\(percent) \(result.ratio > 1 ? "daha uzun" : "daha kısa") sürdü.")
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
                    description: Text("Haritada bir noktaya uzun basın, kartın menüsünden \"Kamera işaretle\" ya da \"Kasis işaretle\" seçin.")
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
    /// Plays a sample prompt the way guidance speaks it (also in silent mode), e.g. after downloading a voice.
    @State private var sampleVoice = VoiceGuide()
    let showDiagnostics: () -> Void

    /// Which Turkish voice guidance uses, and how to get a better one when only the compact voice is there.
    private var voiceSection: some View {
        let voice = VoiceGuide.bestTurkishVoice()
        let quality = switch voice?.quality {
        case .premium: "Premium"
        case .enhanced: "Geliştirilmiş"
        default: "Standart"
        }
        return Section {
            LabeledContent("Ses", value: voice.map { "\($0.name) · \(quality)" } ?? "Türkçe ses yok")
            if voice != nil {
                Button("Örnek dinle", systemImage: "play.circle") {
                    sampleVoice.speak("300 metre sonra sağa dönün, Ankara Caddesi.")
                }
            }
        } header: {
            Text("Sesli yönlendirme")
        } footer: {
            if voice?.quality != .enhanced, voice?.quality != .premium {
                Text("Daha doğal bir ses için: Ayarlar → Erişilebilirlik → Seslendirilen İçerik → Sesler → Türkçe'den bir sesin \"Geliştirilmiş\" sürümünü indirin. Atlas indirileni kendiliğinden kullanır.")
            }
        }
    }

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
                Text("Otomatik: bulunduğunuz yerde gün batımından gün doğumuna kadar gece haritası.")
            }

            Section {
                Toggle("Ücretli yollardan kaçın", isOn: $settings.avoidsTolls)
                Toggle("Feribotlardan kaçın", isOn: $settings.avoidsFerries)
            } header: {
                Text("Rota")
            } footer: {
                Text("Ücretli yollardan kaçınan rota köprü, tünel ve otoyol gişelerinden geçmez; Boğaz'ı araba vapuruyla geçebilir ve daha uzun sürebilir. İkisi birlikte açıkken Boğaz'ın karşısına rota bulunamaz.")
            }

            voiceSection

            Section {
                Toggle("Hız kamerası uyarıları", isOn: $settings.warnsCameras)
                Toggle("Kasis uyarıları", isOn: $settings.warnsBumps)
                Toggle("Hız sınırı uyarısı", isOn: $settings.warnsSpeeding)
                NavigationLink {
                    MarkedHazardsView()
                } label: {
                    LabeledContent("İşaretlerim", value: "\(userHazards.hazards.count)")
                }
            } header: {
                Text("Uyarılar")
            } footer: {
                Text("Veri: OpenStreetMap, \(HazardData.fetched). Her kamera ve kasis haritada yer almıyor; Pendik, Kartal ve Tuzla'da kamera verisi çok az.")
            }

            Section {
                NavigationLink {
                    TripsView()
                } label: {
                    LabeledContent("Sürüşlerim", value: "\(trips.trips.count)")
                }
            } footer: {
                Text("Varış tahminlerinin sürüşlerinizde ne kadar tuttuğu.")
            }

            if let date = OfflineMap.dataDate {
                Section {
                    LabeledContent("İstanbul verisi", value: date)
                } header: {
                    Text("Çevrimdışı")
                } footer: {
                    Text("İnternet yokken harita, arama ve rota bu veriyle çalışır; yeni sürümle tazelenir.")
                }
            }

            Section {
                Button("GPS tanılama", systemImage: "antenna.radiowaves.left.and.right", action: showDiagnostics)
                Toggle("Sürüş simülasyonu", isOn: $settings.showsDriveSimulation)
            } header: {
                Text("Tanılama")
            } footer: {
                Text("Rota kartına simülasyon düğmesi ekler: konum, GPS yerine rota boyunca ilerler. Sesli yönlendirmeyi araç kullanmadan denemek için.")
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
