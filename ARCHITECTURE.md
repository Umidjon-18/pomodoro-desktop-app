# Pomodoro — architecture & interface contract

Native macOS 14+ app (Swift 5.10, SwiftUI, SwiftData, Swift Charts, AppKit). arm64, not sandboxed,
ad-hoc signed. Menu bar app (`LSUIElement = true`) + one main window. No third-party packages.

Build: `make build` (Release), `make debug`, `make test`, `make install` (copies to /Applications).
XcodeGen generates `Pomodoro.xcodeproj` from `project.yml` — never edit the xcodeproj.

## File ownership

| Area | Files |
|---|---|
| App shell (fixed) | `App/PomodoroApp.swift`, `App/AppServices.swift`, `Models/*.swift` |
| Core | `App/AppDelegate.swift`, `Services/AppSettings.swift`, `Services/SessionManager.swift`, `Services/ActiveSessionStore.swift`, `Services/Notifier.swift` |
| App blocking | `Services/AppBlocker.swift`, `Services/AppCatalog.swift`, `Views/BlockPanel.swift` |
| Domain blocking | `Services/DomainBlocker.swift`, `Services/BrowserGuard.swift`, `Services/HostsBlock.swift`, `Resources/pomodoro-hosts`, `Resources/install-helper.sh`, `Resources/uninstall-helper.sh`, `PomodoroTests/HostsBlockTests.swift` |
| UI & stats | `Views/CustomDurationControl.swift`, `Views/MenuBarLabel.swift`, `Views/MenuBarView.swift`, `Views/MainWindowView.swift`, `Views/FocusView.swift`, `Views/AllowedAppsView.swift`, `Views/BlockedDomainsView.swift`, `Views/StatsView.swift`, `Views/SettingsView.swift`, `Views/AppIconView.swift`, `Services/Stats.swift`, `PomodoroTests/StatsTests.swift` |

## Fixed (already written)

- `FocusSession` (@Model): `id, startDate, endDate, plannedMinutes, focusedSeconds, completed`, `var record: SessionRecord`.
- `SessionRecord` (struct): `startDate, plannedMinutes, focusedSeconds, completed`.
- `AllowedApp` (@Model): `@Attribute(.unique) bundleID, name, path`.
- `BlockedDomain` (@Model): `@Attribute(.unique) domain, isEnabled, createdAt`.
- `AppServices.shared` (@MainActor): `container, settings, catalog, appBlocker, domainBlocker, session`;
  `static var isRunningTests` — when true, never hide apps, never touch /etc/hosts, never prompt.
- `PomodoroApp` injects `.environment(session/catalog/settings/domainBlocker)` + `.modelContainer(container)`
  into `MenuBarView` and `MainWindowView`; `MenuBarLabel` gets `.environment(session)`.
  Main window: `Window("Pomodoro", id: MainWindowView.windowID)`.

## Public interfaces (implement exactly; extra private helpers are fine)

### Core
```swift
@MainActor @Observable final class AppSettings {
    var playSound: Bool                 // UserDefaults "playSound", default true
    var launchAtLogin: Bool             // backed by SMAppService.mainApp (register/unregister); stored mirror for observation
    private(set) var launchAtLoginError: String?
    init()
}

@MainActor @Observable final class SessionManager {
    enum Phase: Equatable { case idle, running }
    static let presets: [Int]           // [25, 45, 60]; DEBUG builds prepend 1
    static let customMinutesRange = 1...240   // custom length; AppSettings.customMinutes remembers the last value
    private(set) var phase: Phase
    private(set) var plannedMinutes: Int
    private(set) var startDate: Date?
    private(set) var endDate: Date?
    private(set) var now: Date          // refreshed every second while running (drives UI)
    var isRunning: Bool { get }
    var remaining: TimeInterval { get } // max(0, endDate - now)
    var remainingText: String { get }   // "24:13" ("1:00:00" style not needed; 60 min shows "60:00")
    var progress: Double { get }        // elapsed fraction 0...1
    var menuBarTitle: String { get }    // "🍅" idle, "🍅 24:13" running
    private(set) var sessionAllowedBundleIDs: Set<String>
    private(set) var statusMessage: String?   // non-fatal warning shown in UI, e.g. domain block failed
    init(container: ModelContainer, appBlocker: AppBlocker, domainBlocker: DomainBlocker, catalog: AppCatalog, settings: AppSettings)
    func start(minutes: Int)
    func stop()                          // user stop: saves FocusSession(completed: false) if focusedSeconds >= 1
    func allowForSession(bundleID: String)   // add to session set + appBlocker.unhide
    func alwaysAllow(_ app: AppInfo)     // insert AllowedApp if missing (save) + allowForSession
    func allowlistDidChange()            // call after AllowedApp edits; re-evaluates running apps if running
    func domainsDidChange()              // call after BlockedDomain edits; re-applies hosts block if running
    func recoverAfterLaunch()            // finish/record an interrupted session from ActiveSessionStore, clear stale hosts block
    func prepareForTermination()         // synchronous: record partial session, deactivate blocker, clear hosts
    func allowedBundleIDs() -> Set<String>   // persistent ∪ session ∪ AppBlocker.essentialBundleIDs
    func clearStatusMessage()
}
```
Behaviour: on finish → `Notifier` posts "Session complete" + sound (if `settings.playSound`), saves
`FocusSession(completed: true, focusedSeconds: plannedMinutes*60)`, deactivates blocking, clears hosts.
Time is computed from `endDate` (sleep-safe). Active session persisted via `ActiveSessionStore` (UserDefaults JSON:
start, end, planned, sessionAllowedBundleIDs) so a crash/kill is recovered on next launch: if the end date has
passed it is recorded as completed, otherwise as stopped with elapsed seconds (capped at planned).

### App blocking
```swift
struct AppInfo: Identifiable, Hashable { var id: String { bundleID }; let bundleID: String; let name: String; let url: URL }

@MainActor @Observable final class AppCatalog {
    private(set) var installedApps: [AppInfo]   // /Applications, /Applications/Utilities, /System/Applications(+Utilities), ~/Applications; sorted, deduped by bundleID; excludes self
    private(set) var isLoading: Bool
    init()
    func reload()                                // background scan, publishes on main
    func info(forBundleID id: String) -> AppInfo?
    func icon(for url: URL) -> NSImage           // cached NSWorkspace icon
    func runningRegularApps() -> [AppInfo]       // NSWorkspace.runningApplications with .regular policy, excluding self
}

@MainActor final class AppBlocker {
    static let essentialBundleIDs: Set<String>   // self, Finder, Dock, SystemUIServer, ControlCenter, NotificationCenter, Spotlight, loginwindow, SecurityAgent, etc.
    var isAllowed: (String) -> Bool              // set by SessionManager
    var onAllowForSession: (AppInfo) -> Void     // BlockPanel button → SessionManager.allowForSession
    var onAlwaysAllow: (AppInfo) -> Void         // BlockPanel button → SessionManager.alwaysAllow
    private(set) var isActive: Bool
    init()
    func activate()            // hide all non-allowed .regular apps; observe didActivate/didLaunch; 1 s frontmost poll
    func deactivate()          // stop observing + poll, close panel (does not unhide apps)
    func reevaluate()          // re-check running apps (after allowlist change)
    func unhide(bundleID: String)  // unhide + activate running app with that id; close panel if it was about that app
}
```
Block flow: non-allowed app becomes frontmost/launches → `hide()` → re-activate last allowed app →
show `BlockPanel` (floating non-activating NSPanel, top-center): "<icon> <App> is blocked during focus"
with buttons **Allow this session**, **Always allow**, **Stay focused** (asks the app to quit normally; the panel is
suppressed for that app for 15 s) (+ auto-dismiss after ~6 s, which leaves the app hidden).

### Domain blocking
```swift
enum HostsBlock {
    static let beginMarker = "# >>> pomodoro >>>"
    static let endMarker = "# <<< pomodoro <<<"
    static func normalize(_ raw: String) -> String?   // "https://www.YouTube.com/watch?v=1" → "youtube.com"; nil if invalid
    static func isValid(_ domain: String) -> Bool     // ^[a-z0-9-]+(\.[a-z0-9-]+)+$, labels 1-63, total ≤ 253, no leading/trailing '-'
    static func entries(for domains: [String]) -> [String]   // ["0.0.0.0 d", "::1 d", "0.0.0.0 www.d", "::1 www.d"] (mirror of script)
}

@MainActor @Observable final class DomainBlocker {
    static let helperPath = "/usr/local/libexec/pomodoro-hosts"
    private(set) var helperInstalled: Bool
    private(set) var isBlocking: Bool
    private(set) var lastError: String?
    init()
    func refreshHelperStatus()                     // `sudo -n -l <helperPath>` exit 0 → installed
    func apply(domains: [String]) async throws     // `sudo -n helperPath apply d1 d2…` (validated; empty list → clear)
    func clear() async throws                      // `sudo -n helperPath clear`
    func clearSynchronously()                      // best-effort, ≤ 5 s, for app termination
    func installHelper() async throws              // osascript "do shell script … with administrator privileges" running bundled install-helper.sh <user> <bundled helper path>
    func uninstallHelper() async throws
}

@MainActor final class BrowserGuard {           // second layer: hosts only stops *new* lookups
    static let supportedBrowsers: [String: String]   // Chrome(+beta/dev/canary), Chromium, Brave, Edge, Vivaldi, Safari(+TP)
    var onTabsClosed: (String, String) -> Void       // (domain, browser bundle id) → AppBlocker.showSiteBlocked
    var onPermissionDenied: (String) -> Void         // Automation denied (-1743) → SessionManager.statusMessage
    func activate(domains: [String])                 // sweep all running browsers, then poll the frontmost one every 1.5 s
    func deactivate()
}
```
Browsers reuse open connections and cached DNS answers, so a site opened before or during a session can keep
loading despite /etc/hosts. `BrowserGuard` lists tab URLs via `osascript` (background queue, 3 s Apple Event
timeout, 6 s watchdog) and closes tabs whose host is a blocked domain or subdomain
(`HostsBlock.blockedDomain(forURL:in:)`). It never messages a browser that is not running. Firefox has no tab
scripting and is not covered.
Helper `/usr/local/libexec/pomodoro-hosts` (POSIX sh, root:wheel 0755): `apply <domain>…` | `clear`. Validates every
domain, rewrites only the marker block in /etc/hosts atomically (temp file in /etc + mv, keep 644 root:wheel),
then `dscacheutil -flushcache; killall -HUP mDNSResponder`. Sudoers: `/etc/sudoers.d/pomodoro`
(`<user> ALL=(root) NOPASSWD: /usr/local/libexec/pomodoro-hosts`), 0440, validated with `visudo -cf` before moving in.

### UI
- `MenuBarLabel`: `Text(session.menuBarTitle)` (monospaced digits).
- `MenuBarView` (window-style MenuBarExtra, ~300 pt wide): idle → preset buttons 25/45/60 + summary of allowed apps/blocked
  domains count + today's focus total; running → big countdown, progress, Stop, "Allow app…" menu (running, non-allowed apps),
  status message; footer: Open Pomodoro (openWindow + NSApp.activate), Quit.
- `MainWindowView` (`static let windowID = "main"`): NavigationSplitView sidebar: Focus, Allowed Apps, Blocked Domains, Progress, Settings.
- `StatsView` + `Stats` (pure, `Calendar` injected): Day / Week / Month with ‹ › navigation; Swift Charts bar charts;
  totals, completed vs stopped, daily average, best day, current streak (days with ≥1 completed session, today counts if it has one, otherwise streak ending yesterday).
- Editing allowlist/domains calls `session.allowlistDidChange()` / `session.domainsDidChange()`.

### Onboarding
- `OnboardingWindow.show()` (AppKit window hosting `OnboardingView`) opens on launch while
  `AppSettings.hasCompletedOnboarding` is false; closing the window sets it. Settings › General › "Welcome guide"
  reopens it.
- Steps: welcome → work apps (running apps + `AppPickerSheet`) → websites (suggestion chips, `FlowLayout`) →
  helper install → browser access (`BrowserAccessList`) → tips, notifications, launch at login.
- `BrowserPermissions` wraps `AEDeterminePermissionToAutomateTarget` (status without prompting, or prompt; always off
  the main thread). macOS can only answer for a running browser, so "Allow…" launches it in the background first.
  `BrowserAccessList` is also shown in Settings › Browser Access and refreshes every 2 s.
- Notification permission is requested in the guide's last step on first launch, and at launch afterwards.

### Localization (English, Russian, Uzbek Latin)
- Strings live in `Pomodoro/Resources/{en,ru,uz}.lproj/Localizable.strings`, keyed by the English source text
  (`en` is intentionally empty). Keys are extracted by the compiler (`SWIFT_EMIT_LOC_STRINGS`): SwiftUI literals
  are `LocalizedStringKey`; text built in code must use `String(localized:)`; non-linguistic text uses
  `Text(verbatim:)`. Sentences avoid plural agreement ("Sessions: %lld", "%lld min").
- `AppLanguage` stores the choice as this app's `AppleLanguages` preference and `relaunch()`es (a shell waits for
  the old process to exit, then `open`s the bundle). Chosen in Settings › Language or on the guide's first page.
- `LocalizationTests` checks that ru/uz have identical key sets, no empty values, and placeholders matching the key.
- After adding strings: build, collect keys from `build/Build/Intermediates.noindex/Pomodoro.build/Debug/
  Pomodoro.build/Objects-normal/arm64/*.stringsdata`, and add translations to both tables.
