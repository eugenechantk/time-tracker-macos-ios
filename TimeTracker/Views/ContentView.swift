import SwiftUI
import os

private let logger = Logger(
    subsystem: "com.eugenechan.TimeTracker", category: "ContentView"
)

struct ContentView: View {
    @ObservedObject var notificationManager = NotificationManager.shared
    @State private var selectedSlot: TimeSlot?

    var body: some View {
        #if os(iOS)
        NavigationStack {
            TimelineView(selectedSlot: $selectedSlot)
                .navigationBarHidden(true)
                .navigationDestination(item: $selectedSlot) { slot in
                    SlotEditView(slot: slot)
                }
        }
        .onAppear {
            consumePendingSlot()
        }
        .onChange(of: notificationManager.pendingSlot) { _, newSlot in
            if newSlot != nil {
                consumePendingSlot()
            }
        }
        #else
        macOSContentView()
        #endif
    }

    #if os(iOS)
    private func consumePendingSlot() {
        guard let slot = notificationManager.pendingSlot else { return }
        logger.info("Navigating to pending slot: \(slot.label)")
        // First dismiss any existing navigation to avoid stacking
        selectedSlot = nil
        // Delay navigation slightly to ensure the NavigationStack is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.selectedSlot = slot
            self.notificationManager.pendingSlot = nil
        }
    }
    #endif
}

#if os(macOS)
struct macOSContentView: View {
    @ObservedObject var notificationManager = NotificationManager.shared

    /// Use pendingSlot on the singleton as the navigation state so it
    /// survives MenuBarExtra view recreation.
    private var selectedSlot: Binding<TimeSlot?> {
        Binding(
            get: { notificationManager.pendingSlot },
            set: { notificationManager.pendingSlot = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if let slot = notificationManager.pendingSlot {
                HStack {
                    Button {
                        notificationManager.pendingSlot = nil
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)

                SlotEditView(slot: slot)
            } else {
                TimelineView(selectedSlot: selectedSlot)
            }

            Divider()

            Button("Quit TimeTracker") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
        }
        .frame(width: 360, height: 500)
    }
}
#endif
