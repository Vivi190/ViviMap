import Foundation
import Network
import Observation

/// Whether the phone has a usable connection right now (NWPathMonitor), so the map can switch to the
/// shipped Istanbul tiles and the screen can say it is offline. One instance lives as long as the app.
@MainActor
@Observable
public final class Connectivity {
    public private(set) var isOnline = true

    @ObservationIgnored private let monitor = NWPathMonitor()

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                if self?.isOnline != online { self?.isOnline = online }
            }
        }
        monitor.start(queue: DispatchQueue(label: "atlas.connectivity"))
    }
}
