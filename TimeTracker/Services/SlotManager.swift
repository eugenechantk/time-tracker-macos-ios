import Foundation

struct TimeSlot: Identifiable, Equatable, Hashable {
    let start: Date
    let end: Date

    var id: Date { start }

    var label: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let startStr = formatter.string(from: start)
        let endStr = formatter.string(from: end)
        return "\(startStr) - \(endStr)"
    }
}

enum SlotManager {
    static let slotDurationMinutes = 30
    static let startHour = 7
    static let startMinute = 30

    /// Generate all 33 time slots for a given date (7:30 AM to 12:00 AM midnight)
    static func slotsForDate(_ date: Date) -> [TimeSlot] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)

        guard let firstSlotStart = calendar.date(
            bySettingHour: startHour, minute: startMinute, second: 0, of: dayStart
        ) else {
            return []
        }

        // Midnight is start of next day
        guard let lastSlotEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }

        var slots: [TimeSlot] = []
        var current = firstSlotStart

        while current < lastSlotEnd {
            guard let next = calendar.date(byAdding: .minute, value: slotDurationMinutes, to: current) else {
                break
            }
            slots.append(TimeSlot(start: current, end: next))
            current = next
        }

        return slots
    }

    /// Find the slot that a notification at the given time refers to.
    /// Notifications fire at slot end, so the slot starts 30 min before.
    static func slotForNotificationTime(_ notificationTime: Date) -> TimeSlot? {
        guard let slotStart = Calendar.current.date(
            byAdding: .minute, value: -slotDurationMinutes, to: notificationTime
        ) else {
            return nil
        }
        let slots = slotsForDate(slotStart)
        return slots.first { calendar_equal($0.start, slotStart) }
    }

    /// Find the slot containing the given date, if any.
    static func currentSlot(at date: Date = .now) -> TimeSlot? {
        let slots = slotsForDate(date)
        return slots.first { date >= $0.start && date < $0.end }
    }

    private static func calendar_equal(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSince(b)) < 1
    }
}
