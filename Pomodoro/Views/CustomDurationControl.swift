import SwiftUI

/// "Custom [ 30 ] min ⌃⌄ [Start]" — starts a session of any length within `SessionManager.customMinutesRange`.
@MainActor
struct CustomDurationControl: View {
    @Environment(SessionManager.self) private var session
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        let range = SessionManager.customMinutesRange

        HStack(spacing: 6) {
            Text("Custom")
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            TextField("Minutes", value: $settings.customMinutes, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 52)
                .onSubmit(start)
            Stepper("Minutes", value: $settings.customMinutes, in: range, step: 5)
                .labelsHidden()
            Text("min")
                .foregroundStyle(.secondary)
            Button("Start", action: start)
                .buttonStyle(.borderedProminent)
                .help("Start a \(settings.customMinutes)-minute focus session (\(range.lowerBound)–\(range.upperBound) min)")
        }
    }

    private func start() {
        session.start(minutes: settings.customMinutes)
    }
}
