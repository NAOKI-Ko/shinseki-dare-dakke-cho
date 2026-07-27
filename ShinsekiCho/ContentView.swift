import SwiftUI
import SwiftData

struct ContentView: View {
    @Query(filter: #Predicate<Person> { $0.isSelf }) private var selfPersonQuery: [Person]

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
            if selfPersonQuery.isEmpty {
                // 「自分」が未登録なら、まずオンボーディングを通す。
                // onCompleteは何もしなくてよい(SwiftDataへの保存が反映されると
                // selfPersonQueryが自動更新され、このGroupが自然にTabViewへ切り替わる)。
                OnboardingView(onComplete: {})
            } else {
                TabView {
                    PersonListView()
                        .tabItem { Label("親戚", systemImage: "person.2") }

                    GatheringListView()
                        .tabItem { Label("集まり", systemImage: "person.3.sequence") }

                    SettingsView()
                        .tabItem { Label("設定", systemImage: "gearshape") }
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Person.self, Gathering.self], inMemory: true)
}
