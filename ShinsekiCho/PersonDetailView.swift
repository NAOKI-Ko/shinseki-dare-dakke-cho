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
    @Environment(TrialManager.self) private var trialManager
    @Bindable var person: Person

    @Query(filter: #Predicate<Person> { $0.isSelf }) private var selfPersonQuery: [Person]

    @State private var showingEdit = false
    @State private var showingRelationEditor = false
    @State private var mapSelectedPerson: Person?
    @State private var showingPurchaseSheet = false
    @State private var graphRevision = UUID()
    @State private var showingPersonMerge = false

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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    person.relationNote.isEmpty
                        ? person.name
                        : "\(person.name)、続柄、\(person.relationNote)"
                )
                .accessibilityValue(
                    PersonPhotoSupport.image(from: person.photoData) == nil
                        ? "写真なし"
                        : "写真あり"
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            }

            // 保存済み情報だけで「この人は誰か」を先に思い出せるようにする。
            // 経路は永続化せず、現在の関係グラフから表示のたびに再計算する。
            Section {
                PersonMemorySummaryView(summary: memorySummary)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            // 関係の編集は、縦に大きいつながりマップより前に置き、
            // 詳細を開いた直後に見つけられるようにする。
            Section {
                Button {
                    requestEditing { showingRelationEditor = true }
                } label: {
                    Label("関係を編集する", systemImage: "person.line.dotted.person.fill")
                }
                .foregroundStyle(AppTheme.ai)
                .accessibilityIdentifier("personDetail.editRelations")
            } footer: {
                Text("配偶者・親・子を登録すると、つながりマップに表示されます。")
            }
            .listRowBackground(AppTheme.paperRaised)

            Section {
                Button {
                    requestEditing { showingPersonMerge = true }
                } label: {
                    Label("重複した人物を統合", systemImage: "person.2.badge.gearshape")
                }
                .foregroundStyle(AppTheme.inkSoft)
                .accessibilityIdentifier("personDetail.mergeDuplicate")
            } footer: {
                Text("同じ人物を重複して登録した場合に、確認しながら1人へまとめます。自動では統合されません。")
            }
            .listRowBackground(AppTheme.paperRaised)

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
                        .accessibilityLabel(
                            "アレルギー・食事の配慮、\(person.dietaryNotes)、注意"
                        )
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
                    FamilyGraphView(
                        selfPerson: selfPerson,
                        displayedPerson: person,
                        resetButtonIdentifier: "connectionMap.detail.resetButton",
                        onShowDetail: { mapSelectedPerson = $0 }
                    )
                        .id(graphRevision)
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
                        .accessibilityIdentifier("personDetail.gathering.\(gathering.title)")
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
                Button("編集") {
                    requestEditing { showingEdit = true }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            PersonFormView(personToEdit: person)
        }
        .sheet(isPresented: $showingRelationEditor) {
            RelationEditorView(person: person) {
                graphRevision = UUID()
            }
        }
        .sheet(isPresented: $showingPersonMerge) {
            PersonMergeCandidateView(survivor: person) {
                showingPersonMerge = false
                graphRevision = UUID()
            }
        }
        .sheet(isPresented: $showingPurchaseSheet) {
            PurchaseSheet()
        }
        .navigationDestination(item: $mapSelectedPerson) { selectedPerson in
            PersonDetailView(person: selectedPerson)
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

    private var memorySummary: PersonMemorySummary {
        PersonMemorySummaryBuilder.make(
            selfPerson: selfPersonQuery.first,
            target: person
        )
    }

    private func requestEditing(_ action: () -> Void) {
        if trialManager.canEdit {
            action()
        } else {
            showingPurchaseSheet = true
        }
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

struct PersonMemorySummaryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let summary: PersonMemorySummary

    var body: some View {
        HairlineCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("この人を思い出す", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.minchoAmount(15, relativeTo: .headline).weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 4) {
                    Text("自分とのつながり")
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkSoft)
                    Text(summary.relationship.breadcrumb)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("personMemory.relationship")
                        .accessibilityLabel(
                            "自分とのつながり、"
                                + summary.relationship.breadcrumb
                                    .replacingOccurrences(of: " → ", with: "、")
                        )

                    if let label = summary.relationship.structuredLabel {
                        Text(label)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.ai)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(AppTheme.ai.opacity(0.08), in: Capsule())
                            .accessibilityIdentifier("personMemory.structuredRelation")
                            .accessibilityLabel("続柄、\(label)")
                    }
                }

                if let lastMet = summary.lastMet {
                    memoryRow(
                        title: "最後に会った",
                        value: lastMet.date.formatted(.dateTime.year().month().day())
                            + (lastMet.place.map { "・\($0)" } ?? ""),
                        identifier: "personMemory.lastMet"
                    )
                }
                if let livingArea = summary.livingArea {
                    memoryRow(
                        title: "住んでいるところ",
                        value: livingArea,
                        identifier: "personMemory.livingArea"
                    )
                }
                if let memo = summary.memo {
                    memoryRow(
                        title: "会話のきっかけ",
                        value: memo,
                        identifier: "personMemory.memo",
                        lineLimit: 2
                    )
                }
                if let favorites = summary.favorites {
                    memoryRow(
                        title: "好きなもの・苦手なもの",
                        value: favorites,
                        identifier: "personMemory.favorites",
                        lineLimit: 2
                    )
                }
                if let gathering = summary.latestGathering {
                    memoryRow(
                        title: "最近の集まり",
                        value: "\(gathering.title)・\(gathering.date.formatted(.dateTime.year().month().day()))",
                        identifier: "personMemory.latestGathering",
                        lineLimit: 2
                    )
                }
            }
            .padding(14)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("personMemory.summary")
    }

    private func memoryRow(
        title: String,
        value: String,
        identifier: String,
        lineLimit: Int = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.inkSoft)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
                .accessibilityLabel("\(title)、\(value)")
        }
    }
}

// MARK: - 関係編集(配偶者・親・子)

struct RelationEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(TrialManager.self) private var trialManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var person: Person
    var onRelationshipChange: () -> Void = {}

    @Query(sort: [SortDescriptor(\Person.kana), SortDescriptor(\Person.name)])
    private var allPersons: [Person]

    @State private var showingPurchaseSheet = false
    @State private var pendingChildCandidate: Person?
    @State private var sharedChildPrompt: SharedChildPrompt?
    @State private var pendingUnlink: RelationshipCorrectionRequest?
    @State private var replacementRequest: RelationshipCorrectionRequest?
    @State private var errorMessage: String?

    private var candidates: [Person] {
        allPersons.filter { $0.persistentModelID != person.persistentModelID }
    }

    private func linkCandidates(for kind: RelationshipKind) -> [Person] {
        candidates.filter {
            RelationshipManager.canLink(kind, person: person, relative: $0)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("配偶者") {
                    if let spouse = person.spouse {
                        relationshipRow(kind: .spouse, relative: spouse)
                    } else if linkCandidates(for: .spouse).isEmpty {
                        unavailableCandidateRow(for: .spouse)
                    } else {
                        Menu("配偶者を選ぶ") {
                            ForEach(linkCandidates(for: .spouse)) { candidate in
                                Button(candidate.name) {
                                    performEdit({
                                        try RelationshipManager.link(
                                            .spouse,
                                            person: person,
                                            relative: candidate
                                        )
                                    }) {
                                        let children = RelationshipManager.sharedChildCandidates(
                                            of: person,
                                            with: candidate
                                        )
                                        if !children.isEmpty {
                                            sharedChildPrompt = SharedChildPrompt(
                                                person: person,
                                                spouse: candidate,
                                                candidates: children
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .listRowBackground(AppTheme.paperRaised)

                Section("親") {
                    ForEach(person.parents) { parent in
                        relationshipRow(kind: .parent, relative: parent)
                    }
                    if person.parents.count < 2 {
                        if linkCandidates(for: .parent).isEmpty {
                            unavailableCandidateRow(for: .parent)
                        } else {
                            Menu("親を追加") {
                                ForEach(linkCandidates(for: .parent)) { candidate in
                                    Button(candidate.name) {
                                        performEdit {
                                            try RelationshipManager.link(
                                                .parent,
                                                person: person,
                                                relative: candidate
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .listRowBackground(AppTheme.paperRaised)

                Section("子") {
                    ForEach(person.children) { child in
                        relationshipRow(kind: .child, relative: child)
                    }
                    if linkCandidates(for: .child).isEmpty {
                        unavailableCandidateRow(for: .child)
                    } else {
                        Menu("子を追加") {
                            ForEach(linkCandidates(for: .child)) { candidate in
                                Button(candidate.name) {
                                    pendingChildCandidate = candidate
                                }
                            }
                        }
                    }
                }
                .listRowBackground(AppTheme.paperRaised)

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.attention)
                    }
                    .listRowBackground(AppTheme.paperRaised)
                }
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
            .sheet(isPresented: $showingPurchaseSheet) {
                PurchaseSheet()
            }
            .sheet(item: $sharedChildPrompt) { prompt in
                SharedChildrenLinkSheet(prompt: prompt) { selectedChildren in
                    performEdit {
                        RelationshipManager.linkSharedChildren(
                            selectedChildren,
                            of: prompt.person,
                            with: prompt.spouse
                        )
                    }
                }
            }
            .sheet(item: $replacementRequest) { request in
                RelationshipReplacementSheet(
                    request: request,
                    candidates: candidates.filter {
                        RelationshipManager.canReplace(
                            request.kind,
                            person: request.person,
                            oldRelative: request.relative,
                            newRelative: $0
                        )
                    }
                ) { replacement in
                    replaceRelationship(request, with: replacement)
                }
            }
            .alert(
                "関係を解除",
                isPresented: Binding(
                    get: { pendingUnlink != nil },
                    set: { if !$0 { pendingUnlink = nil } }
                ),
                presenting: pendingUnlink
            ) { request in
                Button("関係を解除", role: .destructive) {
                    unlinkRelationship(request)
                }
                Button("キャンセル", role: .cancel) {}
            } message: { request in
                Text(
                    "\(request.relative.name)さんとの「\(request.kind.displayName)」の関係を解除しますか？人物そのものは削除されません。"
                )
            }
            .confirmationDialog(
                "子として追加",
                isPresented: Binding(
                    get: { pendingChildCandidate != nil },
                    set: { if !$0 { pendingChildCandidate = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingChildCandidate
            ) { candidate in
                Button("\(person.name)だけの子として追加") {
                    linkChild(candidate, includeSpouse: false)
                }
                if let spouse = person.spouse {
                    Button("\(person.name)と\(spouse.name)の共同の子として追加") {
                        linkChild(candidate, includeSpouse: true)
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: { _ in
                Text("共同の子にする場合だけ、配偶者との親子関係も追加します。")
            }
        }
    }

    @ViewBuilder
    private func unavailableCandidateRow(for kind: RelationshipKind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("追加できる\(kind.displayName)がいません")
                .foregroundStyle(AppTheme.ink)
            Text("人物を登録するか、既存の関係を確認してください。")
                .font(.caption)
                .foregroundStyle(AppTheme.inkSoft)
        }
        .accessibilityIdentifier("relationship.empty.\(kind.rawValue)")
    }

    @ViewBuilder
    private func relationshipRow(kind: RelationshipKind, relative: Person) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(kind.displayName)
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkSoft)
                Text(relative.name)
                    .foregroundStyle(AppTheme.ink)
                Spacer()
            }
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .trailing, spacing: 0) {
                        relationshipChangeButton(kind: kind, relative: relative)
                        relationshipUnlinkButton(kind: kind, relative: relative)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    HStack(spacing: 16) {
                        Spacer()
                        relationshipChangeButton(kind: kind, relative: relative)
                        relationshipUnlinkButton(kind: kind, relative: relative)
                    }
                }
            }
        }
    }

    private func relationshipChangeButton(
        kind: RelationshipKind,
        relative: Person
    ) -> some View {
        Button("関係を変更") {
            replacementRequest = RelationshipCorrectionRequest(
                kind: kind,
                person: person,
                relative: relative
            )
        }
        .font(.caption)
        .foregroundStyle(AppTheme.ai)
        .buttonStyle(.borderless)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel("\(relative.name)さんとの\(kind.displayName)関係を変更")
        .accessibilityIdentifier(
            "relationship.change.\(kind.rawValue).\(relative.name)"
        )
    }

    private func relationshipUnlinkButton(
        kind: RelationshipKind,
        relative: Person
    ) -> some View {
        Button("関係を解除", role: .destructive) {
            pendingUnlink = RelationshipCorrectionRequest(
                kind: kind,
                person: person,
                relative: relative
            )
        }
        .font(.caption)
        .buttonStyle(.borderless)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel("\(relative.name)さんとの\(kind.displayName)関係を解除")
        .accessibilityIdentifier(
            "relationship.unlink.\(kind.rawValue).\(relative.name)"
        )
    }

    private func unlinkRelationship(_ request: RelationshipCorrectionRequest) {
        pendingUnlink = nil
        performEdit {
            try RelationshipManager.unlink(
                request.kind,
                person: request.person,
                relative: request.relative
            )
        }
    }

    private func replaceRelationship(
        _ request: RelationshipCorrectionRequest,
        with replacement: Person
    ) {
        replacementRequest = nil
        performEdit {
            try RelationshipManager.replace(
                request.kind,
                person: request.person,
                oldRelative: request.relative,
                newRelative: replacement
            )
        }
    }

    private func linkChild(_ child: Person, includeSpouse: Bool) {
        pendingChildCandidate = nil
        performEdit {
            try RelationshipManager.link(
                .child,
                person: person,
                relative: child,
                includeSpouseForChild: includeSpouse
            )
        }
    }

    private func performEdit(
        _ action: () throws -> Void,
        onSuccess: () -> Void = {}
    ) {
        if trialManager.canEdit {
            do {
                try RelationshipTransaction.perform(in: context, action)
                errorMessage = nil
                onRelationshipChange()
                onSuccess()
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            showingPurchaseSheet = true
        }
    }
}

struct RelationshipCorrectionRequest: Identifiable {
    let id = UUID()
    let kind: RelationshipKind
    let person: Person
    let relative: Person
}

extension RelationshipKind {
    var displayName: String {
        switch self {
        case .spouse: "配偶者"
        case .parent: "親"
        case .child: "子"
        }
    }
}

struct RelationshipReplacementSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: RelationshipCorrectionRequest
    let candidates: [Person]
    let onReplace: (Person) -> Void

    @State private var searchText = ""

    private var filteredCandidates: [Person] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return candidates }
        return candidates.filter {
            $0.name.localizedCaseInsensitiveContains(keyword)
                || $0.kana.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("現在の\(request.kind.displayName)") {
                    Text(request.relative.name)
                        .foregroundStyle(AppTheme.ink)
                }
                .listRowBackground(AppTheme.paperRaised)

                Section {
                    if filteredCandidates.isEmpty {
                        Text("変更できる登録済み人物がいません。")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.inkSoft)
                    } else {
                        ForEach(filteredCandidates) { candidate in
                            Button {
                                onReplace(candidate)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(candidate.name)
                                        .foregroundStyle(AppTheme.ink)
                                    Spacer()
                                    Image(systemName: "arrow.right.circle")
                                        .foregroundStyle(AppTheme.ai)
                                }
                            }
                            .accessibilityIdentifier(
                                "relationship.replacement.\(candidate.name)"
                            )
                        }
                    }
                } header: {
                    Text("変更先")
                } footer: {
                    if request.kind == .spouse {
                        Text("配偶者を変更しても、既存の子の親子関係は自動では変更されません。")
                    } else {
                        Text("人物そのものは削除されず、この関係だけが付け替えられます。")
                    }
                }
                .listRowBackground(AppTheme.paperRaised)
            }
            .searchable(text: $searchText, prompt: "名前で検索")
            .scrollContentBackground(.hidden)
            .background(AppTheme.paper)
            .navigationTitle("\(request.kind.displayName)を変更")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(AppTheme.paper)
    }
}

// MARK: - 重複人物の統合

struct PersonMergeCandidateView: View {
    @Environment(\.dismiss) private var dismiss
    let survivor: Person
    let onMerged: () -> Void

    @Query(sort: [SortDescriptor(\Person.kana), SortDescriptor(\Person.name)])
    private var allPersons: [Person]
    @State private var searchText = ""

    private var availablePeople: [Person] {
        allPersons.filter { $0.persistentModelID != survivor.persistentModelID }
    }

    private var detectedCandidates: [Person] {
        PersonDuplicateDetector.candidates(for: survivor, among: availablePeople)
    }

    private var searchedPeople: [Person] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return availablePeople }
        return availablePeople.filter {
            $0.name.localizedCaseInsensitiveContains(keyword)
                || $0.kana.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("現在開いている「\(survivor.name)」を残し、選択した人物の情報・関係・集まりを統合します。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.inkSoft)
                }
                .listRowBackground(AppTheme.paperRaised)

                Section("重複候補") {
                    if detectedCandidates.isEmpty {
                        Text("安全に判定できる重複候補はありません。")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.inkSoft)
                    } else {
                        ForEach(detectedCandidates) { candidate in
                            candidateLink(candidate)
                        }
                    }
                }
                .listRowBackground(AppTheme.paperRaised)

                Section("登録済み人物から探す") {
                    if searchedPeople.isEmpty {
                        Text("該当する人物はいません。")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.inkSoft)
                    } else {
                        ForEach(searchedPeople) { candidate in
                            candidateLink(candidate)
                        }
                    }
                }
                .listRowBackground(AppTheme.paperRaised)
            }
            .searchable(text: $searchText, prompt: "名前・ふりがなで検索")
            .scrollContentBackground(.hidden)
            .background(AppTheme.paper)
            .navigationTitle("重複した人物を統合")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
        .presentationBackground(AppTheme.paper)
    }

    @ViewBuilder
    private func candidateLink(_ candidate: Person) -> some View {
        let selfWouldBeDeleted = candidate.isSelf && !survivor.isSelf
        NavigationLink {
            PersonMergePreviewView(
                survivor: survivor,
                duplicate: candidate,
                onMerged: onMerged
            )
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.name)
                    .foregroundStyle(selfWouldBeDeleted ? AppTheme.inkSoft : AppTheme.ink)
                if !candidate.kana.isEmpty {
                    Text(candidate.kana)
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkSoft)
                }
                if selfWouldBeDeleted {
                    Text("「自分」の人物詳細から統合してください")
                        .font(.caption)
                        .foregroundStyle(AppTheme.attention)
                }
            }
        }
        .disabled(selfWouldBeDeleted)
        .accessibilityIdentifier("personMerge.candidate.\(candidate.name)")
    }
}

struct PersonMergePreviewView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let plan: PersonMergePlan
    let onMerged: () -> Void

    @State private var choices: [PersonMergeField: PersonMergeSide] = [:]
    @State private var showingFinalConfirmation = false
    @State private var errorMessage: String?

    init(survivor: Person, duplicate: Person, onMerged: @escaping () -> Void) {
        plan = PersonMergePlan.make(survivor: survivor, duplicate: duplicate)
        self.onMerged = onMerged
    }

    private var allConflictsResolved: Bool {
        plan.conflicts.allSatisfy { choices[$0.field] != nil }
    }

    var body: some View {
        List {
            Section("残す人物") {
                personSummary(plan.survivor)
            }
            .listRowBackground(AppTheme.paperRaised)

            Section("統合する人物") {
                personSummary(plan.duplicate)
            }
            .listRowBackground(AppTheme.paperRaised)

            if !plan.structuralIssues.isEmpty {
                Section("先に整理が必要です") {
                    ForEach(plan.structuralIssues) { issue in
                        Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.attention)
                    }
                }
                .listRowBackground(AppTheme.paperRaised)
            }

            Section("追加される情報") {
                if plan.addedFields.isEmpty {
                    Text("自動で補完されるプロフィール項目はありません。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.inkSoft)
                } else {
                    ForEach(plan.addedFields) { field in
                        LabeledContent(
                            field.displayName,
                            value: plan.automaticProfile.description(for: field)
                        )
                        .accessibilityIdentifier("personMerge.added.\(field.rawValue)")
                    }
                }
            }
            .listRowBackground(AppTheme.paperRaised)

            if !plan.conflicts.isEmpty {
                Section("確認が必要") {
                    ForEach(plan.conflicts) { conflict in
                        conflictRow(conflict)
                    }
                }
                .listRowBackground(AppTheme.paperRaised)
            }

            Section("引き継ぐつながり") {
                mergeSummary("配偶者", names: plan.relationship.spouse.map { [$0.name] } ?? [])
                mergeSummary("親", names: plan.relationship.parents.map(\.name))
                mergeSummary("子", names: plan.relationship.children.map(\.name))
                mergeSummary("集まり", names: plan.gatherings.map(\.title))
            }
            .listRowBackground(AppTheme.paperRaised)

            Section {
                Button("統合内容を確認", role: .destructive) {
                    showingFinalConfirmation = true
                }
                .frame(maxWidth: .infinity)
                .disabled(!plan.structuralIssues.isEmpty || !allConflictsResolved)
                .accessibilityIdentifier("personMerge.confirmButton")
            } footer: {
                Text("統合は自動では実行されません。次の確認で「統合する」を選んだ場合だけ実行します。")
            }
            .listRowBackground(AppTheme.paperRaised)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.paper)
        .navigationTitle("統合内容の確認")
        .navigationBarTitleDisplayMode(.inline)
        .alert("人物を統合", isPresented: $showingFinalConfirmation) {
            Button("統合する", role: .destructive) { performMerge() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text(
                "「\(plan.duplicate.name)」を「\(plan.survivor.name)」に統合します。\n\n"
                    + "統合後、「\(plan.duplicate.name)」の人物レコードは削除されます。関係・集まり・選択したプロフィール情報は「\(plan.survivor.name)」に引き継がれます。"
            )
        }
        .alert(
            "統合できませんでした",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func personSummary(_ person: Person) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(person.name).foregroundStyle(AppTheme.ink)
            if !person.kana.isEmpty {
                Text(person.kana)
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
    }

    @ViewBuilder
    private func conflictRow(_ conflict: PersonMergeConflict) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(conflict.field.displayName)
                .font(.subheadline.weight(.medium))
            choiceButton(
                field: conflict.field,
                side: .survivor,
                title: "現在の人物を残す",
                value: conflict.survivorValue
            )
            choiceButton(
                field: conflict.field,
                side: .duplicate,
                title: "重複人物から引き継ぐ",
                value: conflict.duplicateValue
            )
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func choiceButton(
        field: PersonMergeField,
        side: PersonMergeSide,
        title: String,
        value: String
    ) -> some View {
        Button {
            choices[field] = side
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: choices[field] == side ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(choices[field] == side ? AppTheme.ai : AppTheme.ruleStrong)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundStyle(AppTheme.inkSoft)
                    Text(value).foregroundStyle(AppTheme.ink)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel("\(title)、\(value)")
        .accessibilityValue(choices[field] == side ? "選択中" : "未選択")
        .accessibilityAddTraits(choices[field] == side ? .isSelected : [])
        .accessibilityIdentifier("personMerge.conflict.\(field.rawValue).\(side.rawValue)")
    }

    @ViewBuilder
    private func mergeSummary(_ label: String, names: [String]) -> some View {
        LabeledContent(label, value: names.isEmpty ? "なし" : names.joined(separator: "、"))
    }

    private func performMerge() {
        do {
            _ = try PersonMergeService.merge(plan: plan, choices: choices, in: context)
            errorMessage = nil
            onMerged()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SharedChildPrompt: Identifiable {
    let id = UUID()
    let person: Person
    let spouse: Person
    let candidates: [Person]
}

struct SharedChildrenLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    let prompt: SharedChildPrompt
    let onLink: ([Person]) -> Void

    @State private var selectedIDs = Set<PersistentIdentifier>()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("この配偶者との子として紐づける人物を選んでください。選ばなかった子の関係は変更しません。")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.inkSoft)
                }
                .listRowBackground(AppTheme.paperRaised)

                Section("既存の子") {
                    ForEach(prompt.candidates) { child in
                        Button {
                            toggle(child)
                        } label: {
                            HStack {
                                Text(child.name)
                                    .foregroundStyle(AppTheme.ink)
                                Spacer()
                                Image(
                                    systemName: selectedIDs.contains(child.persistentModelID)
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                                .foregroundStyle(
                                    selectedIDs.contains(child.persistentModelID)
                                        ? AppTheme.ai
                                        : AppTheme.ruleStrong
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .accessibilityLabel("\(child.name)、共同の子として紐づける")
                        .accessibilityValue(
                            selectedIDs.contains(child.persistentModelID)
                                ? "選択中"
                                : "未選択"
                        )
                        .accessibilityAddTraits(
                            selectedIDs.contains(child.persistentModelID) ? .isSelected : []
                        )
                        .accessibilityIdentifier("sharedChild.candidate.\(child.name)")
                    }
                }
                .listRowBackground(AppTheme.paperRaised)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.paper)
            .navigationTitle("共同の子を選ぶ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("あとで") { dismiss() }
                        .accessibilityIdentifier("sharedChild.later")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("紐づける") {
                        let selected = prompt.candidates.filter {
                            selectedIDs.contains($0.persistentModelID)
                        }
                        onLink(selected)
                        dismiss()
                    }
                    .disabled(selectedIDs.isEmpty)
                    .accessibilityIdentifier("sharedChild.link")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(AppTheme.paper)
        .accessibilityIdentifier("sharedChild.sheet")
    }

    private func toggle(_ child: Person) {
        if selectedIDs.contains(child.persistentModelID) {
            selectedIDs.remove(child.persistentModelID)
        } else {
            selectedIDs.insert(child.persistentModelID)
        }
    }
}
