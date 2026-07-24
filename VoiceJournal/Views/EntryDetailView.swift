import SwiftData
import SwiftUI

struct EntryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("themeColorPreference") private var themeColorPreference = AppColorTheme.h1.rawValue
    @AppStorage("journalFontPreference") private var journalFontPreference = JournalFontPreference.standard.rawValue
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    @AppStorage("transcriptOutputMode") private var transcriptOutputMode = TranscriptOutputMode.asSpoken.rawValue
    @AppStorage("translationTargetLanguage") private var translationTargetLanguage = TranslationLanguage.english.rawValue
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
    @State private var originalTitle: String
    @State private var originalBody: String
    @State private var translatedTitle: String
    @State private var translatedBody: String
    @State private var selectedContentVersion: TranslatedContentVersion
    @State private var isTranslating = false
    @State private var translationError: String?
    @State private var suppressVersionSync = false
    private let processor = JournalProcessor()

    init(entry: JournalEntry) {
        self.entry = entry
        let savedVersion = TranslatedContentVersion(rawValue: entry.displayedVersionRawValue ?? "") ?? .original
        let savedOriginalTitle = entry.originalTitle ?? (savedVersion == .original ? entry.title : "")
        let savedOriginalBody = entry.originalBody ?? (savedVersion == .original ? entry.body : "")
        let savedTranslatedTitle = entry.translatedTitle ?? (savedVersion == .translated ? entry.title : "")
        let savedTranslatedBody = entry.translatedBody ?? (savedVersion == .translated ? entry.body : "")
        _draftTitle = State(initialValue: entry.title)
        _draftBody = State(initialValue: entry.body)
        _draftJournalDate = State(initialValue: entry.journalDate)
        _draftEmoji = State(initialValue: entry.emoji)
        _draftLanguage = State(initialValue: entry.language)
        _originalTitle = State(initialValue: savedOriginalTitle)
        _originalBody = State(initialValue: savedOriginalBody)
        _translatedTitle = State(initialValue: savedTranslatedTitle)
        _translatedBody = State(initialValue: savedTranslatedBody)
        _selectedContentVersion = State(initialValue: savedVersion)
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
                    if shouldShowVersionSwitcher {
                        versionSwitcher
                    }
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
        .onChange(of: draftTitle) { _, newValue in
            guard !suppressVersionSync else { return }
            if selectedContentVersion == .original {
                originalTitle = newValue
                invalidateTranslation()
            } else {
                translatedTitle = newValue
            }
        }
        .onChange(of: draftBody) { _, newValue in
            guard !suppressVersionSync else { return }
            if selectedContentVersion == .original {
                originalBody = newValue
                invalidateTranslation()
            } else {
                translatedBody = newValue
            }
        }
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
            TextField("Title", text: $draftTitle)
                .font(selectedFontDesignPreference.font(.title2, weight: .semibold))
                .textInputAutocapitalization(.sentences)
                .lineLimit(1)
                .focused($focusedField, equals: .title)
        } else {
            Text(draftTitle.isEmpty ? "Untitled Journal" : draftTitle)
                .font(selectedFontDesignPreference.font(.title2, weight: .semibold))
                .foregroundStyle(draftTitle.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private var versionSwitcher: some View {
        VStack(spacing: 8) {
            TranslatedContentSwitcher(
                selection: selectedContentVersion,
                translatedLabel: translationLanguage.compactDisplayName,
                isTranslating: isTranslating,
                translatedVersionAvailable: !translatedBody.isEmpty
            ) { version in
                selectContentVersion(version)
            }

            if let translationError {
                Text(translationError)
                    .font(selectedFontDesignPreference.font(.caption))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
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

    private var selectedTranscriptOutputMode: TranscriptOutputMode {
        TranscriptOutputMode.value(for: transcriptOutputMode)
    }

    private var translationLanguage: TranslationLanguage {
        TranslationLanguage.value(for: entry.translationLanguageRawValue ?? translationTargetLanguage)
    }

    private var shouldShowVersionSwitcher: Bool {
        !translatedBody.isEmpty || isTranslating
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
        storeActiveVersion()
        entry.title = draftTitle
        entry.body = draftBody
        entry.journalDate = draftJournalDate
        entry.emoji = draftEmoji
        entry.language = draftLanguage
        entry.originalTitle = originalTitle
        entry.originalBody = originalBody
        entry.translatedTitle = translatedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : translatedTitle
        entry.translatedBody = translatedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : translatedBody
        entry.translationLanguageRawValue = translatedBody.isEmpty ? nil : translationLanguage.rawValue
        entry.displayedVersionRawValue = selectedContentVersion.rawValue
        entry.updatedAt = .now
        try? modelContext.save()
    }

    private func selectRecordingMode() {
        focusedField = nil
        isEditing = false
        isRecordingMode = true
    }

    private func appendDraft(_ draft: JournalDraft) {
        storeActiveVersion()
        let appendedText = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appendedText.isEmpty else { return }

        let existingBody = originalBody.trimmingCharacters(in: .whitespacesAndNewlines)
        originalBody = existingBody.isEmpty ? appendedText : "\(existingBody)\n\n\(appendedText)"
        if originalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || originalTitle == "Untitled Journal" {
            originalTitle = processor.makeTitle(from: originalBody, language: draft.language)
        }
        draftLanguage = draft.language
        draftEmoji = processor.moodEmoji(from: originalBody, language: draft.language)
        translatedTitle = ""
        translatedBody = ""
        setDisplayedContent(title: originalTitle, body: originalBody, version: .original)
        isRecordingMode = false
        if selectedTranscriptOutputMode == .translate {
            Task {
                await prepareTranslation(selectTranslatedWhenReady: true)
            }
        }
    }

    private func selectContentVersion(_ version: TranslatedContentVersion) {
        guard version != selectedContentVersion else { return }
        storeActiveVersion()
        if version == .translated, translatedBody.isEmpty {
            Task {
                await prepareTranslation(selectTranslatedWhenReady: true)
            }
            return
        }
        let content = version == .original
            ? (originalTitle, originalBody)
            : (translatedTitle, translatedBody)
        setDisplayedContent(title: content.0, body: content.1, version: version)
    }

    private func storeActiveVersion() {
        if selectedContentVersion == .original {
            originalTitle = draftTitle
            originalBody = draftBody
        } else {
            translatedTitle = draftTitle
            translatedBody = draftBody
        }
    }

    private func setDisplayedContent(title: String, body: String, version: TranslatedContentVersion) {
        suppressVersionSync = true
        selectedContentVersion = version
        draftTitle = title
        draftBody = body
        Task { @MainActor in
            await Task.yield()
            suppressVersionSync = false
        }
    }

    private func invalidateTranslation() {
        translatedTitle = ""
        translatedBody = ""
        translationError = nil
    }

    @MainActor
    private func prepareTranslation(selectTranslatedWhenReady: Bool) async {
        guard translatedBody.isEmpty, !isTranslating else { return }
        storeActiveVersion()
        guard !originalBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isTranslating = true
        translationError = nil
        do {
            let translation = try await OpenAIJournalService().translate(
                title: originalTitle,
                body: originalBody,
                to: TranslationLanguage.value(for: translationTargetLanguage)
            )
            translatedTitle = translation.title
            translatedBody = translation.body
            if selectTranslatedWhenReady {
                setDisplayedContent(title: translatedTitle, body: translatedBody, version: .translated)
            }
        } catch {
            translationError = "Translation is unavailable right now. Your original is safe."
        }
        isTranslating = false
    }
}
