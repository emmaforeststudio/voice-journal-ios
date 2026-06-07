import SwiftUI

struct ReviewDraftView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var journalBody: String
    @State private var journalDate: Date
    @State private var emoji: String
    private let language: JournalLanguage
    private let onSave: (JournalEntry) -> Void

    init(draft: JournalDraft, onSave: @escaping (JournalEntry) -> Void) {
        _title = State(initialValue: draft.title)
        _journalBody = State(initialValue: draft.body)
        _journalDate = State(initialValue: draft.journalDate)
        _emoji = State(initialValue: draft.emoji)
        language = draft.language
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    DatePicker("Date", selection: $journalDate, displayedComponents: .date)
                    EmojiSelector(selection: $emoji)
                }

                Section("Journal") {
                    TextEditor(text: $journalBody)
                        .frame(minHeight: 220)
                }
            }
            .navigationTitle("Review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let entry = JournalEntry(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Journal" : title,
                            body: journalBody.trimmingCharacters(in: .whitespacesAndNewlines),
                            journalDate: journalDate,
                            emoji: emoji,
                            language: language
                        )
                        onSave(entry)
                        dismiss()
                    }
                    .disabled(journalBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct EmojiSelector: View {
    @Binding var selection: String
    private let emojis = ["🙂", "😊", "🥲", "😌", "😔", "😤", "🥰", "🤔", "😴", "✨"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(emojis, id: \.self) { emoji in
                    Button {
                        selection = emoji
                    } label: {
                        Text(emoji)
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .background(selection == emoji ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityLabel("Emotion emoji")
    }
}
