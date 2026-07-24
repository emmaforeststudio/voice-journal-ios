import SwiftData
import SwiftUI

struct CalendarJournalView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("importantJournalEntryIDs") private var importantJournalEntryIDs = ""
    @AppStorage("themeColorPreference") private var themeColorPreference = AppColorTheme.h1.rawValue
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    @Query(sort: \JournalEntry.journalDate, order: .reverse) private var entries: [JournalEntry]
    let resetToken: Int
    @State private var visibleMonth = Date()
    @State private var selectedDate = Date()
    @State private var query = ""
    @State private var isSearchActive = false
    @State private var selectedEntry: JournalEntry?
    @State private var renderedFontPreference = JournalFontPreference.current.rawValue

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 7)
    private let processor = JournalProcessor()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    calendarHeader

                    if isSearchActive {
                        searchField
                        searchResults
                    } else {
                        weekdayHeader
                        monthGrid
                        selectedEntries
                    }
                }
                .id(renderedFontPreference)
                .padding()
            }
            .background(AppThemeBackground())
            .navigationDestination(item: $selectedEntry) { entry in
                EntryDetailView(entry: entry)
            }
            .onAppear {
                refreshRenderedFontPreference()
            }
            .onChange(of: resetToken) { _, _ in
                resetToMainCalendar()
            }
        }
        .background(AppThemeBackground())
    }

    private func resetToMainCalendar() {
        query = ""
        isSearchActive = false
        selectedEntry = nil
    }

    private func refreshRenderedFontPreference() {
        renderedFontPreference = JournalFontPreference.current.rawValue
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search title or journal", text: $query)
                .font(selectedFontDesignPreference.font(.body))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppThemeCardBackground())
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder
    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(trimmedQuery.isEmpty ? "All Journals" : "Search Results")
                .font(selectedFontDesignPreference.font(.headline))

            if searchEntries.isEmpty {
                AppUnavailableView(
                    title: trimmedQuery.isEmpty ? "No journals" : "No matching journals",
                    systemImage: trimmedQuery.isEmpty ? "book.closed" : "magnifyingglass",
                    description: trimmedQuery.isEmpty ? "Record or write a journal to begin." : "Try a different title or phrase.",
                    size: trimmedQuery.isEmpty ? .prominent : .standard
                )
            } else {
                ForEach(searchEntries) { entry in
                    SwipeableJournalRow(
                        entry: entry,
                        isImportant: isImportant(entry),
                        openEntry: openEntry,
                        deleteEntry: deleteEntry,
                        toggleImportant: toggleImportant
                    )
                }
            }
        }
    }

    private var calendarHeader: some View {
        HStack {
            Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
                .font(selectedFontDesignPreference.font(.title2, weight: .bold))

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isSearchActive {
                        query = ""
                    }
                    isSearchActive.toggle()
                }
            } label: {
                Image(systemName: isSearchActive ? "xmark" : "magnifyingglass")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .background(AppThemeCardBackground())
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSearchActive ? "Close search" : "Search journals")
        }
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(calendar.shortWeekdaySymbols, id: \.self) { day in
                Text(day)
                    .font(selectedFontDesignPreference.font(.caption, weight: .semibold))
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
        .gesture(
            DragGesture(minimumDistance: 28)
                .onEnded { value in
                    handleMonthSwipe(value.translation.width)
                }
        )
    }

    private var selectedEntries: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text(displayedSelectedDate.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(selectedFontDesignPreference.font(.headline))

                Spacer()

                if shouldShowTodayShortcut {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDate = Date()
                            visibleMonth = Date()
                        }
                    } label: {
                        Text("Tap to today")
                            .font(selectedFontDesignPreference.font(.caption, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(calendarShortcutBackground)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Go to today's date")
                }
            }

            let dayEntries = entries(on: displayedSelectedDate)
            if dayEntries.isEmpty {
                AppUnavailableView(
                    title: "No journals",
                    systemImage: "book.closed",
                    description: "Record or write a journal for this day.",
                    size: .prominent
                )
            } else {
                ForEach(dayEntries) { entry in
                    SwipeableJournalRow(
                        entry: entry,
                        isImportant: isImportant(entry),
                        openEntry: openEntry,
                        deleteEntry: deleteEntry,
                        toggleImportant: toggleImportant
                    )
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
        guard calendar.isDate(date, equalTo: visibleMonth, toGranularity: .month) else {
            return []
        }
        return entries.filter { calendar.isDate($0.journalDate, inSameDayAs: date) }
    }

    private var displayedSelectedDate: Date {
        if calendar.isDate(selectedDate, equalTo: visibleMonth, toGranularity: .month) {
            return selectedDate
        }
        return calendar.dateInterval(of: .month, for: visibleMonth)?.start ?? visibleMonth
    }

    private var shouldShowTodayShortcut: Bool {
        !calendar.isDateInToday(selectedDate) || !calendar.isDate(visibleMonth, equalTo: Date(), toGranularity: .month)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }

    private var selectedTheme: AppColorTheme {
        AppColorTheme.value(for: themeColorPreference)
    }

    private var calendarShortcutBackground: Color {
        Color.accentColor.opacity(selectedTheme.colorScheme == .dark ? 0.44 : 0.26)
    }

    private var searchEntries: [JournalEntry] {
        let matches: [JournalEntry]
        if trimmedQuery.isEmpty {
            matches = entries
        } else {
            matches = entries.filter { entry in
                entry.title.localizedCaseInsensitiveContains(trimmedQuery) ||
                    entry.body.localizedCaseInsensitiveContains(trimmedQuery)
            }
        }
        return matches.sorted { $0.journalDate > $1.journalDate }
    }

    private func emoji(on date: Date) -> String? {
        processor.dailyMoodEmoji(from: entries(on: date).map(\.emoji))
    }

    private func handleMonthSwipe(_ horizontalTranslation: CGFloat) {
        guard abs(horizontalTranslation) > 44 else { return }
        let monthDelta = horizontalTranslation < 0 ? 1 : -1
        withAnimation(.easeInOut(duration: 0.22)) {
            let newMonth = calendar.date(byAdding: .month, value: monthDelta, to: visibleMonth) ?? visibleMonth
            visibleMonth = newMonth
            selectedDate = preferredSelectedDate(in: newMonth)
        }
    }

    private func preferredSelectedDate(in month: Date) -> Date {
        if calendar.isDate(month, equalTo: Date(), toGranularity: .month) {
            return Date()
        }
        return calendar.dateInterval(of: .month, for: month)?.start ?? month
    }

    private func deleteEntry(_ entry: JournalEntry) {
        modelContext.delete(entry)
        removeImportantID(entry.id)
        try? modelContext.save()
    }

    private func openEntry(_ entry: JournalEntry) {
        selectedEntry = entry
    }

    private func toggleImportant(_ entry: JournalEntry) {
        var ids = importantIDs
        let id = entry.id.uuidString
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        importantJournalEntryIDs = ids.sorted().joined(separator: ",")
    }

    private func isImportant(_ entry: JournalEntry) -> Bool {
        importantIDs.contains(entry.id.uuidString)
    }

    private var importantIDs: Set<String> {
        Set(
            importantJournalEntryIDs
                .split(separator: ",")
                .map(String.init)
        )
    }

    private func removeImportantID(_ id: UUID) {
        var ids = importantIDs
        ids.remove(id.uuidString)
        importantJournalEntryIDs = ids.sorted().joined(separator: ",")
    }
}

struct CalendarDayCell: View {
    @AppStorage("themeColorPreference") private var themeColorPreference = AppColorTheme.h1.rawValue
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    let date: Date
    let isSelected: Bool
    let emoji: String?

    var body: some View {
        VStack(spacing: 4) {
            Text(date.formatted(.dateTime.day()))
                .font(selectedFontDesignPreference.font(.callout, weight: isSelected ? .bold : .regular))
            Text(emoji ?? "")
                .font(selectedFontDesignPreference.font(.caption))
                .lineLimit(1)
                .frame(height: 14)
        }
        .frame(width: 42, height: 54)
        .background {
            if isSelected {
                selectedDateBackground
            } else {
                AppThemeCardBackground()
            }
        }
        .foregroundStyle(isSelected && selectedTheme.colorScheme == .dark ? Color.white : Color.primary)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .frame(maxWidth: .infinity)
    }

    private var selectedTheme: AppColorTheme {
        AppColorTheme.value(for: themeColorPreference)
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }

    private var selectedDateBackground: Color {
        selectedTheme.colorScheme == .dark ? selectedTheme.primaryColor.opacity(0.88) : Color.accentColor.opacity(0.26)
    }
}

struct JournalRow: View {
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    let entry: JournalEntry
    let isImportant: Bool
    private let trailingColumnWidth: CGFloat = 38

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Text(entry.title)
                        .font(selectedFontDesignPreference.font(.headline))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(entry.emoji)
                    .font(.title2)
                    .frame(width: trailingColumnWidth, alignment: .trailing)
                    .accessibilityHidden(true)
            }

            Text(entry.body)
                .font(selectedFontPreference.rowBodyFont(design: selectedFontDesignPreference))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppThemeCardBackground())
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(alignment: .topTrailing) {
            if isImportant {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                    .frame(width: trailingColumnWidth, alignment: .center)
                    .offset(x: 5.5)
                    .padding(.top, -1)
                    .padding(.trailing, 16)
                    .accessibilityLabel("Important")
            }
        }
    }

    private var selectedFontPreference: JournalFontPreference {
        JournalFontPreference.current
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }
}

private struct SwipeableJournalRow: View {
    let entry: JournalEntry
    let isImportant: Bool
    let openEntry: (JournalEntry) -> Void
    let deleteEntry: (JournalEntry) -> Void
    let toggleImportant: (JournalEntry) -> Void
    @State private var horizontalOffset: CGFloat = 0
    @State private var restingOffset: CGFloat = 0
    @State private var didDrag = false
    @State private var rowHeight: CGFloat = 76
    @State private var activeDragAxis: DragAxis?

    private let actionWidth: CGFloat = 86

    private enum DragAxis {
        case horizontal
        case vertical
    }

    var body: some View {
        ZStack(alignment: horizontalOffset >= 0 ? .leading : .trailing) {
            if horizontalOffset > 0 {
                bookmarkAction
                    .opacity(min(Double(horizontalOffset / actionWidth), 1))
            } else if horizontalOffset < 0 {
                deleteAction
                    .opacity(min(Double(abs(horizontalOffset) / actionWidth), 1))
            }

            JournalRow(entry: entry, isImportant: isImportant)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                rowHeight = proxy.size.height
                            }
                            .onChange(of: proxy.size.height) { _, newValue in
                                rowHeight = newValue
                            }
                    }
                )
                .offset(x: horizontalOffset)
                .contentShape(RoundedRectangle(cornerRadius: 24))
                .onTapGesture {
                    if horizontalOffset >= actionWidth * 0.9 {
                        toggleImportant(entry)
                        closeActions()
                    } else if horizontalOffset <= -actionWidth * 0.9 {
                        deleteEntry(entry)
                    } else if horizontalOffset == 0, !didDrag {
                        openEntry(entry)
                    } else {
                        closeActions()
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 18)
                        .onChanged { value in
                            if activeDragAxis == nil {
                                activeDragAxis = abs(value.translation.width) > abs(value.translation.height) * 1.35 ? .horizontal : .vertical
                            }

                            guard activeDragAxis == .horizontal else { return }
                            didDrag = true
                            let proposedOffset = restingOffset + value.translation.width
                            horizontalOffset = min(max(proposedOffset, -actionWidth), actionWidth)
                        }
                        .onEnded { value in
                            defer {
                                activeDragAxis = nil
                            }

                            guard activeDragAxis == .horizontal else {
                                didDrag = false
                                return
                            }

                            let proposedOffset = restingOffset + value.translation.width
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                                if proposedOffset > actionWidth * 0.58 {
                                    horizontalOffset = actionWidth
                                } else if proposedOffset < -actionWidth * 0.58 {
                                    horizontalOffset = -actionWidth
                                } else {
                                    horizontalOffset = 0
                                }
                                restingOffset = horizontalOffset
                            }
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(160))
                                didDrag = false
                            }
                        }
                )
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var bookmarkAction: some View {
        Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                toggleImportant(entry)
                closeActions()
            }
        } label: {
            Image(systemName: isImportant ? "bookmark.slash" : "bookmark")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: actionWidth, height: rowHeight)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isImportant ? "Unmark important" : "Mark important")
    }

    private var deleteAction: some View {
        Button(role: .destructive) {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                deleteEntry(entry)
            }
        } label: {
            Image("icon-trash")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 21, height: 21)
                .foregroundStyle(.white)
                .frame(width: actionWidth, height: rowHeight)
                .background(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete journal")
    }

    private func closeActions() {
        horizontalOffset = 0
        restingOffset = 0
    }
}
