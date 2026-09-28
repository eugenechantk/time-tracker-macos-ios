import SwiftUI
import SwiftData
import os

private let logger = Logger(
    subsystem: "com.eugenechan.TimeTracker", category: "SlotEditView"
)

struct SlotEditView: View {
    @Environment(\.dismiss) private var dismiss
    let slot: TimeSlot
    @State private var description: String
    @State private var existingEntry: TimeEntry?
    @State private var todayDescriptions: [String]
    @State private var selectedSuggestionIndex: Int?
    @FocusState private var isTextFieldFocused: Bool
    @State private var textFieldHeight: CGFloat = 0

    init(slot: TimeSlot) {
        self.slot = slot
        // Eagerly load data in init so it's available even if onAppear doesn't fire
        // (known MenuBarExtra lifecycle issue on macOS when switching if/else branches).
        let data = Self.loadSlotData(for: slot)
        _existingEntry = State(initialValue: data.existingEntry)
        _description = State(initialValue: data.existingEntry?.entryDescription ?? "")
        _todayDescriptions = State(initialValue: data.todayDescriptions)
        logger.debug("init: slot=\(slot.label), existingEntry=\(data.existingEntry != nil), todayDescriptions=\(data.todayDescriptions.count)")
    }

    private var suggestions: [String] {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lower = trimmed.lowercased()
        return todayDescriptions.filter {
            $0.lowercased().contains(lower) && $0 != trimmed
        }
    }

    private var selectedSuggestion: String? {
        guard let selectedSuggestionIndex,
              suggestions.indices.contains(selectedSuggestionIndex) else {
            return nil
        }
        return suggestions[selectedSuggestionIndex]
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
                            ForEach(Array(suggestions.enumerated()), id: \.element) { index, suggestion in
                                Button {
                                    acceptSuggestion(suggestion)
                                } label: {
                                    Text(suggestion)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)
                                .background(
                                    index == selectedSuggestionIndex
                                        ? Color.accentColor.opacity(0.18)
                                        : Color.clear
                                )
                                .accessibilityIdentifier("entrySuggestion_\(index)")

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
                .onKeyPress(.downArrow) {
                    moveSuggestionSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveSuggestionSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.return) {
                    guard let selectedSuggestion else { return .ignored }
                    acceptSuggestion(selectedSuggestion)
                    return .handled
                }
                .onKeyPress(.tab) {
                    guard let selectedSuggestion else { return .ignored }
                    acceptSuggestion(selectedSuggestion)
                    return .handled
                }
                .onKeyPress(.escape) {
                    selectedSuggestionIndex = nil
                    return .handled
                }

            Button {
                save()
            } label: {
                Text(existingEntry != nil ? "Update" : "Submit")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
        }
        .padding()
        .onAppear {
            // Data is loaded in init; onAppear refreshes as a safety net
            // and handles focus (which can't be set in init).
            refreshSlotData()
            if let existing = existingEntry {
                description = existing.entryDescription
            }
            isTextFieldFocused = true
        }
        .onChange(of: description) {
            selectedSuggestionIndex = nil
        }
        .onChange(of: suggestions) { _, newSuggestions in
            guard let selectedSuggestionIndex else { return }
            if !newSuggestions.indices.contains(selectedSuggestionIndex) {
                self.selectedSuggestionIndex = newSuggestions.isEmpty ? nil : newSuggestions.count - 1
            }
        }
        .navigationTitle("Log Entry")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func moveSuggestionSelection(by offset: Int) {
        guard !suggestions.isEmpty else {
            selectedSuggestionIndex = nil
            return
        }

        let currentIndex = selectedSuggestionIndex ?? (offset > 0 ? -1 : suggestions.count)
        selectedSuggestionIndex = (currentIndex + offset + suggestions.count) % suggestions.count
    }

    private func acceptSuggestion(_ suggestion: String) {
        description = suggestion
        selectedSuggestionIndex = nil
        isTextFieldFocused = true
    }

    private func refreshSlotData() {
        let data = Self.loadSlotData(for: slot)
        existingEntry = data.existingEntry
        todayDescriptions = data.todayDescriptions
    }

    private func save() {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Use a fresh context so we always read/write against the latest persisted state.
        // This avoids stale-cache issues when the view opens via notification tap.
        let context = ModelContext(TimeTrackerApp.sharedModelContainer)
        let slotStart = slot.start
        let exactSlotEnd = slotStart.addingTimeInterval(1)

        // Re-fetch the entry in this context so the object belongs to it
        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate { entry in
                entry.slotStart >= slotStart && entry.slotStart < exactSlotEnd
            },
            sortBy: [SortDescriptor(\.submittedAt, order: .reverse)]
        )
        let existing = (try? context.fetch(descriptor))?.first

        let savedEntry: TimeEntry
        if let existing {
            existing.entryDescription = trimmed
            existing.slotEnd = slot.end
            existing.submittedAt = .now
            savedEntry = existing
        } else {
            let entry = TimeEntry(slotStart: slot.start, slotEnd: slot.end, entryDescription: trimmed)
            context.insert(entry)
            savedEntry = entry
        }

        // Persist immediately so any fresh ModelContext sees the data
        try? context.save()

        // Push to the sync API for cross-device sync
        SyncService.shared.pushEntry(savedEntry)

        #if os(macOS)
        // Navigate back first, then trigger refresh so TimelineView is mounted to receive it
        NotificationManager.shared.pendingSlot = nil
        DispatchQueue.main.async {
            SyncService.shared.refreshID = UUID()
        }
        #else
        SyncService.shared.refreshID = UUID()
        dismiss()
        #endif
    }

    private static func loadSlotData(for slot: TimeSlot) -> SlotData {
        let context = ModelContext(TimeTrackerApp.sharedModelContainer)
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: slot.start)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate { entry in
                entry.slotStart >= dayStart && entry.slotStart < dayEnd
            },
            sortBy: [SortDescriptor(\.submittedAt, order: .reverse)]
        )
        let entries = (try? context.fetch(descriptor)) ?? []
        let currentSlotStart = slot.start
        let existing = entries.first {
            abs($0.slotStart.timeIntervalSince(currentSlotStart)) < 1
        }
        let descriptions = Array(Set(
            entries
                .filter { abs($0.slotStart.timeIntervalSince(currentSlotStart)) >= 1 }
                .map { $0.entryDescription }
                .filter { !$0.isEmpty }
        )).sorted()

        return SlotData(existingEntry: existing, todayDescriptions: descriptions)
    }

    private struct SlotData {
        let existingEntry: TimeEntry?
        let todayDescriptions: [String]
    }
}
