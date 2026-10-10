import SwiftUI
import SwiftData

/// Manages the websites blocked (via /etc/hosts) during focus sessions.
@MainActor
struct BlockedDomainsView: View {
    @Environment(SessionManager.self) private var session
    @Environment(DomainBlocker.self) private var domainBlocker
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \BlockedDomain.createdAt) private var domains: [BlockedDomain]

    @State private var input = ""
    @State private var validationError: String?
    @State private var isInstalling = false
    @State private var installError: String?

    private static let suggestions = [
        "youtube.com", "instagram.com", "facebook.com", "x.com", "tiktok.com", "reddit.com", "netflix.com",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !domainBlocker.helperInstalled {
                helperBanner
                Divider()
            }

            addSection
                .padding(12)
            Divider()

            List {
                ForEach(domains, id: \.domain) { domain in
                    DomainRow(domain: domain, onToggle: { domain.isEnabled = $0; commit() }) {
                        delete([domain])
                    }
                    .contextMenu {
                        Button(domain.isEnabled ? "Disable" as LocalizedStringKey : "Enable") {
                            domain.isEnabled.toggle()
                            commit()
                        }
                        Button("Delete", role: .destructive) { delete([domain]) }
                    }
                }
                .onDelete { offsets in delete(offsets.map { domains[$0] }) }
            }
            .overlay {
                if domains.isEmpty {
                    ContentUnavailableView(
                        "No Blocked Domains",
                        systemImage: "network.slash",
                        description: Text(String(localized: "Add sites like youtube.com. The www. version is blocked too."))
                    )
                }
            }

            Divider()
            footer
                .padding(12)
        }
        .navigationTitle("Blocked Domains")
        .onAppear { domainBlocker.refreshHelperStatus() }
        .alert("Helper installation failed", isPresented: installErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(installError ?? "")
        }
    }

    // MARK: Sections

    private var helperBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Domain blocking needs a one-time helper install")
                    .font(.headline)
                Text("macOS will ask for your administrator password once. Afterwards sessions block sites without prompting.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isInstalling {
                SwiftUI.ProgressView().controlSize(.small)
            }
            Button("Install Helper") { installHelper() }
                .buttonStyle(.borderedProminent)
                .disabled(isInstalling)
        }
        .padding(12)
        .background(.orange.opacity(0.1))
    }

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Add a domain, e.g. youtube.com", text: $input)
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

            let missing = Self.suggestions.filter { suggestion in !domains.contains { $0.domain == suggestion } }
            if !missing.isEmpty {
                FlowLayout(spacing: 6) {
                    Text("Quick add:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(height: 22)
                    ForEach(missing, id: \.self) { suggestion in
                        Button {
                            add(suggestion)
                        } label: {
                            Label(suggestion, systemImage: "plus")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if session.isRunning {
                Label(domainBlocker.isBlocking ? "Blocking is active for this session." as LocalizedStringKey : "Blocking is not active.",
                      systemImage: domainBlocker.isBlocking ? "lock.fill" : "lock.open")
                    .foregroundStyle(domainBlocker.isBlocking ? Color.green : Color.orange)
            }
            Text("During a session, tabs on these sites (and their subdomains) are closed in Safari, Chrome, Edge, Brave and Vivaldi. macOS asks once per browser to let Pomodoro control it. Firefox tabs are not closed, and Firefox with DNS-over-HTTPS can bypass the block.")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private var installErrorPresented: Binding<Bool> {
        Binding(get: { installError != nil }, set: { if !$0 { installError = nil } })
    }

    // MARK: Actions

    private func addFromInput() {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        guard let domain = HostsBlock.normalize(raw) else {
            validationError = String(localized: "“\(raw)” is not a valid domain. Use a form like youtube.com.")
            return
        }
        add(domain)
        input = ""
    }

    private func add(_ domain: String) {
        // Duplicates are silently ignored.
        guard !domains.contains(where: { $0.domain == domain }) else { return }
        modelContext.insert(BlockedDomain(domain: domain))
        commit()
    }

    private func delete(_ items: [BlockedDomain]) {
        guard !items.isEmpty else { return }
        for item in items { modelContext.delete(item) }
        commit()
    }

    private func commit() {
        try? modelContext.save()
        session.domainsDidChange()
    }

    private func installHelper() {
        isInstalling = true
        Task {
            do {
                try await domainBlocker.installHelper()
                // Apply the block right away if a session is already running.
                session.domainsDidChange()
            } catch DomainBlockerError.installCancelled {
                // The user dismissed the password prompt; nothing to report.
            } catch {
                installError = error.localizedDescription
            }
            isInstalling = false
        }
    }
}

@MainActor
private struct DomainRow: View {
    let domain: BlockedDomain
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { domain.isEnabled }, set: onToggle))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                Text(domain.domain)
                    .foregroundStyle(domain.isEnabled ? .primary : .secondary)
                Text(String(localized: "also www.\(domain.domain)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Delete \(domain.domain)")
        }
        .padding(.vertical, 2)
    }
}

/// Lays out children left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, width: bounds.width)
        for (index, origin) in rows.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(subviews: Subviews, width maxWidth: CGFloat) -> (origins: [CGPoint], width: CGFloat, height: CGFloat) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (origins, widest, y + rowHeight)
    }
}
