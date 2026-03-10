import SwiftUI
import SwiftData

struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [TimeEntry]
    @Binding var selectedSlot: TimeSlot?
    @State private var selectedDate: Date = .now

    private var slots: [TimeSlot] {
        SlotManager.slotsForDate(selectedDate)
    }

    private var entriesBySlotStart: [Date: TimeEntry] {
        Dictionary(uniqueKeysWithValues: entries.compactMap { entry in
            (entry.slotStart, entry)
        })
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    /// The closest unfilled past slot, or the first upcoming slot if all past slots are filled
    private var closestOpenSlot: TimeSlot? {
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
                if let target = closestOpenSlot {
                    proxy.scrollTo(target.id, anchor: .center)
                }
            }
            .onChange(of: selectedDate) {
                if let target = closestOpenSlot {
                    proxy.scrollTo(target.id, anchor: .center)
                }
            }
        }
    }

    init(selectedSlot: Binding<TimeSlot?>) {
        _selectedSlot = selectedSlot
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
