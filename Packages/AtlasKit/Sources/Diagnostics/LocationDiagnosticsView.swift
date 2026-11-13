import CoreLocation
import LocationEngine
import SwiftUI

/// Live GPS readout for validating location quality on a real device (accuracy, speed, update rate).
public struct LocationDiagnosticsView: View {
    @Environment(LocationProvider.self) private var location

    public init() {}

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            List {
                Section("İzin") {
                    LabeledContent("Konum izni", value: authorizationText)
                    LabeledContent("Hassas konum", value: location.isPreciseLocation ? "Açık" : "Kapalı (yaklaşık)")
                }
                Section("Son konum") {
                    if let fix = location.lastLocation {
                        LabeledContent("Yatay doğruluk", value: metres(fix.horizontalAccuracy))
                        LabeledContent("Konum yaşı", value: String(format: "%.1f sn", context.date.timeIntervalSince(fix.timestamp)))
                        LabeledContent("Güncelleme aralığı", value: location.updateInterval.map { String(format: "%.2f sn", $0) } ?? "—")
                        LabeledContent("GPS hızı", value: speed(fix))
                        LabeledContent("Hız doğruluğu", value: fix.speedAccuracy >= 0 ? String(format: "±%.1f km/sa", fix.speedAccuracy * 3.6) : "Bilinmiyor")
                        LabeledContent("Hareket yönü", value: fix.course >= 0 ? String(format: "%.0f° (±%.0f°)", fix.course, fix.courseAccuracy) : "Bilinmiyor")
                        LabeledContent("Rakım", value: fix.verticalAccuracy >= 0 ? String(format: "%.0f m (±%.0f m)", fix.altitude, fix.verticalAccuracy) : "Bilinmiyor")
                        LabeledContent("Koordinat", value: String(format: "%.5f, %.5f", fix.coordinate.latitude, fix.coordinate.longitude))
                            .textSelection(.enabled)
                    } else {
                        Text("Henüz konum alınmadı.")
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = location.lastError {
                    Section("Son hata") {
                        Text(error).foregroundStyle(.secondary)
                    }
                }
            }
            .monospacedDigit()
        }
        .navigationTitle("GPS tanılama")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var authorizationText: String {
        switch location.authorization {
        case .authorizedAlways: "Her zaman"
        case .authorizedWhenInUse: "Uygulama kullanılırken"
        case .denied: "Reddedildi"
        case .restricted: "Kısıtlı"
        case .notDetermined: "Sorulmadı"
        @unknown default: "Bilinmiyor"
        }
    }

    private func metres(_ value: CLLocationAccuracy) -> String {
        value >= 0 ? String(format: "±%.0f m", value) : "Geçersiz"
    }

    private func speed(_ fix: CLLocation) -> String {
        fix.speed >= 0 ? String(format: "%.1f km/sa", fix.speed * 3.6) : "Geçersiz"
    }
}
