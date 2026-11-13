import DesignSystem
import LocationEngine
import SwiftUI

/// Shows a chip only when location needs attention: permission off, approximate location, weak or lost GPS.
/// Its own view so GPS updates re-render just this chip, not the map screen.
struct GPSStatusChip: View {
    @Environment(LocationProvider.self) private var location
    let openSettings: () -> Void
    let showDiagnostics: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { context in
            Group {
                if location.isDenied {
                    Button(action: openSettings) {
                        StatusChip(systemImage: "location.slash.fill", title: "Konum izni kapalı", tone: .critical)
                    }
                } else if location.isAuthorized, !location.isPreciseLocation {
                    Button(action: openSettings) {
                        StatusChip(systemImage: "location.circle", title: "Yaklaşık konum açık", tone: .warning)
                    }
                } else if location.isAuthorized, let chip = signalChip(at: context.date) {
                    Button(action: showDiagnostics) { chip }
                }
            }
            .buttonStyle(.plain)
            .transition(.opacity)
        }
    }

    private func signalChip(at date: Date) -> StatusChip? {
        switch location.quality(at: date) {
        case .poor:
            let radius = Int(location.lastLocation?.horizontalAccuracy ?? 0)
            return StatusChip(systemImage: "antenna.radiowaves.left.and.right", title: "GPS zayıf · ±\(radius) m", tone: .warning)
        case .unavailable where location.hasFix:
            return StatusChip(systemImage: "antenna.radiowaves.left.and.right.slash", title: "GPS sinyali yok", tone: .warning)
        default:
            return nil
        }
    }
}

/// Speed badge while moving; hidden when standing still or when there is no usable speed.
struct SpeedOverlay: View {
    @Environment(LocationProvider.self) private var location

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let reading = location.speedReading(at: context.date)
            ZStack {
                if let kmh = reading.kmh, kmh > 0 {
                    SpeedometerView(kmh: kmh, isReliable: reading.isReliable)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: (reading.kmh ?? 0) > 0)
        }
    }
}
