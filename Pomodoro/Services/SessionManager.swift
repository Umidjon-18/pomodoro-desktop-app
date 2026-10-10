import AppKit
import Observation
import SwiftData

/// Runs the focus timer and switches app/domain blocking on and off with it.
@MainActor @Observable
final class SessionManager {
    enum Phase: Equatable { case idle, running }

    #if DEBUG
    static let presets: [Int] = [1, 25, 45, 60]
    #else
    static let presets: [Int] = [25, 45, 60]
    #endif
    /// Allowed length of a custom session, in minutes.
    static let customMinutesRange = 1...240

    private(set) var phase: Phase = .idle
    private(set) var plannedMinutes: Int = 25
    private(set) var startDate: Date?
    private(set) var endDate: Date?
    private(set) var now: Date = .now
    private(set) var sessionAllowedBundleIDs: Set<String> = []
    private(set) var statusMessage: String?

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let appBlocker: AppBlocker
    @ObservationIgnored private let domainBlocker: DomainBlocker
    @ObservationIgnored private let browserGuard: BrowserGuard
    @ObservationIgnored private let catalog: AppCatalog
    @ObservationIgnored private let settings: AppSettings

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    /// Domains last sent to the helper during this session (non-empty → hosts must be cleared at the end).
    @ObservationIgnored private var appliedDomains: [String] = []
    /// Hosts operations run one after another so a late `apply` can never overwrite a `clear`.
    @ObservationIgnored private var hostsTask: Task<Void, Never>?

    private static let helperMissingMessage = String(localized: "Domain blocking is off: install the helper in Settings")

    init(container: ModelContainer, appBlocker: AppBlocker, domainBlocker: DomainBlocker, browserGuard: BrowserGuard,
         catalog: AppCatalog, settings: AppSettings) {
        self.container = container
        self.appBlocker = appBlocker
        self.domainBlocker = domainBlocker
        self.browserGuard = browserGuard
        self.catalog = catalog
        self.settings = settings

        appBlocker.isAllowed = { [weak self] bundleID in
            self?.allowedBundleIDs().contains(bundleID) ?? true
        }
        appBlocker.onAllowForSession = { [weak self] app in
            self?.allowForSession(bundleID: app.bundleID)
        }
        appBlocker.onAlwaysAllow = { [weak self] app in
            self?.alwaysAllow(app)
        }
        browserGuard.onTabsClosed = { [weak appBlocker] domain, browserID in
            appBlocker?.showSiteBlocked(domain: domain, browserBundleID: browserID)
        }
        browserGuard.onPermissionDenied = { [weak self] browser in
            self?.statusMessage = String(localized: "To close blocked websites, allow Pomodoro to control \(browser) in System Settings › Privacy & Security › Automation")
        }

        // The timer does not fire during sleep; re-check immediately on wake.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    // MARK: - Derived state

    var isRunning: Bool { phase == .running }

    var remaining: TimeInterval {
        guard let endDate else { return TimeInterval(plannedMinutes * 60) }
        return max(0, endDate.timeIntervalSince(now))
    }

    var remainingText: String {
        let seconds = Int(remaining.rounded(.up))
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var progress: Double {
        guard let startDate, let endDate else { return 0 }
        let total = endDate.timeIntervalSince(startDate)
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(startDate) / total))
    }

    var menuBarTitle: String {
        isRunning ? "🍅 \(remainingText)" : "🍅"
    }

    // MARK: - Session control

    func start(minutes: Int) {
        guard phase == .idle, Self.customMinutesRange.contains(minutes) else { return }
        let start = Date.now
        plannedMinutes = minutes
        startDate = start
        endDate = start.addingTimeInterval(TimeInterval(minutes * 60))
        now = start
        sessionAllowedBundleIDs = []
        statusMessage = nil
        phase = .running
        persistActiveSession()
        startTimer()

        guard !AppServices.isRunningTests else { return }
        appBlocker.activate()
        applyEnabledDomains()
    }

    func stop() {
        guard phase == .running, let startDate else { return }
        let end = Date.now
        let focused = focusedSeconds(from: startDate, to: end)
        if focused >= 1 {
            record(start: startDate, end: end, focusedSeconds: focused, completed: false)
        }
        endSession()
    }

    private func finish() {
        guard phase == .running, let startDate, let endDate else { return }
        let minutes = plannedMinutes
        record(start: startDate, end: endDate, focusedSeconds: minutes * 60, completed: true)
        endSession()

        guard !AppServices.isRunningTests else { return }
        Notifier.sessionCompleted(minutes: minutes)
        if settings.playSound { Notifier.playCompletionSound() }
    }

    /// Shared teardown for stop and finish.
    private func endSession() {
        stopTimer()
        if !AppServices.isRunningTests {
            appBlocker.deactivate()
            browserGuard.deactivate()
            if !appliedDomains.isEmpty || domainBlocker.isBlocking {
                enqueueHostsOperation { try await $0.clear() }
            }
        }
        resetState()
    }

    private func resetState() {
        appliedDomains = []
        ActiveSessionStore.clear()
        phase = .idle
        startDate = nil
        endDate = nil
        sessionAllowedBundleIDs = []
        now = .now
    }

    // MARK: - Allowlist

    func allowForSession(bundleID: String) {
        if isRunning {
            sessionAllowedBundleIDs.insert(bundleID)
            persistActiveSession()
        }
        appBlocker.unhide(bundleID: bundleID)
    }

    func alwaysAllow(_ app: AppInfo) {
        let context = container.mainContext
        let bundleID = app.bundleID
        let descriptor = FetchDescriptor<AllowedApp>(predicate: #Predicate { $0.bundleID == bundleID })
        if ((try? context.fetchCount(descriptor)) ?? 0) == 0 {
            context.insert(AllowedApp(bundleID: app.bundleID, name: app.name, path: app.url.path))
            try? context.save()
        }
        allowForSession(bundleID: bundleID)
    }

    func allowlistDidChange() {
        guard isRunning, !AppServices.isRunningTests else { return }
        appBlocker.reevaluate()
    }

    /// Persistent allowlist ∪ session allowances ∪ system essentials.
    func allowedBundleIDs() -> Set<String> {
        let saved = (try? container.mainContext.fetch(FetchDescriptor<AllowedApp>())) ?? []
        return Set(saved.map(\.bundleID))
            .union(sessionAllowedBundleIDs)
            .union(AppBlocker.essentialBundleIDs)
    }

    // MARK: - Domains

    func domainsDidChange() {
        guard isRunning, !AppServices.isRunningTests else { return }
        applyEnabledDomains()
    }

    private func enabledDomains() -> [String] {
        let descriptor = FetchDescriptor<BlockedDomain>(
            predicate: #Predicate { $0.isEnabled },
            sortBy: [SortDescriptor(\.domain)]
        )
        let domains = (try? container.mainContext.fetch(descriptor)) ?? []
        return domains.map(\.domain)
    }

    private func applyEnabledDomains() {
        let domains = enabledDomains()
        // The tab guard works without the helper, so it runs regardless of the hosts block.
        browserGuard.activate(domains: domains)
        if domains.isEmpty {
            if !appliedDomains.isEmpty || domainBlocker.isBlocking {
                enqueueHostsOperation { try await $0.clear() }
            }
            appliedDomains = []
            if statusMessage == Self.helperMissingMessage { statusMessage = nil }
            return
        }
        guard domainBlocker.helperInstalled else {
            statusMessage = Self.helperMissingMessage
            return
        }
        appliedDomains = domains
        enqueueHostsOperation { try await $0.apply(domains: domains) }
    }

    private func enqueueHostsOperation(_ operation: @escaping @MainActor (DomainBlocker) async throws -> Void) {
        let previous = hostsTask
        let blocker = domainBlocker
        hostsTask = Task { @MainActor [weak self] in
            await previous?.value
            do {
                try await operation(blocker)
                if self?.statusMessage == Self.helperMissingMessage { self?.statusMessage = nil }
            } catch {
                self?.statusMessage = blocker.helperInstalled
                    ? String(localized: "Domain blocking failed: \(error.localizedDescription)")
                    : Self.helperMissingMessage
            }
        }
    }

    // MARK: - Launch / termination

    func recoverAfterLaunch() {
        guard phase == .idle else { return }
        if let active = ActiveSessionStore.load() {
            let current = Date.now
            if active.endDate <= current {
                record(start: active.startDate, end: active.endDate,
                       plannedMinutes: active.plannedMinutes,
                       focusedSeconds: active.plannedMinutes * 60, completed: true)
            } else {
                let elapsed = Int(current.timeIntervalSince(active.startDate))
                let focused = min(max(0, elapsed), active.plannedMinutes * 60)
                if focused >= 1 {
                    record(start: active.startDate, end: current,
                           plannedMinutes: active.plannedMinutes,
                           focusedSeconds: focused, completed: false)
                }
            }
            ActiveSessionStore.clear()
        }

        // A crash can leave the hosts block in place; remove it (no-op when nothing is blocked).
        guard !AppServices.isRunningTests else { return }
        if domainBlocker.helperInstalled || FileManager.default.isExecutableFile(atPath: DomainBlocker.helperPath) {
            let blocker = domainBlocker
            hostsTask = Task { @MainActor in try? await blocker.clear() }
        }
    }

    func prepareForTermination() {
        guard phase == .running, let startDate else { return }
        stopTimer()
        let end = Date.now
        let focused = focusedSeconds(from: startDate, to: end)
        if focused >= 1 {
            record(start: startDate, end: end, focusedSeconds: focused, completed: false)
        }
        if !AppServices.isRunningTests {
            appBlocker.deactivate()
            browserGuard.deactivate()
            hostsTask?.cancel()
            if !appliedDomains.isEmpty || domainBlocker.isBlocking {
                domainBlocker.clearSynchronously()
            }
        }
        resetState()
    }

    func clearStatusMessage() {
        statusMessage = nil
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isRunning, let endDate else { return }
        now = .now
        if now >= endDate { finish() }
    }

    // MARK: - Persistence helpers

    private func focusedSeconds(from start: Date, to end: Date) -> Int {
        min(max(0, Int(end.timeIntervalSince(start))), plannedMinutes * 60)
    }

    private func record(start: Date, end: Date, plannedMinutes: Int? = nil, focusedSeconds: Int, completed: Bool) {
        let context = container.mainContext
        context.insert(FocusSession(
            startDate: start,
            endDate: end,
            plannedMinutes: plannedMinutes ?? self.plannedMinutes,
            focusedSeconds: focusedSeconds,
            completed: completed
        ))
        try? context.save()
    }

    private func persistActiveSession() {
        guard let startDate, let endDate else { return }
        ActiveSessionStore(
            startDate: startDate,
            endDate: endDate,
            plannedMinutes: plannedMinutes,
            sessionAllowedBundleIDs: sessionAllowedBundleIDs
        ).save()
    }
}
