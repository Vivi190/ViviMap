import AppIntents
import Observation
import SearchEngine
import SwiftUI

/// What Siri or the Shortcuts app asked for. HomeScreen takes it once it can serve it: on screen and with a
/// location fix (a cold start from Siri has neither for a moment).
@MainActor
@Observable
final class ShortcutInbox {
    static let shared = ShortcutInbox()
    var destination: SearchController.Slot?
}

/// "Atlas ile eve git": opens the app on the route card to the saved home, like the search sheet's shortcut.
struct GoHomeIntent: AppIntent {
    static var title: LocalizedStringResource { "Eve git" }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        ShortcutInbox.shared.destination = .home
        return .result()
    }
}

struct GoToWorkIntent: AppIntent {
    static var title: LocalizedStringResource { "İşe git" }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        ShortcutInbox.shared.destination = .work
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

/// Hands a pending request to HomeScreen as soon as there is a fix. A view of its own so HomeScreen's body
/// does not grow by more modifiers.
struct ShortcutListener: View {
    let inbox: ShortcutInbox
    let hasFix: Bool
    let open: (SearchController.Slot) -> Void

    private struct Request: Equatable {
        let slot: SearchController.Slot?
        let hasFix: Bool
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: Request(slot: inbox.destination, hasFix: hasFix), initial: true) { _, request in
                guard let slot = request.slot, request.hasFix else { return }
                inbox.destination = nil
                open(slot)
            }
    }
}
