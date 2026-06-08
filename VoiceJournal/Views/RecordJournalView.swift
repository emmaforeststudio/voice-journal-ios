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
                        Text(viewModel.formattedRecordingDuration)
                            .font(.system(.title2, design: .monospaced, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                }

                if viewModel.isRecording {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Live Preview")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ScrollView {
                            Text(viewModel.liveTranscript.isEmpty ? "Listening..." : viewModel.liveTranscript)
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
}
