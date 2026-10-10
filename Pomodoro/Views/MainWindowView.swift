import SwiftUI

/// The main window: sidebar navigation between the app's screens.
@MainActor
struct MainWindowView: View {
    static let windowID = "main"

    enum Screen: String, CaseIterable, Identifiable, Hashable {
        case focus, allowedApps, blockedDomains, progress, settings

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .focus: "Focus"
            case .allowedApps: "Allowed Apps"
            case .blockedDomains: "Blocked Domains"
            case .progress: "Progress"
            case .settings: "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .focus: "timer"
            case .allowedApps: "app.badge.checkmark"
            case .blockedDomains: "network.slash"
            case .progress: "chart.bar.xaxis"
            case .settings: "gearshape"
            }
        }
    }

    @Environment(AppCatalog.self) private var catalog
    @SceneStorage("mainWindow.screen") private var screen: Screen = .focus

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                ForEach(Screen.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
            }
            .scrollDisabled(true)
            .safeAreaInset(edge: .bottom) {
                Button {
                    OnboardingWindow.show()
                } label: {
                    Label("Welcome Guide", systemImage: "sparkles")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .help("Open the setup guide again")
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 250, max: 320)
        } detail: {
            detail
        }
        .onAppear {
            if catalog.installedApps.isEmpty && !catalog.isLoading {
                catalog.reload()
            }
        }
    }

    private var selection: Binding<Screen?> {
        Binding(
            get: { screen },
            set: { if let newValue = $0 { screen = newValue } }
        )
    }

    @ViewBuilder
    private var detail: some View {
        switch screen {
        case .focus: FocusView()
        case .allowedApps: AllowedAppsView()
        case .blockedDomains: BlockedDomainsView()
        case .progress: StatsView()
        case .settings: SettingsView()
        }
    }
}
