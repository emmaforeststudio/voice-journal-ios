import SwiftData
import SwiftUI

struct SearchJournalView: View {
    @Query(sort: \JournalEntry.journalDate, order: .reverse) private var entries: [JournalEntry]
    @State private var query = ""
    @State private var useDateFilter = false
    @State private var filterDate = Date()

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Search title or journal", text: $query)
                        .textInputAutocapitalization(.never)

                    Toggle("Filter by date", isOn: $useDateFilter)
                    if useDateFilter {
                        DatePicker("Date", selection: $filterDate, displayedComponents: .date)
                    }
                }

                Section {
                    if filteredEntries.isEmpty {
                        ContentUnavailableView("No matching journals", systemImage: "magnifyingglass")
                    } else {
                        ForEach(filteredEntries) { entry in
                            NavigationLink {
                                EntryDetailView(entry: entry)
                            } label: {
                                JournalRow(entry: entry)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search")
        }
    }

    private var filteredEntries: [JournalEntry] {
        entries.filter { entry in
            let matchesQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                entry.title.localizedCaseInsensitiveContains(query) ||
                entry.body.localizedCaseInsensitiveContains(query)

            let matchesDate = !useDateFilter || calendar.isDate(entry.journalDate, inSameDayAs: filterDate)
            return matchesQuery && matchesDate
        }
    }
}
