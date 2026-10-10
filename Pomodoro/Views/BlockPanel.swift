import AppKit
import SwiftUI

/// Floating, non-activating HUD shown at the top of the screen when a blocked app tries to come forward
/// or a tab on a blocked website was closed.
@MainActor
final class BlockPanel: NSPanel {
    var onAllowForSession: ((AppInfo) -> Void)?
    var onAlwaysAllow: ((AppInfo) -> Void)?
    var onStayFocused: ((AppInfo) -> Void)?

    /// The app the panel is currently about (nil when hidden or when showing a website notice).
    private(set) var appInfo: AppInfo?
    /// The blocked domain the panel is currently about (nil unless showing a website notice).
    private(set) var siteDomain: String?

    private let hostingView = FirstMouseHostingView(rootView: AnyView(EmptyView()))
    private var dismissWorkItem: DispatchWorkItem?

    private static let minimumWidth: CGFloat = 360
    private static let cornerRadius: CGFloat = 16

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.minimumWidth, height: 150),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
        appearance = NSAppearance(named: .darkAqua)

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: Self.cornerRadius)

        hostingView.frame = background.bounds
        hostingView.autoresizingMask = [.width, .height]
        background.addSubview(hostingView)
        contentView = background
    }

    // Lets the buttons receive clicks (and Return) without activating the app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Shows (or retargets) the panel for a blocked app and restarts the auto-dismiss timer.
    func show(for info: AppInfo) {
        appInfo = info
        siteDomain = nil
        present(BlockPanelView(
            title: String(localized: "\(info.name) is blocked"),
            subtitle: String(localized: "You're in a focus session"),
            icon: NSWorkspace.shared.icon(forFile: info.url.path),
            onAllowForSession: { [weak self] in self?.choose(self?.onAllowForSession) },
            onAlwaysAllow: { [weak self] in self?.choose(self?.onAlwaysAllow) },
            onStayFocused: { [weak self] in self?.choose(self?.onStayFocused) },
            stayFocusedHelp: String(localized: "Quit \(info.name) and keep focusing")
        ))
    }

    /// Tells the user a tab on a blocked website was closed.
    func showSite(domain: String, browserIcon: NSImage) {
        appInfo = nil
        siteDomain = domain
        present(BlockPanelView(
            title: String(localized: "\(domain) is blocked"),
            subtitle: String(localized: "The tab was closed — you're in a focus session"),
            icon: browserIcon,
            onStayFocused: { [weak self] in self?.dismiss() }
        ))
    }

    private func present(_ view: BlockPanelView) {
        hostingView.rootView = AnyView(view)

        let fitting = hostingView.fittingSize
        let size = NSSize(width: max(Self.minimumWidth, ceil(fitting.width)), height: ceil(fitting.height))
        setFrame(NSRect(origin: Self.topCenterOrigin(for: size), size: size), display: true)

        if !isVisible {
            alphaValue = 0
            orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                animator().alphaValue = 1
            }
        } else {
            orderFrontRegardless()
        }
        invalidateShadow()
        restartAutoDismiss()
    }

    func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        appInfo = nil
        siteDomain = nil
        orderOut(nil)
    }

    func restartAutoDismiss(after delay: TimeInterval = 6) {
        dismissWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Stay up while the pointer is over the panel.
            if self.frame.contains(NSEvent.mouseLocation) {
                self.restartAutoDismiss(after: 1.5)
            } else {
                self.dismiss()
            }
        }
        dismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - Private

    private func choose(_ action: ((AppInfo) -> Void)?) {
        guard let info = appInfo else { return }
        dismiss()
        action?(info)
    }

    private static func topCenterOrigin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return .zero }
        return NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 12)
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Hosting view that accepts the first click, so buttons work while the panel is not key.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct BlockPanelView: View {
    let title: String
    let subtitle: String
    let icon: NSImage
    /// App notices offer the allow buttons; website notices only have "Stay focused".
    var onAllowForSession: (() -> Void)?
    var onAlwaysAllow: (() -> Void)?
    let onStayFocused: () -> Void
    var stayFocusedHelp: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 280, alignment: .leading)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                if let onAllowForSession {
                    Button("Allow this session", action: onAllowForSession)
                }
                if let onAlwaysAllow {
                    Button("Always allow", action: onAlwaysAllow)
                }
                Spacer(minLength: 8)
                Button("Stay focused", action: onStayFocused)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .help(stayFocusedHelp ?? "")
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(minWidth: 360, alignment: .leading)
        .fixedSize()
    }
}
