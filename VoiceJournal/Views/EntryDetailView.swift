import SwiftData
import SwiftUI

struct EntryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("themeColorPreference") private var themeColorPreference = AppColorTheme.h1.rawValue
    @AppStorage("journalFontPreference") private var journalFontPreference = JournalFontPreference.standard.rawValue
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    @FocusState private var focusedField: Field?
    let entry: JournalEntry
    @State private var isEditing = false
    @State private var isRecordingMode = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingDatePicker = false
    @State private var isShowingContinuationRecorder = false
    @State private var draftTitle: String
    @State private var draftBody: String
    @State private var draftJournalDate: Date
    @State private var draftEmoji: String
    @State private var draftLanguage: JournalLanguage
    private let processor = JournalProcessor()

    init(entry: JournalEntry) {
        self.entry = entry
        _draftTitle = State(initialValue: entry.title)
        _draftBody = State(initialValue: entry.body)
        _draftJournalDate = State(initialValue: entry.journalDate)
        _draftEmoji = State(initialValue: entry.emoji)
        _draftLanguage = State(initialValue: entry.language)
    }

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
            .background(AppThemeBackground())
            .scrollDismissesKeyboard(.interactively)
        }
        .background(AppThemeBackground())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            bottomActionBar
        }
        .sheet(isPresented: $isShowingDatePicker) {
            NavigationStack {
                DatePicker("Journal Date", selection: $draftJournalDate, displayedComponents: [.date, .hourAndMinute])
                    .font(selectedFontDesignPreference.font(.body))
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
    }

    private var detailHeader: some View {
        HStack {
            Button {
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
                    Image("tab-create-microphone")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .frame(width: 34, height: 34)
                        .background(modeSelectionBackground(isRecordingMode))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose recording mode")

                Button {
                    beginEditing()
                } label: {
                    Image("icon-edit-text")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .frame(width: 34, height: 34)
                        .background(modeSelectionBackground(isEditing))
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
                Group {
                    if isEditing {
                        Image(systemName: "checkmark")
                            .font(.headline.weight(.semibold))
                    } else {
                        Image("icon-trash")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 21, height: 21)
                    }
                }
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
            TextField("Title", text: $draftTitle, axis: .vertical)
                .font(selectedFontDesignPreference.font(.title2, weight: .semibold))
                .textInputAutocapitalization(.sentences)
                .lineLimit(1...4)
                .focused($focusedField, equals: .title)
        } else {
            Text(draftTitle.isEmpty ? "Untitled Journal" : draftTitle)
                .font(selectedFontDesignPreference.font(.title2, weight: .semibold))
                .foregroundStyle(draftTitle.isEmpty ? .secondary : .primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var metadataRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                isShowingDatePicker = true
            } label: {
                Text(draftJournalDate.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()))
                    .font(selectedFontDesignPreference.font(.footnote))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            EmojiSelector(selection: $draftEmoji, itemSize: 32, font: selectedFontDesignPreference.font(.body))
                .frame(maxWidth: 210, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var bodyView: some View {
        if isEditing {
            TextEditor(text: $draftBody)
                .font(selectedFontPreference.editorFont(design: selectedFontDesignPreference))
                .frame(minHeight: 460)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, -5)
                .focused($focusedField, equals: .body)
        } else {
            Text(draftBody.isEmpty ? "No journal text yet." : draftBody)
                .font(selectedFontPreference.editorFont(design: selectedFontDesignPreference))
                .foregroundStyle(draftBody.isEmpty ? .secondary : .primary)
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
                Label {
                    Text(bottomPrimaryTitle)
                        .font(selectedFontDesignPreference.font(.body))
                } icon: {
                    Image(isRecordingMode ? "tab-create-microphone" : "icon-edit-text")
                }
                    .frame(width: 128)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Button {
                saveChanges()
                dismiss()
            } label: {
                Text("Save")
                    .font(selectedFontDesignPreference.font(.body))
                    .frame(width: 128)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private var selectedTheme: AppColorTheme {
        AppColorTheme.value(for: themeColorPreference)
    }

    private func modeSelectionBackground(_ isSelected: Bool) -> Color {
        guard isSelected else { return .clear }
        return selectedTheme.colorScheme == .dark ? selectedTheme.primaryColor : Color.white.opacity(0.90)
    }

    private func beginEditing() {
        isRecordingMode = false
        isEditing = true
        focusedField = .body
    }

    private func finishEditing() {
        focusedField = nil
        isEditing = false
    }

    private func saveChanges() {
        entry.title = draftTitle
        entry.body = draftBody
        entry.journalDate = draftJournalDate
        entry.emoji = draftEmoji
        entry.language = draftLanguage
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

        let existingBody = draftBody.trimmingCharacters(in: .whitespacesAndNewlines)
        draftBody = existingBody.isEmpty ? appendedText : "\(existingBody)\n\n\(appendedText)"
        if draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draftTitle == "Untitled Journal" {
            draftTitle = processor.makeTitle(from: draftBody, language: draft.language)
        }
        draftLanguage = draft.language
        draftEmoji = processor.moodEmoji(from: draftBody, language: draft.language)
        isRecordingMode = false
    }
}
