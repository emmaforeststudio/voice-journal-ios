import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct InsightsJournalView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("profileDisplayName") private var profileDisplayName = ""
    @Query(sort: \JournalEntry.journalDate, order: .reverse) private var entries: [JournalEntry]
    @State private var exportURL: URL?
    @State private var backendStatus: BackendStatus = .checking
    @State private var themeCloudMonth = Date()
    @State private var isEditingProfileName = false
    @State private var profileNameDraft = ""

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    insightsHeader
                    metricsSection
                    themesSection
                }
                .padding()
            }
            .task {
                await refreshBackendStatus()
            }
            .sheet(isPresented: $isEditingProfileName) {
                NavigationStack {
                    Form {
                        TextField("Name", text: $profileNameDraft)
                            .textInputAutocapitalization(.words)
                    }
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
    }

    private var insightsHeader: some View {
        HStack(alignment: .center) {
            Button {
                profileNameDraft = profileDisplayName
                isEditingProfileName = true
            } label: {
                HStack(spacing: 8) {
                    Text(profileDisplayName.isEmpty ? "Add your name" : profileDisplayName)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Image(systemName: "pencil")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(profileDisplayName.isEmpty ? "Add your name" : "Edit name")

            Spacer()

            NavigationLink {
                VoiceJournalSettingsView(
                    entries: entries,
                    exportURL: $exportURL,
                    backendStatus: backendStatus,
                    makeMarkdownExport: makeMarkdownExport,
                    deleteAllJournals: deleteAllJournals
                )
            } label: {
                Image(systemName: "gearshape")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(Color.secondary.opacity(0.10))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Settings")
        }
    }

    private var metricsSection: some View {
        LazyVGrid(columns: metricColumns, spacing: 8) {
            InsightMetricCard(title: "Current Streak", value: "\(currentStreak) days", systemImage: "flame")
            InsightMetricCard(title: "This Month", value: entryCountText(entriesThisMonth), systemImage: "calendar")
        }
    }

    private var themesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Theme Cloud")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(themeCloudMonthLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if themeCloudItems.isEmpty {
                ContentUnavailableView("No themes yet", systemImage: "text.magnifyingglass", description: Text("Themes will appear after more journal text is saved."))
            } else {
                ThemeCloudView(themes: themeCloudItems)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .gesture(
            DragGesture(minimumDistance: 28)
                .onEnded { value in
                    handleThemeCloudSwipe(value.translation.width)
                }
        )
    }

    private var metricColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)
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

    private var themeCloudItems: [(theme: String, count: Int)] {
        JournalInsightCalculator.themeCloud(entriesForThemeCloudMonth, limit: 12)
    }

    private var themeCloudMonthLabel: String {
        themeCloudMonth.formatted(.dateTime.month(.wide).year())
    }

    private func entryCountText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "entry" : "entries")"
    }

    private func moveThemeCloudMonth(by value: Int) {
        themeCloudMonth = calendar.date(byAdding: .month, value: value, to: themeCloudMonth) ?? themeCloudMonth
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
            .appendingPathComponent("Voice Journal Export")
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
    @AppStorage("appThemePreference") private var appThemePreference = AppThemePreference.system.rawValue
    @AppStorage("journalFontPreference") private var journalFontPreference = JournalFontPreference.standard.rawValue
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    @AppStorage("showLivePreview") private var showLivePreview = true

    @State private var requestedFaceIDLock = false
    @State private var requestedPasswordLock = false
    @State private var isShowingDeleteAccountConfirmation = false
    @State private var isShowingDeleteJournalsConfirmation = false
    @State private var isShowingImportPicker = false
    @State private var isShowingPasswordSetup = false
    @State private var passwordDraft = ""
    @State private var importMessage: String?
    @State private var lockMessage: String?

    var body: some View {
        Form {
            Section {
                Picker("Theme Mode", selection: $appThemePreference) {
                    ForEach(AppThemePreference.allCases) { preference in
                        Text(preference.displayName).tag(preference.rawValue)
                    }
                }

                Picker("Font Size", selection: $journalFontPreference) {
                    ForEach(JournalFontPreference.allCases) { preference in
                        Text(preference.displayName).tag(preference.rawValue)
                    }
                }

                Picker("Font Style", selection: $journalFontDesignPreference) {
                    ForEach(JournalFontDesignPreference.allCases) { preference in
                        Text(preference.displayName).tag(preference.rawValue)
                    }
                }

                Toggle(isOn: $showLivePreview) {
                    Label("Live Preview While Recording", systemImage: "waveform")
                }
            } header: {
                Text("Appearance")
            }

            Section {
                Toggle(isOn: $requestedFaceIDLock) {
                    Label("Face ID Lock", systemImage: "faceid")
                }

                Toggle(isOn: $requestedPasswordLock) {
                    Label("Password Lock", systemImage: "lock.rectangle")
                }

                if passwordLockEnabled {
                    Button {
                        passwordDraft = ""
                        isShowingPasswordSetup = true
                    } label: {
                        Label("Change Password", systemImage: "number")
                    }
                }

                if let lockMessage {
                    Text(lockMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Privacy & Security")
            }

            Section {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Share Markdown Export", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        exportURL = makeMarkdownExport()
                    } label: {
                        Label("Export Journals", systemImage: "doc.text")
                    }
                    .disabled(entries.isEmpty)
                }

                Button {
                    isShowingImportPicker = true
                } label: {
                    Label("Import Journals", systemImage: "square.and.arrow.down")
                }

                Button(role: .destructive) {
                    isShowingDeleteJournalsConfirmation = true
                } label: {
                    Label("Delete All Journals", systemImage: "trash")
                }
                .disabled(entries.isEmpty)

                if let importMessage {
                    Text(importMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Privacy & Data")
            }

            Section {
                HStack {
                    Label("Backend", systemImage: "network")
                    Spacer()
                    Text(backendStatus.displayText)
                        .foregroundStyle(backendStatus.color)
                }
            } header: {
                Text("Connection")
            }

            Section {
                Button(role: .destructive) {
                    isShowingDeleteAccountConfirmation = true
                } label: {
                    Label("Delete Account", systemImage: "person.crop.circle.badge.xmark")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
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
        .confirmationDialog("Delete all journals?", isPresented: $isShowingDeleteJournalsConfirmation, titleVisibility: .visible) {
            Button("Delete All Journals", role: .destructive) {
                deleteAllJournals()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only deletes journals stored in Voice Journal. This cannot be undone.")
        }
        .confirmationDialog("Delete account?", isPresented: $isShowingDeleteAccountConfirmation, titleVisibility: .visible) {
            Button("Delete Account and Journals", role: .destructive) {
                deleteAccount()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the local profile and deletes all journals stored in Voice Journal. This cannot be undone.")
        }
    }

    private func handleFaceIDLockChange(_ isEnabled: Bool) {
        guard isEnabled != faceIDLockEnabled else { return }

        if isEnabled {
            Task {
                let result = await AppLockAuthenticator.authenticate(reason: "Use Face ID to lock Voice Journal.")
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
}

private struct PasswordSetupView: View {
    @Binding var password: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @State private var didSubmit = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer(minLength: 12)

                VStack(spacing: 14) {
                    Image(systemName: "lock.rectangle")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Color.accentColor)

                    Text("Create a 6-digit password")
                        .font(.title3.bold())

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

                Text("Use six numbers to unlock Voice Journal without Face ID.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 28)
            .navigationTitle("Set Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
}

enum AppThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            "System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    static func value(for rawValue: String) -> AppThemePreference {
        if rawValue == "classic" {
            return .light
        }
        return AppThemePreference(rawValue: rawValue) ?? .system
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
            .system(.callout, design: design.fontDesign)
        case .standard:
            .system(.body, design: design.fontDesign)
        case .spacious:
            .system(.title3, design: design.fontDesign)
        }
    }

    func rowBodyFont(design: JournalFontDesignPreference) -> Font {
        switch self {
        case .compact:
            .system(.caption, design: design.fontDesign)
        case .standard:
            .system(.subheadline, design: design.fontDesign)
        case .spacious:
            .system(.body, design: design.fontDesign)
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

    static func value(for rawValue: String) -> JournalFontDesignPreference {
        JournalFontDesignPreference(rawValue: rawValue) ?? .system
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
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .center, spacing: 5) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(.headline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.58)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.72))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }
}

private struct ThemeCloudView: View {
    let themes: [(theme: String, count: Int)]

    private var maxCount: Int {
        themes.map(\.count).max() ?? 1
    }

    private var displayThemes: ArraySlice<(theme: String, count: Int)> {
        themes.prefix(12)
    }

    var body: some View {
        VStack(spacing: 14) {
            if let mainTheme = displayThemes.first {
                Text(mainTheme.theme)
                    .font(.system(size: fontSize(for: mainTheme.count) + 6, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel(mainTheme.theme)
            }

            ThemeCloudFlowLayout(spacing: 11, lineSpacing: 13) {
                ForEach(Array(displayThemes.dropFirst().enumerated()), id: \.element.theme) { index, item in
                    Text(item.theme)
                        .fontWeight(index < 2 ? .semibold : .regular)
                        .foregroundStyle(foregroundStyle(at: index + 1))
                        .font(.system(size: fontSize(for: item.count)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 2)
                        .accessibilityLabel(item.theme)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 230, alignment: .center)
        .padding(.horizontal, 4)
        .padding(.vertical, 12)
    }

    private func fontSize(for count: Int) -> CGFloat {
        let ratio = CGFloat(count) / CGFloat(maxCount)
        return 17 + (15 * ratio)
    }

    private func foregroundStyle(at index: Int) -> Color {
        let colors: [Color] = [.primary, .accentColor, .secondary, .teal, .indigo, .mint]
        return colors[index % colors.count]
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
        ThemeRule(label: "App Testing", terms: ["test", "testing", "app", "voice journal", "transcription", "recording", "测试", "应用", "语音日记", "转录", "录音"])
    ]
}

enum MarkdownJournalExporter {
    static func makeMarkdown(entries: [JournalEntry]) -> String {
        var lines = ["# Voice Journal Export", ""]

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
