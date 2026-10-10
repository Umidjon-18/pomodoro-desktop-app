import SwiftUI

/// Menu bar title: "🍅" when idle, "🍅 24:13" while a session runs.
@MainActor
struct MenuBarLabel: View {
    @Environment(SessionManager.self) private var session

    var body: some View {
        Text(session.menuBarTitle)
            .monospacedDigit()
    }
}
