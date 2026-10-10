import AppKit

/// App lifecycle hooks: start services on launch, clean up blocking on quit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppServices.isRunningTests else { return }
        let services = AppServices.shared
        Notifier.configure()
        services.catalog.reload()
        services.domainBlocker.refreshHelperStatus()
        services.session.recoverAfterLaunch()

        if services.settings.hasCompletedOnboarding {
            Notifier.requestAuthorization()
        } else {
            // The guide asks for notifications itself, after explaining why.
            OnboardingWindow.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppServices.shared.session.prepareForTermination()
    }

    /// Menu bar app: closing the main window must not quit.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
