import Foundation
import Observation
import ServiceManagement

/// User preferences. `launchAtLogin` is backed by `SMAppService.mainApp`.
@MainActor @Observable
final class AppSettings {
    private enum Keys {
        static let playSound = "playSound"
        static let customMinutes = "customMinutes"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    @ObservationIgnored private let defaults: UserDefaults

    private var playSoundValue: Bool
    private var customMinutesValue: Int
    private var hasCompletedOnboardingValue: Bool
    private var launchAtLoginValue = false

    var playSound: Bool {
        get { playSoundValue }
        set {
            playSoundValue = newValue
            defaults.set(newValue, forKey: Keys.playSound)
        }
    }

    /// Length of a custom session, remembered between launches.
    var customMinutes: Int {
        get { customMinutesValue }
        set {
            let range = SessionManager.customMinutesRange
            customMinutesValue = min(max(newValue, range.lowerBound), range.upperBound)
            defaults.set(customMinutesValue, forKey: Keys.customMinutes)
        }
    }

    /// Set when the welcome guide is closed; until then it opens on launch.
    var hasCompletedOnboarding: Bool {
        get { hasCompletedOnboardingValue }
        set {
            hasCompletedOnboardingValue = newValue
            defaults.set(newValue, forKey: Keys.hasCompletedOnboarding)
        }
    }

    var launchAtLogin: Bool {
        get { launchAtLoginValue }
        set { setLaunchAtLogin(newValue) }
    }

    private(set) var launchAtLoginError: String?

    init() {
        defaults = .standard
        defaults.register(defaults: [Keys.playSound: true, Keys.customMinutes: 30])
        playSoundValue = defaults.bool(forKey: Keys.playSound)
        hasCompletedOnboardingValue = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        let range = SessionManager.customMinutesRange
        customMinutesValue = min(max(defaults.integer(forKey: Keys.customMinutes), range.lowerBound), range.upperBound)
        refreshLaunchAtLogin()
    }

    /// Re-reads the login item status (it can change in System Settings).
    func refreshLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        launchAtLoginValue = status == .enabled || status == .requiresApproval
        if status == .requiresApproval {
            launchAtLoginError = "Approve Pomodoro in System Settings › General › Login Items."
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status != .notRegistered { try service.unregister() }
            }
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        refreshLaunchAtLogin()
    }
}
