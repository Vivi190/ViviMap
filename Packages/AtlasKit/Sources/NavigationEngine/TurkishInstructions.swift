@preconcurrency import FerrostarCoreFFI
import Foundation

/// Turkish maneuver text built from maneuver type/modifier, because Valhalla's tr-TR narration is
/// unusable ("Kübra Sokak caddesinde", a bare "sol.", "sol yönelin" — docs/research §11b).
///
/// Sentences avoid case suffixes on road names ("Ankara Caddesi'ne") so they are always grammatical:
/// the road name follows after a comma.
public enum TurkishInstructions {
    /// Short imperative for the banner: "Sola dön", "Göbekten sağa çık".
    public static func action(type: ManeuverType?, modifier: ManeuverModifier?, roundaboutExitDegrees: UInt16? = nil) -> String? {
        guard let type else { return nil }
        switch type {
        case .depart:
            return "Rotaya başla"
        case .arrive:
            switch modifier {
            case .left, .slightLeft, .sharpLeft: return "Hedef solunda"
            case .right, .slightRight, .sharpRight: return "Hedef sağında"
            default: return "Hedefe ulaştın"
            }
        case .turn, .endOfRoad:
            let turn = turnPhrase(modifier)
            return type == .endOfRoad ? "Yolun sonunda \(turn.lowercasedFirst)" : turn
        case .continue, .newName, .notification:
            return keepPhrase(modifier)
        case .merge:
            return side(modifier).map { "\($0)dan yola katıl" } ?? "Yola katıl"
        case .onRamp:
            return side(modifier).map { "\($0)daki bağlantı yoluna gir" } ?? "Bağlantı yoluna gir"
        case .offRamp:
            return side(modifier).map { "\($0)daki çıkışa gir" } ?? "Çıkışa gir"
        case .fork:
            return side(modifier).map { "Yol ayrımında \($0.lowercased(with: tr))dan devam et" } ?? "Yol ayrımında devam et"
        case .roundabout, .rotary, .roundaboutTurn:
            return roundaboutPhrase(roundaboutExitDegrees, modifier: modifier)
        case .exitRoundabout, .exitRotary:
            return "Göbekten çık"
        }
    }

    /// Spoken sentence: "300 metre sonra sola dön, Ankara Caddesi."; distance nil means "now".
    /// `then` chains a maneuver that follows right after: "…, ardından sağa dön."
    public static func spoken(action: String, distance: Double?, road: String?, then: String? = nil) -> String {
        var sentence = distance.map { "\(distancePhrase($0)) sonra \(action.lowercasedFirst)" } ?? action
        if let road, !road.isEmpty { sentence += ", \(road)" }
        if let then { sentence += ", ardından \(then.lowercasedFirst)" }
        return sentence + "."
    }

    /// The maneuver after the next one, worth announcing together when it comes within `window` metres
    /// (dense Istanbul streets). Road-name changes and "keep straight" are noise, so they return nil.
    public static func followUp(
        type: ManeuverType?, modifier: ManeuverModifier?, roundaboutExitDegrees: UInt16?,
        after distance: Double, window: Double = 150
    ) -> String? {
        guard distance <= window, let type else { return nil }
        switch type {
        case .continue, .newName, .notification, .depart: return nil
        case .turn where modifier == .straight || modifier == nil: return nil
        default: return action(type: type, modifier: modifier, roundaboutExitDegrees: roundaboutExitDegrees)
        }
    }

    /// "50 metre", "300 metre", "1,2 kilometre" — rounded the way drivers read signs.
    public static func distancePhrase(_ meters: Double) -> String {
        if meters >= 950 {
            let km = (meters / 100).rounded() / 10
            let text = km.formatted(.number.precision(.fractionLength(km < 10 ? 1 : 0)).locale(Locale(identifier: "tr_TR")))
            return "\(text) kilometre"
        }
        let step: Double = meters > 200 ? 50 : 10
        return "\(Int(max(step, (meters / step).rounded() * step))) metre"
    }

    private static let tr = Locale(identifier: "tr_TR")

    private static func turnPhrase(_ modifier: ManeuverModifier?) -> String {
        switch modifier {
        case .left: "Sola dön"
        case .right: "Sağa dön"
        case .slightLeft: "Hafif sola dön"
        case .slightRight: "Hafif sağa dön"
        case .sharpLeft: "Keskin sola dön"
        case .sharpRight: "Keskin sağa dön"
        case .uTurn: "U dönüşü yap"
        case .straight, nil: "Düz devam et"
        }
    }

    private static func keepPhrase(_ modifier: ManeuverModifier?) -> String {
        switch modifier {
        case .left, .sharpLeft: "Soldan devam et"
        case .right, .sharpRight: "Sağdan devam et"
        case .slightLeft: "Hafif soldan devam et"
        case .slightRight: "Hafif sağdan devam et"
        case .uTurn: "U dönüşü yap"
        case .straight, nil: "Düz devam et"
        }
    }

    /// "Sol" / "Sağ" for side-dependent phrases, nil when the side does not matter.
    private static func side(_ modifier: ManeuverModifier?) -> String? {
        switch modifier {
        case .left, .slightLeft, .sharpLeft: "Sol"
        case .right, .slightRight, .sharpRight: "Sağ"
        default: nil
        }
    }

    private static func roundaboutPhrase(_ degrees: UInt16?, modifier: ManeuverModifier?) -> String {
        // Exit bearing relative to entry: ~90° right, ~180° straight, ~270° left (right-hand traffic).
        guard let degrees else {
            return side(modifier).map { "Göbekten \($0 == "Sol" ? "sola" : "sağa") çık" } ?? "Göbekten çık"
        }
        switch degrees {
        case ..<135: return "Göbekten sağa çık"
        case 135 ..< 225: return "Göbekten düz çık"
        case 225 ..< 315: return "Göbekten sola çık"
        default: return "Göbekten geri dön"
        }
    }
}

extension String {
    /// "Sola dön" → "sola dön" mid-sentence, but "U dönüşü" stays as is.
    var lowercasedFirst: String {
        guard let first, count > 1, self[index(after: startIndex)].isLowercase else { return self }
        return first.lowercased(with: Locale(identifier: "tr_TR")) + dropFirst()
    }
}

private extension Character {
    func lowercased(with locale: Locale) -> String {
        String(self).lowercased(with: locale)
    }
}
