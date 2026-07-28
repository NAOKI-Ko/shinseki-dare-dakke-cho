import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(TrialManager.self) private var trialManager
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<Person> { $0.isSelf }) private var selfPersonQuery: [Person]
    @AppStorage("onboarding.guidePending") private var isContinuingOnboarding = false

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
            if selfPersonQuery.isEmpty || isContinuingOnboarding {
                // 「自分」が未登録なら、まずオンボーディングを通す。
                // 登録直後は使い方説明まで同じフロー内に留まり、完了または
                // スキップ後にselfPersonQueryの通常画面へ切り替える。
                OnboardingFlowView(
                    startAtGuide: !selfPersonQuery.isEmpty,
                    onRegistrationComplete: {
                        isContinuingOnboarding = true
                    },
                    onComplete: {
                        isContinuingOnboarding = false
                    }
                )
            } else {
                TabView {
                    HomeView()
                        .tabItem { Label("親戚", systemImage: "person.2") }

                    GatheringListView()
                        .tabItem { Label("集まり", systemImage: "person.3.sequence") }

                    SettingsView()
                        .tabItem { Label("設定", systemImage: "gearshape") }
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await trialManager.refreshEntitlement() }
        }
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
