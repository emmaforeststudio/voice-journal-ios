import SwiftData
import SwiftUI
import UIKit
import UserNotifications
import UniformTypeIdentifiers

struct InsightsJournalView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var navigationPath: NavigationPath
    @AppStorage("profileDisplayName") private var profileDisplayName = ""
    @AppStorage("insightsMemoryCardMode") private var insightsMemoryCardMode = InsightsMemoryCardMode.onThisDay.rawValue
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    @Query(sort: \JournalEntry.journalDate, order: .reverse) private var entries: [JournalEntry]
    @State private var exportURL: URL?
    @State private var backendStatus: BackendStatus = .checking
    @State private var themeCloudMonth = Date()
    @State private var selectedMemoryEntry: JournalEntry?
    @State private var isEditingProfileName = false
    @State private var profileNameDraft = ""
    @State private var renderedFontPreference = JournalFontPreference.current.rawValue
    @State private var memoryCardSessionSeed = Int.random(in: 0..<1_000_000_000)

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack(path: $navigationPath) {
            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 10) {
                        insightsHeader
                        memoryCardSection
                        metricsSection
                        themesSection
                            .frame(maxHeight: .infinity, alignment: .top)
                        futureLetterSection
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
            .id(renderedFontPreference)
            .background(AppThemeBackground())
            .task {
                await refreshBackendStatus()
            }
            .onAppear {
                refreshRenderedFontPreference()
                refreshMemoryCardSelection()
            }
            .onChange(of: navigationPath.count) { _, count in
                if count == 0 {
                    refreshMemoryCardSelection()
                }
            }
            .navigationDestination(for: InsightsRoute.self) { route in
                switch route {
                case .settings:
                    VoiceJournalSettingsView(
                        entries: entries,
                        exportURL: $exportURL,
                        backendStatus: backendStatus,
                        makeMarkdownExport: makeMarkdownExport,
                        deleteAllJournals: deleteAllJournals
                    )
                case .futureLetter:
                    FutureLetterComposerView()
                }
            }
            .navigationDestination(item: $selectedMemoryEntry) { entry in
                EntryDetailView(entry: entry)
            }
            .sheet(isPresented: $isEditingProfileName) {
                NavigationStack {
                    Form {
                        TextField("Name", text: $profileNameDraft)
                            .textInputAutocapitalization(.words)
                    }
                    .scrollContentBackground(.hidden)
                    .background(AppThemeBackground())
                    .navigationTitle(profileDisplayName.isEmpty ? "Add Name" : "Edit Name")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                isEditingProfileName = false
                            }
                        }

                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                profileDisplayName = profileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                isEditingProfileName = false
                            }
                        }
                    }
                }
                .presentationDetents([.height(220)])
            }
        }
        .background(AppThemeBackground())
    }

    private var insightsHeader: some View {
        HStack(alignment: .center) {
            Button {
                profileNameDraft = profileDisplayName
                isEditingProfileName = true
            } label: {
                HStack(spacing: 8) {
                    Text(profileDisplayName.isEmpty ? "Add your name" : profileDisplayName)
                        .font(selectedFontDesignPreference.font(.largeTitle, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Image("icon-edit-text")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 17, height: 17)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(profileDisplayName.isEmpty ? "Add your name" : "Edit name")

            Spacer()

            NavigationLink(value: InsightsRoute.settings) {
                Image("icon-settings")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .frame(width: 42, height: 42)
                    .background(AppThemeCardBackground())
                    .clipShape(Circle())
            }
            .accessibilityLabel("Settings")
        }
    }

    private enum InsightsRoute: Hashable {
        case settings
        case futureLetter
    }

    private var metricsSection: some View {
        LazyVGrid(columns: metricColumns, spacing: 8) {
            InsightMetricCard(title: "Current Streak", value: "\(currentStreak) days", imageName: "metric-streak-flame")
            InsightMetricCard(title: "This Month", value: entryCountText(entriesThisMonth), imageName: "metric-calendar")
        }
        .frame(minHeight: 96)
    }

    private var memoryCardSection: some View {
        InsightMemoryCard(mode: selectedMemoryCardMode, entry: memoryCardEntry) { entry in
            selectedMemoryEntry = entry
        }
    }

    private var futureLetterSection: some View {
        NavigationLink(value: InsightsRoute.futureLetter) {
            LetterToFutureMeCard()
        }
        .buttonStyle(.plain)
    }

    private var themesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Month Recap")
                    .font(selectedFontDesignPreference.font(.subheadline, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    resetThemeCloudMonthToCurrent()
                } label: {
                    Text(themeCloudMonthLabel)
                        .font(selectedFontDesignPreference.font(.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(isThemeCloudMonthCurrent ? "Current month" : "Return to current month")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if themeCloudItems.isEmpty {
                AppUnavailableView(
                    title: "No themes yet",
                    systemImage: "text.magnifyingglass",
                    description: "Themes will appear after more journal text is saved."
                )
            } else {
                ThemeCloudView(themes: themeCloudItems)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppThemeCardBackground())
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .gesture(
            DragGesture(minimumDistance: 28)
                .onEnded { value in
                    handleThemeCloudSwipe(value.translation.width)
                }
        )
    }

    private var metricColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }

    private var selectedMemoryCardMode: InsightsMemoryCardMode {
        InsightsMemoryCardMode.value(for: insightsMemoryCardMode)
    }

    private func refreshRenderedFontPreference() {
        renderedFontPreference = JournalFontPreference.current.rawValue
    }

    private var entriesThisMonth: Int {
        JournalInsightCalculator.entriesThisMonth(entries, calendar: calendar)
    }

    private var currentStreak: Int {
        JournalInsightCalculator.currentStreak(entries, calendar: calendar)
    }

    private var entriesForThisMonth: [JournalEntry] {
        JournalInsightCalculator.entriesInMonth(entries, calendar: calendar)
    }

    private var entriesForThemeCloudMonth: [JournalEntry] {
        JournalInsightCalculator.entriesInMonth(entries, referenceDate: themeCloudMonth, calendar: calendar)
    }

    private var memoryCardEntry: JournalEntry? {
        let candidates: [JournalEntry]
        switch selectedMemoryCardMode {
        case .onThisDay:
            candidates = entries.filter { isEntryOnThisDay($0) }
        case .randomEntry:
            candidates = entries
        }
        return randomMemoryEntry(from: candidates, mode: selectedMemoryCardMode)
    }

    private var themeCloudItems: [(theme: String, count: Int)] {
        JournalInsightCalculator.themeCloud(entriesForThemeCloudMonth, limit: 10)
    }

    private var themeCloudMonthLabel: String {
        themeCloudMonth.formatted(.dateTime.month(.wide).year())
    }

    private var isThemeCloudMonthCurrent: Bool {
        calendar.isDate(themeCloudMonth, equalTo: Date(), toGranularity: .month)
    }

    private func entryCountText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "entry" : "entries")"
    }

    private func isEntryOnThisDay(_ entry: JournalEntry) -> Bool {
        let todayComponents = calendar.dateComponents([.month, .day], from: Date())
        let entryComponents = calendar.dateComponents([.month, .day], from: entry.journalDate)
        return todayComponents.month == entryComponents.month && todayComponents.day == entryComponents.day
    }

    private func randomMemoryEntry(from candidates: [JournalEntry], mode: InsightsMemoryCardMode) -> JournalEntry? {
        let sortedCandidates = sortedMemoryCandidates(candidates)
        guard !sortedCandidates.isEmpty else { return nil }
        return sortedCandidates[memorySeed(for: mode) % sortedCandidates.count]
    }

    private func refreshMemoryCardSelection() {
        let candidates: [JournalEntry]
        switch selectedMemoryCardMode {
        case .onThisDay:
            candidates = sortedMemoryCandidates(entries.filter { isEntryOnThisDay($0) })
        case .randomEntry:
            candidates = sortedMemoryCandidates(entries)
        }
        guard !candidates.isEmpty else { return }

        let currentEntryID = randomMemoryEntry(from: candidates, mode: selectedMemoryCardMode)?.id
        var nextSeed = Int.random(in: 0..<1_000_000_000)

        if candidates.count > 1 {
            for _ in 0..<8 {
                let nextIndex = (nextSeed + memoryModeOffset(for: selectedMemoryCardMode)) % candidates.count
                if candidates[nextIndex].id != currentEntryID {
                    break
                }
                nextSeed = Int.random(in: 0..<1_000_000_000)
            }
        }

        memoryCardSessionSeed = nextSeed
    }

    private func sortedMemoryCandidates(_ candidates: [JournalEntry]) -> [JournalEntry] {
        candidates.sorted { first, second in
            if first.journalDate == second.journalDate {
                return first.id.uuidString < second.id.uuidString
            }
            return first.journalDate < second.journalDate
        }
    }

    private func memorySeed(for mode: InsightsMemoryCardMode) -> Int {
        memoryCardSessionSeed + memoryModeOffset(for: mode)
    }

    private func memoryModeOffset(for mode: InsightsMemoryCardMode) -> Int {
        mode == .onThisDay ? 17 : 53
    }

    private func moveThemeCloudMonth(by value: Int) {
        themeCloudMonth = calendar.date(byAdding: .month, value: value, to: themeCloudMonth) ?? themeCloudMonth
    }

    private func resetThemeCloudMonthToCurrent() {
        guard !isThemeCloudMonthCurrent else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            themeCloudMonth = Date()
        }
    }

    private func handleThemeCloudSwipe(_ horizontalTranslation: CGFloat) {
        guard abs(horizontalTranslation) > 44 else { return }
        let monthDelta = horizontalTranslation < 0 ? 1 : -1
        withAnimation(.easeInOut(duration: 0.22)) {
            moveThemeCloudMonth(by: monthDelta)
        }
    }

    private func makeMarkdownExport() -> URL? {
        let sortedEntries = entries.sorted { $0.journalDate > $1.journalDate }
        let markdown = MarkdownJournalExporter.makeMarkdown(entries: sortedEntries)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Flara Day Export")
            .appendingPathExtension("md")

        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private func deleteAllJournals() {
        for entry in entries {
            modelContext.delete(entry)
        }
        try? modelContext.save()
        exportURL = nil
    }

    private func refreshBackendStatus() async {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "VoiceJournalBackendURL") as? String,
            let url = URL(string: value)?.appendingPathComponent("health")
        else {
            backendStatus = .unconfigured
            return
        }

        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) {
                backendStatus = .connected
            } else {
                backendStatus = .unavailable
            }
        } catch {
            backendStatus = .unavailable
        }
    }
}

private struct VoiceJournalSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    let entries: [JournalEntry]
    @Binding var exportURL: URL?
    let backendStatus: BackendStatus
    let makeMarkdownExport: () -> URL?
    let deleteAllJournals: () -> Void

    @AppStorage("profileDisplayName") private var profileDisplayName = ""
    @AppStorage("faceIDLockEnabled") private var faceIDLockEnabled = false
    @AppStorage("passwordLockEnabled") private var passwordLockEnabled = false
    @AppStorage("appLockPassword") private var appLockPassword = ""
    @AppStorage("themeColorPreference") private var themeColorPreference = AppColorTheme.h1.rawValue
    @AppStorage("journalFontPreference") private var journalFontPreference = JournalFontPreference.standard.rawValue
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    @AppStorage("insightsMemoryCardMode") private var insightsMemoryCardMode = InsightsMemoryCardMode.onThisDay.rawValue
    @AppStorage("showLivePreview") private var showLivePreview = true

    @State private var requestedFaceIDLock = false
    @State private var requestedPasswordLock = false
    @State private var isShowingDeleteAccountConfirmation = false
    @State private var isShowingDeleteJournalsConfirmation = false
    @State private var exportDocument: ExportDocument?
    @State private var isShowingImportPicker = false
    @State private var isShowingPasswordSetup = false
    @State private var passwordDraft = ""
    @State private var importMessage: String?
    @State private var lockMessage: String?

    var body: some View {
        Form {
            Section {
                ThemePicker(selection: $themeColorPreference)
                    .listRowBackground(AppThemeCardBackground())

                FontDesignPicker(selection: $journalFontDesignPreference)
                    .listRowBackground(AppThemeCardBackground())

                FontSizePicker(selection: $journalFontPreference)
                    .listRowBackground(AppThemeCardBackground())

                MemoryCardModePicker(selection: $insightsMemoryCardMode)
                    .listRowBackground(AppThemeCardBackground())

                Toggle(isOn: $showLivePreview) {
                    SettingsRowLabel(title: "Live Preview While Recording", imageName: "icon-live-preview")
                }
                .listRowBackground(AppThemeCardBackground())
            } header: {
                Text("Appearance")
                    .font(selectedFontDesignPreference.unscaledFont(.subheadline, weight: .semibold))
            }
            .listRowBackground(AppThemeCardBackground())

            Section {
                NavigationLink {
                    FeatureRequestBoardView()
                } label: {
                    SettingsRowLabel(title: "Request / Vote on Features", systemImageName: "triangle.fill")
                }
                .listRowBackground(AppThemeCardBackground())

                NavigationLink {
                    VersionHistoryView()
                } label: {
                    SettingsRowLabel(title: "Version History", systemImageName: "clock")
                }
                .listRowBackground(AppThemeCardBackground())
            } header: {
                Text("Support")
                    .font(selectedFontDesignPreference.unscaledFont(.subheadline, weight: .semibold))
            }
            .listRowBackground(AppThemeCardBackground())

            Section {
                Toggle(isOn: $requestedFaceIDLock) {
                    SettingsRowLabel(title: "Face ID Lock", imageName: "icon-face-id")
                }
                .listRowBackground(AppThemeCardBackground())

                Toggle(isOn: $requestedPasswordLock) {
                    SettingsRowLabel(title: "Password Lock", imageName: "icon-password-lock")
                }
                .listRowBackground(AppThemeCardBackground())

                if passwordLockEnabled {
                    Button {
                        passwordDraft = ""
                        isShowingPasswordSetup = true
                    } label: {
                        SettingsRowLabel(title: "Change Password", imageName: "icon-change-password")
                    }
                    .listRowBackground(AppThemeCardBackground())
                }

                if let lockMessage {
                    Text(lockMessage)
                        .font(selectedFontPreference.font(.caption, design: selectedFontDesignPreference))
                        .foregroundStyle(.secondary)
                        .listRowBackground(AppThemeCardBackground())
                }
                Button {
                    if let url = makeMarkdownExport() {
                        exportURL = url
                        exportDocument = ExportDocument(url: url)
                        importMessage = nil
                    } else {
                        importMessage = "Export failed. Please try again."
                    }
                } label: {
                    SettingsRowLabel(title: "Export Journals", imageName: "icon-export-journals", foregroundColor: settingsActionTextColor, iconColor: Color.accentColor)
                }
                .disabled(entries.isEmpty)
                .listRowBackground(AppThemeCardBackground())

                Button {
                    isShowingImportPicker = true
                } label: {
                    SettingsRowLabel(title: "Import Journals", imageName: "icon-import-journals", foregroundColor: settingsActionTextColor, iconColor: Color.accentColor)
                }
                .listRowBackground(AppThemeCardBackground())

                Button(role: .destructive) {
                    isShowingDeleteJournalsConfirmation = true
                } label: {
                    SettingsRowLabel(title: "Delete All Journals", imageName: "icon-trash", foregroundColor: .red)
                }
                .disabled(entries.isEmpty)
                .listRowBackground(AppThemeCardBackground())

                if let importMessage {
                    Text(importMessage)
                        .font(selectedFontPreference.font(.caption, design: selectedFontDesignPreference))
                        .foregroundStyle(.secondary)
                        .listRowBackground(AppThemeCardBackground())
                }
            } header: {
                Text("Privacy")
                    .font(selectedFontDesignPreference.unscaledFont(.subheadline, weight: .semibold))
            }
            .listRowBackground(AppThemeCardBackground())

            Section {
                HStack {
                    SettingsRowLabel(title: "Backend", imageName: "icon-backend")
                    Spacer()
                    Text(backendStatus.displayText)
                        .foregroundStyle(backendStatus.color)
                }
                .listRowBackground(AppThemeCardBackground())
            } header: {
                Text("Connection")
                    .font(selectedFontDesignPreference.unscaledFont(.subheadline, weight: .semibold))
            }
            .listRowBackground(AppThemeCardBackground())

            Section {
                Button(role: .destructive) {
                    isShowingDeleteAccountConfirmation = true
                } label: {
                    SettingsRowLabel(title: "Delete Account", imageName: "icon-delete-account", foregroundColor: .red)
                }
                .listRowBackground(AppThemeCardBackground())
            }
            .listRowBackground(AppThemeCardBackground())
        }
        .scrollContentBackground(.hidden)
        .background(AppThemeBackground())
        .tint(selectedTheme.primaryColor)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Settings")
                    .font(selectedFontPreference.font(.headline, design: selectedFontDesignPreference, weight: .semibold))
            }
        }
        .onAppear {
            requestedFaceIDLock = faceIDLockEnabled
            requestedPasswordLock = passwordLockEnabled
        }
        .onChange(of: requestedFaceIDLock) { _, newValue in
            handleFaceIDLockChange(newValue)
        }
        .onChange(of: requestedPasswordLock) { _, newValue in
            handlePasswordLockChange(newValue)
        }
        .fileImporter(
            isPresented: $isShowingImportPicker,
            allowedContentTypes: [.plainText, .text, .utf8PlainText, .json, .data],
            allowsMultipleSelection: true
        ) { result in
            importJournals(from: result)
        }
        .sheet(isPresented: $isShowingPasswordSetup, onDismiss: handlePasswordSetupDismissal) {
            PasswordSetupView(password: $passwordDraft) {
                appLockPassword = passwordDraft
                passwordLockEnabled = true
                requestedPasswordLock = true
                lockMessage = "Password lock is on."
                isShowingPasswordSetup = false
            } onCancel: {
                isShowingPasswordSetup = false
            }
        }
        .sheet(item: $exportDocument) { document in
            ActivityView(activityItems: [document.url])
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Delete all journals?", isPresented: $isShowingDeleteJournalsConfirmation, titleVisibility: .visible) {
            Button("Delete All Journals", role: .destructive) {
                deleteAllJournals()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only deletes journals stored in Flara Day. This cannot be undone.")
        }
        .confirmationDialog("Delete account?", isPresented: $isShowingDeleteAccountConfirmation, titleVisibility: .visible) {
            Button("Delete Account and Journals", role: .destructive) {
                deleteAccount()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the local profile and deletes all journals stored in Flara Day. This cannot be undone.")
        }
    }

    private func handleFaceIDLockChange(_ isEnabled: Bool) {
        guard isEnabled != faceIDLockEnabled else { return }

        if isEnabled {
            Task {
                let result = await AppLockAuthenticator.authenticate(reason: "Use Face ID to lock Flara Day.")
                await MainActor.run {
                    if result.isSuccess {
                        faceIDLockEnabled = true
                        lockMessage = "Face ID lock is on."
                    } else {
                        requestedFaceIDLock = false
                        lockMessage = result.message
                    }
                }
            }
        } else {
            faceIDLockEnabled = false
            lockMessage = "Face ID lock is off."
        }
    }

    private func handlePasswordLockChange(_ isEnabled: Bool) {
        if isEnabled {
            if appLockPassword.count == 6 {
                passwordLockEnabled = true
                lockMessage = "Password lock is on."
            } else {
                requestedPasswordLock = false
                passwordDraft = ""
                isShowingPasswordSetup = true
            }
        } else {
            passwordLockEnabled = false
            lockMessage = "Password lock is off."
        }
    }

    private func handlePasswordSetupDismissal() {
        if !passwordLockEnabled {
            requestedPasswordLock = false
        }
    }

    private func importJournals(from result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            var importedCount = 0

            for url in urls {
                let canAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if canAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let text = try String(contentsOf: url, encoding: .utf8)
                let importedEntries = MarkdownJournalImporter.importEntries(from: text, fallbackTitle: url.deletingPathExtension().lastPathComponent)
                for entry in importedEntries {
                    modelContext.insert(entry)
                }
                importedCount += importedEntries.count
            }

            try modelContext.save()
            importMessage = importedCount == 1 ? "Imported 1 journal." : "Imported \(importedCount) journals."
        } catch {
            importMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func logOutProfile() {
        profileDisplayName = ""
    }

    private func deleteAccount() {
        logOutProfile()
        faceIDLockEnabled = false
        requestedFaceIDLock = false
        passwordLockEnabled = false
        requestedPasswordLock = false
        appLockPassword = ""
        deleteAllJournals()
    }

    private var selectedTheme: AppColorTheme {
        AppColorTheme.value(for: themeColorPreference)
    }

    private var settingsActionTextColor: Color {
        selectedTheme.colorScheme == .dark ? .white : .black
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }

    private var selectedFontPreference: JournalFontPreference {
        JournalFontPreference.value(for: journalFontPreference)
    }
}

private struct FeatureRequestBoardView: View {
    @AppStorage("featureRequestBoardItemsV2") private var storedItemsData = ""
    @AppStorage("themeColorPreference") private var themeColorPreference = AppColorTheme.h1.rawValue
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    @AppStorage("journalFontPreference") private var journalFontPreference = JournalFontPreference.standard.rawValue
    @State private var items = FeatureRequestItem.defaultItems
    @State private var draftTitle = ""
    @State private var draftDetails = ""
    @State private var isShowingRequestSheet = false
    @State private var selectedFeatureRequest: FeatureRequestItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Vote on what should come next.")
                    .font(selectedFontDesignPreference.font(.subheadline))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)

                ForEach(items.sorted(by: sortFeatureRequests)) { item in
                    FeatureRequestCardView(
                        item: item,
                        theme: selectedTheme,
                        fontDesign: selectedFontDesignPreference,
                        open: {
                            selectedFeatureRequest = item
                        }
                    ) {
                        vote(for: item)
                    }
                }
            }
            .padding()
        }
        .background(AppThemeBackground())
        .tint(selectedTheme.primaryColor)
        .navigationTitle("Feature Requests")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Feature Requests")
                    .font(selectedFontDesignPreference.font(.headline, weight: .semibold))
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    draftTitle = ""
                    draftDetails = ""
                    isShowingRequestSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Request feature")
            }
        }
        .sheet(isPresented: $isShowingRequestSheet) {
            requestSheet
        }
        .navigationDestination(item: $selectedFeatureRequest) { item in
            FeatureRequestDetailView(
                item: item,
                theme: selectedTheme,
                fontDesign: selectedFontDesignPreference
            ) {
                vote(for: item)
                selectedFeatureRequest = items.first(where: { $0.id == item.id })
            }
        }
        .onAppear(perform: loadItems)
    }

    private var requestSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Feature title", text: $draftTitle)
                        .textInputAutocapitalization(.sentences)
                        .listRowBackground(AppThemeCardBackground())

                    TextField("Why would this help?", text: $draftDetails, axis: .vertical)
                        .lineLimit(3...6)
                        .textInputAutocapitalization(.sentences)
                        .listRowBackground(AppThemeCardBackground())
                }
                .listRowBackground(AppThemeCardBackground())
                .font(selectedFontDesignPreference.font(.body))
            }
            .scrollContentBackground(.hidden)
            .background(AppThemeBackground())
            .tint(selectedTheme.primaryColor)
            .navigationTitle("Request Feature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Request Feature")
                        .font(selectedFontDesignPreference.font(.headline, weight: .semibold))
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowingRequestSheet = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addRequest()
                    }
                    .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var selectedTheme: AppColorTheme {
        AppColorTheme.value(for: themeColorPreference)
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }

    private func loadItems() {
        guard
            let data = storedItemsData.data(using: .utf8),
            let decodedItems = try? JSONDecoder().decode([FeatureRequestItem].self, from: data),
            !decodedItems.isEmpty
        else {
            items = FeatureRequestItem.defaultItems
            return
        }

        items = decodedItems
    }

    private func addRequest() {
        let trimmedTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let trimmedDetails = draftDetails.trimmingCharacters(in: .whitespacesAndNewlines)
        items.insert(FeatureRequestItem(title: trimmedTitle, details: trimmedDetails, voteCount: 1, status: "Requested"), at: 0)
        draftTitle = ""
        draftDetails = ""
        isShowingRequestSheet = false
        persistItems()
    }

    private func vote(for item: FeatureRequestItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        items[index].voteCount += 1
        persistItems()
    }

    private func persistItems() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        storedItemsData = String(data: data, encoding: .utf8) ?? ""
    }

    private func sortFeatureRequests(_ lhs: FeatureRequestItem, _ rhs: FeatureRequestItem) -> Bool {
        if lhs.voteCount == rhs.voteCount {
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        return lhs.voteCount > rhs.voteCount
    }
}

private struct FeatureRequestItem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var title: String
    var details: String
    var voteCount: Int
    var status: String

    init(id: UUID = UUID(), title: String, details: String, voteCount: Int, status: String) {
        self.id = id
        self.title = title
        self.details = details
        self.voteCount = voteCount
        self.status = status
    }

    static let defaultItems = [
        FeatureRequestItem(title: "Cloud sync across devices", details: "Keep journals available on iPhone and iPad.", voteCount: 12, status: "Planned"),
        FeatureRequestItem(title: "More export formats", details: "Export entries as PDF, DOCX, or clean text bundles.", voteCount: 8, status: "Requested"),
        FeatureRequestItem(title: "Custom monthly insight prompts", details: "Let users choose the reflection questions used for recaps.", voteCount: 5, status: "Under Review")
    ]
}

private struct FeatureRequestCardView: View {
    let item: FeatureRequestItem
    let theme: AppColorTheme
    let fontDesign: JournalFontDesignPreference
    let open: () -> Void
    let vote: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Button(action: vote) {
                VStack(spacing: 4) {
                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.bold))
                    Text("\(item.voteCount)")
                        .font(fontDesign.font(.callout, weight: .bold))
                }
                .foregroundStyle(theme.primaryColor)
                .frame(width: 52, height: 58)
                .background(theme.primaryColor.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Vote for \(item.title)")

            Button(action: open) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.title)
                            .font(fontDesign.font(.headline, weight: .semibold))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(item.status)
                            .font(fontDesign.font(.caption, weight: .semibold))
                            .foregroundStyle(theme.primaryColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(theme.primaryColor.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    if !item.details.isEmpty {
                        Text(item.details)
                            .font(fontDesign.font(.subheadline))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(AppThemeCardBackground())
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct FeatureRequestDetailView: View {
    let item: FeatureRequestItem
    let theme: AppColorTheme
    let fontDesign: JournalFontDesignPreference
    let vote: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(item.title)
                        .font(fontDesign.font(.title2, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(item.status)
                        .font(fontDesign.font(.caption, weight: .semibold))
                        .foregroundStyle(theme.primaryColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(theme.primaryColor.opacity(0.12))
                        .clipShape(Capsule())
                }

                Button(action: vote) {
                    Label("\(item.voteCount) votes", systemImage: "chevron.up")
                        .font(fontDesign.font(.callout, weight: .semibold))
                        .foregroundStyle(theme.primaryColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(theme.primaryColor.opacity(0.13))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Text(item.details.isEmpty ? "No description yet." : item.details)
                    .font(fontDesign.font(.body))
                    .foregroundStyle(item.details.isEmpty ? .secondary : .primary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
        }
        .background(AppThemeBackground())
        .navigationTitle("Feature Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Feature Detail")
                    .font(fontDesign.font(.headline, weight: .semibold))
            }
        }
    }
}

private struct VersionHistoryView: View {
    @AppStorage("themeColorPreference") private var themeColorPreference = AppColorTheme.h1.rawValue
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    @AppStorage("journalFontPreference") private var journalFontPreference = JournalFontPreference.standard.rawValue

    var body: some View {
        Form {
            Section {
                HStack {
                    SettingsRowLabel(title: "Installed Version", imageName: "metric-calendar")
                    Spacer()
                    Text(versionDisplayText)
                        .font(selectedFontDesignPreference.font(.body))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Current")
                    .font(selectedFontDesignPreference.unscaledFont(.caption, weight: .semibold))
            }
            .listRowBackground(AppThemeCardBackground())

            Section {
                VersionHistoryEntryView(
                    version: versionDisplayText,
                    changes: [
                        "Chunked live preview with overlap",
                        "Calendar and insights navigation reset",
                        "Tinted theme surfaces and support settings"
                    ]
                )
            } header: {
                Text("History")
                    .font(selectedFontDesignPreference.unscaledFont(.caption, weight: .semibold))
            }
            .listRowBackground(AppThemeCardBackground())
        }
        .scrollContentBackground(.hidden)
        .background(AppThemeBackground())
        .tint(selectedTheme.primaryColor)
        .navigationTitle("Version History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Version History")
                    .font(selectedFontDesignPreference.font(.headline, weight: .semibold))
            }
        }
    }

    private var selectedTheme: AppColorTheme {
        AppColorTheme.value(for: themeColorPreference)
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }

    private var versionDisplayText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

private struct VersionHistoryEntryView: View {
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    let version: String
    let changes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(version)
                .font(selectedFontDesignPreference.font(.headline))

            ForEach(changes, id: \.self) { change in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("-")
                    Text(change)
                }
                .font(selectedFontDesignPreference.font(.subheadline))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }
}

private struct PasswordSetupView: View {
    @AppStorage("themeColorPreference") private var themeColorPreference = AppColorTheme.h1.rawValue
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    @AppStorage("journalFontPreference") private var journalFontPreference = JournalFontPreference.standard.rawValue
    @Binding var password: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @State private var didSubmit = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer(minLength: 12)

                VStack(spacing: 14) {
                    Image("icon-change-password")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 38, height: 38)
                        .foregroundColor(selectedTheme.primaryColor)

                    Text("Create a 6-digit password")
                        .font(selectedFontDesignPreference.font(.title3, weight: .bold))

                    NumericPasswordDots(count: password.count, length: 6)
                        .padding(.top, 6)
                }

                NumericPasswordKeypad { digit in
                    guard password.count < 6 else { return }
                    password.append(digit)
                    submitIfComplete()
                } onDelete: {
                    if !password.isEmpty {
                        password.removeLast()
                    }
                }

                Text("Use six numbers to unlock Flara Day without Face ID.")
                    .font(selectedFontDesignPreference.font(.caption))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppThemeBackground())
            .tint(selectedTheme.primaryColor)
            .navigationTitle("Set Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Set Password")
                        .font(selectedFontDesignPreference.font(.headline, weight: .semibold))
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .presentationDetents([.height(620), .large])
        .onChange(of: password) { _, newValue in
            password = String(newValue.filter(\.isNumber).prefix(6))
            submitIfComplete()
        }
    }

    private func submitIfComplete() {
        guard password.count == 6, !didSubmit else { return }
        didSubmit = true
        onSave()
    }

    private var selectedTheme: AppColorTheme {
        AppColorTheme.value(for: themeColorPreference)
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }
}

enum AppColorTheme: String, CaseIterable, Identifiable {
    case h1
    case j1
    case j2
    case j4
    case r1
    case r2
    case r3
    case l2
    case y4
    case o1
    case o3
    case o4

    var id: String { rawValue }

    static let lightThemes: [AppColorTheme] = [.r1, .r2, .r3, .l2, .h1, .j1, .j4]
    static let nightThemes: [AppColorTheme] = [.y4, .o1, .o3, .o4]

    var displayName: String {
        switch self {
        case .h1:
            "H1 · Seafoam + Soft Butter"
        case .j1:
            "J1 · Lilac + Soft Butter"
        case .j2:
            "J2 · Lilac + Peach"
        case .j4:
            "J4 · Sage + Soft Butter"
        case .r1:
            "R1 · Dusty Rose"
        case .r2:
            "R2 · Soft Coral"
        case .r3:
            "R3 · Muted Berry"
        case .l2:
            "L2 · Warm Honey"
        case .y4:
            "Y4 · Dark Burnt Honey"
        case .o1:
            "O1 · Black + Balanced Periwinkle"
        case .o3:
            "O3 · Black Forest + Balanced Teal"
        case .o4:
            "O4 · Black Plum + Balanced Rose"
        }
    }

    var shortName: String {
        String(displayName.prefix { $0 != "·" }).trimmingCharacters(in: .whitespaces)
    }

    var primaryColor: Color {
        Color(hex: primaryHex)
    }

    var backgroundColor: Color {
        Color(hex: backgroundHex)
    }

    var cardColor: Color {
        Color(hex: cardHex)
    }

    var colorScheme: ColorScheme {
        AppColorTheme.nightThemes.contains(self) ? .dark : .light
    }

    var swatchHexes: [String] {
        switch self {
        case .h1:
            ["#6FC6B8", "#F6E7A9"]
        case .j1:
            ["#A99BEA", "#F6E7A9"]
        case .j2:
            ["#A99BEA", "#F0B28F"]
        case .j4:
            ["#91B99D", "#F6E7A9"]
        case .r1:
            ["#D994A3"]
        case .r2:
            ["#E08E76"]
        case .r3:
            ["#C66A86"]
        case .l2:
            ["#E8C766"]
        case .y4:
            ["#D09A45", "#05060A"]
        case .o1:
            ["#505BB8", "#05060A"]
        case .o3:
            ["#167D70", "#05060A"]
        case .o4:
            ["#A64463", "#05060A"]
        }
    }

    private var primaryHex: String {
        swatchHexes[0]
    }

    private var backgroundHex: String {
        switch self {
        case .h1:
            "#E0F1EC"
        case .j1, .j2:
            "#ECE3F8"
        case .j4:
            "#E3F1E7"
        case .r1:
            "#F3DFE6"
        case .r2:
            "#F4E1D9"
        case .r3:
            "#F2DBE5"
        case .l2:
            "#F2E4BD"
        case .y4:
            "#080808"
        case .o1:
            "#080A17"
        case .o3:
            "#07120F"
        case .o4:
            "#100A12"
        }
    }

    private var cardHex: String {
        switch self {
        case .h1:
            "#E8F6F3"
        case .j1:
            "#F2ECFC"
        case .j2:
            "#F4ECFA"
        case .j4:
            "#EBF6EE"
        case .r1:
            "#F9E7ED"
        case .r2:
            "#FAE9E2"
        case .r3:
            "#F7E4EC"
        case .l2:
            "#F9EED0"
        case .y4:
            "#1C150D"
        case .o1:
            "#13162E"
        case .o3:
            "#0B2622"
        case .o4:
            "#27141E"
        }
    }

    static func value(for rawValue: String) -> AppColorTheme {
        AppColorTheme(rawValue: rawValue) ?? .h1
    }
}

struct AppThemeBackground: View {
    @AppStorage("themeColorPreference") private var themeColorPreference = AppColorTheme.h1.rawValue

    var body: some View {
        AppColorTheme.value(for: themeColorPreference)
            .backgroundColor
            .ignoresSafeArea()
    }
}

struct AppThemeCardBackground: View {
    @AppStorage("themeColorPreference") private var themeColorPreference = AppColorTheme.h1.rawValue

    var body: some View {
        AppColorTheme.value(for: themeColorPreference)
            .cardColor
    }
}

struct AppUnavailableView: View {
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    let title: String
    let systemImage: String
    let description: String
    var size: AppUnavailableViewSize = .standard

    var body: some View {
        VStack(spacing: size.spacing) {
            Image(systemName: systemImage)
                .font(iconFont)
                .foregroundStyle(.secondary)

            Text(title)
                .font(titleFont)
                .multilineTextAlignment(.center)

            Text(description)
                .font(descriptionFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, size.verticalPadding)
        .padding(.horizontal, 18)
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }

    private var iconFont: Font {
        switch size {
        case .standard:
            selectedFontDesignPreference.unscaledFont(.title2, weight: .semibold)
        case .prominent:
            selectedFontDesignPreference.unscaledFont(.largeTitle, weight: .semibold)
        }
    }

    private var titleFont: Font {
        switch size {
        case .standard:
            selectedFontDesignPreference.unscaledFont(.headline, weight: .semibold)
        case .prominent:
            selectedFontDesignPreference.unscaledFont(.title2, weight: .semibold)
        }
    }

    private var descriptionFont: Font {
        switch size {
        case .standard:
            selectedFontDesignPreference.unscaledFont(.subheadline)
        case .prominent:
            selectedFontDesignPreference.unscaledFont(.body)
        }
    }
}

enum AppUnavailableViewSize {
    case standard
    case prominent

    var spacing: CGFloat {
        switch self {
        case .standard:
            10
        case .prominent:
            12
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .standard:
            28
        case .prominent:
            34
        }
    }
}

enum InsightsMemoryCardMode: String, CaseIterable, Identifiable {
    case onThisDay
    case randomEntry

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .onThisDay:
            "On This Day"
        case .randomEntry:
            "Random Entry"
        }
    }

    static func value(for rawValue: String) -> InsightsMemoryCardMode {
        InsightsMemoryCardMode(rawValue: rawValue) ?? .onThisDay
    }
}

private extension Color {
    init(hex: String) {
        let trimmedHex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = Int(trimmedHex, radix: 16) ?? 0
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255

        self.init(red: red, green: green, blue: blue)
    }
}

private struct ThemePicker: View {
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    @AppStorage("journalFontPreference") private var journalFontPreference = JournalFontPreference.standard.rawValue
    @Binding var selection: String
    @State private var isExpanded = false

    private var selectedTheme: AppColorTheme {
        AppColorTheme.value(for: selection)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 18) {
                themeRow(title: "Light", themes: AppColorTheme.lightThemes)
                themeRow(title: "Dark", themes: AppColorTheme.nightThemes)
            }
            .padding(.top, 14)
            .padding(.bottom, 10)
        } label: {
            HStack {
                SettingsRowLabel(title: "Theme", imageName: "icon-theme-mode")
                Spacer()
                Circle()
                    .fill(selectedTheme.primaryColor)
                    .frame(width: 18, height: 18)
                    .overlay {
                        Circle()
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    }
            }
        }
        .accessibilityLabel("Theme")
        .accessibilityValue(selectedTheme.displayName)
    }

    private func themeRow(title: String, themes: [AppColorTheme]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(selectedFontPreference.font(.caption, design: selectedFontDesignPreference, weight: .semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(themes) { theme in
                        Button {
                            selection = theme.rawValue
                        } label: {
                            ThemeSelectionSwatch(
                                theme: theme,
                                isSelected: selectedTheme == theme
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(theme.displayName)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }

    private var selectedFontPreference: JournalFontPreference {
        JournalFontPreference.value(for: journalFontPreference)
    }
}

private struct FontDesignPicker: View {
    @Binding var selection: String
    @State private var isExpanded = false

    private var selectedPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: selection)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(JournalFontDesignPreference.allCases) { preference in
                        AppearanceChoiceButton(
                            title: preference.displayName,
                            isSelected: selectedPreference == preference,
                            font: .system(.callout, design: preference.fontDesign, weight: .semibold)
                        ) {
                            selection = preference.rawValue
                        }
                    }
                }
                .padding(.vertical, 10)
            }
        } label: {
            HStack {
                SettingsRowLabel(title: "Font", imageName: "icon-font-style")
                Spacer()
                    Text(selectedPreference.displayName)
                    .font(selectedFontPreference.font(.body, design: selectedPreference))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Font")
        .accessibilityValue(selectedPreference.displayName)
    }

    @AppStorage("journalFontPreference") private var journalFontPreference = JournalFontPreference.standard.rawValue

    private var selectedFontPreference: JournalFontPreference {
        JournalFontPreference.value(for: journalFontPreference)
    }
}

private struct FontSizePicker: View {
    @Binding var selection: String
    @State private var isExpanded = false
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue

    private var selectedPreference: JournalFontPreference {
        JournalFontPreference.value(for: selection)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(JournalFontPreference.allCases) { preference in
                        AppearanceChoiceButton(
                            title: preference.displayName,
                            isSelected: selectedPreference == preference,
                            font: choiceFont(for: preference)
                        ) {
                            select(preference)
                        }
                    }
                }
                .padding(.vertical, 10)
            }
        } label: {
            HStack {
                SettingsRowLabel(title: "Font Size", imageName: "icon-font-size")
                Spacer()
                Text(selectedPreference.displayName)
                    .font(selectedPreference.font(.body, design: selectedFontDesignPreference))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Font Size")
        .accessibilityValue(selectedPreference.displayName)
    }

    private func choiceFont(for preference: JournalFontPreference) -> Font {
        switch preference {
        case .compact:
            preference.font(.caption, design: selectedFontDesignPreference, weight: .semibold)
        case .standard:
            preference.font(.callout, design: selectedFontDesignPreference, weight: .semibold)
        case .spacious:
            preference.font(.title3, design: selectedFontDesignPreference, weight: .semibold)
        }
    }

    private func select(_ preference: JournalFontPreference) {
        JournalFontPreference.setCurrent(preference)

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            selection = preference.rawValue
        }
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }
}

private struct MemoryCardModePicker: View {
    @Binding var selection: String
    @State private var isExpanded = false
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    @AppStorage("journalFontPreference") private var journalFontPreference = JournalFontPreference.standard.rawValue

    private var selectedMode: InsightsMemoryCardMode {
        InsightsMemoryCardMode.value(for: selection)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(InsightsMemoryCardMode.allCases) { mode in
                        AppearanceChoiceButton(
                            title: mode.displayName,
                            isSelected: selectedMode == mode,
                            font: selectedFontPreference.font(.callout, design: selectedFontDesignPreference, weight: .semibold)
                        ) {
                            selection = mode.rawValue
                        }
                    }
                }
                .padding(.vertical, 10)
            }
        } label: {
            HStack {
                SettingsRowLabel(title: "Memory Card", systemImageName: "sparkles")
                Spacer()
                Text(selectedMode.displayName)
                    .font(selectedFontPreference.font(.body, design: selectedFontDesignPreference))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Memory Card")
        .accessibilityValue(selectedMode.displayName)
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }

    private var selectedFontPreference: JournalFontPreference {
        JournalFontPreference.value(for: journalFontPreference)
    }
}

private struct AppearanceChoiceButton: View {
    let title: String
    let isSelected: Bool
    let font: Font
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(font)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.06))
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SettingsRowLabel: View {
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    @AppStorage("journalFontPreference") private var journalFontPreference = JournalFontPreference.standard.rawValue
    let title: String
    let imageName: String?
    let systemImageName: String?
    var foregroundColor: Color?
    var iconColor: Color?

    init(title: String, imageName: String, foregroundColor: Color? = nil, iconColor: Color? = nil) {
        self.title = title
        self.imageName = imageName
        self.systemImageName = nil
        self.foregroundColor = foregroundColor
        self.iconColor = iconColor
    }

    init(title: String, systemImageName: String, foregroundColor: Color? = nil, iconColor: Color? = nil) {
        self.title = title
        self.imageName = nil
        self.systemImageName = systemImageName
        self.foregroundColor = foregroundColor
        self.iconColor = iconColor
    }

    var body: some View {
        HStack(spacing: 12) {
            if let systemImageName {
                SettingsSystemIcon(systemImageName, color: iconColor ?? foregroundColor ?? Color.accentColor)
            } else if let imageName {
                SettingsIcon(imageName, color: iconColor ?? foregroundColor ?? Color.accentColor)
            }
            Text(title)
                .font(selectedFontPreference.font(.body, design: selectedFontDesignPreference))
                .foregroundStyle(foregroundColor ?? Color.primary)
        }
    }

    private var selectedFontPreference: JournalFontPreference {
        JournalFontPreference.value(for: journalFontPreference)
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }
}

private struct SettingsSystemIcon: View {
    let systemImageName: String
    let color: Color

    init(_ systemImageName: String, color: Color = Color.accentColor) {
        self.systemImageName = systemImageName
        self.color = color
    }

    var body: some View {
        Image(systemName: systemImageName)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 28, alignment: .center)
    }
}

private struct SettingsIcon: View {
    let imageName: String
    let color: Color

    init(_ imageName: String, color: Color = Color.accentColor) {
        self.imageName = imageName
        self.color = color
    }

    var body: some View {
        Image(imageName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 21, height: 21)
            .foregroundStyle(color)
            .frame(width: 28, alignment: .center)
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct ExportDocument: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ThemeSelectionSwatch: View {
    let theme: AppColorTheme
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(theme.primaryColor)
            .frame(width: 30, height: 30)
            .overlay {
                Circle()
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
            .padding(2)
            .overlay {
                Circle()
                    .stroke(isSelected ? theme.primaryColor : Color.clear, lineWidth: 2)
            }
            .overlay {
                Circle()
                    .stroke(isSelected ? Color.white.opacity(0.82) : Color.clear, lineWidth: 1)
                    .padding(2)
            }
            .frame(width: 42, height: 42)
    }
}

enum JournalFontPreference: String, CaseIterable, Identifiable {
    case compact
    case standard
    case spacious

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compact:
            "Small"
        case .standard:
            "Normal"
        case .spacious:
            "Large"
        }
    }

    func editorFont(design: JournalFontDesignPreference) -> Font {
        switch self {
        case .compact:
            font(.callout, design: design)
        case .standard:
            font(.body, design: design)
        case .spacious:
            font(.title3, design: design)
        }
    }

    func rowBodyFont(design: JournalFontDesignPreference) -> Font {
        switch self {
        case .compact:
            font(.caption, design: design)
        case .standard:
            font(.subheadline, design: design)
        case .spacious:
            font(.body, design: design)
        }
    }

    func font(_ textStyle: Font.TextStyle, design: JournalFontDesignPreference, weight: Font.Weight? = nil) -> Font {
        let baseSize = basePointSize(for: textStyle)
        let adjustedSize = baseSize * scale
        return .system(size: adjustedSize, weight: weight ?? defaultWeight(for: textStyle), design: design.fontDesign)
    }

    func fixedFont(size: CGFloat, design: JournalFontDesignPreference, weight: Font.Weight = .regular) -> Font {
        .system(size: size * scale, weight: weight, design: design.fontDesign)
    }

    func uiFont(size: CGFloat, design: JournalFontDesignPreference, weight: UIFont.Weight) -> UIFont {
        design.uiFont(size: size * scale, weight: weight)
    }

    static var current: JournalFontPreference {
        value(for: currentRawValue)
    }

    static func setCurrent(_ preference: JournalFontPreference) {
        currentRawValue = preference.rawValue
    }

    private static var currentRawValue = UserDefaults.standard.string(forKey: "journalFontPreference") ?? standard.rawValue

    private var scale: CGFloat {
        switch self {
        case .compact:
            1.0
        case .standard:
            1.12
        case .spacious:
            1.24
        }
    }

    private func basePointSize(for textStyle: Font.TextStyle) -> CGFloat {
        switch textStyle {
        case .largeTitle:
            34
        case .title:
            28
        case .title2:
            22
        case .title3:
            20
        case .headline:
            17
        case .subheadline:
            15
        case .body:
            17
        case .callout:
            16
        case .footnote:
            13
        case .caption:
            12
        case .caption2:
            11
        @unknown default:
            17
        }
    }

    private func defaultWeight(for textStyle: Font.TextStyle) -> Font.Weight {
        switch textStyle {
        case .headline:
            .semibold
        default:
            .regular
        }
    }

    static func value(for rawValue: String) -> JournalFontPreference {
        JournalFontPreference(rawValue: rawValue) ?? .standard
    }
}

enum JournalFontDesignPreference: String, CaseIterable, Identifiable {
    case system
    case serif
    case rounded
    case monospaced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            "System"
        case .serif:
            "Serif"
        case .rounded:
            "Rounded"
        case .monospaced:
            "Mono"
        }
    }

    var fontDesign: Font.Design {
        switch self {
        case .system:
            .default
        case .serif:
            .serif
        case .rounded:
            .rounded
        case .monospaced:
            .monospaced
        }
    }

    func font(_ textStyle: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        JournalFontPreference.current.font(textStyle, design: self, weight: weight)
    }

    func unscaledFont(_ textStyle: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        let baseFont = Font.system(textStyle, design: fontDesign)
        if let weight {
            return baseFont.weight(weight)
        }

        return baseFont
    }

    func fixedFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        JournalFontPreference.current.fixedFont(size: size, design: self, weight: weight)
    }

    func unscaledFixedFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: fontDesign)
    }

    func uiFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let baseDescriptor = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        let design: UIFontDescriptor.SystemDesign
        switch self {
        case .system:
            return UIFont.systemFont(ofSize: size, weight: weight)
        case .serif:
            design = .serif
        case .rounded:
            design = .rounded
        case .monospaced:
            design = .monospaced
        }

        return UIFont(descriptor: baseDescriptor.withDesign(design) ?? baseDescriptor, size: size)
    }

    static func value(for rawValue: String) -> JournalFontDesignPreference {
        if rawValue == "sanFranciscoPro" {
            return .system
        }
        return JournalFontDesignPreference(rawValue: rawValue) ?? .system
    }
}

struct ProfileEmojiPicker: View {
    @Binding var selection: String
    private let emojis = JournalProcessor.supportedMoodEmojis

    var body: some View {
        Menu {
            ForEach(emojis, id: \.self) { emoji in
                Button {
                    selection = emoji
                } label: {
                    Text(emoji)
                }
            }
        } label: {
            Text(selection)
                .font(.largeTitle)
                .frame(width: 64, height: 64)
                .background(Color.accentColor.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel("Profile emoji")
    }
}

private struct InsightMetricCard: View {
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    let title: String
    let value: String
    let imageName: String

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Image(imageName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(selectedFontDesignPreference.font(.headline, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.58)
            Text(title)
                .font(selectedFontDesignPreference.font(.caption, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.72))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .center)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(AppThemeCardBackground())
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }
}

private struct InsightMemoryCard: View {
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    let mode: InsightsMemoryCardMode
    let entry: JournalEntry?
    let openEntry: (JournalEntry) -> Void

    var body: some View {
        Group {
            if let entry {
                Button {
                    openEntry(entry)
                } label: {
                    cardContent(entryTitle: entryTitle(entry))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Open journal")
            } else {
                cardContent(entryTitle: emptyTitle)
                    .accessibilityHint(emptyDescription)
            }
        }
    }

    private func cardContent(entryTitle: String) -> some View {
        VStack(alignment: .center, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(selectedFontDesignPreference.font(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text(mode.displayName)
                    .font(selectedFontDesignPreference.font(.headline))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Text(entryTitle)
                .font(selectedFontDesignPreference.font(.title3, weight: .bold))
                .foregroundStyle(entry == nil ? .secondary : Color.accentColor)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 114, alignment: .center)
        .background(AppThemeCardBackground())
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .contentShape(RoundedRectangle(cornerRadius: 28))
    }

    private func entryTitle(_ entry: JournalEntry) -> String {
        let trimmed = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Journal" : trimmed
    }

    private var emptyTitle: String {
        switch mode {
        case .onThisDay:
            "No entries for today"
        case .randomEntry:
            "No journals yet"
        }
    }

    private var emptyDescription: String {
        switch mode {
        case .onThisDay:
            "Entries from this date will appear here."
        case .randomEntry:
            "Record or write a journal to begin."
        }
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }
}

private struct LetterToFutureMeCard: View {
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Spacer(minLength: 0)

            Image(systemName: "envelope")
                .font(selectedFontDesignPreference.font(.headline, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text("Letter to Future Me")
                .font(selectedFontDesignPreference.font(.headline))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .center)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(AppThemeCardBackground())
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .accessibilityLabel("Letter to Future Me")
        .accessibilityHint("Open letter composer")
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }
}

private struct FutureLetterComposerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    @Query(sort: \FutureLetter.deliveryDate, order: .forward) private var letters: [FutureLetter]
    @StateObject private var recorder = AudioRecorder()
    @State private var title = ""
    @State private var bodyText = ""
    @State private var deliveryDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var deliveryMethod = FutureLetterDeliveryMethod.inAppNotification
    @State private var selectedLetter: FutureLetter?
    @State private var isRecording = false
    @State private var isProcessingRecording = false
    @State private var compositionMode = FutureLetterCompositionMode.record
    @State private var message: String?
    @FocusState private var focusedField: FutureLetterFocusedField?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                composeSection
                deliverySection
                actionButtons
                savedLettersSection
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .background {
            AppThemeBackground()
                .onTapGesture {
                    deactivateTextEditing()
                }
        }
        .navigationTitle("Future Letter")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            try? await recorder.prepare()
        }
        .navigationDestination(item: $selectedLetter) { letter in
            FutureLetterDetailView(letter: letter)
        }
    }

    private var composeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $title)
                .font(selectedFontDesignPreference.font(.body, weight: .semibold))
                .textInputAutocapitalization(.sentences)
                .focused($focusedField, equals: .title)
                .padding(14)
                .background(AppThemeCardBackground())
                .clipShape(RoundedRectangle(cornerRadius: 18))

            letterBodyEditor(placeholder: letterBodyPlaceholder)
            compositionModePicker
            statusSection
        }
    }

    private var compositionModePicker: some View {
        HStack(spacing: 10) {
            compositionModeButton(.record)
            compositionModeButton(.type)
        }
    }

    private func compositionModeButton(_ mode: FutureLetterCompositionMode) -> some View {
        Button {
            handleCompositionModeTap(mode)
        } label: {
            Label(compositionModeTitle(for: mode), systemImage: compositionModeSystemImage(for: mode))
                .font(selectedFontDesignPreference.font(.body, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .foregroundStyle(compositionMode == mode || (mode == .record && isRecording) ? .white : Color.accentColor)
        .background {
            if compositionMode == mode || (mode == .record && isRecording) {
                Color.accentColor
            } else {
                AppThemeCardBackground()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .disabled(isProcessingRecording)
    }

    private func compositionModeTitle(for mode: FutureLetterCompositionMode) -> String {
        mode == .record && isRecording ? "Stop" : mode.displayName
    }

    private func compositionModeSystemImage(for mode: FutureLetterCompositionMode) -> String {
        mode == .record && isRecording ? "stop.fill" : mode.systemImage
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isProcessingRecording {
                ProgressView("Transcribing your letter")
                    .font(selectedFontDesignPreference.font(.callout))
            }

            if let message {
                Text(message)
                    .font(selectedFontDesignPreference.font(.callout))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var letterBodyPlaceholder: String {
        if isRecording {
            return "Recording..."
        }

        switch compositionMode {
        case .record:
            return "Record your letter. The transcript will appear here."
        case .type:
            return "Write your letter."
        }
    }

    private func letterBodyEditor(placeholder: String) -> some View {
        TextEditor(text: $bodyText)
            .font(selectedFontDesignPreference.font(.body))
            .focused($focusedField, equals: .body)
            .frame(minHeight: 220)
            .scrollContentBackground(.hidden)
            .padding(10)
            .background(AppThemeCardBackground())
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .topLeading) {
                if bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(selectedFontDesignPreference.font(.body))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
    }

    private var deliverySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            FutureLetterDeliveryDatePicker(date: $deliveryDate)
            .font(selectedFontDesignPreference.font(.body))
            .onChange(of: deliveryDate) { _, _ in
                deactivateTextEditing()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Delivery Method")
                    .font(selectedFontDesignPreference.font(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)

                deliveryMethodButton(.inAppNotification, subtitle: "Schedule a private local reminder on this iPhone.", isEnabled: true)
                deliveryMethodButton(.email, subtitle: "Requires an email delivery service before launch.", isEnabled: false)
            }
        }
        .padding(16)
        .background(AppThemeCardBackground())
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .simultaneousGesture(
            TapGesture().onEnded {
                deactivateTextEditing()
            }
        )
    }

    private func deliveryMethodButton(_ method: FutureLetterDeliveryMethod, subtitle: String, isEnabled: Bool) -> some View {
        Button {
            deactivateTextEditing()
            if isEnabled {
                deliveryMethod = method
                message = nil
            } else {
                message = "Email delivery needs a backend email provider before it can be enabled."
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: deliveryMethod == method ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isEnabled ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(method.displayName)
                        .font(selectedFontDesignPreference.font(.body, weight: .semibold))
                        .foregroundStyle(isEnabled ? .primary : .secondary)
                    Text(subtitle)
                        .font(selectedFontDesignPreference.font(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                saveLetter(shouldSchedule: false)
            } label: {
                Text("Save")
                    .font(selectedFontDesignPreference.font(.body, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!canSave)

            Button {
                saveLetter(shouldSchedule: true)
            } label: {
                Text("Schedule")
                    .font(selectedFontDesignPreference.font(.body, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
        }
    }

    private var savedLettersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved Letters")
                .font(selectedFontDesignPreference.font(.headline))

            if letters.isEmpty {
                Text("Saved future letters will appear here.")
                    .font(selectedFontDesignPreference.font(.callout))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(AppThemeCardBackground())
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                ForEach(letters) { letter in
                    SwipeToDeleteFutureLetterRow(
                        letter: letter,
                        title: letterTitle(letter),
                        onOpen: { selectedLetter = letter },
                        onDelete: { deleteLetter(letter) }
                    )
                }
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                deactivateTextEditing()
            }
        )
    }

    private var canSave: Bool {
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        deliveryMethod == .inAppNotification &&
        !isRecording &&
        !isProcessingRecording
    }

    private func handleCompositionModeTap(_ mode: FutureLetterCompositionMode) {
        message = nil

        switch mode {
        case .record:
            compositionMode = .record
            focusedField = nil
            toggleRecording()
        case .type:
            compositionMode = .type
            if isRecording {
                stopRecording()
            } else {
                focusedField = .body
            }
        }
    }

    private func deactivateTextEditing() {
        focusedField = nil
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        message = nil
        focusedField = nil
        Task {
            do {
                try await recorder.start()
                isRecording = true
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func stopRecording() {
        isProcessingRecording = true
        isRecording = false
        Task {
            do {
                let url = try recorder.stop()
                defer { recorder.deleteRecording(at: url) }
                let transcript = try await OpenAIJournalService().previewTranscript(from: url)
                appendTranscript(transcript)
                message = "Recording added to your letter."
            } catch {
                message = error.localizedDescription
            }
            isProcessingRecording = false
            try? await recorder.prepare()
        }
    }

    private func appendTranscript(_ transcript: String) {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else { return }
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        bodyText = trimmedBody.isEmpty ? trimmedTranscript : "\(trimmedBody)\n\n\(trimmedTranscript)"
    }

    private func saveLetter(shouldSchedule: Bool) {
        focusedField = nil
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let letter = FutureLetter(
            title: trimmedTitle,
            body: trimmedBody,
            deliveryDate: deliveryDate,
            deliveryMethod: deliveryMethod
        )

        Task {
            do {
                var resultMessage = "Letter saved."
                if shouldSchedule {
                    do {
                        let notificationID = try await FutureLetterNotificationScheduler.schedule(letter: letter)
                        letter.notificationIdentifier = notificationID
                        resultMessage = "Letter scheduled."
                    } catch {
                        resultMessage = "Letter saved. Notification was not scheduled: \(error.localizedDescription)"
                    }
                }

                modelContext.insert(letter)
                try modelContext.save()
                title = ""
                bodyText = ""
                deliveryDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
                message = resultMessage
                if shouldSchedule, letter.notificationIdentifier != nil {
                    dismiss()
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func deleteLetter(_ letter: FutureLetter) {
        if let notificationIdentifier = letter.notificationIdentifier {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
        }
        if selectedLetter?.id == letter.id {
            selectedLetter = nil
        }
        modelContext.delete(letter)
        try? modelContext.save()
    }

    private func letterTitle(_ letter: FutureLetter) -> String {
        let trimmed = letter.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Letter" : trimmed
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }
}

private struct FutureLetterDeliveryDatePicker: View {
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    @Binding var date: Date

    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            Image(systemName: "calendar")
                .font(selectedFontDesignPreference.font(.title3, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            DatePicker(
                "Delivery Date & Time",
                selection: $date,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Delivery Date & Time")
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }
}

private struct SwipeToDeleteFutureLetterRow: View {
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    let letter: FutureLetter
    let title: String
    let onOpen: () -> Void
    let onDelete: () -> Void
    @State private var horizontalOffset: CGFloat = 0
    @GestureState private var dragTranslation: CGFloat = 0

    private let deleteWidth: CGFloat = 86

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive) {
                deleteRow()
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(selectedFontDesignPreference.font(.caption, weight: .semibold))
                    .labelStyle(.iconOnly)
                    .frame(width: deleteWidth)
                    .frame(maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Color.red.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(selectedFontDesignPreference.font(.body, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(letter.deliveryDate.formatted(date: .abbreviated, time: .shortened))
                    .font(selectedFontDesignPreference.font(.caption))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(AppThemeCardBackground())
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .offset(x: displayedOffset)
            .onTapGesture {
                if horizontalOffset == 0 {
                    onOpen()
                } else {
                    closeRow()
                }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 12)
                    .updating($dragTranslation) { value, state, _ in
                        state = min(0, value.translation.width)
                    }
                    .onEnded { value in
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            let finalOffset = horizontalOffset + value.translation.width
                            if finalOffset < -deleteWidth * 1.45 {
                                deleteRow()
                            } else {
                                horizontalOffset = finalOffset < -36 ? -deleteWidth : 0
                            }
                        }
                    }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func closeRow() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            horizontalOffset = 0
        }
    }

    private func deleteRow() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            horizontalOffset = 0
        }
        onDelete()
    }

    private var displayedOffset: CGFloat {
        min(0, max(-deleteWidth, horizontalOffset + dragTranslation))
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }
}

private struct FutureLetterDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    @StateObject private var recorder = AudioRecorder()
    let letter: FutureLetter
    @State private var title = ""
    @State private var bodyText = ""
    @State private var deliveryDate = Date()
    @State private var deliveryMethod = FutureLetterDeliveryMethod.inAppNotification
    @State private var isRecording = false
    @State private var isProcessingRecording = false
    @State private var compositionMode = FutureLetterCompositionMode.type
    @State private var message: String?
    @FocusState private var focusedField: FutureLetterFocusedField?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                composeSection
                deliverySection
                actionButtons
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .background {
            AppThemeBackground()
                .onTapGesture {
                    deactivateTextEditing()
                }
        }
        .navigationTitle("Future Letter")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadLetter()
        }
        .task {
            try? await recorder.prepare()
        }
    }

    private var composeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $title)
                .font(selectedFontDesignPreference.font(.body, weight: .semibold))
                .textInputAutocapitalization(.sentences)
                .focused($focusedField, equals: .title)
                .padding(14)
                .background(AppThemeCardBackground())
                .clipShape(RoundedRectangle(cornerRadius: 18))

            letterBodyEditor(placeholder: letterBodyPlaceholder)
            compositionModePicker
            statusSection
        }
    }

    private var compositionModePicker: some View {
        HStack(spacing: 10) {
            compositionModeButton(.record)
            compositionModeButton(.type)
        }
    }

    private func compositionModeButton(_ mode: FutureLetterCompositionMode) -> some View {
        Button {
            handleCompositionModeTap(mode)
        } label: {
            Label(compositionModeTitle(for: mode), systemImage: compositionModeSystemImage(for: mode))
                .font(selectedFontDesignPreference.font(.body, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .foregroundStyle(compositionMode == mode || (mode == .record && isRecording) ? .white : Color.accentColor)
        .background {
            if compositionMode == mode || (mode == .record && isRecording) {
                Color.accentColor
            } else {
                AppThemeCardBackground()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .disabled(isProcessingRecording)
    }

    private func compositionModeTitle(for mode: FutureLetterCompositionMode) -> String {
        mode == .record && isRecording ? "Stop" : mode.displayName
    }

    private func compositionModeSystemImage(for mode: FutureLetterCompositionMode) -> String {
        mode == .record && isRecording ? "stop.fill" : mode.systemImage
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isProcessingRecording {
                ProgressView("Transcribing your letter")
                    .font(selectedFontDesignPreference.font(.callout))
            }

            if let message {
                Text(message)
                    .font(selectedFontDesignPreference.font(.callout))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var letterBodyPlaceholder: String {
        if isRecording {
            return "Recording..."
        }

        switch compositionMode {
        case .record:
            return "Record again. The transcript will be added here."
        case .type:
            return "Edit your letter."
        }
    }

    private func letterBodyEditor(placeholder: String) -> some View {
        TextEditor(text: $bodyText)
            .font(selectedFontDesignPreference.font(.body))
            .focused($focusedField, equals: .body)
            .frame(minHeight: 220)
            .scrollContentBackground(.hidden)
            .padding(10)
            .background(AppThemeCardBackground())
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .topLeading) {
                if bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(selectedFontDesignPreference.font(.body))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
    }

    private var deliverySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            FutureLetterDeliveryDatePicker(date: $deliveryDate)
            .font(selectedFontDesignPreference.font(.body))
            .onChange(of: deliveryDate) { _, _ in
                deactivateTextEditing()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Delivery Method")
                    .font(selectedFontDesignPreference.font(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)

                deliveryMethodButton(.inAppNotification, subtitle: "Schedule a private local reminder on this iPhone.", isEnabled: true)
                deliveryMethodButton(.email, subtitle: "Requires an email delivery service before launch.", isEnabled: false)
            }
        }
        .padding(16)
        .background(AppThemeCardBackground())
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .simultaneousGesture(
            TapGesture().onEnded {
                deactivateTextEditing()
            }
        )
    }

    private func deliveryMethodButton(_ method: FutureLetterDeliveryMethod, subtitle: String, isEnabled: Bool) -> some View {
        Button {
            deactivateTextEditing()
            if isEnabled {
                deliveryMethod = method
                message = nil
            } else {
                message = "Email delivery needs a backend email provider before it can be enabled."
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: deliveryMethod == method ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isEnabled ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(method.displayName)
                        .font(selectedFontDesignPreference.font(.body, weight: .semibold))
                        .foregroundStyle(isEnabled ? .primary : .secondary)
                    Text(subtitle)
                        .font(selectedFontDesignPreference.font(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                saveChanges(shouldSchedule: false)
            } label: {
                Text("Save")
                    .font(selectedFontDesignPreference.font(.body, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!canSave)

            Button {
                saveChanges(shouldSchedule: true)
            } label: {
                Text("Schedule")
                    .font(selectedFontDesignPreference.font(.body, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
        }
    }

    private var canSave: Bool {
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        deliveryMethod == .inAppNotification &&
        !isRecording &&
        !isProcessingRecording
    }

    private func loadLetter() {
        title = letter.title
        bodyText = letter.body
        deliveryDate = max(letter.deliveryDate, Date())
        deliveryMethod = letter.deliveryMethod
    }

    private func handleCompositionModeTap(_ mode: FutureLetterCompositionMode) {
        message = nil

        switch mode {
        case .record:
            compositionMode = .record
            focusedField = nil
            toggleRecording()
        case .type:
            compositionMode = .type
            if isRecording {
                stopRecording()
            } else {
                focusedField = .body
            }
        }
    }

    private func deactivateTextEditing() {
        focusedField = nil
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        message = nil
        focusedField = nil
        Task {
            do {
                try await recorder.start()
                isRecording = true
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func stopRecording() {
        isProcessingRecording = true
        isRecording = false
        Task {
            do {
                let url = try recorder.stop()
                defer { recorder.deleteRecording(at: url) }
                let transcript = try await OpenAIJournalService().previewTranscript(from: url)
                appendTranscript(transcript)
                message = "Recording added to your letter."
            } catch {
                message = error.localizedDescription
            }
            isProcessingRecording = false
            try? await recorder.prepare()
        }
    }

    private func appendTranscript(_ transcript: String) {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else { return }
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        bodyText = trimmedBody.isEmpty ? trimmedTranscript : "\(trimmedBody)\n\n\(trimmedTranscript)"
    }

    private func saveChanges(shouldSchedule: Bool) {
        focusedField = nil
        if let notificationIdentifier = letter.notificationIdentifier {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
            letter.notificationIdentifier = nil
        }

        letter.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        letter.body = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        letter.deliveryDate = deliveryDate
        letter.deliveryMethod = deliveryMethod
        letter.updatedAt = Date()

        Task {
            do {
                var resultMessage = "Letter saved."
                if shouldSchedule {
                    do {
                        let notificationID = try await FutureLetterNotificationScheduler.schedule(letter: letter)
                        letter.notificationIdentifier = notificationID
                        resultMessage = "Letter scheduled."
                    } catch {
                        resultMessage = "Letter saved. Notification was not scheduled: \(error.localizedDescription)"
                    }
                }

                try modelContext.save()
                message = resultMessage
                if shouldSchedule, letter.notificationIdentifier != nil {
                    dismiss()
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }
}

private enum FutureLetterNotificationScheduler {
    static func schedule(letter: FutureLetter) async throws -> String {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { throw FutureLetterError.notificationPermissionDenied }
        } else if settings.authorizationStatus == .denied {
            throw FutureLetterError.notificationPermissionDenied
        }

        let content = UNMutableNotificationContent()
        content.title = "Letter to Future Me"
        content.body = "A letter you saved is ready to read."
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: letter.deliveryDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = "future-letter-\(letter.id.uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await center.add(request)
        return identifier
    }
}

private enum FutureLetterError: LocalizedError {
    case notificationPermissionDenied

    var errorDescription: String? {
        switch self {
        case .notificationPermissionDenied:
            "Notification permission is needed to deliver letters in the app."
        }
    }
}

private enum FutureLetterCompositionMode: CaseIterable {
    case record
    case type

    var displayName: String {
        switch self {
        case .record:
            "Record"
        case .type:
            "Type"
        }
    }

    var systemImage: String {
        switch self {
        case .record:
            "mic.fill"
        case .type:
            "square.and.pencil"
        }
    }
}

private enum FutureLetterFocusedField: Hashable {
    case title
    case body
}

private struct ThemeCloudView: View {
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    let themes: [(theme: String, count: Int)]

    private var rankedCounts: [Int] {
        Array(Set(displayThemes.map(\.count))).sorted(by: >)
    }

    private var displayThemes: [(theme: String, count: Int)] {
        Array(themes.prefix(10))
    }

    private var mainTheme: (theme: String, count: Int)? {
        displayThemes.max { first, second in
            if first.count == second.count {
                return first.theme > second.theme
            }
            return first.count < second.count
        }
    }

    private var surroundingThemes: [(theme: String, count: Int)] {
        guard let mainTheme else { return [] }
        var hasSkippedMainTheme = false
        return displayThemes.filter { item in
            if !hasSkippedMainTheme, item.theme == mainTheme.theme, item.count == mainTheme.count {
                hasSkippedMainTheme = true
                return false
            }
            return true
        }
    }

    private var topThemes: [(theme: String, count: Int)] {
        Array(surroundingThemes.prefix(surroundingThemes.count / 2))
    }

    private var bottomThemes: [(theme: String, count: Int)] {
        Array(surroundingThemes.dropFirst(surroundingThemes.count / 2))
    }

    var body: some View {
        VStack(spacing: 12) {
            if !topThemes.isEmpty {
                themeFlow(topThemes, startIndex: 1)
            }

            Spacer(minLength: 0)

            if let mainTheme {
                Text(mainTheme.theme)
                    .font(selectedFontDesignPreference.fixedFont(size: fontSize(for: mainTheme.count) + 4, weight: .bold))
                    .foregroundStyle(themeColor(at: 0))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel(mainTheme.theme)
            }

            Spacer(minLength: 0)

            if !bottomThemes.isEmpty {
                themeFlow(bottomThemes, startIndex: topThemes.count + 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 4)
        .clipped()
    }

    private func fontSize(for count: Int) -> CGFloat {
        guard rankedCounts.count > 1 else {
            return 24
        }

        let rank = rankedCounts.firstIndex(of: count) ?? rankedCounts.count - 1
        let sizes: [CGFloat] = [24, 21.5, 19.5, 17.5, 16, 15, 14]
        if rank < sizes.count {
            return sizes[rank]
        }

        return 13
    }

    private func themeFlow(_ items: [(theme: String, count: Int)], startIndex: Int) -> some View {
        ThemeCloudFlowLayout(spacing: 9, lineSpacing: 10) {
            ForEach(Array(items.enumerated()), id: \.element.theme) { index, item in
                let displayIndex = startIndex + index
                let weight = displayIndex <= 2 ? Font.Weight.semibold : .regular
                Text(item.theme)
                    .fontWeight(weight)
                    .foregroundStyle(themeColor(at: displayIndex))
                    .font(selectedFontDesignPreference.fixedFont(size: fontSize(for: item.count), weight: weight))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .padding(.horizontal, 1)
                    .accessibilityLabel(item.theme)
            }
        }
    }

    private func themeColor(at index: Int) -> Color {
        let colors: [Color] = [
            .accentColor,
            Color(hex: "#2A9D8F"),
            Color(hex: "#E76F51"),
            Color(hex: "#5E60CE"),
            Color(hex: "#D18400"),
            Color(hex: "#0077B6"),
            Color(hex: "#C44569"),
            Color(hex: "#4D908E"),
            Color(hex: "#9B5DE5"),
            Color(hex: "#F15BB5"),
            Color(hex: "#0081A7"),
            Color(hex: "#BC6C25"),
            Color(hex: "#577590"),
            Color(hex: "#6A994E"),
            Color(hex: "#B5179E"),
            Color(hex: "#F77F00")
        ]
        return colors[index % colors.count]
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }
}

private struct ThemeCloudFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let rows = makeRows(width: width, subviews: subviews)
        let height = rows.reduce(CGFloat.zero) { partial, row in
            partial + row.height
        } + CGFloat(max(rows.count - 1, 0)) * lineSpacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = makeRows(width: bounds.width, subviews: subviews)
        let totalHeight = rows.reduce(CGFloat.zero) { partial, row in
            partial + row.height
        } + CGFloat(max(rows.count - 1, 0)) * lineSpacing
        var y = bounds.midY - totalHeight / 2

        for row in rows {
            var x = bounds.midX - row.width / 2
            for item in row.items {
                let size = item.size
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(width: size.width, height: size.height)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private func makeRows(width: CGFloat, subviews: Subviews) -> [ThemeCloudRow] {
        var rows: [ThemeCloudRow] = []
        var currentItems: [ThemeCloudRow.Item] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextWidth = currentItems.isEmpty ? size.width : currentWidth + spacing + size.width

            if nextWidth > width, !currentItems.isEmpty {
                rows.append(ThemeCloudRow(items: currentItems, width: currentWidth, height: currentHeight))
                currentItems = [ThemeCloudRow.Item(index: index, size: size)]
                currentWidth = size.width
                currentHeight = size.height
            } else {
                currentItems.append(ThemeCloudRow.Item(index: index, size: size))
                currentWidth = nextWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if !currentItems.isEmpty {
            rows.append(ThemeCloudRow(items: currentItems, width: currentWidth, height: currentHeight))
        }

        return rows
    }
}

private struct ThemeCloudRow {
    struct Item {
        let index: Int
        let size: CGSize
    }

    let items: [Item]
    let width: CGFloat
    let height: CGFloat
}

private enum BackendStatus {
    case checking
    case connected
    case unavailable
    case unconfigured

    var displayText: String {
        switch self {
        case .checking:
            "Checking"
        case .connected:
            "Connected"
        case .unavailable:
            "Unavailable"
        case .unconfigured:
            "Not configured"
        }
    }

    var color: Color {
        switch self {
        case .checking:
            .secondary
        case .connected:
            .green
        case .unavailable, .unconfigured:
            .orange
        }
    }
}

enum JournalInsightCalculator {
    static func entriesThisWeek(
        _ entries: [JournalEntry],
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        entries.filter { calendar.isDate($0.journalDate, equalTo: referenceDate, toGranularity: .weekOfYear) }.count
    }

    static func entriesThisMonth(
        _ entries: [JournalEntry],
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        entriesInMonth(entries, referenceDate: referenceDate, calendar: calendar).count
    }

    static func entriesInMonth(
        _ entries: [JournalEntry],
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> [JournalEntry] {
        entries.filter { calendar.isDate($0.journalDate, equalTo: referenceDate, toGranularity: .month) }
    }

    static func currentStreak(
        _ entries: [JournalEntry],
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let days = Set(uniqueJournalDays(entries, calendar: calendar))
        var streak = 0
        var cursor = calendar.startOfDay(for: referenceDate)

        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return streak
    }

    static func longestStreak(_ entries: [JournalEntry], calendar: Calendar = .current) -> Int {
        let days = uniqueJournalDays(entries, calendar: calendar).sorted()
        guard !days.isEmpty else { return 0 }

        var longest = 1
        var current = 1

        for index in 1..<days.count {
            let previous = days[index - 1]
            let day = days[index]
            if calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                current += 1
            } else {
                longest = max(longest, current)
                current = 1
            }
        }

        return max(longest, current)
    }

    static func averageLength(_ entries: [JournalEntry]) -> Int {
        guard !entries.isEmpty else { return 0 }
        return entries.map(approximateLength).reduce(0, +) / entries.count
    }

    static func moodCounts(_ entries: [JournalEntry]) -> [(emoji: String, count: Int)] {
        let counts = Dictionary(grouping: entries, by: \.emoji)
            .map { (emoji: $0.key, count: $0.value.count) }
        return counts.sorted {
            if $0.count == $1.count {
                return $0.emoji < $1.emoji
            }
            return $0.count > $1.count
        }
    }

    static func topThemes(_ entries: [JournalEntry], limit: Int) -> [String] {
        themeCloud(entries, limit: limit).map(\.theme)
    }

    static func themeCloud(_ entries: [JournalEntry], limit: Int) -> [(theme: String, count: Int)] {
        Array(sortedThemeCounts(detectedThemeCounts(entries)).prefix(limit))
    }

    private static func sortedThemeCounts(_ counts: [String: Int]) -> [(theme: String, count: Int)] {
        counts
            .map { (theme: $0.key, count: $0.value) }
            .sorted {
                if $0.count == $1.count {
                    return $0.theme < $1.theme
                }
                return $0.count > $1.count
            }
    }

    static func approximateLength(_ entry: JournalEntry) -> Int {
        if [.chinese, .japanese, .korean].contains(entry.language) {
            let count = entry.body.unicodeScalars
                .filter {
                    !CharacterSet.whitespacesAndNewlines.contains($0) &&
                        !CharacterSet.punctuationCharacters.contains($0)
                }
                .count
            return max(1, count / 2)
        }

        return entry.body
            .split { $0.isWhitespace || $0.isPunctuation }
            .count
    }

    private static func uniqueJournalDays(_ entries: [JournalEntry], calendar: Calendar) -> [Date] {
        let starts = Set(entries.map { calendar.startOfDay(for: $0.journalDate) })
        return starts.sorted()
    }

    private static func detectedThemeCounts(_ entries: [JournalEntry]) -> [String: Int] {
        var counts: [String: Int] = [:]

        for entry in entries {
            let text = "\(entry.title) \(entry.body)".lowercased()
            for rule in themeRules {
                let matches = rule.terms.filter { text.contains($0) }.count
                if matches > 0 {
                    counts[rule.label, default: 0] += matches
                }
            }
        }

        return counts
    }

    private struct ThemeRule {
        let label: String
        let terms: [String]
    }

    private static let themeRules: [ThemeRule] = [
        ThemeRule(label: "Sleep Struggles", terms: ["sleep", "slept", "insomnia", "couldn't sleep", "cant sleep", "woke up", "tired", "exhausted", "睡觉", "失眠", "睡不着", "醒来", "很困", "疲惫"]),
        ThemeRule(label: "Remote Work", terms: ["remote work", "work from home", "working from home", "wfh", "zoom", "slack", "远程工作", "在家工作", "居家办公"]),
        ThemeRule(label: "Long Calls", terms: ["long call", "phone call", "video call", "call lasted", "meeting ran", "long meeting", "电话", "视频会议", "开会很久", "会议很长"]),
        ThemeRule(label: "Awkwardness", terms: ["awkward", "uncomfortable", "weird interaction", "embarrassed", "cringe", "尴尬", "不舒服", "奇怪的互动"]),
        ThemeRule(label: "Dissatisfaction", terms: ["dissatisfied", "disappointed", "not happy", "unhappy", "frustrated", "annoyed", "upset", "不满意", "失望", "不开心", "没有成功", "不太开心", "很烦"]),
        ThemeRule(label: "Acting Practice", terms: ["acting", "audition", "rehearsal", "practice lines", "scene study", "monologue", "表演", "试镜", "排练", "练台词", "独白"]),
        ThemeRule(label: "Work Stress", terms: ["work stress", "deadline", "project", "manager", "client", "task", "meeting", "job", "工作压力", "截止日期", "项目", "老板", "客户", "任务", "同事"]),
        ThemeRule(label: "Family Time", terms: ["family", "mom", "mother", "dad", "father", "parents", "sister", "brother", "家人", "妈妈", "爸爸", "父母", "姐姐", "妹妹", "哥哥", "弟弟"]),
        ThemeRule(label: "Friendship", terms: ["friend", "friends", "hang out", "texted", "catch up", "朋友", "聊天", "见面", "聚会"]),
        ThemeRule(label: "Relationship", terms: ["relationship", "date", "dating", "partner", "boyfriend", "girlfriend", "关系", "约会", "伴侣", "男朋友", "女朋友"]),
        ThemeRule(label: "Health", terms: ["health", "doctor", "sick", "pain", "headache", "medicine", "therapy", "健康", "医生", "生病", "疼", "头痛", "药", "治疗"]),
        ThemeRule(label: "Exercise", terms: ["exercise", "workout", "gym", "run", "walk", "yoga", "运动", "锻炼", "健身", "跑步", "散步", "瑜伽"]),
        ThemeRule(label: "Anxiety", terms: ["anxious", "anxiety", "worried", "worry", "nervous", "panic", "焦虑", "担心", "紧张", "恐慌"]),
        ThemeRule(label: "Gratitude", terms: ["grateful", "thankful", "appreciate", "lucky", "blessed", "感谢", "感恩", "珍惜", "幸运"]),
        ThemeRule(label: "Creative Work", terms: ["creative", "writing", "design", "music", "painting", "art", "创作", "写作", "设计", "音乐", "画画", "艺术"]),
        ThemeRule(label: "Learning", terms: ["learn", "study", "class", "course", "school", "practice", "学习", "上课", "课程", "学校", "练习"]),
        ThemeRule(label: "Money", terms: ["money", "budget", "cost", "bill", "billing", "expensive", "salary", "钱", "预算", "花费", "账单", "贵", "工资"]),
        ThemeRule(label: "Home Life", terms: ["home", "apartment", "room", "cleaning", "laundry", "cook", "cooking", "家里", "公寓", "房间", "打扫", "洗衣", "做饭"]),
        ThemeRule(label: "Self Reflection", terms: ["realized", "reflect", "reflection", "understand myself", "feel like", "i noticed", "意识到", "反思", "理解自己", "我发现"]),
        ThemeRule(label: "App Testing", terms: ["test", "testing", "app", "voice journal", "flara day", "transcription", "recording", "测试", "应用", "语音日记", "转录", "录音"])
    ]
}

enum MarkdownJournalExporter {
    static func makeMarkdown(entries: [JournalEntry]) -> String {
        var lines = ["# Flara Day Export", ""]

        if entries.isEmpty {
            lines.append("No journals yet.")
            return lines.joined(separator: "\n")
        }

        for entry in entries {
            lines.append("## \(entry.title.isEmpty ? "Untitled Journal" : entry.title)")
            lines.append("")
            lines.append("- Date: \(entry.journalDate.formatted(date: .abbreviated, time: .omitted))")
            lines.append("- Mood: \(entry.emoji)")
            lines.append("- Language: \(entry.language.displayName)")
            lines.append("")
            lines.append(entry.body.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

enum MarkdownJournalImporter {
    static func importEntries(from text: String, fallbackTitle: String) -> [JournalEntry] {
        let markdownEntries = parseMarkdownEntries(from: text)
        if !markdownEntries.isEmpty {
            return markdownEntries
        }

        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return [] }

        return [
            JournalEntry(
                title: fallbackTitle.isEmpty ? "Imported Journal" : fallbackTitle,
                body: body,
                journalDate: .now,
                emoji: "🙂",
                language: .other
            )
        ]
    }

    private static func parseMarkdownEntries(from text: String) -> [JournalEntry] {
        let lines = text.components(separatedBy: .newlines)
        let entryStarts = lines.indices.filter { lines[$0].hasPrefix("## ") }
        guard !entryStarts.isEmpty else { return [] }

        var entries: [JournalEntry] = []

        for (position, startIndex) in entryStarts.enumerated() {
            let endIndex = position + 1 < entryStarts.count ? entryStarts[position + 1] : lines.endIndex
            let block = Array(lines[startIndex..<endIndex])
            guard let entry = parseEntryBlock(block) else { continue }
            entries.append(entry)
        }

        return entries
    }

    private static func parseEntryBlock(_ lines: [String]) -> JournalEntry? {
        guard let titleLine = lines.first else { return nil }
        let title = String(titleLine.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)

        var date = Date.now
        var emoji = "🙂"
        var language = JournalLanguage.other
        var bodyLines: [String] = []
        var didReachBody = false

        for line in lines.dropFirst() {
            if !didReachBody, line.hasPrefix("- Date: ") {
                let dateText = String(line.dropFirst("- Date: ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                date = parseDate(dateText) ?? date
                continue
            }

            if !didReachBody, line.hasPrefix("- Mood: ") {
                emoji = String(line.dropFirst("- Mood: ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            if !didReachBody, line.hasPrefix("- Language: ") {
                let languageText = String(line.dropFirst("- Language: ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                language = parseLanguage(languageText)
                continue
            }

            if !didReachBody, line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }

            didReachBody = true
            bodyLines.append(line)
        }

        let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }

        return JournalEntry(
            title: title.isEmpty ? "Imported Journal" : title,
            body: body,
            journalDate: date,
            emoji: emoji.isEmpty ? "🙂" : emoji,
            language: language
        )
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        if let date = formatter.date(from: text) {
            return date
        }

        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    private static func parseLanguage(_ text: String) -> JournalLanguage {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return JournalLanguage.allCases.first {
            $0.rawValue.lowercased() == normalized || $0.displayName.lowercased() == normalized
        } ?? .other
    }
}
