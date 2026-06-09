import SwiftData
import SwiftUI

struct RecordJournalView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = RecorderViewModel()
    let onSaved: () -> Void

    init(onSaved: @escaping () -> Void = {}) {
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 16) {
                    Button {
                        viewModel.toggleRecording()
                    } label: {
                        Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 52, weight: .semibold))
                            .frame(width: 132, height: 132)
                            .foregroundStyle(.white)
                            .background(viewModel.isRecording ? Color.red : Color.accentColor)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(viewModel.isRecording ? "Stop recording" : "Start recording")
                    .disabled(viewModel.isProcessing || viewModel.isStartingRecording || (!viewModel.isReadyToRecord && !viewModel.isRecording))

                    Text(statusText)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if viewModel.isRecording {
                        VStack(spacing: 10) {
                            Text(viewModel.formattedRecordingDuration)
                                .font(.system(.title2, design: .monospaced, weight: .semibold))
                                .foregroundStyle(.red)

                            MicrophoneLevelView(
                                level: viewModel.microphoneLevel,
                                hasDetectedAudio: viewModel.hasDetectedAudio
                            )
                        }
                    }
                }

                if viewModel.isRecording {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Live Preview")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ScrollView {
                            Text(livePreviewText)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(viewModel.liveTranscript.isEmpty ? .secondary : .primary)
                        }
                        .frame(maxHeight: 150)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if viewModel.isProcessing {
                    ProgressView("Transcribing and shaping your journal")
                }

                if let error = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Write Manually") {
                            viewModel.createManualDraft()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("New Journal")
            .task {
                viewModel.prepareForRecording()
            }
            .sheet(item: $viewModel.draft) { draft in
                ReviewDraftView(draft: draft) { entry in
                    modelContext.insert(entry)
                    try? modelContext.save()
                    viewModel.draft = nil
                    onSaved()
                }
            }
        }
    }

    private var statusText: String {
        if viewModel.isProcessing {
            "Cleaning up your journal"
        } else if viewModel.isStartingRecording {
            "Starting recording..."
        } else if viewModel.isRecording {
            "Recording. Tap stop when you are finished."
        } else if viewModel.isReadyToRecord {
            "Ready. Tap to start your voice journal."
        } else {
            "Preparing microphone..."
        }
    }

    private var livePreviewText: String {
        viewModel.liveTranscript.isEmpty
            ? viewModel.livePreviewNotice ?? "Listening in any language... Text will appear shortly."
            : viewModel.liveTranscript
    }

}

private struct MicrophoneLevelView: View {
    let level: Float
    let hasDetectedAudio: Bool

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.16))
                    Capsule()
                        .fill(hasDetectedAudio ? Color.green : Color.orange)
                        .frame(width: geometry.size.width * displayedLevel)
                }
            }
            .frame(width: 150, height: 8)

            Text(hasDetectedAudio ? "Microphone is hearing you" : "Speak to check the microphone")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var displayedLevel: CGFloat {
        min(max(CGFloat(level) * 20, 0.03), 1)
    }
}
