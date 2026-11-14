import AppIntents
import Observation
import SearchEngine
import SwiftUI

/// What Siri or the Shortcuts app asked for. HomeScreen takes it once it can serve it: on screen and, to plan a
/// route, with a location fix (a cold start from Siri has none for a moment).
@MainActor
@Observable
final class ShortcutInbox {
    static let shared = ShortcutInbox()
    private(set) var destination: SearchController.Slot?
    private(set) var requestedAt = Date.distantPast

    func request(_ slot: SearchController.Slot) {
        requestedAt = .now
        destination = slot
    }

    func clear() { destination = nil }
}

/// "Atlas ile eve git": opens the app on the route card to the saved home, like the search sheet's shortcut.
struct GoHomeIntent: AppIntent {
    static var title: LocalizedStringResource { "Eve git" }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        ShortcutInbox.shared.request(.home)
        return .result()
    }
}

struct GoToWorkIntent: AppIntent {
    static var title: LocalizedStringResource { "İşe git" }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        ShortcutInbox.shared.request(.work)
        return .result()
    }
}

/// Offered to Siri and the Shortcuts app without any setup.
struct AtlasShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GoHomeIntent(),
            phrases: ["\(.applicationName) ile eve git", "\(.applicationName) eve git"],
            shortTitle: "Eve git",
            systemImageName: "house.fill"
        )
        AppShortcut(
            intent: GoToWorkIntent(),
            phrases: ["\(.applicationName) ile işe git", "\(.applicationName) işe git"],
            shortTitle: "İşe git",
            systemImageName: "briefcase.fill"
        )
    }
}

/// Hands a pending request to HomeScreen when it arrives and again when the first fix does. A view of its own
/// so HomeScreen's body does not grow by more modifiers.
struct ShortcutListener: View {
    let inbox: ShortcutInbox
    let hasFix: Bool
    /// Serves the request now, or returns false to keep it until a fix arrives.
    let open: (SearchController.Slot) -> Bool

    private struct Request: Equatable {
        let slot: SearchController.Slot?
        let hasFix: Bool
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: Request(slot: inbox.destination, hasFix: hasFix), initial: true) { _, request in
                guard let slot = request.slot else { return }
                // Waited over a minute (location off, no fix): no longer what the driver is asking for.
                guard Date.now.timeIntervalSince(inbox.requestedAt) < 60 else { return inbox.clear() }
                if open(slot) { inbox.clear() }
            }
    }
}
