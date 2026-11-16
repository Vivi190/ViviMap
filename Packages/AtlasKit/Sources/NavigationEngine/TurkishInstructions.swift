@preconcurrency import FerrostarCoreFFI
import Foundation

/// Turkish maneuver text built from maneuver type/modifier, because Valhalla's tr-TR narration is
/// unusable ("Kübra Sokak caddesinde", a bare "sol.", "sol yönelin" — docs/research §11b).
///
/// The register is the formal plural imperative ("dönün", "çıkın") that Turkish navigation voices use.
/// Sentences avoid case suffixes on road names ("Ankara Caddesi'ne") so they are always grammatical:
/// the road name follows after a comma.
public enum TurkishInstructions {
    /// Short imperative for the banner: "Sola dönün", "Döner kavşakta ikinci çıkıştan çıkın".
    /// - Parameters:
    ///   - roundaboutExitNumber: the exit to take, counted from the entry, when the route gives it.
    ///   - leavingFerry: a `notification` is a change of travel mode; true for the one that ends a ferry leg.
    public static func action(
        type: ManeuverType?, modifier: ManeuverModifier?, roundaboutExitDegrees: UInt16? = nil,
        roundaboutExitNumber: UInt8? = nil, leavingFerry: Bool = false
    ) -> String? {
        guard let type else { return nil }
        switch type {
        case .depart:
            return "Rotaya başlayın"
        case .arrive:
            switch modifier {
            case .left, .slightLeft, .sharpLeft: return "Hedefiniz solda"
            case .right, .slightRight, .sharpRight: return "Hedefiniz sağda"
            default: return "Hedef"
            }
        case .turn, .endOfRoad:
            let turn = turnPhrase(modifier)
            return type == .endOfRoad ? "Yolun sonunda \(turn.lowercasedFirst)" : turn
        case .continue:
            // Valhalla sends "turn left to stay on X", and every U-turn, as `continue`: a turn like any other.
            return changesDirection(modifier) ? turnPhrase(modifier) : keepPhrase(modifier)
        case .newName:
            return keepPhrase(modifier)
        case .notification:
            return leavingFerry ? "Feribottan inin" : "Feribota binin"
        case .merge:
            return side(modifier).map { "\($0)dan yola katılın" } ?? "Yola katılın"
        case .onRamp:
            return side(modifier).map { "\($0)daki bağlantı yoluna girin" } ?? "Bağlantı yoluna girin"
        case .offRamp:
            return side(modifier).map { "\($0)daki çıkıştan çıkın" } ?? "Çıkıştan çıkın"
        case .fork:
            return side(modifier).map { "Yol ayrımında \($0.lowercased(with: tr))dan devam edin" } ?? "Yol ayrımında devam edin"
        case .roundabout, .rotary, .roundaboutTurn:
            return roundaboutPhrase(roundaboutExitDegrees, modifier: modifier, exitNumber: roundaboutExitNumber)
        case .exitRoundabout, .exitRotary:
            return "Döner kavşaktan çıkın"
        }
    }

    /// Spoken sentence: "300 metre sonra sola dönün, Ankara Caddesi."; distance nil means "now".
    /// `then` chains a maneuver that follows right after: "…, ardından sağa dönün."
    public static func spoken(action: String, distance: Double?, road: String?, then: String? = nil) -> String {
        var sentence = distance.map { "\(distancePhrase($0)) sonra \(action.lowercasedFirst)" } ?? action
        if let road, !road.isEmpty { sentence += ", \(road)" }
        if let then { sentence += ", ardından \(then.lowercasedFirst)" }
        return sentence + "."
    }

    /// Approaching the destination: "Hedefe 400 metre kaldı.", with its side when the route knows it
    /// ("Hedefe 120 metre kaldı, solda."). Distance nil is the sentence at the destination itself
    /// ("Hedefiniz solda."); "… sonra hedef" would not be a sentence, so arriving has its own form.
    public static func arrival(distance: Double?, modifier: ManeuverModifier?) -> String {
        guard let distance else { return (action(type: .arrive, modifier: modifier) ?? "Hedef") + "." }
        let place = side(modifier).map { $0 == "Sol" ? ", solda" : ", sağda" } ?? ""
        return "Hedefe \(distancePhrase(distance)) kaldı\(place)."
    }

    /// A road event ahead, from its kind: "2 kilometre sonra yol çalışması.", "800 metre sonra kaza.",
    /// "1 kilometre sonra yol kapalı." The traffic provider's own Turkish description is not read out: it is
    /// no sentence ("Arasında Begonya Sokak ve Aydınlı Yolu Caddesi - Kapalı arasında").
    static func roadEvent(_ kind: RoadEvent.Kind, distance: Double) -> String {
        let words = switch kind {
        case .closure: "yol kapalı"
        case .accident: "kaza"
        case .roadworks: "yol çalışması"
        }
        return "\(distancePhrase(distance)) sonra \(words)."
    }

    /// The maneuver after the next one, worth announcing together when it comes within `window` metres
    /// (dense Istanbul streets). Road-name changes and "keep straight" are noise, so they return nil, and so
    /// is a roundabout exit: Valhalla follows every roundabout entry with one, and "Döner kavşakta ikinci çıkıştan
    /// çıkın" already says which exit to take.
    public static func followUp(
        type: ManeuverType?, modifier: ManeuverModifier?, roundaboutExitDegrees: UInt16?,
        roundaboutExitNumber: UInt8? = nil, after distance: Double, window: Double = 150
    ) -> String? {
        guard distance <= window, let type else { return nil }
        switch type {
        case .newName, .notification, .depart, .exitRoundabout, .exitRotary: return nil
        case .continue where !changesDirection(modifier): return nil
        case .turn where modifier == .straight || modifier == nil: return nil
        // "Hedef" alone is no clause after "ardından": the future form says what follows the maneuver.
        case .arrive where side(modifier) == nil: return "Hedefinize ulaşacaksınız"
        default:
            return action(
                type: type, modifier: modifier, roundaboutExitDegrees: roundaboutExitDegrees,
                roundaboutExitNumber: roundaboutExitNumber
            )
        }
    }

    /// Nothing to do at the maneuver, so nothing to say: a road that only changes its name, and going
    /// straight on (a ferry that lies straight ahead included). The banner still shows them.
    static func isSilent(type: ManeuverType?, modifier: ManeuverModifier?) -> Bool {
        guard let type else { return true }
        switch type {
        case .newName, .depart: return true
        case .turn, .continue, .notification: return modifier == nil || modifier == .straight
        default: return false
        }
    }

    /// A turn at a junction: `turn`, `end of road`, and `continue` with a real change of direction. Ramps,
    /// forks and roundabouts are not.
    static func isTurn(type: ManeuverType?, modifier: ManeuverModifier?) -> Bool {
        guard let type else { return false }
        switch type {
        case .turn, .endOfRoad: return true
        case .continue: return changesDirection(modifier)
        default: return false
        }
    }

    /// "50 metre", "300 metre", "1 kilometre", "1,2 kilometre" — rounded the way drivers read signs.
    public static func distancePhrase(_ meters: Double) -> String {
        if meters >= 950 {
            let km = (meters / 100).rounded() / 10
            // A whole number goes without its decimal: "1,0 kilometre" is read out as "bir virgül sıfır".
            let digits: Int = (km < 10 && km != km.rounded()) ? 1 : 0
            let text = km.formatted(.number.precision(.fractionLength(digits)).locale(Locale(identifier: "tr_TR")))
            return "\(text) kilometre"
        }
        let step: Double = meters > 200 ? 50 : 10
        return "\(Int(max(step, (meters / step).rounded() * step))) metre"
    }

    private static let tr = Locale(identifier: "tr_TR")

    private static func turnPhrase(_ modifier: ManeuverModifier?) -> String {
        switch modifier {
        case .left: "Sola dönün"
        case .right: "Sağa dönün"
        case .slightLeft: "Hafif sola dönün"
        case .slightRight: "Hafif sağa dönün"
        case .sharpLeft: "Keskin sola dönün"
        case .sharpRight: "Keskin sağa dönün"
        case .uTurn: "Geri dönün"
        case .straight, nil: "Düz devam edin"
        }
    }

    private static func keepPhrase(_ modifier: ManeuverModifier?) -> String {
        switch modifier {
        case .left, .sharpLeft: "Soldan devam edin"
        case .right, .sharpRight: "Sağdan devam edin"
        case .slightLeft: "Hafif soldan devam edin"
        case .slightRight: "Hafif sağdan devam edin"
        case .uTurn: "Geri dönün"
        case .straight, nil: "Düz devam edin"
        }
    }

    /// Left, right, sharp or back: the car leaves its line, unlike a slight bend or straight on.
    private static func changesDirection(_ modifier: ManeuverModifier?) -> Bool {
        switch modifier {
        case .left, .right, .sharpLeft, .sharpRight, .uTurn: true
        case .slightLeft, .slightRight, .straight, nil: false
        }
    }

    /// A turn at a traffic light, said the way drivers (and Yandex) say it: "Işıklarda sağa dönün".
    public static func atLights(_ action: String) -> String {
        "Işıklarda \(action.lowercasedFirst)"
    }

    /// "Sol" / "Sağ" for side-dependent phrases, nil when the side does not matter.
    static func side(_ modifier: ManeuverModifier?) -> String? {
        switch modifier {
        case .left, .slightLeft, .sharpLeft: "Sol"
        case .right, .slightRight, .sharpRight: "Sağ"
        default: nil
        }
    }

    private static let ordinals = [
        "birinci", "ikinci", "üçüncü", "dördüncü", "beşinci", "altıncı", "yedinci", "sekizinci", "dokuzuncu", "onuncu",
    ]

    private static func roundaboutPhrase(_ degrees: UInt16?, modifier: ManeuverModifier?, exitNumber: UInt8?) -> String {
        // Counting exits needs no judgement of angles, so the number leads whenever the route has it.
        if let exitNumber, exitNumber >= 1, Int(exitNumber) <= ordinals.count {
            return "Döner kavşakta \(ordinals[Int(exitNumber) - 1]) çıkıştan çıkın"
        }
        guard let degrees else {
            return side(modifier).map { "Döner kavşaktan \($0 == "Sol" ? "sola" : "sağa") çıkın" } ?? "Döner kavşaktan çıkın"
        }
        switch RoundaboutExit(degrees: degrees) {
        case .right: return "Döner kavşaktan sağa çıkın"
        case .straight: return "Döner kavşaktan düz devam edin"
        case .left: return "Döner kavşaktan sola çıkın"
        case .back: return "Döner kavşaktan geri dönün"
        }
    }
}

/// Where a roundabout is left, from the angle driven round it (right-hand traffic): about 90° is the first
/// quarter, to the right; 180° straight across; 270° to the left. A U-turn is 0°, which the data gives on
/// either side of the 0/360 wrap (7° as well as 350°).
enum RoundaboutExit {
    case right, straight, left, back

    init(degrees: UInt16) {
        switch degrees {
        case 45 ..< 135: self = .right
        case 135 ..< 225: self = .straight
        case 225 ..< 315: self = .left
        default: self = .back
        }
    }
}

extension String {
    /// "Sola dönün" → "sola dönün" mid-sentence, but "U dönüşü" stays as is.
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
