import SwiftData
import SwiftUI

struct CalendarJournalView: View {
    @Query(sort: \JournalEntry.journalDate, order: .reverse) private var entries: [JournalEntry]
    @State private var visibleMonth = Date()
    @State private var selectedDate = Date()

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    private let processor = JournalProcessor()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    monthHeader
                    weekdayHeader
                    monthGrid
                    selectedEntries
                }
                .padding()
            }
            .navigationTitle("Journal")
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                visibleMonth = calendar.date(byAdding: .month, value: -1, to: visibleMonth) ?? visibleMonth
            } label: {
                Image(systemName: "chevron.left")
            }

            Spacer()

            Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
                .font(.title3.bold())

            Spacer()

            Button {
                visibleMonth = calendar.date(byAdding: .month, value: 1, to: visibleMonth) ?? visibleMonth
            } label: {
                Image(systemName: "chevron.right")
            }
        }
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(calendar.shortWeekdaySymbols, id: \.self) { day in
                Text(day)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(monthDays, id: \.self) { date in
                if let date {
                    CalendarDayCell(
                        date: date,
                        isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                        emoji: emoji(on: date)
                    )
                    .onTapGesture {
                        selectedDate = date
                    }
                } else {
                    Color.clear
                        .frame(height: 54)
                }
            }
        }
    }

    private var selectedEntries: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedDate.formatted(.dateTime.weekday(.wide).month().day()))
                .font(.headline)

            let dayEntries = entries(on: selectedDate)
            if dayEntries.isEmpty {
                ContentUnavailableView("No journals", systemImage: "book.closed", description: Text("Record or write a journal for this day."))
            } else {
                ForEach(dayEntries) { entry in
                    NavigationLink {
                        EntryDetailView(entry: entry)
                    } label: {
                        JournalRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var monthDays: [Date?] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth),
            let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end.addingTimeInterval(-1))
        else {
            return []
        }

        var dates: [Date?] = []
        var cursor = firstWeek.start
        while cursor < lastWeek.end {
            dates.append(calendar.isDate(cursor, equalTo: monthInterval.start, toGranularity: .month) ? cursor : nil)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(86_400)
        }
        return dates
    }

    private func entries(on date: Date) -> [JournalEntry] {
        entries.filter { calendar.isDate($0.journalDate, inSameDayAs: date) }
    }

    private func emoji(on date: Date) -> String? {
        processor.dailyMoodEmoji(from: entries(on: date).map(\.emoji))
    }
}

struct CalendarDayCell: View {
    let date: Date
    let isSelected: Bool
    let emoji: String?

    var body: some View {
        VStack(spacing: 4) {
            Text(date.formatted(.dateTime.day()))
                .font(.callout.weight(isSelected ? .bold : .regular))
            Text(emoji ?? "")
                .font(.caption)
                .lineLimit(1)
                .frame(height: 14)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct JournalRow: View {
    let entry: JournalEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.emoji)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(entry.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding()
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
