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
            PersonListView(searchText: $searchText)
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
        prompt: "名前・続柄で探す"
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
      ContentUnavailableView(
        "自分を登録してください",
        systemImage: "person.crop.circle.badge.plus",
        description: Text("設定から自分を登録すると、つながりを表示できます。")
      )
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
