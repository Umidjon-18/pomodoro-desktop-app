import SwiftUI
import SwiftData

@main
struct PomodoroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let services = AppServices.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(services.session)
                .environment(services.catalog)
                .environment(services.settings)
                .environment(services.domainBlocker)
                .modelContainer(services.container)
        } label: {
            MenuBarLabel()
                .environment(services.session)
        }
        .menuBarExtraStyle(.window)

        Window("Pomodoro", id: MainWindowView.windowID) {
            MainWindowView()
                .environment(services.session)
                .environment(services.catalog)
                .environment(services.settings)
                .environment(services.domainBlocker)
                .modelContainer(services.container)
                .frame(minWidth: 760, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 620)
    }
}
