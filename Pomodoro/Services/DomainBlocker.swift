import Foundation
import Observation

enum DomainBlockerError: LocalizedError, Equatable {
    case helperNotInstalled
    case installCancelled
    case resourceMissing(String)
    case invalidUser(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .helperNotInstalled:
            return String(localized: "The website-blocking helper is not installed. Install it in Settings to block domains.")
        case .installCancelled:
            return String(localized: "Authorization was cancelled.")
        case .resourceMissing(let name):
            return String(localized: "The app bundle is missing \(name). Reinstall Pomodoro.")
        case .invalidUser(let name):
            return String(localized: "Cannot install the helper for user \"\(name)\".")
        case .commandFailed(let message):
            return message.isEmpty ? String(localized: "The website-blocking helper failed.") : message
        }
    }
}

/// Blocks domains during focus sessions by asking the root helper
/// (`/usr/local/libexec/pomodoro-hosts`, run through passwordless sudo) to rewrite
/// the Pomodoro block in /etc/hosts. All process work happens off the main thread.
@MainActor @Observable
final class DomainBlocker {
    nonisolated static let helperPath = "/usr/local/libexec/pomodoro-hosts"

    private(set) var helperInstalled = false
    private(set) var isBlocking = false
    private(set) var lastError: String?

    init() {
        refreshHelperStatus()
    }

    /// Re-checks that the helper exists and that sudo lets us run it without a password.
    func refreshHelperStatus() {
        guard !AppServices.isRunningTests else { return }
        Task {
            helperInstalled = await Self.checkHelperInstalled()
        }
    }

    /// Replaces the hosts block with `domains`. An empty (or all-invalid) list clears it.
    func apply(domains: [String]) async throws {
        guard !AppServices.isRunningTests else { return }
        var seen = Set<String>()
        let valid = domains.compactMap(HostsBlock.normalize).filter { seen.insert($0).inserted }
        guard !valid.isEmpty else {
            try await clear()
            return
        }
        guard FileManager.default.isExecutableFile(atPath: Self.helperPath) else {
            helperInstalled = false
            try fail(.helperNotInstalled)
        }
        try await runHelper(["apply"] + valid)
        isBlocking = true
    }

    /// Removes the hosts block. Does nothing when the helper is not installed.
    func clear() async throws {
        guard !AppServices.isRunningTests else { return }
        guard FileManager.default.isExecutableFile(atPath: Self.helperPath) else {
            isBlocking = false
            return
        }
        try await runHelper(["clear"])
        isBlocking = false
    }

    /// Best-effort clear for app termination; blocks the caller for at most 5 seconds.
    func clearSynchronously() {
        guard !AppServices.isRunningTests,
              FileManager.default.isExecutableFile(atPath: Self.helperPath)
        else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", Self.helperPath, "clear"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do {
            try process.run()
        } catch {
            return
        }
        if done.wait(timeout: .now() + 5) == .timedOut {
            process.terminate()
        } else if process.terminationStatus == 0 {
            isBlocking = false
        }
    }

    /// Installs the helper and its sudoers rule after asking for an administrator password.
    func installHelper() async throws {
        guard !AppServices.isRunningTests else { return }
        guard let script = Bundle.main.path(forResource: "install-helper", ofType: "sh") else {
            try fail(.resourceMissing("install-helper.sh"))
        }
        guard let helper = Bundle.main.path(forResource: "pomodoro-hosts", ofType: nil) else {
            try fail(.resourceMissing("pomodoro-hosts"))
        }
        let user = NSUserName()
        guard user.range(of: "^[a-z_][a-z0-9_.-]*$", options: .regularExpression) != nil else {
            try fail(.invalidUser(user))
        }
        try await runPrivileged(script: script, arguments: [user, helper])
        helperInstalled = await Self.checkHelperInstalled()
        if !helperInstalled {
            try fail(.commandFailed(String(localized: "The helper was installed but sudo does not allow running it yet.")))
        }
    }

    /// Clears any block, then removes the helper and its sudoers rule (asks for a password).
    func uninstallHelper() async throws {
        guard !AppServices.isRunningTests else { return }
        guard let script = Bundle.main.path(forResource: "uninstall-helper", ofType: "sh") else {
            try fail(.resourceMissing("uninstall-helper.sh"))
        }
        try await runPrivileged(script: script, arguments: [])
        isBlocking = false
        helperInstalled = await Self.checkHelperInstalled()
    }

    // MARK: - Private

    private func runHelper(_ arguments: [String]) async throws {
        let result = await Self.run("/usr/bin/sudo", ["-n", Self.helperPath] + arguments)
        guard result.status == 0 else {
            if result.stderr.contains("password is required") || result.stderr.contains("not allowed") {
                helperInstalled = false
                try fail(.helperNotInstalled)
            }
            try fail(.commandFailed(result.stderr))
        }
        lastError = nil
    }

    /// Runs `/bin/sh <script> <arguments…>` as root through an AppleScript authorization prompt.
    private func runPrivileged(script: String, arguments: [String]) async throws {
        let command = ([script] + arguments)
            .map { "quoted form of \(Self.appleScriptLiteral($0))" }
            .joined(separator: " & \" \" & ")
        let source = "do shell script \"/bin/sh \" & \(command) with administrator privileges"
        let result = await Self.run("/usr/bin/osascript", ["-e", source])
        guard result.status == 0 else {
            if result.stderr.contains("(-128)") {
                throw DomainBlockerError.installCancelled
            }
            try fail(.commandFailed(Self.cleanOsascriptError(result.stderr)))
        }
        lastError = nil
    }

    /// Records the error for the UI, then throws it.
    private func fail(_ error: DomainBlockerError) throws -> Never {
        lastError = error.localizedDescription
        throw error
    }

    private nonisolated static func checkHelperInstalled() async -> Bool {
        guard FileManager.default.isExecutableFile(atPath: helperPath) else { return false }
        return await run("/usr/bin/sudo", ["-n", "-l", helperPath]).status == 0
    }

    /// A double-quoted AppleScript string literal for `value`.
    private nonisolated static func appleScriptLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Strips osascript's "0:123: execution error: … (1)" wrapper.
    private nonisolated static func cleanOsascriptError(_ message: String) -> String {
        var text = message
        if let range = text.range(of: "execution error: ") {
            text = String(text[range.upperBound...])
        }
        if let range = text.range(of: #"\s*\(-?\d+\)\s*$"#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct ProcessResult {
        let status: Int32
        let stderr: String
    }

    /// Runs a process on a background queue and returns its exit status and stderr.
    private nonisolated static func run(_ executable: String, _ arguments: [String]) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = FileHandle.nullDevice
                let errorPipe = Pipe()
                process.standardError = errorPipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: ProcessResult(status: -1, stderr: error.localizedDescription))
                    return
                }
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let stderr = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: ProcessResult(status: process.terminationStatus, stderr: stderr))
            }
        }
    }
}
