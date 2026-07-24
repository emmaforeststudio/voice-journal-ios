import SwiftUI

struct ReviewDraftView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("themeColorPreference") private var themeColorPreference = AppColorTheme.h1.rawValue
    @AppStorage("journalFontPreference") private var journalFontPreference = JournalFontPreference.standard.rawValue
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    @AppStorage("transcriptOutputMode") private var transcriptOutputMode = TranscriptOutputMode.asSpoken.rawValue
    @AppStorage("translationTargetLanguage") private var translationTargetLanguage = TranslationLanguage.english.rawValue
    @FocusState private var focusedField: Field?
    @State private var title: String
    @State private var journalBody: String
    @State private var journalDate: Date
    @State private var emoji: String
    @State private var didManuallyChooseEmoji = false
    @State private var isEditing = false
    @State private var isRecordingMode = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingDatePicker = false
    @State private var isShowingContinuationRecorder = false
    @State private var originalTitle: String
    @State private var originalBody: String
    @State private var translatedTitle = ""
    @State private var translatedBody = ""
    @State private var selectedContentVersion = TranslatedContentVersion.original
    @State private var isTranslating = false
    @State private var translationError: String?
    @State private var suppressAutomaticTitleUpdate = false
    private let language: JournalLanguage
    private let notice: String?
    private let onSave: (JournalEntry) -> Void
    private let processor = JournalProcessor()

    private enum Field {
        case title
        case body
    }

    init(
        draft: JournalDraft,
        onSave: @escaping (JournalEntry) -> Void
    ) {
        _title = State(initialValue: draft.title)
        _journalBody = State(initialValue: draft.body)
        _originalTitle = State(initialValue: draft.title)
        _originalBody = State(initialValue: draft.body)
        _journalDate = State(initialValue: draft.journalDate)
        _emoji = State(initialValue: draft.emoji)
        language = draft.language
        notice = draft.notice
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                reviewHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let notice {
                            Label(notice, systemImage: "exclamationmark.bubble")
                                .font(selectedFontDesignPreference.font(.caption))
                                .foregroundStyle(.secondary)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                        }

                        titleView
                        metadataRow
                        if shouldShowVersionSwitcher {
                            versionSwitcher
                        }
                        Divider()
                        journalBodyView
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    .padding(.bottom, 92)
                }
                .background(AppThemeBackground())
                .scrollDismissesKeyboard(.interactively)
            }
            .background(AppThemeBackground())
            .onChange(of: title) { _, newValue in
                guard !suppressAutomaticTitleUpdate else { return }
                if selectedContentVersion == .original {
                    originalTitle = newValue
                    invalidateTranslation()
                } else {
                    translatedTitle = newValue
                }
            }
            .onChange(of: journalBody) { _, newValue in
                guard !suppressAutomaticTitleUpdate else { return }
                if selectedContentVersion == .original {
                    originalBody = newValue
                    invalidateTranslation()
                    title = processor.makeTitle(from: newValue, language: language)
                    if !didManuallyChooseEmoji {
                        emoji = processor.moodEmoji(from: newValue, language: language)
                    }
                } else {
                    translatedBody = newValue
                }
            }
            .task {
                await prepareTranslationIfNeeded(selectTranslatedWhenReady: true)
            }
            .safeAreaInset(edge: .bottom) {
                bottomActionBar
            }
            .sheet(isPresented: $isShowingDatePicker) {
                NavigationStack {
                DatePicker("Journal Date", selection: $journalDate, displayedComponents: [.date, .hourAndMinute])
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
            .confirmationDialog("Delete this draft?", isPresented: $isShowingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Draft", role: .destructive) {
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This recording has not been saved yet.")
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private var reviewHeader: some View {
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

            modeSwitcher

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
            .accessibilityLabel(isEditing ? "Finish editing" : "Delete draft")
        }
        .padding(.horizontal, 24)
        .padding(.top, 0)
        .padding(.bottom, 8)
    }

    private var modeSwitcher: some View {
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
            .font(selectedFontDesignPreference.font(.title3))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.10))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var titleView: some View {
        if isEditing {
            TextField("Title", text: $title)
                .font(selectedFontDesignPreference.font(.title2, weight: .semibold))
                .textInputAutocapitalization(.sentences)
                .foregroundStyle(title == "Untitled Journal" ? .secondary : .primary)
                .lineLimit(1)
                .focused($focusedField, equals: .title)
        } else {
            Text(title.isEmpty ? "Untitled Journal" : title)
                .font(selectedFontDesignPreference.font(.title2, weight: .semibold))
                .foregroundStyle(title == "Untitled Journal" ? .secondary : .primary)
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
                Text(journalDate.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()))
                    .font(selectedFontDesignPreference.font(.footnote))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            EmojiSelector(selection: $emoji, itemSize: 32, font: selectedFontDesignPreference.font(.body)) {
                didManuallyChooseEmoji = true
            }
            .frame(maxWidth: 210, alignment: .trailing)
        }
    }

    private var versionSwitcher: some View {
        VStack(spacing: 8) {
            TranslatedContentSwitcher(
                selection: selectedContentVersion,
                translatedLabel: selectedTranslationLanguage.compactDisplayName,
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
    private var journalBodyView: some View {
        if isEditing {
            TextEditor(text: $journalBody)
                .font(selectedFontPreference.editorFont(design: selectedFontDesignPreference))
                .frame(minHeight: 460)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, -5)
                .focused($focusedField, equals: .body)
        } else {
            Text(journalBody.isEmpty ? "No journal text yet." : journalBody)
                .font(selectedFontPreference.editorFont(design: selectedFontDesignPreference))
                .foregroundStyle(journalBody.isEmpty ? .secondary : .primary)
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
                saveDraft()
            } label: {
                Text("Save")
                    .font(selectedFontDesignPreference.font(.body))
                    .frame(width: 128)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(journalBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private var selectedTranslationLanguage: TranslationLanguage {
        TranslationLanguage.value(for: translationTargetLanguage)
    }

    private var shouldShowVersionSwitcher: Bool {
        selectedTranscriptOutputMode == .translate || !translatedBody.isEmpty
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
        originalTitle = processor.makeTitle(from: originalBody, language: language)
        translatedTitle = ""
        translatedBody = ""
        setDisplayedContent(title: originalTitle, body: originalBody, version: .original)
        isRecordingMode = false
        Task {
            await prepareTranslationIfNeeded(selectTranslatedWhenReady: true)
        }
    }

    private func saveDraft() {
        storeActiveVersion()
        let entry = JournalEntry(
            title: title,
            body: journalBody.trimmingCharacters(in: .whitespacesAndNewlines),
            journalDate: journalDate,
            emoji: emoji,
            language: language,
            originalTitle: originalTitle,
            originalBody: originalBody,
            translatedTitle: translatedTitle.nilIfEmpty,
            translatedBody: translatedBody.nilIfEmpty,
            translationLanguage: translatedBody.isEmpty ? nil : selectedTranslationLanguage,
            displayedVersion: selectedContentVersion
        )
        onSave(entry)
        dismiss()
    }

    private func selectContentVersion(_ version: TranslatedContentVersion) {
        guard version != selectedContentVersion else { return }
        storeActiveVersion()
        if version == .translated, translatedBody.isEmpty {
            Task {
                await prepareTranslationIfNeeded(selectTranslatedWhenReady: true)
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
            originalTitle = title
            originalBody = journalBody
        } else {
            translatedTitle = title
            translatedBody = journalBody
        }
    }

    private func invalidateTranslation() {
        translatedTitle = ""
        translatedBody = ""
        translationError = nil
    }

    private func setDisplayedContent(title: String, body: String, version: TranslatedContentVersion) {
        suppressAutomaticTitleUpdate = true
        selectedContentVersion = version
        self.title = title
        journalBody = body
        Task { @MainActor in
            await Task.yield()
            suppressAutomaticTitleUpdate = false
        }
    }

    @MainActor
    private func prepareTranslationIfNeeded(selectTranslatedWhenReady: Bool) async {
        guard selectedTranscriptOutputMode == .translate, translatedBody.isEmpty, !isTranslating else { return }
        storeActiveVersion()
        guard !originalBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isTranslating = true
        translationError = nil
        do {
            let translation = try await OpenAIJournalService().translate(
                title: originalTitle,
                body: originalBody,
                to: selectedTranslationLanguage
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

struct TranslatedContentSwitcher: View {
    let selection: TranslatedContentVersion
    let translatedLabel: String
    let isTranslating: Bool
    let translatedVersionAvailable: Bool
    let onSelect: (TranslatedContentVersion) -> Void
    @AppStorage("themeColorPreference") private var themeColorPreference = AppColorTheme.h1.rawValue

    var body: some View {
        HStack(spacing: 0) {
            option(title: "Original", version: .original, isEnabled: true)
            option(
                title: translatedLabel,
                version: .translated,
                isEnabled: translatedVersionAvailable || !isTranslating
            )
        }
        .padding(2)
        .frame(maxWidth: 270)
        .background(selectedTheme.primaryColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .frame(maxWidth: .infinity)
    }

    private func option(title: String, version: TranslatedContentVersion, isEnabled: Bool) -> some View {
        Button {
            onSelect(version)
        } label: {
            Group {
                if version == .translated && isTranslating && !translatedVersionAvailable {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(selection == version ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background {
                if selection == version {
                    AppThemeCardBackground()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityAddTraits(selection == version ? .isSelected : [])
    }

    private var selectedTheme: AppColorTheme {
        AppColorTheme.value(for: themeColorPreference)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct EmojiSelector: View {
    @Binding var selection: String
    var itemSize: CGFloat = 44
    var font: Font = .title2
    var onSelect: (() -> Void)?
    private let emojis = JournalProcessor.supportedMoodEmojis

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(emojis, id: \.self) { emoji in
                    Button {
                        selection = emoji
                        onSelect?()
                    } label: {
                        Text(emoji)
                            .font(font)
                            .frame(width: itemSize, height: itemSize)
                            .background(selection == emoji ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: itemSize * 0.28))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityLabel("Emotion emoji")
    }
}

struct ContinuationRecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("showLivePreview") private var showLivePreview = false
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    @StateObject private var viewModel = RecorderViewModel()
    @State private var didStartRecording = false
    @State private var isFinishingRecording = false
    let onComplete: (JournalDraft) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack(alignment: .bottom) {
                AppThemeBackground()

                ScrollView {
                    VStack(spacing: 0) {
                        Text("Continue Journal")
                            .font(selectedContinuationFontDesignPreference.font(.title2, weight: .bold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 18)

                        if showLivePreview {
                            livePreviewContent
                                .padding(.top, 18)
                        }

                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(selectedContinuationFontDesignPreference.font(.callout))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 18)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if viewModel.isProcessing {
                            if let limitReason = viewModel.processingLimitReason {
                                RecordingLimitProcessingBanner(
                                    reason: limitReason,
                                    contentName: "journal",
                                    fontDesign: selectedContinuationFontDesignPreference
                                )
                                .padding(.top, 22)
                            } else {
                                ProgressView("Adding to your journal")
                                    .font(selectedContinuationFontDesignPreference.font(.body))
                                    .padding(.top, 22)
                            }
                        }
                    }
                    .padding(.bottom, 220)
                }

                VStack(spacing: 18) {
                    Text(viewModel.formattedRecordingDuration)
                        .font(.system(.title2, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.red)

                    Button {
                        if viewModel.isRecording {
                            isFinishingRecording = true
                            viewModel.stopRecording()
                        } else if !viewModel.isProcessing {
                            isFinishingRecording = false
                            viewModel.startRecording()
                        }
                    } label: {
                        ContinuationWaveformRecordButton(
                            isRecording: viewModel.isRecording,
                            isProcessing: viewModel.isProcessing,
                            isFinishingRecording: isFinishingRecording,
                            level: viewModel.microphoneLevel,
                            hasDetectedAudio: viewModel.hasDetectedAudio
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isProcessing || viewModel.isStartingRecording)
                    .accessibilityLabel(viewModel.isRecording ? "Stop recording" : "Start recording")
                }
                .padding(.bottom, 10)
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppThemeBackground())
        .task {
            guard !didStartRecording else { return }
            didStartRecording = true
            viewModel.updateLivePreviewEnabled(showLivePreview)
            viewModel.startRecording()
        }
        .onChange(of: showLivePreview) { _, newValue in
            viewModel.updateLivePreviewEnabled(newValue)
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            if newValue != nil {
                isFinishingRecording = false
            }
        }
        .onChange(of: viewModel.draft?.id) { _, _ in
            guard let draft = viewModel.draft else { return }
            onComplete(draft)
            viewModel.draft = nil
            dismiss()
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private var header: some View {
        HStack {
            Button {
                if viewModel.isRecording {
                    viewModel.cancelRecording()
                }
                onCancel()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(AppThemeCardBackground())
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 0)
        .padding(.bottom, 8)
    }

    private var livePreviewContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live Preview")
                .font(selectedContinuationFontDesignPreference.font(.caption, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(livePreviewText)
                .font(selectedContinuationFontDesignPreference.font(.body))
                .foregroundStyle(viewModel.liveTranscript.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var livePreviewText: String {
        viewModel.liveTranscript.isEmpty
            ? viewModel.livePreviewNotice ?? "Listening... this continuation will be added to the current journal."
            : viewModel.liveTranscript
    }

    private var selectedContinuationFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }
}

private struct ContinuationWaveformRecordButton: View {
    let isRecording: Bool
    let isProcessing: Bool
    let isFinishingRecording: Bool
    let level: Float
    let hasDetectedAudio: Bool

    var body: some View {
        TimelineView(.animation) { context in
            if isRecording || isProcessing || isFinishingRecording {
                let time = context.date.timeIntervalSinceReferenceDate

                HStack(spacing: 5) {
                    ForEach(0..<7, id: \.self) { index in
                        Capsule()
                            .fill(.white)
                            .frame(width: 6, height: barHeight(index: index, time: time))
                            .animation(.easeInOut(duration: 0.18), value: level)
                    }
                }
                .frame(width: 106, height: 106)
                .background(Color.red)
                .clipShape(Circle())
                .shadow(color: Color.red.opacity(0.18), radius: 18, y: 10)
            } else {
                Image("tab-create-microphone")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .frame(width: 106, height: 106)
                    .foregroundStyle(.white)
                    .background(Color.accentColor)
                    .clipShape(Circle())
                    .shadow(color: Color.accentColor.opacity(0.18), radius: 18, y: 10)
            }
        }
    }

    private func barHeight(index: Int, time: TimeInterval) -> CGFloat {
        let normalizedLevel = hasDetectedAudio ? min(max(CGFloat(level) * 30, 0.22), 1) : 0.14
        let phase = CGFloat(sin((time * 8) + Double(index) * 0.74))
        let wave = hasDetectedAudio ? (phase + 1) / 2 : 0.18
        let base: CGFloat = 16
        let spread: CGFloat = 48
        return base + spread * normalizedLevel * (0.36 + wave * 0.64)
    }
}
