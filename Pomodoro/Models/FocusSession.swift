import Foundation
import SwiftData

/// One focus session, saved when it finishes or is stopped.
@Model
final class FocusSession {
    var id: UUID
    var startDate: Date
    var endDate: Date
    var plannedMinutes: Int
    /// Seconds actually spent focusing (equals plannedMinutes * 60 when completed).
    var focusedSeconds: Int
    /// true = timer ran to zero, false = stopped early by the user (or app quit / crash).
    var completed: Bool

    init(id: UUID = UUID(), startDate: Date, endDate: Date, plannedMinutes: Int, focusedSeconds: Int, completed: Bool) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.plannedMinutes = plannedMinutes
        self.focusedSeconds = focusedSeconds
        self.completed = completed
    }

    /// Plain value copy used by `Stats` (keeps statistics testable without SwiftData).
    var record: SessionRecord {
        SessionRecord(startDate: startDate, plannedMinutes: plannedMinutes, focusedSeconds: focusedSeconds, completed: completed)
    }
}

struct SessionRecord: Hashable {
    var startDate: Date
    var plannedMinutes: Int
    var focusedSeconds: Int
    var completed: Bool
}
