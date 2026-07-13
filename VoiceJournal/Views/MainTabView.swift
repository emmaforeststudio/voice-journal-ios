import SwiftUI
import UIKit

struct MainTabView: View {
    @EnvironmentObject private var notificationNavigationCoordinator: NotificationNavigationCoordinator
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    @State private var selectedTab = 0
    @State private var calendarResetToken = 0
    @State private var insightsNavigationPath = NavigationPath()
    @State private var isOpeningNotificationLetter = false

    init() {
        Self.applyTabBarAppearance(for: .system)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            RecordJournalView {
                selectedTab = 1
            }
                .tabItem {
                    Label {
                        Text("Create")
                            .font(selectedFontDesignPreference.unscaledFont(.caption, weight: .medium))
                    } icon: {
                        Image("tab-create-microphone")
                    }
                }
                .tag(0)

            CalendarJournalView(resetToken: calendarResetToken)
                .tabItem {
                    Label {
                        Text("Calendar")
                            .font(selectedFontDesignPreference.unscaledFont(.caption, weight: .medium))
                    } icon: {
                        Image("tab-calendar")
                    }
                }
                .tag(1)

            InsightsJournalView(navigationPath: $insightsNavigationPath)
                .tabItem {
                    Label {
                        Text("Insights")
                            .font(selectedFontDesignPreference.unscaledFont(.caption, weight: .medium))
                    } icon: {
                        Image("tab-insights")
                    }
                }
                .tag(2)
        }
        .id(journalFontDesignPreference)
        .onAppear {
            Self.applyTabBarAppearance(for: selectedFontDesignPreference)
#if DEBUG
            openDebugFutureLetterIfRequested()
#endif
            openRequestedFutureLetter()
        }
        .onChange(of: journalFontDesignPreference) { _, _ in
            Self.applyTabBarAppearance(for: selectedFontDesignPreference)
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == 1, oldValue != 1 {
                calendarResetToken += 1
            }
            if newValue == 2,
               oldValue != 2,
               !isOpeningNotificationLetter {
                insightsNavigationPath = NavigationPath()
            }
        }
        .onChange(of: notificationNavigationCoordinator.futureLetterID) { _, _ in
            openRequestedFutureLetter()
        }
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }

    private func openRequestedFutureLetter() {
        guard let letterID = notificationNavigationCoordinator.futureLetterID else { return }
        isOpeningNotificationLetter = true
        selectedTab = 2
        insightsNavigationPath = NavigationPath()
        insightsNavigationPath.append(InsightsRoute.futureLetterDetail(letterID))
        notificationNavigationCoordinator.consumeFutureLetter(id: letterID)
        Task { @MainActor in
            await Task.yield()
            isOpeningNotificationLetter = false
        }
    }

#if DEBUG
    private func openDebugFutureLetterIfRequested() {
        let arguments = CommandLine.arguments
        guard let flagIndex = arguments.firstIndex(of: "--open-future-letter"),
              arguments.indices.contains(flagIndex + 1),
              let letterID = UUID(uuidString: arguments[flagIndex + 1]) else {
            return
        }
        notificationNavigationCoordinator.openFutureLetter(id: letterID)
    }
#endif

    private static func applyTabBarAppearance(for fontDesign: JournalFontDesignPreference) {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        configureTabBarItemAppearance(appearance.stackedLayoutAppearance, fontDesign: fontDesign)
        configureTabBarItemAppearance(appearance.inlineLayoutAppearance, fontDesign: fontDesign)
        configureTabBarItemAppearance(appearance.compactInlineLayoutAppearance, fontDesign: fontDesign)

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance

        UITabBarItem.appearance().setTitleTextAttributes(
            [.font: fontDesign.uiFont(size: 12.5, weight: .medium)],
            for: .normal
        )
        UITabBarItem.appearance().setTitleTextAttributes(
            [.font: fontDesign.uiFont(size: 12.5, weight: .semibold)],
            for: .selected
        )
    }

    private static func configureTabBarItemAppearance(_ appearance: UITabBarItemAppearance, fontDesign: JournalFontDesignPreference) {
        appearance.normal.titleTextAttributes = [
            .font: fontDesign.uiFont(size: 12.5, weight: .medium)
        ]
        appearance.selected.titleTextAttributes = [
            .font: fontDesign.uiFont(size: 12.5, weight: .semibold)
        ]
    }
}
