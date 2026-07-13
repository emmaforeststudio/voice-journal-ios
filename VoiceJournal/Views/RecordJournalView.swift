import SwiftData
import SwiftUI

struct RecordJournalView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("profileDisplayName") private var profileDisplayName = ""
    @AppStorage("showLivePreview") private var showLivePreview = true
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    @StateObject private var viewModel = RecorderViewModel()
    @State private var renderedFontPreference = JournalFontPreference.current.rawValue
    @State private var createPrompt = "What's on your mind today?"
    let onSaved: () -> Void

    init(onSaved: @escaping () -> Void = {}) {
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppThemeBackground()

                Group {
                    if viewModel.isRecording {
                        recordingLayout
                    } else {
                        idleLayout
                    }
                }
                .id(renderedFontPreference)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .task {
                viewModel.prepareForRecording()
                viewModel.updateLivePreviewEnabled(showLivePreview)
            }
            .onAppear {
                refreshRenderedFontPreference()
                refreshCreatePrompt()
            }
            .onChange(of: showLivePreview) { _, newValue in
                viewModel.updateLivePreviewEnabled(newValue)
            }
            .fullScreenCover(item: $viewModel.draft) { draft in
                ReviewDraftView(draft: draft) { entry in
                    modelContext.insert(entry)
                    try? modelContext.save()
                    viewModel.draft = nil
                    onSaved()
                }
                .presentationDragIndicator(.hidden)
            }
        }
        .toolbar(viewModel.isRecording ? .hidden : .visible, for: .tabBar)
        .background(AppThemeBackground())
    }

    private var idleLayout: some View {
        VStack(spacing: 0) {
            promptHeader(isCompact: false)
                .padding(.top, 58)

            if viewModel.isProcessing {
                ProgressView("Transcribing and shaping your journal")
                    .font(selectedFontDesignPreference.font(.body))
                    .padding(.top, 36)
            }

            if let error = viewModel.errorMessage {
                errorView(error)
                    .padding(.top, 28)
            }

            Spacer(minLength: 44)

            recordingActions(includeTypeButton: !viewModel.isProcessing)
                .padding(.bottom, 84)
        }
    }

    private var recordingLayout: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    promptHeader(isCompact: true)
                        .padding(.top, 24)

                    if showLivePreview {
                        livePreviewContent
                            .padding(.top, 22)
                    }
                }
                .padding(.bottom, 220)
            }

            VStack(spacing: 18) {
                Text(viewModel.formattedRecordingDuration)
                    .font(.system(.title2, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.red)

                recordingActions(includeTypeButton: false)
            }
            .padding(.bottom, 6)
        }
    }

    private func recordingActions(includeTypeButton: Bool) -> some View {
        VStack(spacing: includeTypeButton ? 40 : 16) {
            Button {
                viewModel.toggleRecording()
            } label: {
                if viewModel.isRecording {
                    WaveformRecordButton(
                        level: viewModel.microphoneLevel,
                        hasDetectedAudio: viewModel.hasDetectedAudio
                    )
                } else {
                    IdleRecordButton()
                }
            }
            .accessibilityLabel(viewModel.isRecording ? "Stop recording" : "Start recording")
            .disabled(viewModel.isProcessing || viewModel.isStartingRecording || (!viewModel.isReadyToRecord && !viewModel.isRecording))
            .buttonStyle(.plain)

            if includeTypeButton {
                Button {
                    viewModel.createManualDraft()
                } label: {
                    Label {
                        Text("Type Journal")
                            .font(selectedFontDesignPreference.font(.body))
                    } icon: {
                        Image("icon-edit-text")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func promptHeader(isCompact: Bool) -> some View {
        VStack(spacing: 8) {
            if !displayName.isEmpty {
                Text(displayName)
                    .font(isCompact ? selectedFontDesignPreference.font(.title2, weight: .bold) : selectedFontDesignPreference.font(.largeTitle, weight: .bold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(createPrompt)
                .font(promptFont(isCompact: isCompact))
                .foregroundStyle(displayName.isEmpty ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.72)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    private func promptFont(isCompact: Bool) -> Font {
        if isCompact {
            return displayName.isEmpty ? selectedFontDesignPreference.font(.title2, weight: .bold) : selectedFontDesignPreference.font(.title3, weight: .semibold)
        }

        return displayName.isEmpty ? selectedFontDesignPreference.font(.largeTitle, weight: .bold) : selectedFontDesignPreference.font(.title, weight: .semibold)
    }

    private var livePreviewContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live Preview")
                .font(selectedFontDesignPreference.font(.caption, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(livePreviewText)
                .font(selectedFontDesignPreference.font(.body))
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(viewModel.liveTranscript.isEmpty ? .secondary : .primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func errorView(_ error: String) -> some View {
        Text(error)
            .font(selectedFontDesignPreference.font(.callout))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var displayName: String {
        profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }

    private var livePreviewText: String {
        viewModel.liveTranscript.isEmpty
            ? viewModel.livePreviewNotice ?? "Listening in any language... Text will appear shortly."
            : viewModel.liveTranscript
    }

    private func refreshCreatePrompt() {
        let prompts = [
            "what's on your mind today?",
            "what do you want to remember from today?",
            "how are you feeling right now?",
            "what feels important today?",
            "what has been sitting with you lately?",
            "what would you like to say out loud?"
        ]
        let prompt = prompts.randomElement() ?? prompts[0]
        createPrompt = prompt.capitalizedFirstSentence
    }

    private func refreshRenderedFontPreference() {
        renderedFontPreference = JournalFontPreference.current.rawValue
    }
}

private extension String {
    var capitalizedFirstSentence: String {
        guard let first else { return self }
        return first.uppercased() + String(dropFirst())
    }
}

private struct IdleRecordButton: View {
    var body: some View {
        Image("tab-create-microphone")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 62, height: 62)
            .frame(width: 132, height: 132)
            .foregroundStyle(.white)
            .background(Color.accentColor)
            .clipShape(Circle())
            .shadow(color: Color.accentColor.opacity(0.18), radius: 18, y: 10)
    }
}

private struct WaveformRecordButton: View {
    let level: Float
    let hasDetectedAudio: Bool

    var body: some View {
        TimelineView(.animation) { context in
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
