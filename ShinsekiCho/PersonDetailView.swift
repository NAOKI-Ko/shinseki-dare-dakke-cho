import SwiftUI
import SwiftData

enum PersonContactURL {
    static func phone(from rawValue: String) -> URL? {
        let digits = rawValue.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel://\(digits)")
    }

    static func email(from rawValue: String) -> URL? {
        let address = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty,
              let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "mailto:\(encoded)")
    }
}

struct PersonDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var person: Person

    @Query(filter: #Predicate<Person> { $0.isSelf }) private var selfPersonQuery: [Person]

    @State private var showingEdit = false
    @State private var showingRelationEditor = false

    var body: some View {
        List {
            // 見出し(図鑑の顔写真・名前・続柄)
            Section {
                HairlineCard {
                    VStack(spacing: 10) {
                        photoView
                        Text(person.name)
                            .font(.minchoAmount(20, relativeTo: .title3))
                            .foregroundStyle(AppTheme.ink)
                        if !person.relationNote.isEmpty {
                            Text(person.relationNote)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.inkSoft)
                        }
                    }
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            }

            // 連絡先(タップで発信・メール作成)
            if person.hasContact {
                Section {
                    if let url = PersonContactURL.phone(from: person.phone) {
                        Link(destination: url) {
                            Label(person.phone, systemImage: "phone.fill")
                        }
                        .foregroundStyle(AppTheme.ai)
                        .accessibilityIdentifier("personDetail.phoneLink")
                        .accessibilityValue(url.absoluteString)
                    }
                    if let url = PersonContactURL.email(from: person.email) {
                        Link(destination: url) {
                            Label(person.email, systemImage: "envelope.fill")
                        }
                        .foregroundStyle(AppTheme.ai)
                        .accessibilityIdentifier("personDetail.emailLink")
                        .accessibilityValue(url.absoluteString)
                    }
                } header: {
                    Text("連絡先")
                        .accessibilityIdentifier("personDetail.contactHeader")
                }
                .listRowBackground(AppTheme.paperRaised)
            }

            // 図鑑プロフィール(埋まっている項目だけ並べる)
            Section {
                if let lastMet = person.lastMetDate {
                    LabeledContent("最後に会った日") {
                        Text(lastMet.formatted(.dateTime.year().month().day())
                            + (person.lastMetPlace.isEmpty ? "" : "・\(person.lastMetPlace)"))
                    }
                    .accessibilityIdentifier("personDetail.lastMet")
                }
                if !person.livingArea.isEmpty {
                    LabeledContent("居住地", value: person.livingArea)
                        .accessibilityIdentifier("personDetail.livingArea")
                }
                if let birthday = person.birthday {
                    LabeledContent(
                        "誕生日",
                        value: birthday.formatted(.dateTime.month().day())
                    )
                    .accessibilityIdentifier("personDetail.birthday")
                }
                if !person.postalAddress.isEmpty {
                    LabeledContent("住所", value: person.postalAddress)
                        .accessibilityIdentifier("personDetail.postalAddress")
                }
                if !person.favorites.isEmpty {
                    LabeledContent("好み", value: person.favorites)
                        .accessibilityIdentifier("personDetail.favorites")
                }
                if !person.dietaryNotes.isEmpty {
                    LabeledContent("アレルギー・食事の配慮", value: person.dietaryNotes)
                        .foregroundStyle(AppTheme.attention)
                        .accessibilityIdentifier("personDetail.dietaryNotes")
                        .accessibilityValue("AppTheme.attention")
                }
                if allProfileFieldsEmpty {
                    Text("「編集」から、居住地や誕生日などを登録できます。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.inkSoft)
                        .accessibilityIdentifier("personDetail.emptyProfile")
                }
            } header: {
                Text("プロフィール")
                    .accessibilityIdentifier("personDetail.profileHeader")
            }
            .listRowBackground(AppTheme.paperRaised)

            // つながりマップ(自分を起点に、辿った人物が蓄積表示される)
            Section {
                if let selfPerson = selfPersonQuery.first {
                    FamilyGraphView(selfPerson: selfPerson) { _ in }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(AppTheme.paperRaised)
                } else {
                    Text("「設定」タブで、まず「自分」を登録してください。つながりマップは自分を起点に表示されます。")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.inkSoft)
                        .padding()
                        .listRowBackground(AppTheme.paperRaised)
                }
            } header: {
                Text("つながり")
            } footer: {
                Text("ノードをタップすると、その人の親・子・配偶者が地図上に広がります。ピンチで拡大縮小、ドラッグで移動できます。")
            }

            // 関係の編集(常にperson自身に対して行う)
            Section {
                Button {
                    showingRelationEditor = true
                } label: {
                    Label("関係を編集する", systemImage: "person.line.dotted.person.fill")
                }
                .foregroundStyle(AppTheme.ai)
            } footer: {
                Text("配偶者・親・子を登録すると、つながりマップに表示されます。")
            }
            .listRowBackground(AppTheme.paperRaised)

            // 会話メモ
            if !person.memo.isEmpty {
                Section("会話メモ") {
                    Text(person.memo)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.inkSoft)
                        .accessibilityIdentifier("personDetail.memo")
                }
                .listRowBackground(AppTheme.paperRaised)
            }

            // 出席した集まり
            if !person.gatherings.isEmpty {
                Section("出席した集まり") {
                    ForEach(person.gatherings.sorted { $0.date > $1.date }) { gathering in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(gathering.title).font(.body.weight(.medium))
                            Text(gathering.date.formatted(.dateTime.year().month().day()))
                                .font(.caption)
                                .foregroundStyle(AppTheme.inkSoft)
                        }
                    }
                }
                .listRowBackground(AppTheme.paperRaised)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.paper)
        // フローティング形状のタブバー下まで、最後のプロフィール行を
        // スクロールして完全に見せられる余白を確保する。
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: 64)
                .accessibilityHidden(true)
        }
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("編集") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            PersonFormView(personToEdit: person)
        }
        .sheet(isPresented: $showingRelationEditor) {
            RelationEditorView(person: person)
        }
    }

    private var allProfileFieldsEmpty: Bool {
        person.lastMetDate == nil
            && person.livingArea.isEmpty
            && person.birthday == nil
            && person.postalAddress.isEmpty
            && person.favorites.isEmpty
            && person.dietaryNotes.isEmpty
    }

    @ViewBuilder
    private var photoView: some View {
        Group {
            if let uiImage = PersonPhotoSupport.image(from: person.photoData) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(AppTheme.ai.opacity(0.08))
                    Text(PersonPhotoSupport.initial(for: person.name))
                        .font(.minchoTitle(30, relativeTo: .largeTitle))
                        .foregroundStyle(AppTheme.ai)
                        .accessibilityIdentifier("personDetail.photo.initial")
                }
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(Circle())
        .overlay(Circle().stroke(AppTheme.ai.opacity(0.35), lineWidth: 1.5))
    }
}

// MARK: - 関係編集(配偶者・親・子)

struct RelationEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var person: Person

    @Query(sort: [SortDescriptor(\Person.kana), SortDescriptor(\Person.name)])
    private var allPersons: [Person]

    private var candidates: [Person] {
        allPersons.filter { $0.persistentModelID != person.persistentModelID }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("配偶者") {
                    if let spouse = person.spouse {
                        HStack {
                            Text(spouse.name)
                            Spacer()
                            Button("解除") { RelationshipManager.removeSpouse(of: person) }
                                .font(.caption)
                                .foregroundStyle(AppTheme.attention)
                        }
                    } else {
                        Menu("配偶者を選ぶ") {
                            ForEach(candidates) { candidate in
                                Button(candidate.name) {
                                    RelationshipManager.setSpouse(person, candidate)
                                }
                            }
                        }
                    }
                }
                .listRowBackground(AppTheme.paperRaised)

                Section("親") {
                    ForEach(person.parents) { parent in
                        HStack {
                            Text(parent.name)
                            Spacer()
                            Button("解除") { RelationshipManager.removeParentChild(parent: parent, child: person) }
                                .font(.caption)
                                .foregroundStyle(AppTheme.attention)
                        }
                    }
                    if person.parents.count < 2 {
                        Menu("親を追加") {
                            ForEach(candidates.filter { !person.parents.contains($0) }) { candidate in
                                Button(candidate.name) {
                                    RelationshipManager.addParentChild(parent: candidate, child: person)
                                }
                            }
                        }
                    }
                }
                .listRowBackground(AppTheme.paperRaised)

                Section("子") {
                    ForEach(person.children) { child in
                        HStack {
                            Text(child.name)
                            Spacer()
                            Button("解除") { RelationshipManager.removeParentChild(parent: person, child: child) }
                                .font(.caption)
                                .foregroundStyle(AppTheme.attention)
                        }
                    }
                    Menu("子を追加") {
                        ForEach(candidates.filter { !person.children.contains($0) }) { candidate in
                            Button(candidate.name) {
                                RelationshipManager.addParentChild(parent: person, child: candidate)
                            }
                        }
                    }
                }
                .listRowBackground(AppTheme.paperRaised)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.paper)
            .navigationTitle("\(person.name)さんの関係")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }
}
