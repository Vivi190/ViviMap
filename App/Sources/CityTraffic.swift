import Foundation
import MapEngine
import Observation
import TrafficEngine

/// The "Trafik" layer: slow, queuing and stopped roads where the map rests, from the same provider as the
/// route times (ADR-5). One request covers a bit more than the screen and is reused for 3 minutes, so panning
/// around stays cheap; the layer has its own monthly cap (RequestBudget.areaFlow). Zoomed out to more than
/// half a degree it shows main roads only, beyond that nothing new (HERETrafficProvider.flow(in:)).
@MainActor
@Observable
final class CityTraffic {
    private(set) var lines: [TrafficLine] = []
    /// Shown under the search bar when the layer cannot load ("Bu ayın trafik sorgu sınırı doldu.").
    private(set) var notice: String?
    @ObservationIgnored private var fetched: (area: TrafficArea, at: Date)?

    static let refreshInterval: Duration = .seconds(180)

    func refresh(_ visible: TrafficArea, using provider: any TrafficProvider) async {
        // Zoomed out further than half a degree: answers get too big for a phone; keep what is drawn.
        guard visible.span <= 0.5 else { return }
        if let fetched, fetched.area.contains(visible), Date.now.timeIntervalSince(fetched.at) < 170 { return }
        let area = visible.expanded(by: 0.2)
        do {
            let segments = try await provider.flow(in: area)
            lines = AreaTraffic.sections(segments).map { TrafficLine($0) }
            fetched = (area, .now)
            notice = nil
        } catch let error as TrafficError where error == .budgetExhausted {
            lines = []
            notice = error.localizedDescription
        } catch {
            // Offline or a server hiccup: the next rest of the map tries again.
        }
    }
}

extension TrafficLine {
    init(_ section: TrafficSection) {
        let level: TrafficLine.Level = switch section.level {
        case .slow: .slow
        case .heavy: .heavy
        case .stopped: .stopped
        }
        self.init(level: level, coordinates: section.coordinates)
    }
}
