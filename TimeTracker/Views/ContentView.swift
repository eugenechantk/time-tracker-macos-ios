import SwiftUI

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
        .onChange(of: notificationManager.pendingSlot) { _, newSlot in
            if let slot = newSlot {
                selectedSlot = slot
                notificationManager.pendingSlot = nil
            }
        }
        #else
        macOSContentView()
        #endif
    }
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
