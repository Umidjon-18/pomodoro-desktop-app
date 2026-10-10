import SwiftUI
import SwiftData
import UserNotifications

/// First-launch guide: what the app does, then allowed apps, blocked sites, the hosts helper,
/// browser Automation access and notifications. Reopen it from Settings.
@MainActor
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, apps, websites, helper, browsers, finish
    }

    let onFinish: () -> Void

    @State private var step: Step

    init(onFinish: @escaping () -> Void, initialStep: Step = .welcome) {
        self.onFinish = onFinish
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: WelcomeStep()
                case .apps: AppsStep()
                case .websites: WebsitesStep()
                case .helper: HelperStep()
                case .browsers: BrowsersStep()
                case .finish: FinishStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 40)
            .padding(.top, 40)
            .padding(.bottom, 16)
            .id(step)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))

            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 660, height: 620)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: item == step ? 18 : 7, height: 7)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: step)

            Spacer()

            if step != .welcome {
                Button("Back") { move(by: -1) }
                    .controlSize(.large)
            }
            if step == .finish {
                Button("Start Using Pomodoro", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                Button(step == .welcome ? "Get Started" : "Continue") { move(by: 1) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }

    private func move(by offset: Int) {
        guard let next = Step(rawValue: step.rawValue + offset) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { step = next }
    }
}

// MARK: - Shared pieces

@MainActor
private struct StepHeader: View {
    let symbol: String
    let color: Color
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(text)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
private struct Tip: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Steps

@MainActor
private struct WelcomeStep: View {
    @Environment(SessionManager.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            languagePicker

            HStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Pomodoro")
                        .font(.largeTitle.weight(.bold))
                    Text("Focus sessions that actually keep distractions away.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                Tip(symbol: "timer",
                    title: "Start a session from the menu bar",
                    text: "Click 🍅 at the top of your screen and pick 25, 45 or 60 minutes — or set a custom length.")
                Tip(symbol: "app.badge.checkmark",
                    title: "Only your work apps stay open",
                    text: "Other apps are hidden as soon as they come forward. You can allow one on the spot, or quit it.")
                Tip(symbol: "network.slash",
                    title: "Distracting websites are blocked",
                    text: "Sites on your list can't be reached, and their open tabs are closed.")
                Tip(symbol: "chart.bar.xaxis",
                    title: "See your progress",
                    text: "Daily, weekly and monthly focus time, plus your streak.")
            }

            Text("Setup takes about a minute. You'll pick your apps and websites and grant two permissions.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// Choosing a different language restarts the app; the guide reopens in that language.
    private var languagePicker: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
            ForEach(AppLanguage.allCases.filter { $0 != .system }) { language in
                let isCurrent = language == AppLanguage.current
                Button {
                    guard !isCurrent else { return }
                    AppLanguage.select(language)
                    OnboardingWindow.isRelaunching = true
                    AppLanguage.relaunch()
                } label: {
                    Text(verbatim: language.nativeName)
                        .fontWeight(isCurrent ? .semibold : .regular)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(isCurrent ? Color.accentColor.opacity(0.18) : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(session.isRunning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

@MainActor
private struct AppsStep: View {
    @Environment(AppCatalog.self) private var catalog
    @Environment(SessionManager.self) private var session
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \AllowedApp.name) private var allowedApps: [AllowedApp]

    @State private var candidates: [AppInfo] = []
    @State private var showingPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(
                symbol: "app.badge.checkmark", color: .blue,
                title: "Choose your work apps",
                text: "During a session only these apps stay usable. Pick the ones you need for focused work — your editor, browser, notes."
            )

            Text("Apps running now")
                .font(.headline)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { index, app in
                        if index > 0 { Divider() }
                        HStack(spacing: 10) {
                            AppIconView(url: app.url, size: 26)
                            Text(app.name)
                            Spacer()
                            Toggle("Allow \(app.name)", isOn: binding(for: app))
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        .padding(.vertical, 6)
                    }
                    if candidates.isEmpty {
                        Text("No other apps are running. Use Browse All Apps to pick some.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 14)
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Button("Browse All Apps…") { showingPicker = true }
                Spacer()
                Text("\(allowedApps.count) allowed · Finder and system UI always stay available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: loadCandidates)
        .sheet(isPresented: $showingPicker, onDismiss: loadCandidates) {
            AppPickerSheet(allowedIDs: Set(allowedApps.map(\.bundleID)), onToggle: toggle)
        }
    }

    /// Running apps plus anything already allowed, so the list never loses a checked app.
    private func loadCandidates() {
        var seen = Set<String>()
        var apps: [AppInfo] = []
        for app in catalog.runningRegularApps()
        where !AppBlocker.essentialBundleIDs.contains(app.bundleID) && seen.insert(app.bundleID).inserted {
            apps.append(app)
        }
        for app in allowedApps where seen.insert(app.bundleID).inserted {
            apps.append(AppInfo(bundleID: app.bundleID, name: app.name, url: URL(fileURLWithPath: app.path)))
        }
        candidates = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func binding(for app: AppInfo) -> Binding<Bool> {
        Binding(
            get: { allowedApps.contains { $0.bundleID == app.bundleID } },
            set: { isOn in
                let isAllowed = allowedApps.contains { $0.bundleID == app.bundleID }
                if isOn != isAllowed { toggle(app) }
            }
        )
    }

    private func toggle(_ app: AppInfo) {
        if let existing = allowedApps.first(where: { $0.bundleID == app.bundleID }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(AllowedApp(bundleID: app.bundleID, name: app.name, path: app.url.path))
        }
        try? modelContext.save()
        session.allowlistDidChange()
    }
}

@MainActor
private struct WebsitesStep: View {
    @Environment(SessionManager.self) private var session
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \BlockedDomain.createdAt) private var domains: [BlockedDomain]

    @State private var input = ""
    @State private var validationError: String?

    private static let suggestions = [
        "youtube.com", "instagram.com", "facebook.com", "x.com", "tiktok.com", "reddit.com", "netflix.com", "linkedin.com",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(
                symbol: "network.slash", color: .red,
                title: "Block distracting websites",
                text: "These sites can't be opened while a session runs. Subdomains like www. and m. are covered too."
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("Add a website, e.g. youtube.com", text: $input)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addFromInput)
                        .onChange(of: input) { validationError = nil }
                    Button("Add", action: addFromInput)
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let validationError {
                    Label(validationError, systemImage: "xmark.octagon.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Popular picks — click to toggle")
                    .font(.headline)
                FlowLayout(spacing: 8) {
                    ForEach(Self.suggestions, id: \.self) { suggestion in
                        let isOn = domains.contains { $0.domain == suggestion }
                        let button = Button {
                            isOn ? remove(suggestion) : add(suggestion)
                        } label: {
                            Label(suggestion, systemImage: isOn ? "checkmark" : "plus")
                        }
                        if isOn {
                            button.buttonStyle(.borderedProminent).tint(.red)
                        } else {
                            button.buttonStyle(.bordered)
                        }
                    }
                }
            }

            let custom = domains.filter { !Self.suggestions.contains($0.domain) }
            if !custom.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your list")
                        .font(.headline)
                    FlowLayout(spacing: 8) {
                        ForEach(custom, id: \.domain) { item in
                            Button {
                                remove(item.domain)
                            } label: {
                                Label(item.domain, systemImage: "xmark")
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .help("Remove \(item.domain)")
                        }
                    }
                }
            }

            Spacer(minLength: 0)
            Text("You can change this any time under Blocked Domains in the main window.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func addFromInput() {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        guard let domain = HostsBlock.normalize(raw) else {
            validationError = String(localized: "“\(raw)” is not a valid website. Use a form like youtube.com.")
            return
        }
        add(domain)
        input = ""
    }

    private func add(_ domain: String) {
        guard !domains.contains(where: { $0.domain == domain }) else { return }
        modelContext.insert(BlockedDomain(domain: domain))
        commit()
    }

    private func remove(_ domain: String) {
        for item in domains where item.domain == domain { modelContext.delete(item) }
        commit()
    }

    private func commit() {
        try? modelContext.save()
        session.domainsDidChange()
    }
}

@MainActor
private struct HelperStep: View {
    @Environment(DomainBlocker.self) private var domainBlocker
    @Environment(SessionManager.self) private var session

    @State private var isInstalling = false
    @State private var installError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(
                symbol: "lock.shield", color: .orange,
                title: "Install the website blocker",
                text: "To block sites in every browser and app, Pomodoro edits /etc/hosts, which needs administrator rights. Install a small helper once: macOS asks for your password one time, and sessions never prompt again."
            )

            Card {
                HStack(spacing: 12) {
                    if domainBlocker.helperInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Helper installed").font(.headline)
                            Text("Websites will be blocked automatically during sessions.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.title)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Not installed yet").font(.headline)
                            Text("Click Install, then enter your Mac login password.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if isInstalling {
                        SwiftUI.ProgressView().controlSize(.small)
                    } else if !domainBlocker.helperInstalled {
                        Button("Install Helper…", action: install)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                }
                .padding(.vertical, 8)
            }

            if let installError {
                Label(installError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("What gets installed").font(.headline)
                Text("• /usr/local/libexec/pomodoro-hosts — a small script that only edits the Pomodoro section of /etc/hosts")
                Text("• /etc/sudoers.d/pomodoro — lets your account run that one script without a password")
                Text("Nothing else is changed. You can uninstall it from Settings at any time.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)
            Text("Skipping is OK: open tabs are still closed in supported browsers, but other apps could still reach blocked sites.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { domainBlocker.refreshHelperStatus() }
    }

    private func install() {
        isInstalling = true
        installError = nil
        Task {
            do {
                try await domainBlocker.installHelper()
                session.domainsDidChange()
            } catch DomainBlockerError.installCancelled {
                // The password prompt was dismissed; the user can try again or skip.
            } catch {
                installError = error.localizedDescription
            }
            domainBlocker.refreshHelperStatus()
            isInstalling = false
        }
    }
}

@MainActor
private struct BrowsersStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(
                symbol: "safari", color: .purple,
                title: "Let Pomodoro close blocked tabs",
                text: "Browsers keep pages that were already open working even after a site is blocked. During a session Pomodoro closes those tabs — for that, macOS asks once per browser whether Pomodoro may control it."
            )

            Card {
                BrowserAccessList()
            }

            Label("Click Allow…, then choose **OK** in the macOS dialog. If you clicked Don't Allow, use Open System Settings and switch Pomodoro on under your browser.", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
            Text("Firefox can't be controlled this way; its tabs are not closed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
private struct FinishStep: View {
    @Environment(AppSettings.self) private var settings

    @State private var notificationStatus: UNAuthorizationStatus?

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: 18) {
            StepHeader(
                symbol: "checkmark.seal.fill", color: .green,
                title: "You're all set",
                text: "A few things worth knowing before your first session:"
            )

            VStack(alignment: .leading, spacing: 14) {
                Tip(symbol: "menubar.arrow.up.rectangle",
                    title: "Everything starts from 🍅 in the menu bar",
                    text: "While a session runs it shows the time left. Stop whenever you need to — the time still counts.")
                Tip(symbol: "hand.raised",
                    title: "When a blocked app appears",
                    text: "Allow this session · Always allow · Stay focused (quits the app).")
                Tip(symbol: "plus.app",
                    title: "Need another app mid-session?",
                    text: "Use “Allow an app” in the menu bar, or “Allow Another App” on the Focus screen.")
            }

            Card {
                VStack(spacing: 0) {
                    HStack {
                        Label("Notify me when a session ends", systemImage: "bell.badge")
                        Spacer()
                        notificationControl
                    }
                    .padding(.vertical, 8)
                    Divider()
                    HStack {
                        Label("Open Pomodoro when I log in", systemImage: "power")
                        Spacer()
                        Toggle("Open Pomodoro when I log in", isOn: $settings.launchAtLogin)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    .padding(.vertical, 8)
                }
            }
            if let error = settings.launchAtLoginError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .task { notificationStatus = await Notifier.authorizationStatus() }
    }

    @ViewBuilder
    private var notificationControl: some View {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            Label("On", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .denied:
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                    NSWorkspace.shared.open(url)
                }
            }
        default:
            Button("Allow…") {
                Task {
                    await Notifier.requestAuthorizationAsync()
                    notificationStatus = await Notifier.authorizationStatus()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
