import AppKit
import CoreServices

/// Checks and requests the macOS Automation permission `BrowserGuard` needs to read and close tabs.
enum BrowserPermissions {
    enum Status: Equatable {
        case allowed
        case denied
        case notDetermined
        /// macOS can only answer while the browser is running.
        case notRunning
        case unknown
    }

    /// Supported browsers that are installed on this Mac, sorted by name.
    @MainActor
    static func installedBrowsers() -> [AppInfo] {
        BrowserGuard.supportedBrowsers.compactMap { id, name in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            return AppInfo(bundleID: id, name: name, url: url)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Current permission state without prompting.
    static func status(of bundleID: String) async -> Status {
        await Task.detached { determine(bundleID: bundleID, askUser: false) }.value
    }

    /// Shows the macOS "Pomodoro wants to control …" prompt (launching the browser in the background first
    /// if needed) and returns the user's answer.
    @MainActor
    static func request(_ browser: AppInfo) async -> Status {
        if !isRunning(browser.bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: browser.url, configuration: configuration, completionHandler: nil)
            for _ in 0..<40 where !isRunning(browser.bundleID) {
                try? await Task.sleep(for: .milliseconds(250))
            }
            // Give the browser a moment to start answering Apple Events.
            try? await Task.sleep(for: .seconds(1))
        }
        let id = browser.bundleID
        return await Task.detached { determine(bundleID: id, askUser: true) }.value
    }

    @MainActor
    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    private static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Blocks while the consent prompt is shown, so it must never run on the main thread.
    private static func determine(bundleID: String, askUser: Bool) -> Status {
        var target = AEAddressDesc()
        let bytes = Array(bundleID.utf8)
        let created = bytes.withUnsafeBytes {
            AECreateDesc(DescType(typeApplicationBundleID), $0.baseAddress, $0.count, &target)
        }
        guard created == noErr else { return .unknown }
        defer { AEDisposeDesc(&target) }

        let result = AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), askUser)
        switch Int(result) {
        case Int(noErr): return .allowed
        case Int(errAEEventNotPermitted): return .denied
        case Int(errAEEventWouldRequireUserConsent): return .notDetermined
        case Int(procNotFound): return .notRunning
        default: return .unknown
        }
    }
}
