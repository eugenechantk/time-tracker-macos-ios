import Foundation
import SwiftData

@Model
final class TimeEntry {
    var id: UUID = UUID()
    var slotStart: Date = Date.distantPast
    var entryDescription: String = ""
    var submittedAt: Date = Date.now

    init(slotStart: Date, entryDescription: String, submittedAt: Date = .now) {
        self.id = UUID()
        self.slotStart = slotStart
        self.entryDescription = entryDescription
        self.submittedAt = submittedAt
    }
}
