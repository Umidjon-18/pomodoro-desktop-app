import AppKit
import Observation

/// An installed or running application, identified by its bundle identifier.
struct AppInfo: Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let url: URL
}

/// Lists the applications installed on this Mac and caches their icons.
@MainActor @Observable
final class AppCatalog {
    private(set) var installedApps: [AppInfo] = []
    private(set) var isLoading = false

    @ObservationIgnored private var appsByID: [String: AppInfo] = [:]
    @ObservationIgnored private var iconCache: [String: NSImage] = [:]
    @ObservationIgnored private var scanGeneration = 0

    private static let ownBundleID = Bundle.main.bundleIdentifier ?? "com.local.Pomodoro"

    /// Folders scanned for apps, in priority order (the first copy of a bundle id wins).
    private static var searchDirectories: [URL] {
        let fm = FileManager.default
        var dirs = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
        ]
        dirs.append(fm.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory))
        return dirs
    }

    init() {
        reload()
    }

    /// Rescans the application folders on a background task and publishes the result on the main actor.
    func reload() {
        scanGeneration += 1
        let generation = scanGeneration
        isLoading = true
        let directories = Self.searchDirectories
        let excluded = Self.ownBundleID
        Task.detached(priority: .utility) { [weak self] in
            let apps = Self.scan(directories: directories, excluding: excluded)
            await self?.publish(apps, generation: generation)
        }
    }

    func info(forBundleID id: String) -> AppInfo? {
        if let info = appsByID[id] { return info }
        // Apps outside the scanned folders: ask Launch Services or a running instance.
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first,
           let url = running.bundleURL {
            return AppInfo(bundleID: id, name: running.localizedName ?? Self.displayName(for: url), url: url)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return AppInfo(bundleID: id, name: Self.displayName(for: url), url: url)
        }
        return nil
    }

    /// The Finder icon for an app bundle (32×32 by default), cached by path.
    func icon(for url: URL) -> NSImage {
        let key = url.path
        if let cached = iconCache[key] { return cached }
        let image = NSWorkspace.shared.icon(forFile: key)
        image.size = NSSize(width: 32, height: 32)
        iconCache[key] = image
        return image
    }

    /// Running apps that show in the Dock (activation policy `.regular`), excluding this app.
    func runningRegularApps() -> [AppInfo] {
        var seen = Set<String>()
        var result: [AppInfo] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, id != Self.ownBundleID, seen.insert(id).inserted else { continue }
            guard let url = app.bundleURL ?? appsByID[id]?.url else { continue }
            let name = app.localizedName ?? appsByID[id]?.name ?? Self.displayName(for: url)
            result.append(AppInfo(bundleID: id, name: name, url: url))
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Private

    private func publish(_ apps: [AppInfo], generation: Int) {
        guard generation == scanGeneration else { return }
        installedApps = apps
        appsByID = Dictionary(apps.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
        isLoading = false
    }

    nonisolated private static func scan(directories: [URL], excluding excludedID: String) -> [AppInfo] {
        var seen = Set<String>()
        var apps: [AppInfo] = []
        for directory in directories {
            for bundleURL in appBundles(in: directory, descend: true) {
                guard let bundle = Bundle(url: bundleURL),
                      let id = bundle.bundleIdentifier,
                      id != excludedID,
                      seen.insert(id).inserted
                else { continue }
                apps.append(AppInfo(bundleID: id, name: displayName(of: bundle, at: bundleURL), url: bundleURL))
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// `.app` bundles directly inside `directory`, plus (when `descend`) those one folder deeper,
    /// e.g. "/Applications/Microsoft Office/…". Never looks inside an `.app` bundle.
    nonisolated private static func appBundles(in directory: URL, descend: Bool) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [URL] = []
        for entry in entries {
            if entry.pathExtension.lowercased() == "app" {
                result.append(entry)
                continue
            }
            guard descend else { continue }
            let resolved = entry.resolvingSymlinksInPath()
            let values = try? resolved.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true, values?.isPackage != true {
                result.append(contentsOf: appBundles(in: resolved, descend: false))
            }
        }
        return result
    }

    nonisolated private static func displayName(of bundle: Bundle, at url: URL) -> String {
        let keys = ["CFBundleDisplayName", "CFBundleName"]
        for key in keys {
            if let name = bundle.localizedInfoDictionary?[key] as? String, !name.isEmpty { return name }
            if let name = bundle.infoDictionary?[key] as? String, !name.isEmpty { return name }
        }
        return url.deletingPathExtension().lastPathComponent
    }

    nonisolated private static func displayName(for url: URL) -> String {
        if let bundle = Bundle(url: url) { return displayName(of: bundle, at: url) }
        return url.deletingPathExtension().lastPathComponent
    }
}
