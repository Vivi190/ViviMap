import AVFoundation

/// Speaks Turkish prompts with the system voice, ducking music/podcasts while speaking and releasing the
/// audio session afterwards so other apps return to full volume.
@MainActor
public final class VoiceGuide: NSObject {
    /// Muting also ends the sentence in progress: it is what the driver wanted to stop.
    public var isMuted = false {
        didSet {
            if isMuted { synthesizer.stopSpeaking(at: .immediate) }
        }
    }

    /// Every prompt guidance produces, spoken or muted (simulated-drive tests read the sequence).
    public var onPrompt: (@MainActor (String) -> Void)?
    /// A sentence is being spoken or waits in the queue.
    public var isSpeaking: Bool { synthesizer.isSpeaking }

    private let synthesizer = AVSpeechSynthesizer()
    private let voice = VoiceGuide.bestTurkishVoice()

    /// The best Turkish voice on the phone. `AVSpeechSynthesisVoice(language:)` gives the compact default even
    /// when an enhanced or premium one is installed (Settings → Accessibility → Spoken Content → Voices →
    /// Turkish); novelty and personal voices are left out. Shown in the map settings too.
    public static func bestTurkishVoice() -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "tr-TR" && !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice) }
            .max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: "tr-TR")
    }

    override public init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks after whatever is already being said or queued.
    public func speak(_ text: String) {
        guard !text.isEmpty else { return }
        onPrompt?(text)
        guard !isMuted else { return }
        enqueue(text)
    }

    /// The prompt at the turn itself, which is worth nothing a few seconds late: the sentence in progress is
    /// cut and the queue emptied before it is spoken. Cut at once, not at the next word: a stop that takes
    /// effect later could take the new sentence with it.
    public func speakNow(_ text: String) {
        guard !text.isEmpty else { return }
        onPrompt?(text)
        guard !isMuted else { return }
        synthesizer.stopSpeaking(at: .immediate)
        enqueue(text)
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func enqueue(_ text: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        synthesizer.speak(utterance)
    }
}

extension VoiceGuide: AVSpeechSynthesizerDelegate {
    // Called on an arbitrary queue; only touches the shared audio session, which is thread-safe.
    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        guard !synthesizer.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // A sentence that was stopped (stop(), muting, the prompt at the turn) ends here, not in didFinish:
    // without this the session stayed active and other apps stayed ducked until the next prompt.
    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
        guard !synthesizer.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
