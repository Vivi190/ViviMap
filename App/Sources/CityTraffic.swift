import Foundation
import MapEngine
import Observation
import TrafficEngine

/// The "Trafik" layer, on by default: every road where the map rests, green to dark red, from the same
/// provider as the route times (ADR-5). One request covers a bit more than the screen and is reused for 5
/// minutes, so panning around stays cheap; the layer has its own monthly cap (RequestBudget.areaFlow). The
/// farther out, the fewer road classes (HERETrafficProvider.areaFlowRequest); beyond half a degree, nothing new.
@MainActor
@Observable
final class CityTraffic {
    private(set) var lines: [TrafficLine] = []
    /// 0 flowing … 10 standstill for the roads around (AreaTraffic.score), as Yandex scores its traffic.
    private(set) var score: Int?
    /// Shown under the search bar when the layer cannot load ("Bu ayın trafik sorgu sınırı doldu.").
    private(set) var notice: String?
    @ObservationIgnored private var fetched: (area: TrafficArea, at: Date)?

    static let refreshInterval: Duration = .seconds(300)

    func refresh(_ visible: TrafficArea, using provider: any TrafficProvider) async {
        // Zoomed out further than half a degree: answers get too big for a phone; keep what is drawn.
        guard visible.span <= 0.5 else { return }
        if let fetched, fetched.area.contains(visible), Date.now.timeIntervalSince(fetched.at) < 290 { return }
        let area = visible.expanded(by: 0.2)
        do {
            let segments = try await provider.flow(in: area)
            lines = AreaTraffic.sections(segments).map { TrafficLine($0) }
            score = AreaTraffic.score(segments)
            fetched = (area, .now)
            notice = nil
        } catch let error as TrafficError where error == .budgetExhausted {
            lines = []
            score = nil
            notice = error.localizedDescription
        } catch {
            // Offline or a server hiccup: the next rest of the map tries again.
        }
    }
}

extension TrafficLine {
    init(_ section: TrafficSection) {
        let level: TrafficLine.Level = switch section.level {
        case .free: .free
        case .slow: .slow
        case .heavy: .heavy
        case .stopped: .stopped
        }
        self.init(level: level, coordinates: section.coordinates)
    }
}
