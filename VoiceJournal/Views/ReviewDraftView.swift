import SwiftUI

struct ReviewDraftView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var journalBody: String
    @State private var journalDate: Date
    @State private var emoji: String
    @State private var didManuallyChooseEmoji = false
    private let language: JournalLanguage
    private let notice: String?
    private let onSave: (JournalEntry) -> Void
    private let processor = JournalProcessor()

    init(draft: JournalDraft, onSave: @escaping (JournalEntry) -> Void) {
        _title = State(initialValue: draft.title)
        _journalBody = State(initialValue: draft.body)
        _journalDate = State(initialValue: draft.journalDate)
        _emoji = State(initialValue: draft.emoji)
        language = draft.language
        notice = draft.notice
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                if let notice {
                    Section {
                        Label(notice, systemImage: "exclamationmark.bubble")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Generated Title") {
                    Text(title)
                        .foregroundStyle(title == "Untitled Journal" ? .secondary : .primary)
                }

                Section {
                    DatePicker("Date", selection: $journalDate, displayedComponents: .date)
                    EmojiSelector(selection: $emoji) {
                        didManuallyChooseEmoji = true
                    }
                }

                Section("Transcribed Journal") {
                    TextEditor(text: $journalBody)
                        .frame(minHeight: 220)
                }
            }
            .navigationTitle("Review Text Journal")
            .onChange(of: journalBody) { _, newValue in
                title = processor.makeTitle(from: newValue, language: language)
                if !didManuallyChooseEmoji {
                    emoji = processor.moodEmoji(from: newValue, language: language)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let entry = JournalEntry(
                            title: title,
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
    var onSelect: (() -> Void)?
    private let emojis = JournalProcessor.supportedMoodEmojis

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(emojis, id: \.self) { emoji in
                    Button {
                        selection = emoji
                        onSelect?()
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
