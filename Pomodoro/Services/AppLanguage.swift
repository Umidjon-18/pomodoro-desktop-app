import AppKit

/// The app's interface language. Stored as this app's own `AppleLanguages` preference, which macOS reads
/// at launch, so switching takes effect after a relaunch and covers every string (SwiftUI and AppKit).
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case russian = "ru"
    case uzbek = "uz"

    var id: String { rawValue }

    /// Languages are always listed in their own name so people can find theirs.
    var nativeName: String {
        switch self {
        case .system: String(localized: "System Default")
        case .english: "English"
        case .russian: "Русский"
        case .uzbek: "Oʻzbekcha"
        }
    }

    private static let preferenceKey = "AppleLanguages"

    /// The language chosen in Pomodoro (`.system` when it follows macOS).
    static var selected: AppLanguage {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        guard let code = (domain?[preferenceKey] as? [String])?.first else { return .system }
        return allCases.first { $0 != .system && code.hasPrefix($0.rawValue) } ?? .system
    }

    /// The language the interface is showing right now.
    static var current: AppLanguage {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        return allCases.first { $0 != .system && code.hasPrefix($0.rawValue) } ?? .english
    }

    /// Saves the choice; call `relaunch()` to apply it.
    static func select(_ language: AppLanguage) {
        if language == .system {
            UserDefaults.standard.removeObject(forKey: preferenceKey)
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: preferenceKey)
        }
    }

    /// Quits and reopens Pomodoro. A small shell waits for this process to exit, then opens the app again.
    @MainActor
    static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open \"$0\"",
            Bundle.main.bundlePath, String(ProcessInfo.processInfo.processIdentifier),
        ]
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            NSSound.beep()
        }
    }
}
