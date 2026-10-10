import SwiftUI
import SwiftData

/// Content of the menu bar popover.
@MainActor
struct MenuBarView: View {
    @Environment(SessionManager.self) private var session
    @Environment(AppCatalog.self) private var catalog
    @Environment(\.openWindow) private var openWindow

    @Query(sort: \FocusSession.startDate) private var sessions: [FocusSession]
    @Query private var allowedApps: [AllowedApp]
    @Query private var blockedDomains: [BlockedDomain]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if session.isRunning {
                runningContent
            } else {
                idleContent
            }

            if let message = session.statusMessage {
                StatusBanner(message: message) { session.clearStatusMessage() }
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
    }

    // MARK: Idle

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start focus")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(SessionManager.presets, id: \.self) { minutes in
                    Button {
                        session.start(minutes: minutes)
                    } label: {
                        VStack(spacing: 0) {
                            Text(verbatim: "\(minutes)")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text("min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("Start a \(minutes)-minute focus session")
                }
            }

            CustomDurationControl()

            VStack(alignment: .leading, spacing: 4) {
                Label(summaryLine, systemImage: "lock.shield")
                Label("Today: \(todayFocusText) focused", systemImage: "chart.bar")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            if allowedApps.isEmpty {
                Label("No allowed apps yet — everything except Finder will be hidden", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var summaryLine: String {
        let enabledDomains = blockedDomains.filter(\.isEnabled).count
        return String(localized: "Allowed apps: \(allowedApps.count) · Blocked domains: \(enabledDomains)")
    }

    private var todayFocusText: String {
        let calendar = Calendar.current
        let today = Stats.interval(for: .day, containing: .now, calendar: calendar)
        let summary = Stats.summary(records: sessions.map(\.record), in: today, calendar: calendar)
        return Stats.formatDuration(seconds: summary.focusedSeconds)
    }

    // MARK: Running

    private var runningContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.remainingText)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Spacer()
                if let end = session.endDate {
                    Text("Ends at \(end.formatted(date: .omitted, time: .shortened))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            SwiftUI.ProgressView(value: session.progress)
                .progressViewStyle(.linear)
                .tint(.red)

            HStack {
                allowAppMenu
                Spacer()
                Button(role: .destructive) {
                    session.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(".", modifiers: .command)
            }
        }
    }

    private var allowAppMenu: some View {
        let allowed = session.allowedBundleIDs()
        let candidates = catalog.runningRegularApps()
            .filter { !allowed.contains($0.bundleID) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return Menu {
            if candidates.isEmpty {
                Text("All running apps are already allowed")
            } else {
                ForEach(candidates) { app in
                    Menu(app.name) {
                        Button("Allow This Session") { session.allowForSession(bundleID: app.bundleID) }
                        Button("Always Allow") { session.alwaysAllow(app) }
                    }
                }
            }
        } label: {
            Label("Allow an app", systemImage: "plus.app")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button {
                openWindow(id: MainWindowView.windowID)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open Pomodoro", systemImage: "macwindow")
            }
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }
}

/// A dismissible warning row for `SessionManager.statusMessage`.
@MainActor
struct StatusBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
