import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(TrialManager.self) private var trialManager
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<Person> { $0.isSelf }) private var selfPersonQuery: [Person]
    @AppStorage(OnboardingStorageKeys.hasStarted) private var onboardingHasStarted = false
    @AppStorage(OnboardingStorageKeys.hasCompleted) private var onboardingHasCompleted = false
    @AppStorage(OnboardingStorageKeys.legacyGuidePending) private var legacyGuidePending = false
    @State private var onboardingReplayRequested = false

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(AppTheme.paper)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance

        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(AppTheme.ai)
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.foregroundColor: UIColor.white], for: .selected
        )
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.foregroundColor: UIColor(AppTheme.ink)], for: .normal
        )
    }

    var body: some View {
        Group {
            if shouldPresentOnboarding {
                OnboardingFlowView(
                    mode: onboardingMode,
                    existingSelf: selfPersonQuery.first,
                    onComplete: finishOnboarding,
                    onSkip: finishOnboarding
                )
                .onAppear { onboardingHasStarted = true }
            } else {
                TabView {
                    HomeView(onStartOnboarding: requestOnboardingReplay)
                        .tabItem { Label("親戚", systemImage: "person.2") }

                    GatheringListView()
                        .tabItem { Label("集まり", systemImage: "person.3.sequence") }

                    SettingsView(onReplayOnboarding: requestOnboardingReplay)
                        .tabItem { Label("設定", systemImage: "gearshape") }
                }
            }
        }
        .onAppear(perform: migrateLegacyOnboardingStateIfNeeded)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await trialManager.refreshEntitlement() }
        }
    }

    private var shouldPresentOnboarding: Bool {
        if legacyGuidePending { return true }
        return OnboardingProgress(
            hasStarted: onboardingHasStarted,
            hasCompleted: onboardingHasCompleted,
            isReplayRequested: onboardingReplayRequested
        ).shouldPresent(hasRegisteredSelf: !selfPersonQuery.isEmpty)
    }

    private var onboardingMode: OnboardingMode {
        onboardingReplayRequested && !selfPersonQuery.isEmpty ? .replay : .firstRun
    }

    private func requestOnboardingReplay() {
        onboardingReplayRequested = true
    }

    private func finishOnboarding() {
        onboardingHasStarted = true
        onboardingHasCompleted = true
        onboardingReplayRequested = false
        legacyGuidePending = false
    }

    private func migrateLegacyOnboardingStateIfNeeded() {
        guard !onboardingHasStarted,
              !onboardingHasCompleted,
              !legacyGuidePending,
              !selfPersonQuery.isEmpty
        else { return }
        // 旧版でオンボーディングを完了している既存利用者を完了扱いにする。
        onboardingHasCompleted = true
    }
}

#Preview {
    ContentView()
        .environment(
            TrialManager(
                defaults: UserDefaults(suiteName: "preview.trial")!,
                firstLaunchDateStore: KeychainStore(service: "preview.shinsekicho.trial")
            )
        )
        .modelContainer(for: [Person.self, Gathering.self], inMemory: true)
}
