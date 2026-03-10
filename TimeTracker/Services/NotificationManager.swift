import Combine
import Foundation
import UserNotifications
import os
#if os(macOS)
import AppKit
#endif

private let logger = Logger(
    subsystem: "com.eugenechan.TimeTracker", category: "NotificationManager"
)

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    static let slotStartKey = "slotStart"

    @Published var pendingSlot: TimeSlot?

    #if os(macOS)
    /// Opens the MenuBarExtra popover by showing its window directly
    func openMenuBarPopover() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApp.windows {
                let className = NSStringFromClass(type(of: window))
                if className.contains("MenuBarExtraWindow") {
                    window.makeKeyAndOrderFront(nil)
                    return
                }
            }
        }
    }
    #endif

    override init() {
        super.init()
    }

    func setup() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("Notification authorization granted: \(granted)")
            return granted
        } catch {
            logger.error("Notification authorization error: \(error.localizedDescription)")
            return false
        }
    }

    func scheduleNotifications(for date: Date) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let slots = SlotManager.slotsForDate(date)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        let key = NotificationManager.slotStartKey

        let now = Date.now
        for slot in slots {
            // Only schedule notifications for future slot endings
            guard slot.end > now else { continue }

            let content = UNMutableNotificationContent()
            let startLabel = formatter.string(from: slot.start)
            let endLabel = formatter.string(from: slot.end)
            content.title = "What were you doing?"
            content.body = "\(startLabel) - \(endLabel)"
            content.sound = .default
            content.userInfo = [key: slot.start.timeIntervalSince1970]

            let triggerDate = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: slot.end
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

            let id = "slot-\(Int(slot.start.timeIntervalSince1970))"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

            do {
                try await center.add(request)
            } catch {
                logger.error("Failed to schedule notification: \(error.localizedDescription)")
            }
        }

        logger.info("Scheduled \(slots.count) notifications for \(date)")
    }

    // Called when user taps a notification
    // Uses completion handler version instead of async to avoid UIKit threading crash
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let key = "slotStart"
        guard let slotStartInterval = userInfo[key] as? TimeInterval else {
            logger.warning("Notification tapped but no slotStart in userInfo")
            completionHandler()
            return
        }

        let slotStartDate = Date(timeIntervalSince1970: slotStartInterval)
        let slots = SlotManager.slotsForDate(slotStartDate)
        if let slot = slots.first(where: { abs($0.start.timeIntervalSince(slotStartDate)) < 1 }) {
            let slotLabel = slot.label
            logger.info("Notification tapped for slot: \(slotLabel)")
            DispatchQueue.main.async {
                self.pendingSlot = slot
                #if os(macOS)
                self.openMenuBarPopover()
                #endif
            }
        }
        completionHandler()
    }

    #if DEBUG
    /// Schedules a test notification that fires in a few seconds for the most recent past slot
    func scheduleTestNotification() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["test-notification"])

        let slots = SlotManager.slotsForDate(.now)
        guard let slot = slots.last(where: { $0.end <= .now }) ?? slots.first else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        let content = UNMutableNotificationContent()
        content.title = "What were you doing?"
        content.body = "\(formatter.string(from: slot.start)) - \(formatter.string(from: slot.end))"
        content.sound = .default
        content.userInfo = [NotificationManager.slotStartKey: slot.start.timeIntervalSince1970]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(identifier: "test-notification", content: content, trigger: trigger)
        do {
            try await center.add(request)
            logger.info("Test notification scheduled for 3 seconds from now")
        } catch {
            logger.error("Failed to schedule test notification: \(error.localizedDescription)")
        }
    }
    #endif

    // Show notification even when app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
