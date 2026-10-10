import AppKit
import SwiftUI

/// Hosts `OnboardingView` in its own window. Shown on first launch and from Settings.
@MainActor
enum OnboardingWindow {
    private static var window: NSWindow?
    /// Set while restarting to change the language, so the guide opens again afterwards.
    static var isRelaunching = false
    private static let closeObserver = CloseObserver()

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let services = AppServices.shared
        let root = OnboardingView(onFinish: { OnboardingWindow.window?.close() })
            .environment(services.session)
            .environment(services.catalog)
            .environment(services.settings)
            .environment(services.domainBlocker)
            .modelContainer(services.container)

        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = String(localized: "Welcome to Pomodoro")
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = closeObserver
        window.center()
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Closing the window (finished or not) counts as done; the guide stays available in Settings.
    private final class CloseObserver: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) {
            MainActor.assumeIsolated {
                if !OnboardingWindow.isRelaunching {
                    AppServices.shared.settings.hasCompletedOnboarding = true
                }
                OnboardingWindow.window = nil
            }
        }
    }
}
