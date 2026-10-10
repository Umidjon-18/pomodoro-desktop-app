import AppKit
import SwiftData

/// Owns every long-lived service. Created once on the main actor.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let container: ModelContainer
    let settings: AppSettings
    let catalog: AppCatalog
    let appBlocker: AppBlocker
    let domainBlocker: DomainBlocker
    let browserGuard: BrowserGuard
    let session: SessionManager

    /// True when the process is hosting unit tests; side effects (blocking, hosts edits) are skipped.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private init() {
        container = Self.makeContainer()
        settings = AppSettings()
        catalog = AppCatalog()
        appBlocker = AppBlocker()
        domainBlocker = DomainBlocker()
        browserGuard = BrowserGuard()
        session = SessionManager(
            container: container,
            appBlocker: appBlocker,
            domainBlocker: domainBlocker,
            browserGuard: browserGuard,
            catalog: catalog,
            settings: settings
        )
    }

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([FocusSession.self, AllowedApp.self, BlockedDomain.self])
        let configuration: ModelConfiguration
        if isRunningTests {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            let support = URL.applicationSupportDirectory.appending(path: "Pomodoro", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            configuration = ModelConfiguration(schema: schema, url: support.appending(path: "Pomodoro.store"))
        }
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Could not open the Pomodoro database: \(error)")
        }
    }
}
