import SwiftData
import SwiftUI

enum HomeSegment: String, CaseIterable, Identifiable {
  case connections = "つながり"
  case list = "一覧"

  var id: Self { self }
}

/// つながりマップと人物一覧を、1つの「親戚」タブにまとめる親画面。
struct HomeView: View {
  @Environment(TrialManager.self) private var trialManager
  @Query(filter: #Predicate<Person> { $0.isSelf }) private var selfPersonQuery: [Person]

  @State private var selectedSegment: HomeSegment = .connections
  @State private var segmentBeforeSearch: HomeSegment?
  @State private var searchText = ""
  @State private var navigationPath: [Person] = []
  @State private var showingAddSheet = false
  @State private var showingPurchaseSheet = false

  var onStartOnboarding: () -> Void = {}

  var body: some View {
    NavigationStack(path: $navigationPath) {
      VStack(spacing: 0) {
        Picker("表示", selection: $selectedSegment) {
          ForEach(HomeSegment.allCases) { segment in
            Text(segment.rawValue).tag(segment)
          }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("home.segmentPicker")
        .disabled(!searchText.isEmpty)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)

        Group {
          switch selectedSegment {
          case .connections:
            mapContent
          case .list:
            PersonListView(
              searchText: $searchText,
              onRegisterSelf: onStartOnboarding
            )
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .background(AppTheme.paper)
      .navigationTitle(selectedSegment.rawValue)
      .navigationBarTitleDisplayMode(.inline)
      .searchable(
        text: $searchText,
        placement: .navigationBarDrawer(displayMode: .always),
        prompt: "名前・続柄・地域・集まりで探す"
      )
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            if trialManager.canEdit {
              showingAddSheet = true
            } else {
              showingPurchaseSheet = true
            }
          } label: {
            Image(systemName: "plus")
          }
          .frame(minWidth: 44, minHeight: 44)
          .contentShape(Rectangle())
          .accessibilityLabel("人物を追加")
        }
      }
      .navigationDestination(for: Person.self) { person in
        PersonDetailView(person: person)
      }
      .sheet(isPresented: $showingAddSheet) {
        PersonFormView()
      }
      .sheet(isPresented: $showingPurchaseSheet) {
        PurchaseSheet()
      }
      .onChange(of: searchText) { oldValue, newValue in
        if oldValue.isEmpty, !newValue.isEmpty {
          segmentBeforeSearch = selectedSegment
          selectedSegment = .list
        } else if !oldValue.isEmpty, newValue.isEmpty {
          selectedSegment = segmentBeforeSearch ?? selectedSegment
          segmentBeforeSearch = nil
        }
      }
    }
  }

  @ViewBuilder
  private var mapContent: some View {
    if let selfPerson = selfPersonQuery.first {
      FamilyGraphView(
        selfPerson: selfPerson,
        displayedPerson: selfPerson,
        viewportHeight: nil,
        playsIntroAnimation: false,
        canvasIdentifier: "connectionMap.home.canvas",
        onShowDetail: { navigationPath.append($0) }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      VStack(spacing: 16) {
        ContentUnavailableView(
          "まず自分を登録しましょう",
          systemImage: "person.crop.circle.badge.plus",
          description: Text("自分を起点にすると、親戚のつながりを表示できます。")
        )
        Button("自分を登録する", action: onStartOnboarding)
          .buttonStyle(.borderedProminent)
          .tint(AppTheme.ai)
          .accessibilityIdentifier("home.empty.startOnboarding")
      }
    }
  }
}

#Preview {
  HomeView()
    .environment(
      TrialManager(
        defaults: UserDefaults(suiteName: "preview.home.trial")!,
        firstLaunchDateStore: KeychainStore(service: "preview.home.trial")
      )
    )
    .modelContainer(for: [Person.self, Gathering.self], inMemory: true)
}
