import SwiftUI

/// One row per installed browser showing whether Pomodoro may close its tabs, with the matching action.
@MainActor
struct BrowserAccessList: View {
    @State private var browsers: [AppInfo] = []
    @State private var statuses: [String: BrowserPermissions.Status] = [:]
    @State private var requesting: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if browsers.isEmpty {
                Text("No supported browser is installed. Safari, Chrome, Edge, Brave and Vivaldi are supported.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            ForEach(Array(browsers.enumerated()), id: \.element.id) { index, browser in
                if index > 0 { Divider() }
                row(for: browser)
                    .padding(.vertical, 8)
            }
        }
        .task {
            browsers = BrowserPermissions.installedBrowsers()
            // Keep the list current while it is visible (e.g. after changes in System Settings).
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func row(for browser: AppInfo) -> some View {
        HStack(spacing: 12) {
            AppIconView(url: browser.url, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(browser.name)
                statusLabel(statuses[browser.bundleID])
                    .font(.caption)
            }
            Spacer()
            if requesting.contains(browser.bundleID) {
                SwiftUI.ProgressView().controlSize(.small)
            } else {
                action(for: browser)
            }
        }
    }

    @ViewBuilder
    private func statusLabel(_ status: BrowserPermissions.Status?) -> some View {
        switch status {
        case .allowed:
            Label("Allowed — blocked tabs will be closed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .denied:
            Label("Denied — turn Pomodoro on for it in System Settings", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .notDetermined:
            Label("Not allowed yet", systemImage: "questionmark.circle")
                .foregroundStyle(.orange)
        case .notRunning:
            Label("Not running — click Allow to open it and grant access", systemImage: "moon.zzz")
                .foregroundStyle(.secondary)
        case .unknown, nil:
            Label("Checking…", systemImage: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func action(for browser: AppInfo) -> some View {
        switch statuses[browser.bundleID] {
        case .allowed:
            EmptyView()
        case .denied:
            Button("Open System Settings") { BrowserPermissions.openAutomationSettings() }
        default:
            Button("Allow…") { request(browser) }
                .buttonStyle(.borderedProminent)
        }
    }

    private func request(_ browser: AppInfo) {
        requesting.insert(browser.bundleID)
        Task {
            statuses[browser.bundleID] = await BrowserPermissions.request(browser)
            requesting.remove(browser.bundleID)
        }
    }

    private func refresh() async {
        for browser in browsers where !requesting.contains(browser.bundleID) {
            statuses[browser.bundleID] = await BrowserPermissions.status(of: browser.bundleID)
        }
    }
}
