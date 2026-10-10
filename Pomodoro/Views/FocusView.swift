import SwiftUI
import SwiftData

/// The timer screen of the main window.
@MainActor
struct FocusView: View {
    @Environment(SessionManager.self) private var session
    @Environment(AppCatalog.self) private var catalog

    @Query(sort: \FocusSession.startDate) private var sessions: [FocusSession]
    @Query(sort: \AllowedApp.name) private var allowedApps: [AllowedApp]

    @State private var showingAppSearch = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let message = session.statusMessage {
                    StatusBanner(message: message) { session.clearStatusMessage() }
                        .frame(maxWidth: 520)
                }

                TimerRing(
                    fraction: session.isRunning ? 1 - session.progress : 1,
                    isRunning: session.isRunning,
                    text: session.isRunning ? session.remainingText : String(localized: "Ready"),
                    caption: ringCaption
                )
                .frame(width: 260, height: 260)

                controls

                todayStats
                    .frame(maxWidth: 520)

                usableApps
                    .frame(maxWidth: 520)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Focus")
        .sheet(isPresented: $showingAppSearch) {
            AllowAppSearchSheet()
        }
    }

    private var ringCaption: String {
        if session.isRunning, let end = session.endDate {
            return String(localized: "\(session.plannedMinutes) min · ends \(end.formatted(date: .omitted, time: .shortened))")
        }
        return String(localized: "Choose a session length")
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        if session.isRunning {
            HStack(spacing: 12) {
                allowAppMenu
                Button(role: .destructive) {
                    session.stop()
                } label: {
                    Label("Stop Session", systemImage: "stop.fill")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .keyboardShortcut(".", modifiers: .command)
            }
        } else {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    ForEach(SessionManager.presets, id: \.self) { minutes in
                        Button {
                            session.start(minutes: minutes)
                        } label: {
                            Text("\(minutes) min")
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                                .frame(minWidth: 80)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(minutes == 25 ? .red : .accentColor)
                        .controlSize(.large)
                    }
                }
                CustomDurationControl()
                    .frame(width: 320)
                if allowedApps.isEmpty {
                    Label("No allowed apps yet — everything except Finder will be hidden", systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var allowAppMenu: some View {
        let allowed = session.allowedBundleIDs()
        let running = catalog.runningRegularApps()
            .filter { !allowed.contains($0.bundleID) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return Menu {
            Section("Running Apps") {
                if running.isEmpty {
                    Text("All running apps are already allowed")
                }
                ForEach(running) { app in
                    Menu(app.name) {
                        Button("Allow This Session") { session.allowForSession(bundleID: app.bundleID) }
                        Button("Always Allow") { session.alwaysAllow(app) }
                    }
                }
            }
            Divider()
            Button("Search Installed Apps…") { showingAppSearch = true }
        } label: {
            Label("Allow Another App", systemImage: "plus.app")
        }
        .controlSize(.large)
        .fixedSize()
    }

    // MARK: Today

    private var todayStats: some View {
        let calendar = Calendar.current
        let records = sessions.map(\.record)
        let today = Stats.summary(
            records: records,
            in: Stats.interval(for: .day, containing: .now, calendar: calendar),
            calendar: calendar
        )
        let streak = Stats.currentStreak(records: records, today: .now, calendar: calendar)

        return HStack(spacing: 0) {
            QuickStat(title: "Focused today", value: Stats.formatDuration(seconds: today.focusedSeconds), symbol: "clock")
            Divider().frame(height: 36)
            QuickStat(title: "Sessions", value: "\(today.completedCount)", symbol: "checkmark.circle",
                      detail: today.stoppedCount > 0 ? String(localized: "Stopped: \(today.stoppedCount)") : nil)
            Divider().frame(height: 36)
            QuickStat(title: "Day streak", value: "\(streak)", symbol: "flame")
        }
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Usable apps

    private struct UsableApp: Identifiable {
        let id: String
        let name: String
        let url: URL?
        let sessionOnly: Bool
    }

    private var usableAppList: [UsableApp] {
        var result = allowedApps.map { app in
            UsableApp(id: app.bundleID, name: app.name,
                      url: app.path.isEmpty ? nil : URL(fileURLWithPath: app.path), sessionOnly: false)
        }
        guard session.isRunning else { return result }
        let persistent = Set(allowedApps.map(\.bundleID))
        let extra = session.sessionAllowedBundleIDs
            .subtracting(persistent)
            .map { id -> UsableApp in
                let info = catalog.info(forBundleID: id)
                return UsableApp(id: id, name: info?.name ?? id, url: info?.url, sessionOnly: true)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        result.append(contentsOf: extra)
        return result
    }

    private var usableApps: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                (session.isRunning ? Text("Usable during this session") : Text("Allowed during focus"))
                    .font(.headline)
                Spacer()
                Text("Finder and system UI are always available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let apps = usableAppList
            if apps.isEmpty {
                Text("No allowed apps. Add some under Allowed Apps.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(apps) { app in
                        HStack(spacing: 8) {
                            if let url = app.url {
                                AppIconView(url: url, size: 22)
                            } else {
                                Image(systemName: "app.dashed").frame(width: 22, height: 22)
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                Text(app.name).lineLimit(1)
                                if app.sessionOnly {
                                    Text("This session")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(6)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

// MARK: - Components

/// Circular countdown ring.
private struct TimerRing: View {
    let fraction: Double
    let isRunning: Bool
    let text: String
    let caption: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 14)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(isRunning ? Color.red : Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: fraction)
            VStack(spacing: 6) {
                Text(text)
                    .font(.system(size: isRunning ? 56 : 40, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(caption)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct QuickStat: View {
    let title: LocalizedStringKey
    let value: String
    let symbol: String
    var detail: String?

    var body: some View {
        VStack(spacing: 2) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(detail ?? " ")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Searchable list of installed apps that can be allowed mid-session.
@MainActor
private struct AllowAppSearchSheet: View {
    @Environment(SessionManager.self) private var session
    @Environment(AppCatalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""

    private var candidates: [AppInfo] {
        let allowed = session.allowedBundleIDs()
        let query = search.trimmingCharacters(in: .whitespaces)
        return catalog.installedApps.filter { app in
            !allowed.contains(app.bundleID)
                && (query.isEmpty || app.name.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Allow an App").font(.headline)
                Spacer()
                if catalog.isLoading { SwiftUI.ProgressView().controlSize(.small) }
            }
            .padding([.horizontal, .top])

            SearchField(text: $search)
                .padding()

            List(candidates) { app in
                HStack(spacing: 10) {
                    AppIconView(url: app.url, size: 24)
                    Text(app.name).lineLimit(1)
                    Spacer()
                    Button("This Session") { session.allowForSession(bundleID: app.bundleID) }
                    Button("Always") { session.alwaysAllow(app) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .overlay {
                if candidates.isEmpty && !catalog.isLoading {
                    (search.isEmpty ? Text("All installed apps are allowed") : Text("No matching apps"))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 460, height: 520)
        .onAppear {
            if catalog.installedApps.isEmpty && !catalog.isLoading { catalog.reload() }
        }
    }
}

/// A plain rounded search field (works inside sheets, unlike `.searchable`).
struct SearchField: View {
    @Binding var text: String
    var prompt: LocalizedStringKey = "Search apps"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(7)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}
