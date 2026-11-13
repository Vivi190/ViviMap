@preconcurrency import FerrostarCoreFFI

/// SF Symbols for maneuvers and lanes (right-hand traffic).
enum ManeuverSymbols {
    static func symbol(type: ManeuverType?, modifier: ManeuverModifier?) -> String {
        switch type {
        case .arrive: return "flag.checkered"
        case .depart: return "location.north.fill"
        case .roundabout, .rotary, .roundaboutTurn, .exitRoundabout, .exitRotary:
            return "arrow.triangle.turn.up.right.circle"
        case .merge: return "arrow.triangle.merge"
        case .fork: return modifier.map(isLeft) == true ? "arrow.up.left" : "arrow.up.right"
        default: break
        }
        switch modifier {
        case .left, .sharpLeft: return "arrow.turn.up.left"
        case .right, .sharpRight: return "arrow.turn.up.right"
        case .slightLeft: return "arrow.up.left"
        case .slightRight: return "arrow.up.right"
        case .uTurn: return "arrow.uturn.left"
        case .straight, nil: return "arrow.up"
        }
    }

    /// OSRM lane directions: "left", "slight left", "straight", "right", "uturn" …
    static func lane(_ direction: String?) -> String {
        switch direction {
        case "left", "sharp left": "arrow.turn.up.left"
        case "slight left": "arrow.up.left"
        case "right", "sharp right": "arrow.turn.up.right"
        case "slight right": "arrow.up.right"
        case "uturn": "arrow.uturn.left"
        default: "arrow.up"
        }
    }

    private static func isLeft(_ modifier: ManeuverModifier) -> Bool {
        modifier == .left || modifier == .slightLeft || modifier == .sharpLeft
    }
}
