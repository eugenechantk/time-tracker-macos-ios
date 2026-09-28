import Combine
import SwiftUI
import SwiftData
import os

private let logger = Logger(
    subsystem: "com.eugenechan.TimeTracker", category: "TimelineView"
)

struct TimelineView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let syncService = SyncService.shared
    #if os(macOS)
    @ObservedObject private var notificationManager = NotificationManager.shared
    #endif
    @Binding var selectedSlot: TimeSlot?
    @State private var selectedDate: Date
    @State private var slots: [TimeSlot]
    @State private var entriesBySlotStart: [Date: TimeEntry]

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    /// The slot that should be visible when opening the timeline.
    /// Today prefers the real current slot, even if it is already filled.
    private var openingScrollTarget: TimeSlot? {
        if isToday {
            let now = Date.now
            if let currentSlot = slots.first(where: { now >= $0.start && now < $0.end }) {
                return currentSlot
            }
            return slots.first { $0.end > now } ?? slots.last
        }

        let now = Date.now
        let pastUnfilled = slots.filter { $0.end <= now && entriesBySlotStart[$0.start] == nil }
        if let last = pastUnfilled.last { return last }
        return slots.first { $0.end > now }
    }

    var body: some View {
        VStack(spacing: 0) {
            titleHeader
            dateHeader
            slotList
        }
        .onAppear {
            logger.debug("TimelineView onAppear fired")
            fetchEntries()
        }
        .onChange(of: selectedDate) { _, newDate in fetchEntries(for: newDate) }
        .onReceive(syncService.$refreshID.dropFirst()) { _ in fetchEntries() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                fetchEntries()
            }
        }
        #if os(macOS)
        // MenuBarExtra doesn't reliably fire onAppear when switching if/else branches.
        // When pendingSlot becomes nil (user navigated back from edit), this view
        // is now visible — refresh entries to pick up any newly saved data.
        .onChange(of: notificationManager.pendingSlot) { _, newSlot in
            if newSlot == nil {
                logger.debug("pendingSlot cleared — refreshing entries")
                // Small delay to let SwiftData's persistent store flush
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    fetchEntries()
                }
            }
        }
        #endif
    }

    private func fetchEntries() {
        fetchEntries(for: selectedDate)
    }

    private func fetchEntries(for date: Date) {
        do {
            let dayEntries = try Self.fetchEntries(for: date)
            slots = SlotManager.slotsForDate(date)
            entriesBySlotStart = Self.indexEntriesBySlotStart(dayEntries)
            logger.debug("Fetched \(dayEntries.count) entries for selected day")
        } catch {
            logger.error("Failed to fetch entries: \(error.localizedDescription)")
        }
    }

    private var titleHeader: some View {
        HStack {
            Text("TimeTracker")
                .font(.title.bold())

            Spacer()

            if !isToday {
                Button {
                    selectedDate = .now
                } label: {
                    Text("Today")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var dateHeader: some View {
        HStack {
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            Spacer()

            Text(selectedDate, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.headline)

            Spacer()

            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var slotList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(slots) { slot in
                        let entry = entriesBySlotStart[slot.start]
                        let isPast = slot.end <= Date.now
                        SlotRowView(slot: slot, entry: entry)
                            .id(slot.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isPast || entry != nil {
                                    selectedSlot = slot
                                }
                            }
                            .opacity(isPast || entry != nil ? 1 : 0.35)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .onAppear {
                scrollToOpeningTarget(with: proxy)
            }
            .onChange(of: selectedDate) {
                scrollToOpeningTarget(with: proxy)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    scrollToOpeningTarget(with: proxy)
                }
            }
            #if os(macOS)
            .onChange(of: notificationManager.pendingSlot) { _, newSlot in
                if newSlot == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        scrollToOpeningTarget(with: proxy)
                    }
                }
            }
            #endif
        }
    }

    private func scrollToOpeningTarget(with proxy: ScrollViewProxy) {
        guard let target = openingScrollTarget else { return }
        DispatchQueue.main.async {
            withAnimation(.snappy(duration: 0.2)) {
                proxy.scrollTo(target.id, anchor: .center)
            }
        }
    }

    init(selectedSlot: Binding<TimeSlot?>) {
        _selectedSlot = selectedSlot
        let initialDate = Date.now
        let initialEntries = (try? Self.fetchEntries(for: initialDate)) ?? []
        _selectedDate = State(initialValue: initialDate)
        _slots = State(initialValue: SlotManager.slotsForDate(initialDate))
        _entriesBySlotStart = State(initialValue: Self.indexEntriesBySlotStart(initialEntries))
    }

    private static func fetchEntries(for date: Date) throws -> [TimeEntry] {
        // Fresh context keeps this view in sync with saves from SlotEditView and sync merges.
        let context = ModelContext(TimeTrackerApp.sharedModelContainer)
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate { entry in
                entry.slotStart >= dayStart && entry.slotStart < dayEnd
            },
            sortBy: [SortDescriptor(\.submittedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    private static func indexEntriesBySlotStart(_ entries: [TimeEntry]) -> [Date: TimeEntry] {
        // Use grouping to handle potential duplicates safely.
        Dictionary(grouping: entries, by: { $0.slotStart })
            .compactMapValues { entries in
                entries.max { $0.submittedAt < $1.submittedAt }
            }
    }
}

struct SlotRowView: View {
    let slot: TimeSlot
    let entry: TimeEntry?

    private var isFilled: Bool {
        entry != nil
    }

    private var isPast: Bool {
        slot.end <= Date.now
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isPast && !isFilled ? .secondary : .primary)

                if let entry {
                    Text(entry.entryDescription)
                        .font(.body)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                } else if isPast {
                    Text("Tap to fill in")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .italic()
                } else {
                    Text("Upcoming")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if isFilled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if isPast {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .adaptiveGlass(
            tint: isFilled ? .green.opacity(0.15) : nil,
            isProminent: isPast || isFilled,
            in: .rect(cornerRadius: 12)
        )
    }
}
