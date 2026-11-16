@preconcurrency import FerrostarCoreFFI
import Foundation

/// One line of a route's list of turns: after `distance` metres, "Sağa dönün" onto "Ankara Caddesi".
public struct RouteDirection: Identifiable, Equatable, Sendable {
    public let id: Int
    /// SF Symbol of the maneuver's arrow, the one the turn panel shows for it.
    public let symbol: String
    /// The maneuver in guidance's words.
    public let action: String
    /// The road the maneuver leads onto, when it has a name.
    public let road: String?
    /// Metres driven before the maneuver, from the one before it (the first: from the start).
    public let distance: Double
}

/// A route's turns before the drive, read off the same steps guidance follows and in the same words.
public enum RouteDirections {
    public static func list(for route: Route) -> [RouteDirection] {
        list(for: route.steps)
    }

    /// A step that ends in nothing to do (the road only changes its name, or goes straight on) gives no line:
    /// its length is added to the next one's. A ferry does get a line, also when it lies straight ahead.
    static func list(for steps: [RouteStep]) -> [RouteDirection] {
        var lines: [RouteDirection] = []
        var driven = 0.0
        // A step's banner is the maneuver it ends with. The last step ends at the destination, which the step
        // before it has announced.
        for (index, step) in steps.dropLast().enumerated() {
            driven += step.distance
            let following = steps[index + 1]
            guard let content = step.visualInstructions.first?.primaryContent,
                  content.maneuverType == .notification
                  || !TurkishInstructions.isSilent(type: content.maneuverType, modifier: content.maneuverModifier),
                  let action = TurkishInstructions.action(
                      type: content.maneuverType,
                      modifier: content.maneuverModifier,
                      roundaboutExitDegrees: content.roundaboutExitDegrees,
                      roundaboutExitNumber: following.roundaboutExitNumber,
                      leavingFerry: NavigationSession.isOnFerry(steps[index...].map { $0.visualInstructions.first?.primaryContent.maneuverType })
                  )
            else { continue }
            let road = content.maneuverType == .arrive
                ? nil
                : NavigationSession.roadName(banner: content.text, nextInstruction: following.instruction)
            lines.append(RouteDirection(
                id: index,
                symbol: ManeuverSymbols.symbol(
                    type: content.maneuverType, modifier: content.maneuverModifier, roundaboutExitDegrees: content.roundaboutExitDegrees
                ),
                action: action,
                road: road,
                distance: driven
            ))
            driven = 0
        }
        return lines
    }
}
