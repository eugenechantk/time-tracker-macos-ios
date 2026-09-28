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
    private static let slotNotificationPrefix = "slot-"

    @Published var pendingSlot: TimeSlot?

    #if os(macOS)
    /// Opens the MenuBarExtra popover.
    ///
    /// SwiftUI creates the popover window lazily, on the first click of the menu bar icon,
    /// so until then there is nothing to show. In that case we click the icon open and shut
    /// to create the window, then show it directly like an existing one. We don't leave it
    /// open from the click: a popover SwiftUI opened itself often closes again as the
    /// notification banner is dismissed, while one shown directly stays up.
    func openMenuBarPopover() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let popover = Self.window(classNameContaining: "MenuBarExtraWindow") {
                logger.info("Showing existing popover window")
                popover.makeKeyAndOrderFront(nil)
            } else if let button = Self.statusItemButton() {
                logger.info("No popover window yet — creating it via the status item")
                button.performClick(nil)
                button.performClick(nil)
                Self.showPopoverOnceHidden()
            } else {
                logger.error("Could not open menu bar popover: no status item or popover window")
            }
        }
    }

    /// Shows the new popover window once SwiftUI's close has finished (waits up to ~1s).
    private static func showPopoverOnceHidden(attemptsLeft: Int = 20) {
        guard let popover = window(classNameContaining: "MenuBarExtraWindow") else {
            logger.error("Status item click did not create the popover window")
            return
        }
        if popover.isVisible, attemptsLeft > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                showPopoverOnceHidden(attemptsLeft: attemptsLeft - 1)
            }
            return
        }
        popover.makeKeyAndOrderFront(nil)
    }

    private static func window(classNameContaining name: String) -> NSWindow? {
        NSApp.windows.first { NSStringFromClass(type(of: $0)).contains(name) }
    }

    private static func statusItemButton() -> NSStatusBarButton? {
        guard let contentView = window(classNameContaining: "NSStatusBarWindow")?.contentView else {
            return nil
        }
        return firstSubview(ofType: NSStatusBarButton.self, in: contentView)
    }

    private static func firstSubview<T: NSView>(ofType type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = firstSubview(ofType: type, in: subview) { return match }
        }
        return nil
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

    /// Schedule notifications for today and the next 2 days.
    /// This ensures notifications survive overnight even if the app is killed.
    /// iOS allows up to 64 pending local notifications; 3 days × 33 slots = 99,
    /// but we only schedule future slots so it stays well under the limit.
    func scheduleAllNotifications() async {
        let center = UNUserNotificationCenter.current()
        let desiredRequests = Self.notificationRequests(startingAt: .now)
        let desiredIDs = Set(desiredRequests.map(\.identifier))
        let pendingRequests = await center.pendingNotificationRequests()
        let pendingIDs = Set(pendingRequests.map(\.identifier))

        let obsoleteSlotIDs = pendingIDs.filter {
            $0.hasPrefix(Self.slotNotificationPrefix) && !desiredIDs.contains($0)
        }
        if !obsoleteSlotIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(obsoleteSlotIDs))
        }

        let missingRequests = desiredRequests.filter { !pendingIDs.contains($0.identifier) }
        guard !missingRequests.isEmpty || !obsoleteSlotIDs.isEmpty else {
            logger.debug("Notification schedule already current")
            return
        }

        var scheduledCount = 0
        for request in missingRequests {
            do {
                try await center.add(request)
                scheduledCount += 1
            } catch {
                logger.error("Failed to schedule notification: \(error.localizedDescription)")
            }
        }

        logger.info("Scheduled \(scheduledCount) notifications; removed \(obsoleteSlotIDs.count) stale notifications")
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
        center.removeDeliveredNotifications(withIdentifiers: ["test-notification"])

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

    private static func notificationRequests(startingAt now: Date) -> [UNNotificationRequest] {
        let calendar = Calendar.current
        let timeFormat = Date.FormatStyle.dateTime
            .hour(.defaultDigits(amPM: .abbreviated))
            .minute(.twoDigits)
        let key = NotificationManager.slotStartKey
        var requests: [UNNotificationRequest] = []
        requests.reserveCapacity(64)

        for dayOffset in 0..<3 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let slots = SlotManager.slotsForDate(date)

            for slot in slots {
                guard slot.end > now else { continue }
                guard requests.count < 64 else { return requests }

                let content = UNMutableNotificationContent()
                content.title = "What were you doing?"
                content.body = "\(slot.start.formatted(timeFormat)) - \(slot.end.formatted(timeFormat))"
                content.sound = .default
                content.userInfo = [key: slot.start.timeIntervalSince1970]

                let triggerDate = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: slot.end
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
                let id = "\(slotNotificationPrefix)\(Int(slot.start.timeIntervalSince1970))"
                requests.append(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }

        return requests
    }
}
