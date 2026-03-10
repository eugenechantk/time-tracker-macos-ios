import Testing
import Foundation
@testable import TimeTracker

struct SlotManagerTests {

    @Test func slotsForDateGenerates33Slots() {
        let date = Date()
        let slots = SlotManager.slotsForDate(date)
        #expect(slots.count == 33)
    }

    @Test func firstSlotStartsAt730AM() {
        let date = Date()
        let slots = SlotManager.slotsForDate(date)
        let calendar = Calendar.current
        let first = slots.first!
        #expect(calendar.component(.hour, from: first.start) == 7)
        #expect(calendar.component(.minute, from: first.start) == 30)
    }

    @Test func lastSlotEndsAtMidnight() {
        let date = Date()
        let slots = SlotManager.slotsForDate(date)
        let calendar = Calendar.current
        let last = slots.last!
        // End should be midnight of the next day (hour 0, minute 0)
        #expect(calendar.component(.hour, from: last.end) == 0)
        #expect(calendar.component(.minute, from: last.end) == 0)
    }

    @Test func slotDurationIs30Minutes() {
        let date = Date()
        let slots = SlotManager.slotsForDate(date)
        for slot in slots {
            let duration = slot.end.timeIntervalSince(slot.start)
            #expect(duration == 1800) // 30 * 60
        }
    }

    @Test func slotsAreContiguous() {
        let date = Date()
        let slots = SlotManager.slotsForDate(date)
        for i in 1..<slots.count {
            #expect(slots[i].start == slots[i - 1].end)
        }
    }

    @Test func slotLabelFormatIsCorrect() {
        let date = Date()
        let slots = SlotManager.slotsForDate(date)
        let first = slots.first!
        // Should contain " - " separator and "AM" or "PM"
        #expect(first.label.contains(" - "))
        #expect(first.label.contains("AM") || first.label.contains("PM"))
    }

    @Test func currentSlotReturnsNilOutsideRange() {
        // Create a date at 3 AM (outside 7:30 AM - midnight range)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let threeAM = calendar.date(bySettingHour: 3, minute: 0, second: 0, of: today)!
        let slot = SlotManager.currentSlot(at: threeAM)
        #expect(slot == nil)
    }

    @Test func currentSlotReturnsSlotDuringRange() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tenAM = calendar.date(bySettingHour: 10, minute: 15, second: 0, of: today)!
        let slot = SlotManager.currentSlot(at: tenAM)
        #expect(slot != nil)
        #expect(calendar.component(.hour, from: slot!.start) == 10)
        #expect(calendar.component(.minute, from: slot!.start) == 0)
    }

    @Test func slotForNotificationTimeFindsCorrectSlot() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Notification at 10:00 AM should refer to the 9:30-10:00 slot
        let tenAM = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today)!
        let slot = SlotManager.slotForNotificationTime(tenAM)
        #expect(slot != nil)
        #expect(calendar.component(.hour, from: slot!.start) == 9)
        #expect(calendar.component(.minute, from: slot!.start) == 30)
    }

    @Test func timeSlotEquality() {
        let date = Date()
        let slots = SlotManager.slotsForDate(date)
        let slotsAgain = SlotManager.slotsForDate(date)
        #expect(slots.first == slotsAgain.first)
    }

    @Test func timeSlotHashable() {
        let date = Date()
        let slots = SlotManager.slotsForDate(date)
        let set = Set(slots)
        #expect(set.count == 33)
    }
}

struct TimeEntryTests {

    @Test func timeEntryCreation() {
        let now = Date()
        let entry = TimeEntry(slotStart: now, entryDescription: "Test entry")
        #expect(entry.slotStart == now)
        #expect(entry.entryDescription == "Test entry")
        #expect(entry.id != UUID()) // has a valid UUID
    }
}
