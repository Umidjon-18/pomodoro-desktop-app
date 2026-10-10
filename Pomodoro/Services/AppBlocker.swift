import AppKit

/// Keeps non-allowed apps hidden while a focus session runs.
///
/// Offending apps are hidden, focus is handed back to the last allowed app, and a `BlockPanel` offers to
/// allow the app for this session or permanently. Choosing "Stay focused" quits the app.
@MainActor
final class AppBlocker {
    private static let ownBundleID = Bundle.main.bundleIdentifier ?? "com.local.Pomodoro"

    /// System processes that must never be hidden, regardless of the user's allowlist.
    static let essentialBundleIDs: Set<String> = [
        ownBundleID,
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.loginwindow",
        "com.apple.SecurityAgent",
        "com.apple.coreservices.uiagent",
        "com.apple.UserNotificationCenter",
        "com.apple.screencaptureui",
        "com.apple.ScreenSaver.Engine",
        "com.apple.Siri",
        "com.apple.WindowManager",
        "com.apple.PIPAgent",
    ]

    /// Returns true when the app may be used during the current session. Set by `SessionManager`.
    var isAllowed: (String) -> Bool = { _ in true }
    /// Called from the block panel's "Allow this session" button.
    var onAllowForSession: (AppInfo) -> Void = { _ in }
    /// Called from the block panel's "Always allow" button.
    var onAlwaysAllow: (AppInfo) -> Void = { _ in }

    private(set) var isActive = false

    private var observers: [NSObjectProtocol] = []
    private var pollTimer: Timer?
    private var lastAllowedApp: NSRunningApplication?
    private var panel: BlockPanel?
    private var lastPanelBundleID: String?
    private var lastPanelDate = Date.distantPast
    /// Apps the user chose to quit, with the time of the request. They are still hidden while quitting,
    /// but the panel is not shown again (an unsaved-changes prompt can bring them forward).
    private var quitRequests: [String: Date] = [:]

    private static let panelDebounce: TimeInterval = 1.5
    private static let quitGracePeriod: TimeInterval = 15

    init() {}

    // MARK: - Public

    func activate() {
        guard !isActive else {
            reevaluate()
            return
        }
        isActive = true
        // Unit tests must never hide the developer's apps.
        guard !AppServices.isRunningTests else { return }

        if let front = NSWorkspace.shared.frontmostApplication, front.activationPolicy == .regular,
           let id = front.bundleIdentifier, id != Self.ownBundleID, isAllowedID(id) {
            lastAllowedApp = front
        }
        hideDisallowedApps()
        if let front = NSWorkspace.shared.frontmostApplication, isBlockable(front) {
            // Starting a session should not greet the user with a panel; just move focus away.
            restoreFocus(awayFrom: front)
        }

        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { self?.handleActivation(of: app) }
            },
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { self?.handleLaunch(of: app) }
            },
        ]

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func deactivate() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers = []
        pollTimer?.invalidate()
        pollTimer = nil
        panel?.dismiss()
        lastAllowedApp = nil
        lastPanelBundleID = nil
        quitRequests = [:]
        isActive = false
    }

    /// Shows the panel telling the user a tab on `domain` was closed in the browser `browserBundleID`.
    func showSiteBlocked(domain: String, browserBundleID: String) {
        guard !AppServices.isRunningTests else { return }
        let panel = self.panel ?? makePanel()
        // Don't replace an app prompt that is waiting for an answer.
        guard panel.appInfo == nil || !panel.isVisible else { return }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browserBundleID)
        let icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(named: NSImage.networkName) ?? NSImage()
        panel.showSite(domain: domain, browserIcon: icon)
    }

    func reevaluate() {
        guard isActive, !AppServices.isRunningTests else { return }
        if let shown = panel?.appInfo, isAllowedID(shown.bundleID) {
            panel?.dismiss()
        }
        hideDisallowedApps()
        if let front = NSWorkspace.shared.frontmostApplication, isBlockable(front) {
            block(front)
        }
    }

    func unhide(bundleID: String) {
        if panel?.appInfo?.bundleID == bundleID {
            panel?.dismiss()
        }
        guard !AppServices.isRunningTests else { return }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) where !app.isTerminated {
            app.unhide()
            app.activate(options: [.activateAllWindows])
        }
    }

    // MARK: - Event handling

    private func handleActivation(of app: NSRunningApplication?) {
        guard isActive, let app, app.activationPolicy == .regular, let id = app.bundleIdentifier else { return }
        if isAllowedID(id) {
            if id != Self.ownBundleID { lastAllowedApp = app }
        } else {
            block(app)
        }
    }

    private func handleLaunch(of app: NSRunningApplication?) {
        guard isActive, let app, isBlockable(app) else { return }
        // A freshly launched app may not be hideable yet; the activation observer and poll retry too.
        hide(app)
    }

    private func poll() {
        guard isActive else { return }
        hideDisallowedApps()
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        handleActivation(of: front)
    }

    // MARK: - Blocking

    private func block(_ app: NSRunningApplication) {
        hide(app)
        restoreFocus(awayFrom: app)
        presentPanel(for: app)
    }

    private func hide(_ app: NSRunningApplication) {
        let hidden = app.hide()
        guard let id = app.bundleIdentifier else { return }
        // Some apps ignore the first request (e.g. while still launching); retry once shortly after.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.isActive, !app.isTerminated, !self.isAllowedID(id) else { return }
            if !hidden || !app.isHidden || app.isActive {
                app.hide()
            }
        }
    }

    /// Hides every running regular app that is not allowed. Does not show the panel.
    private func hideDisallowedApps() {
        for app in NSWorkspace.shared.runningApplications where isBlockable(app) && !app.isHidden {
            hide(app)
        }
    }

    private func restoreFocus(awayFrom blocked: NSRunningApplication) {
        if let last = lastAllowedApp, !last.isTerminated, last != blocked,
           let id = last.bundleIdentifier, isAllowedID(id) {
            last.activate(options: [])
        } else {
            lastAllowedApp = nil
            NSApp.activate()
        }
    }

    private func presentPanel(for app: NSRunningApplication) {
        guard let id = app.bundleIdentifier else { return }
        if let requested = quitRequests[id], Date().timeIntervalSince(requested) < Self.quitGracePeriod {
            return
        }
        let panel = self.panel ?? makePanel()

        if panel.isVisible, panel.appInfo?.bundleID == id {
            panel.restartAutoDismiss()
            return
        }
        if lastPanelBundleID == id, Date().timeIntervalSince(lastPanelDate) < Self.panelDebounce {
            return
        }
        lastPanelBundleID = id
        lastPanelDate = Date()
        panel.show(for: appInfo(for: app))
    }

    private func makePanel() -> BlockPanel {
        let panel = BlockPanel()
        panel.onAllowForSession = { [weak self] info in self?.onAllowForSession(info) }
        panel.onAlwaysAllow = { [weak self] info in self?.onAlwaysAllow(info) }
        panel.onStayFocused = { [weak self] info in self?.quit(info) }
        self.panel = panel
        return panel
    }

    /// Asks the app to quit normally, so it can still offer to save unsaved work.
    private func quit(_ info: AppInfo) {
        guard !AppServices.isRunningTests, !isAllowedID(info.bundleID) else { return }
        quitRequests[info.bundleID] = Date()
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: info.bundleID) where !app.isTerminated {
            app.terminate()
        }
    }

    // MARK: - Helpers

    private func isAllowedID(_ id: String) -> Bool {
        Self.essentialBundleIDs.contains(id) || isAllowed(id)
    }

    /// True for a regular (Dock) app with a bundle id that is not allowed in this session.
    private func isBlockable(_ app: NSRunningApplication) -> Bool {
        guard app.activationPolicy == .regular, !app.isTerminated, let id = app.bundleIdentifier else { return false }
        return !isAllowedID(id)
    }

    private func appInfo(for app: NSRunningApplication) -> AppInfo {
        let id = app.bundleIdentifier ?? ""
        let url = app.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            ?? URL(fileURLWithPath: "/Applications", isDirectory: true)
        let name = app.localizedName ?? url.deletingPathExtension().lastPathComponent
        return AppInfo(bundleID: id, name: name, url: url)
    }
}
