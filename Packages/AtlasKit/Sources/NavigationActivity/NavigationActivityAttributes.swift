import ActivityKit
import Foundation

/// The Live Activity while guiding: lock screen, Dynamic Island and, on iOS 26, the CarPlay Dashboard
/// (no CarPlay navigation entitlement needed for that). Shared by the app and the widget extension, which
/// links only this small module.
public struct NavigationActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        /// SF Symbol of the next maneuver.
        public var symbol: String
        /// "300 m", "1,2 km".
        public var distance: String
        /// "Sola dön".
        public var instruction: String
        public var road: String?
        public var arrival: Date
        /// Arrival includes live traffic (HERE) rather than free-flow time.
        public var arrivalWithTraffic: Bool

        public init(symbol: String, distance: String, instruction: String, road: String?, arrival: Date, arrivalWithTraffic: Bool) {
            self.symbol = symbol
            self.distance = distance
            self.instruction = instruction
            self.road = road
            self.arrival = arrival
            self.arrivalWithTraffic = arrivalWithTraffic
        }
    }

    public var destination: String

    public init(destination: String) {
        self.destination = destination
    }
}
