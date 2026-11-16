import CoreLocation
import Foundation
import MapEngine
import Observation
import TrafficEngine

/// The "Trafik" layer, on by default: the roads where the map rests, green to dark red, from the same
/// provider as the route times (ADR-5). One request covers more than the screen (TrafficArea.expanded) and is
/// reused for 2 minutes, so panning around or following the car stays cheap; the layer has its own monthly cap
/// (RequestBudget.areaFlow). The farther out, the fewer road classes (HERETrafficProvider.areaFlowRequest);
/// beyond 0.8°, nothing new.
@MainActor
@Observable
final class CityTraffic {
    private(set) var lines: [TrafficLine] = []
    /// 0 clear … 10 for the main roads around (AreaTraffic.score), as Yandex scores its traffic.
    private(set) var score: Int?
    /// Closures, accidents and road works around; refreshed every 10 minutes at most (its own monthly cap).
    private(set) var incidents: [TrafficIncident] = []
    @ObservationIgnored private var incidentsFetched: (area: TrafficArea, at: Date)?
    /// Shown under the search bar when the layer cannot load ("Bu ayın trafik sorgu sınırı doldu.").
    private(set) var notice: String?
    /// The area of the answer on screen and when it was asked for.
    @ObservationIgnored private var fetched: (area: TrafficArea, at: Date)?

    /// How often the layer asks again while the map rests: two minutes, the pace at which Yandex rebuilds its
    /// picture. At five, a jam that had cleared could stay on the map for ten.
    static let refreshInterval: Duration = .seconds(120)
    /// Seconds an answer is reused for a view it covers: the same two minutes.
    private static let reuseTime: TimeInterval = 120
    /// Seconds after which lines that cannot be renewed are removed: nothing on screen tells old traffic from
    /// live.
    private static let staleTime: TimeInterval = 360

    func refresh(_ visible: TrafficArea, using provider: any TrafficProvider) async {
        // Zoomed out further than 0.8°: HERE answers at most 1° a side, which leaves no margin around the
        // screen, and the answer gets too big for a phone; keep what is drawn.
        guard visible.span <= 0.8 else { return }
        if let fetched, fetched.area.contains(visible), Date.now.timeIntervalSince(fetched.at) < Self.reuseTime { return }
        let area = visible.expanded(by: 0.2)
        // An answer is dated from its request: the periodic refresh wakes `refreshInterval` after the answer
        // came, and must find it due.
        let asked = Date.now
        do {
            let segments = try await provider.flow(in: area)
            lines = AreaTraffic.sections(segments).map { TrafficLine($0) }
            score = AreaTraffic.score(segments)
            fetched = (area, asked)
            notice = nil
            // Road events change slowly: again only for a new area or after 10 minutes.
            let due = incidentsFetched.map { !$0.area.contains(visible) || Date.now.timeIntervalSince($0.at) >= 600 } ?? true
            if due, let found = try? await provider.incidents(in: area) {
                incidents = found
                incidentsFetched = (area, .now)
            }
        } catch let error as TrafficError where error == .budgetExhausted {
            lines = []
            score = nil
            incidents = []
            notice = error.localizedDescription
        } catch {
            // Offline or a server hiccup: the next round tries again, and until then the lines stay, unless they
            // are stale by now.
            if let fetched, Date.now.timeIntervalSince(fetched.at) > Self.staleTime {
                lines = []
                score = nil
                self.fetched = nil
            }
        }
    }
}

extension TrafficLine {
    /// `coordinates` replaces the section's own line (the part still ahead while guiding).
    init(_ section: TrafficSection, coordinates: [CLLocationCoordinate2D]? = nil) {
        let level: TrafficLine.Level = switch section.level {
        case .free: .free
        case .slow: .slow
        case .heavy: .heavy
        case .stopped: .stopped
        }
        self.init(level: level, coordinates: coordinates ?? section.coordinates, isMajor: section.isMajor)
    }
}

extension MapIncident {
    init(_ incident: TrafficIncident) {
        let kind: MapIncident.Kind = switch incident.kind {
        case .closure: .closure
        case .accident: .accident
        case .roadworks: .roadworks
        }
        self.init(kind: kind, coordinates: incident.points)
    }
}
