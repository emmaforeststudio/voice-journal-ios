import SwiftData
import SwiftUI

struct EntryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("journalFontPreference") private var journalFontPreference = JournalFontPreference.standard.rawValue
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    @FocusState private var focusedField: Field?
    @Bindable var entry: JournalEntry
    @State private var isEditing = false
    @State private var isRecordingMode = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingDatePicker = false
    @State private var isShowingContinuationRecorder = false
    private let processor = JournalProcessor()

    private enum Field {
        case title
        case body
    }

    var body: some View {
        VStack(spacing: 0) {
            detailHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleView
                    metadataRow
                    Divider()
                    bodyView
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, 92)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            bottomActionBar
        }
        .sheet(isPresented: $isShowingDatePicker) {
            NavigationStack {
                DatePicker("Journal Date", selection: $entry.journalDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Date & Time")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                isShowingDatePicker = false
                            }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $isShowingContinuationRecorder) {
            ContinuationRecordingView { draft in
                appendDraft(draft)
                isShowingContinuationRecorder = false
            } onCancel: {
                isShowingContinuationRecorder = false
            }
        }
        .confirmationDialog("Delete this journal?", isPresented: $isShowingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Journal", role: .destructive) {
                modelContext.delete(entry)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .onDisappear {
            entry.updatedAt = .now
            try? modelContext.save()
        }
    }

    private var detailHeader: some View {
        HStack {
            Button {
                saveChanges()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(Color.secondary.opacity(0.10))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer()

            HStack(spacing: 6) {
                Button {
                    selectRecordingMode()
                } label: {
                    Image(systemName: "mic")
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(isRecordingMode ? 0.90 : 0))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose recording mode")

                Button {
                    beginEditing()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(isEditing ? 0.90 : 0.72))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit journal")
            }
            .font(.title3)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.10))
            .clipShape(Capsule())

            Spacer()

            Button(role: isEditing ? nil : .destructive) {
                if isEditing {
                    finishEditing()
                } else {
                    isShowingDeleteConfirmation = true
                }
            } label: {
                Image(systemName: isEditing ? "checkmark" : "trash")
                    .font(.headline.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background((isEditing ? Color.accentColor : Color.red).opacity(0.10))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isEditing ? "Finish editing" : "Delete journal")
        }
        .padding(.horizontal, 24)
        .padding(.top, 0)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var titleView: some View {
        if isEditing {
            TextField("Title", text: $entry.title, axis: .vertical)
                .font(.title2.weight(.semibold))
                .textInputAutocapitalization(.sentences)
                .lineLimit(1...4)
                .focused($focusedField, equals: .title)
        } else {
            Text(entry.title.isEmpty ? "Untitled Journal" : entry.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(entry.title.isEmpty ? .secondary : .primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var metadataRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                isShowingDatePicker = true
            } label: {
                Text(entry.journalDate.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            EmojiSelector(selection: $entry.emoji, itemSize: 32, font: .body)
                .frame(maxWidth: 210, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var bodyView: some View {
        if isEditing {
            TextEditor(text: $entry.body)
                .font(selectedFontPreference.editorFont(design: selectedFontDesignPreference))
                .frame(minHeight: 460)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, -5)
                .focused($focusedField, equals: .body)
        } else {
            Text(entry.body.isEmpty ? "No journal text yet." : entry.body)
                .font(selectedFontPreference.editorFont(design: selectedFontDesignPreference))
                .foregroundStyle(entry.body.isEmpty ? .secondary : .primary)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
                .onTapGesture {
                    beginEditing()
                }
        }
    }

    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            Button {
                if isRecordingMode {
                    focusedField = nil
                    isShowingContinuationRecorder = true
                } else {
                    beginEditing()
                }
            } label: {
                Label(bottomPrimaryTitle, systemImage: isRecordingMode ? "mic.fill" : "pencil")
                    .frame(width: 128)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Button {
                saveChanges()
                dismiss()
            } label: {
                Text("Save")
                    .frame(width: 128)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(entry.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var bottomPrimaryTitle: String {
        if isRecordingMode {
            "Recording"
        } else if isEditing {
            "Editing"
        } else {
            "Edit"
        }
    }

    private var selectedFontPreference: JournalFontPreference {
        JournalFontPreference.value(for: journalFontPreference)
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }

    private func beginEditing() {
        isRecordingMode = false
        isEditing = true
        focusedField = .body
    }

    private func finishEditing() {
        focusedField = nil
        isEditing = false
        saveChanges()
    }

    private func saveChanges() {
        entry.updatedAt = .now
        try? modelContext.save()
    }

    private func selectRecordingMode() {
        focusedField = nil
        isEditing = false
        isRecordingMode = true
    }

    private func appendDraft(_ draft: JournalDraft) {
        let appendedText = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appendedText.isEmpty else { return }

        let existingBody = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.body = existingBody.isEmpty ? appendedText : "\(existingBody)\n\n\(appendedText)"
        if entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || entry.title == "Untitled Journal" {
            entry.title = processor.makeTitle(from: entry.body, language: draft.language)
        }
        entry.language = draft.language
        entry.emoji = processor.moodEmoji(from: entry.body, language: draft.language)
        isRecordingMode = false
        saveChanges()
    }
}
