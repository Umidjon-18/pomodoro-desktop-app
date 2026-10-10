import SwiftUI

/// Preferences: domain-blocking helper, launch at login, sound.
@MainActor
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(DomainBlocker.self) private var domainBlocker
    @Environment(SessionManager.self) private var session

    private enum HelperAction { case install, uninstall }

    @State private var runningAction: HelperAction?
    @State private var language = AppLanguage.selected
    @State private var helperError: String?

    private static let dataDirectory = URL.applicationSupportDirectory.appending(path: "Pomodoro", directoryHint: .isDirectory)

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                LabeledContent("Helper") {
                    if domainBlocker.helperInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not installed", systemImage: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button(domainBlocker.helperInstalled ? "Reinstall Helper…" : "Install Helper…") {
                        run(.install)
                    }
                    Button("Uninstall", role: .destructive) {
                        run(.uninstall)
                    }
                    .disabled(!domainBlocker.helperInstalled || session.isRunning)
                    .help(session.isRunning ? "Stop the current session first" : "Remove the helper and its sudo rule")

                    if runningAction != nil {
                        SwiftUI.ProgressView()
                            .controlSize(.small)
                            .padding(.leading, 4)
                    }
                    Spacer()
                    Button("Check Again") { domainBlocker.refreshHelperStatus() }
                        .buttonStyle(.link)
                }
                .fixedSize(horizontal: false, vertical: true)
                .disabled(runningAction != nil)

                if let lastError = domainBlocker.lastError {
                    Label(lastError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Blocking websites requires editing /etc/hosts, which only an administrator can do. The one-time install (you'll be asked for your password) adds:")
                    Text("• /usr/local/libexec/pomodoro-hosts — a small script that only rewrites the Pomodoro section of /etc/hosts")
                    Text("• /etc/sudoers.d/pomodoro — lets your account run that one script without a password")
                    Text("Nothing else on your system is changed. Uninstall removes both files and the Pomodoro section.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Domain Blocking")
            }

            Section {
                BrowserAccessList()
            } header: {
                Text("Browser Access")
            } footer: {
                Text("Lets Pomodoro close tabs on blocked websites during a session. Firefox is not supported.")
                    .foregroundStyle(.secondary)
            }

            Section("Language") {
                Picker("App language", selection: $language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(verbatim: option.nativeName).tag(option)
                    }
                }
                .onChange(of: language) { AppLanguage.select(language) }
                if language != AppLanguage.selected || needsRestartForLanguage {
                    HStack {
                        Text("Pomodoro restarts to switch the language.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart Now") { AppLanguage.relaunch() }
                            .buttonStyle(.borderedProminent)
                            .disabled(session.isRunning)
                            .help(session.isRunning ? "Stop the current session first" : "")
                    }
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                if let error = settings.launchAtLoginError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                Toggle("Play sound when a session ends", isOn: $settings.playSound)
            }

            Section("About") {
                LabeledContent("Version", value: Self.version)
                LabeledContent("Data") {
                    HStack {
                        Text(verbatim: "~/Library/Application Support/Pomodoro")
                            .textSelection(.enabled)
                        Button {
                            NSWorkspace.shared.open(Self.dataDirectory)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help("Show in Finder")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear { domainBlocker.refreshHelperStatus() }
        .alert("Helper operation failed", isPresented: errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(helperError ?? "")
        }
    }

    /// True when the saved language differs from the one on screen (chosen but not yet restarted).
    private var needsRestartForLanguage: Bool {
        let wanted = language == .system ? nil : language
        return wanted.map { $0 != AppLanguage.current } ?? false
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { helperError != nil }, set: { if !$0 { helperError = nil } })
    }

    private func run(_ action: HelperAction) {
        runningAction = action
        Task {
            do {
                switch action {
                case .install:
                    try await domainBlocker.installHelper()
                    // Apply the block right away if a session is already running.
                    session.domainsDidChange()
                case .uninstall: try await domainBlocker.uninstallHelper()
                }
            } catch DomainBlockerError.installCancelled {
                // The user dismissed the password prompt; nothing to report.
            } catch {
                helperError = error.localizedDescription
            }
            domainBlocker.refreshHelperStatus()
            runningAction = nil
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
