import AVFoundation

/// Speaks Turkish prompts with the system voice, ducking music/podcasts while speaking and releasing the
/// audio session afterwards so other apps return to full volume.
@MainActor
public final class VoiceGuide: NSObject {
    public var isMuted = false
    /// Every prompt guidance produces, spoken or muted (simulated-drive tests read the sequence).
    public var onPrompt: (@MainActor (String) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "tr-TR")

    override public init() {
        super.init()
        synthesizer.delegate = self
    }

    public func speak(_ text: String) {
        guard !text.isEmpty else { return }
        onPrompt?(text)
        guard !isMuted else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

extension VoiceGuide: AVSpeechSynthesizerDelegate {
    // Called on an arbitrary queue; only touches the shared audio session, which is thread-safe.
    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        guard !synthesizer.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
