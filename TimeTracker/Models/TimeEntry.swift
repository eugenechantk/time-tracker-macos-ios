import Foundation
import SwiftData

@Model
final class TimeEntry {
    var id: UUID = UUID()
    var slotStart: Date = Date.distantPast
    var slotEnd: Date = Date.distantPast
    var entryDescription: String = ""
    var submittedAt: Date = Date.now

    init(
        slotStart: Date,
        slotEnd: Date? = nil,
        entryDescription: String,
        submittedAt: Date = .now
    ) {
        self.id = UUID()
        self.slotStart = slotStart
        self.slotEnd = slotEnd ?? slotStart.addingTimeInterval(TimeInterval(SlotManager.slotDurationMinutes * 60))
        self.entryDescription = entryDescription
        self.submittedAt = submittedAt
    }
}
