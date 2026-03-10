import SwiftUI
import SwiftData

struct SlotEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let slot: TimeSlot
    @State private var description: String = ""
    @Query private var entries: [TimeEntry]
    @FocusState private var isTextFieldFocused: Bool

    private var existingEntry: TimeEntry? {
        entries.first { abs($0.slotStart.timeIntervalSince(slot.start)) < 1 }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(slot.label)
                .font(.title2.weight(.semibold))
                .padding(.top)

            TextField("What were you doing?", text: $description, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...6)
                .padding()
                .adaptiveGlass(in: .rect(cornerRadius: 12))
                .focused($isTextFieldFocused)
                .accessibilityIdentifier("entryTextField")

            Button {
                save()
            } label: {
                Text(existingEntry != nil ? "Update" : "Submit")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.adaptiveProminent)
            .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
        }
        .padding()
        .onAppear {
            if let existing = existingEntry {
                description = existing.entryDescription
            }
            isTextFieldFocused = true
        }
        .navigationTitle("Log Entry")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func save() {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = existingEntry {
            existing.entryDescription = trimmed
            existing.submittedAt = .now
        } else {
            let entry = TimeEntry(slotStart: slot.start, entryDescription: trimmed)
            modelContext.insert(entry)
        }

        #if os(macOS)
        NotificationManager.shared.pendingSlot = nil
        #else
        dismiss()
        #endif
    }
}
