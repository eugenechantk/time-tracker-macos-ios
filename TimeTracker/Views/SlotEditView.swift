import SwiftUI
import SwiftData

struct SlotEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let slot: TimeSlot
    @State private var description: String = ""
    @State private var existingEntry: TimeEntry?
    @State private var todayDescriptions: [String] = []
    @FocusState private var isTextFieldFocused: Bool
    @State private var textFieldHeight: CGFloat = 0

    private var suggestions: [String] {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lower = trimmed.lowercased()
        return todayDescriptions.filter {
            $0.lowercased().contains(lower) && $0 != trimmed
        }
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
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    textFieldHeight = newHeight
                }
                .overlay(alignment: .topLeading) {
                    if !suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button {
                                    description = suggestion
                                } label: {
                                    Text(suggestion)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)

                                if suggestion != suggestions.last {
                                    Divider()
                                        .padding(.horizontal, 12)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
                        .offset(y: textFieldHeight + 8)
                    }
                }
                .zIndex(1)

            Button {
                save()
            } label: {
                Text(existingEntry != nil ? "Update" : "Submit")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
        }
        .padding()
        .onAppear {
            loadExistingEntry()
            loadTodayDescriptions()
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

    private func loadExistingEntry() {
        let slotStart = slot.start
        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate { entry in
                entry.slotStart >= slotStart
            }
        )
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        existingEntry = entries.first { abs($0.slotStart.timeIntervalSince(slotStart)) < 1 }
    }

    private func loadTodayDescriptions() {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: slot.start)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate { entry in
                entry.slotStart >= dayStart && entry.slotStart < dayEnd
            }
        )
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        // Unique descriptions, excluding the current slot's entry
        let currentSlotStart = slot.start
        todayDescriptions = Array(Set(
            entries
                .filter { abs($0.slotStart.timeIntervalSince(currentSlotStart)) >= 1 }
                .map { $0.entryDescription }
                .filter { !$0.isEmpty }
        )).sorted()
    }

    private func save() {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let savedEntry: TimeEntry
        if let existing = existingEntry {
            existing.entryDescription = trimmed
            existing.submittedAt = .now
            savedEntry = existing
        } else {
            let entry = TimeEntry(slotStart: slot.start, entryDescription: trimmed)
            modelContext.insert(entry)
            savedEntry = entry
        }

        // Optimistic update: use localRefreshID so TimelineView fetches from main context instantly
        ConvexSyncService.shared.refreshID = UUID()

        // Push to Convex for cross-device sync
        ConvexSyncService.shared.pushEntry(savedEntry)

        #if os(macOS)
        NotificationManager.shared.pendingSlot = nil
        #else
        dismiss()
        #endif
    }
}
