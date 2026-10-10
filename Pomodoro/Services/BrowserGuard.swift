import AppKit

/// Closes browser tabs that show a blocked domain while a focus session runs.
///
/// The hosts block only affects new DNS lookups. Browsers keep using connections and DNS answers they
/// already hold, so a site opened shortly before (or during) a session can keep loading. This guard reads
/// tab URLs over Apple Events and closes any tab whose host is a blocked domain or one of its subdomains.
/// It also works when the root helper is not installed.
@MainActor
final class BrowserGuard {
    /// Browsers whose AppleScript dictionary exposes `windows › tabs › URL` and `close tab`.
    static let supportedBrowsers: [String: String] = [
        "com.google.Chrome": "Google Chrome",
        "com.google.Chrome.beta": "Google Chrome Beta",
        "com.google.Chrome.dev": "Google Chrome Dev",
        "com.google.Chrome.canary": "Google Chrome Canary",
        "org.chromium.Chromium": "Chromium",
        "com.brave.Browser": "Brave Browser",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "com.apple.Safari": "Safari",
        "com.apple.SafariTechnologyPreview": "Safari Technology Preview",
    ]

    /// Called after tabs were closed: (blocked domain, browser bundle id).
    var onTabsClosed: (String, String) -> Void = { _, _ in }
    /// Called once per browser and session when macOS denies Automation access: (browser name).
    var onPermissionDenied: (String) -> Void = { _ in }

    private(set) var isActive = false

    private var domains: [String] = []
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var scanning: Set<String> = []
    private var deniedBrowsers: Set<String> = []
    private let queue = DispatchQueue(label: "Pomodoro.BrowserGuard", qos: .userInitiated)

    init() {}

    /// Starts guarding (or updates the domain list) and sweeps every running browser once.
    func activate(domains: [String]) {
        guard !AppServices.isRunningTests else { return }
        guard !domains.isEmpty else {
            deactivate()
            return
        }
        self.domains = domains
        if !isActive {
            isActive = true
            deniedBrowsers = []
            observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated {
                    if let id = app?.bundleIdentifier { self?.scan(id) }
                }
            }
            // Only the frontmost browser is polled: that is where a blocked page can be looked at.
            let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pollFrontmost() }
            }
            timer.tolerance = 0.3
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier { scan(id) }
        }
    }

    func deactivate() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        timer?.invalidate()
        timer = nil
        domains = []
        isActive = false
    }

    // MARK: - Scanning

    private func pollFrontmost() {
        if let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier { scan(id) }
    }

    private func scan(_ bundleID: String) {
        guard isActive, let name = Self.supportedBrowsers[bundleID],
              !scanning.contains(bundleID), !deniedBrowsers.contains(bundleID),
              // Sending Apple Events to a browser that is not running would launch it.
              !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        else { return }

        scanning.insert(bundleID)
        let domains = self.domains
        // The guard lives as long as the app, so capturing it strongly is fine.
        queue.async {
            let result = Self.closeBlockedTabs(bundleID: bundleID, domains: domains)
            Task { @MainActor in self.finishScan(bundleID: bundleID, name: name, result: result) }
        }
    }

    private func finishScan(bundleID: String, name: String, result: ScanResult) {
        scanning.remove(bundleID)
        guard isActive else { return }
        switch result {
        case .closed(let domain):
            onTabsClosed(domain, bundleID)
        case .permissionDenied:
            if deniedBrowsers.insert(bundleID).inserted { onPermissionDenied(name) }
        case .clean, .failed:
            break
        }
    }

    // MARK: - Apple Events (background queue)

    private enum ScanResult {
        case clean
        case closed(domain: String)
        case permissionDenied
        case failed
    }

    private struct TabRef {
        let window: Int
        let tab: Int
        let url: String
        let domain: String
    }

    nonisolated private static func closeBlockedTabs(bundleID: String, domains: [String]) -> ScanResult {
        let listing = runAppleScript(listTabsScript(bundleID: bundleID))
        guard listing.status == 0 else {
            return listing.error.contains("-1743") ? .permissionDenied : .failed
        }

        let targets: [TabRef] = listing.output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3, let window = Int(fields[0]), let tab = Int(fields[1]) else { return nil }
            let url = String(fields[2])
            guard let domain = HostsBlock.blockedDomain(forURL: url, in: domains) else { return nil }
            return TabRef(window: window, tab: tab, url: url, domain: domain)
        }
        guard let first = targets.first else { return .clean }

        let closing = runAppleScript(closeTabsScript(bundleID: bundleID, targets: targets))
        guard closing.status == 0 else {
            return closing.error.contains("-1743") ? .permissionDenied : .failed
        }
        return .closed(domain: first.domain)
    }

    /// Prints one "window<TAB>tab<TAB>url" line per tab. `tab` is a class name inside the browser's
    /// dictionary, so separators are built outside the `tell` block.
    nonisolated private static func listTabsScript(bundleID: String) -> String {
        """
        set sep to character id 9
        set nl to character id 10
        set out to ""
        tell application id "\(bundleID)"
            with timeout of 3 seconds
                repeat with wi from 1 to (count of windows)
                    try
                        set urls to URL of every tab of window wi
                        repeat with ti from 1 to (count of urls)
                            set u to item ti of urls
                            if u is not missing value then set out to out & wi & sep & ti & sep & (u as text) & nl
                        end repeat
                    end try
                end repeat
            end timeout
        end tell
        return out
        """
    }

    /// Closes the given tabs, last window/tab first so earlier indices stay valid. Each tab is closed only
    /// if it still shows the same URL, in case the user moved tabs around since the listing.
    nonisolated private static func closeTabsScript(bundleID: String, targets: [TabRef]) -> String {
        let ordered = targets.sorted { ($0.window, $0.tab) > ($1.window, $1.tab) }
        let statements = ordered.map { ref in
            """
                    try
                        if (URL of tab \(ref.tab) of window \(ref.window)) is "\(appleScriptEscaped(ref.url))" then close tab \(ref.tab) of window \(ref.window)
                    end try
            """
        }
        return """
        tell application id "\(bundleID)"
            with timeout of 3 seconds
        \(statements.joined(separator: "\n"))
            end timeout
        end tell
        """
    }

    nonisolated private static func appleScriptEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Runs a script through `osascript`, killing it if the browser does not answer within 6 s.
    nonisolated private static func runAppleScript(_ source: String) -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let input = Pipe(), output = Pipe(), error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        do {
            try process.run()
        } catch {
            return (-1, "", error.localizedDescription)
        }
        input.fileHandleForWriting.write(Data(source.utf8))
        try? input.fileHandleForWriting.close()

        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 6, execute: watchdog)
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return (process.terminationStatus, String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }
}
