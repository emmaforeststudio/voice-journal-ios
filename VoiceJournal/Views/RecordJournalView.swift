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
                Picker("Language", selection: $viewModel.selectedLanguage) {
                    ForEach(JournalLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)

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
                    .disabled(viewModel.isProcessing)

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

                if viewModel.isProcessing {
                    ProgressView("Transcribing privately on this device")
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
        } else if viewModel.isRecording {
            "Recording. Tap stop when you are finished."
        } else {
            "Tap to start a private voice journal"
        }
    }
}
