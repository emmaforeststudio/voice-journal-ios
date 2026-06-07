import SwiftData
import SwiftUI

struct EntryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var entry: JournalEntry

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $entry.title)
                DatePicker("Date", selection: $entry.journalDate, displayedComponents: .date)
                EmojiSelector(selection: $entry.emoji)
            }

            Section("Journal") {
                TextEditor(text: $entry.body)
                    .frame(minHeight: 260)
            }

            Section {
                Button("Delete", role: .destructive) {
                    modelContext.delete(entry)
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
        .navigationTitle(entry.title.isEmpty ? "Journal" : entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            entry.updatedAt = .now
            try? modelContext.save()
        }
    }
}
