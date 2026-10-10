import SwiftUI
import SwiftData

/// Manages the apps that stay usable during focus sessions.
@MainActor
struct AllowedAppsView: View {
    @Environment(SessionManager.self) private var session
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \AllowedApp.name) private var allowedApps: [AllowedApp]

    @State private var showingPicker = false
    @State private var selection = Set<String>()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            List(selection: $selection) {
                ForEach(allowedApps, id: \.bundleID) { app in
                    AllowedAppRow(app: app) { remove([app]) }
                        .tag(app.bundleID)
                        .contextMenu {
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
                            }
                            Divider()
                            Button("Remove", role: .destructive) { remove(selectedOr(app)) }
                        }
                }
                .onDelete { offsets in remove(offsets.map { allowedApps[$0] }) }
            }
            .onDeleteCommand { remove(allowedApps.filter { selection.contains($0.bundleID) }) }
            .overlay {
                if allowedApps.isEmpty {
                    ContentUnavailableView {
                        Label("No Allowed Apps", systemImage: "app.dashed")
                    } description: {
                        Text("During a session every other app is hidden. Add the apps you need for focused work.")
                    } actions: {
                        Button("Add Apps…") { showingPicker = true }
                    }
                }
            }
        }
        .navigationTitle("Allowed Apps")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingPicker = true
                } label: {
                    Label("Add Apps", systemImage: "plus")
                }
                .help("Add apps to the allowed list")
            }
        }
        .sheet(isPresented: $showingPicker) {
            AppPickerSheet(allowedIDs: Set(allowedApps.map(\.bundleID)), onToggle: toggle)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("These apps stay usable during every focus session; all others are hidden when they come to the front.")
                Text("Finder and system UI are always available. Changes apply immediately, even mid-session.")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            Spacer()
            Button {
                showingPicker = true
            } label: {
                Label("Add Apps…", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
    }

    private func selectedOr(_ app: AllowedApp) -> [AllowedApp] {
        selection.contains(app.bundleID) ? allowedApps.filter { selection.contains($0.bundleID) } : [app]
    }

    private func remove(_ apps: [AllowedApp]) {
        guard !apps.isEmpty else { return }
        for app in apps {
            selection.remove(app.bundleID)
            modelContext.delete(app)
        }
        commit()
    }

    private func toggle(_ info: AppInfo) {
        if let existing = allowedApps.first(where: { $0.bundleID == info.bundleID }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(AllowedApp(bundleID: info.bundleID, name: info.name, path: info.url.path))
        }
        commit()
    }

    private func commit() {
        try? modelContext.save()
        session.allowlistDidChange()
    }
}

@MainActor
private struct AllowedAppRow: View {
    let app: AllowedApp
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(url: URL(fileURLWithPath: app.path), size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                Text(app.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove \(app.name)")
        }
        .padding(.vertical, 2)
    }
}

/// Searchable checklist of installed (and running) apps.
@MainActor
struct AppPickerSheet: View {
    @Environment(AppCatalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss

    let allowedIDs: Set<String>
    let onToggle: (AppInfo) -> Void

    @State private var search = ""

    /// Installed apps plus running apps that live elsewhere (e.g. ~/Downloads).
    private var apps: [AppInfo] {
        var seen = Set(catalog.installedApps.map(\.bundleID))
        var all = catalog.installedApps
        for app in catalog.runningRegularApps() where seen.insert(app.bundleID).inserted {
            all.append(app)
        }
        let query = search.trimmingCharacters(in: .whitespaces)
        return all
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Allowed Apps").font(.headline)
                Spacer()
                if catalog.isLoading { SwiftUI.ProgressView().controlSize(.small) }
                Button {
                    catalog.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Rescan installed apps")
            }
            .padding([.horizontal, .top])

            SearchField(text: $search)
                .padding()

            List(apps) { app in
                let isAllowed = allowedIDs.contains(app.bundleID)
                Button {
                    onToggle(app)
                } label: {
                    HStack(spacing: 10) {
                        AppIconView(url: app.url, size: 24)
                        Text(app.name).lineLimit(1)
                        Spacer()
                        Image(systemName: isAllowed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isAllowed ? Color.accentColor : Color.secondary)
                            .imageScale(.large)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if apps.isEmpty && !catalog.isLoading {
                    Text("No matching apps").foregroundStyle(.secondary)
                }
            }

            Divider()
            HStack {
                Text("Allowed: \(allowedIDs.count)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 460, height: 560)
        .onAppear {
            if catalog.installedApps.isEmpty && !catalog.isLoading { catalog.reload() }
        }
    }
}
