import SwiftUI
import SwiftData
import PhotosUI

struct PersonListView: View {
    @Query(sort: [SortDescriptor(\Person.kana), SortDescriptor(\Person.name)])
    private var persons: [Person]

    @Binding var searchText: String

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 14)]

    private var filteredPersons: [Person] {
        guard !searchText.isEmpty else { return persons }
        return persons.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.kana.localizedCaseInsensitiveContains(searchText)
                || $0.relationNote.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if persons.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(AppTheme.ai.opacity(0.5))
                    Text("まだ登録がありません")
                        .font(.minchoTitle(18, relativeTo: .title3))
                        .foregroundStyle(AppTheme.ink)
                    Text("右上の＋から、法事や帰省で会う親戚を登録してください。顔写真を添えると、あとで探しやすくなります。")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.paper)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(filteredPersons) { person in
                            NavigationLink(value: person) {
                                PersonGridCell(person: person)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("person.cell.\(person.name)")
                            .accessibilityValue(
                                PersonPhotoSupport.image(from: person.photoData) == nil
                                    ? "写真なし"
                                    : "写真あり"
                            )
                        }
                    }
                    .padding(16)
                }
                .background(AppTheme.paper)
            }
        }
    }
}

// MARK: - グリッドの1マス

private struct PersonGridCell: View {
    let person: Person

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let uiImage = PersonPhotoSupport.image(from: person.photoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Circle().fill(AppTheme.ai.opacity(0.08))
                        Text(PersonPhotoSupport.initial(for: person.name))
                            .font(.minchoTitle(24, relativeTo: .title2))
                            .foregroundStyle(AppTheme.ai)
                    }
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(Circle())
            .overlay(Circle().stroke(AppTheme.ruleStrong, lineWidth: 1))

            Text(person.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)

            if !person.relationNote.isEmpty {
                Text(person.relationNote)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkSoft)
                    .lineLimit(1)
            }
        }
        .frame(width: 92)
    }
}

// MARK: - 人物の追加・編集フォーム(基本情報+折りたたみ式の図鑑詳細)

struct PersonFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(TrialManager.self) private var trialManager

    var personToEdit: Person? = nil

    // 基本情報(常に見える)
    @State private var name = ""
    @State private var kana = ""
    @State private var relationNote = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var livingArea = ""
    @State private var lastMetDate: Date?
    @State private var hasLastMet = false
    @State private var lastMetPlace = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?

    // くわしい情報(折りたたみ・すべて任意)
    @State private var showingDetails = false
    @State private var postalAddress = ""
    @State private var birthday: Date?
    @State private var hasBirthday = false
    @State private var favorites = ""
    @State private var dietaryNotes = ""
    @State private var memo = ""
    @State private var showingPurchaseSheet = false
    @FocusState private var isTextInputFocused: Bool

    private var isEditing: Bool { personToEdit != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            photoPreview
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("お名前") {
                    TextField("名前(例: 山田 花子)", text: $name)
                        .focused($isTextInputFocused)
                        .accessibilityIdentifier("personForm.name")
                    TextField("ふりがな(任意)", text: $kana)
                        .focused($isTextInputFocused)
                        .accessibilityIdentifier("personForm.kana")
                }
                .listRowBackground(AppTheme.paperRaised)

                Section {
                    TextField("例: 夫の母の妹 / 佐藤のおじさん", text: $relationNote, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($isTextInputFocused)
                        .accessibilityIdentifier("personForm.relationNote")
                } header: {
                    Text("自分から見た続柄")
                } footer: {
                    Text("正式な関係でなくて構いません。思い出せる言葉で書いてください。配偶者・親・子の構造的なつながりは、保存後に人物詳細から登録できます。")
                }
                .listRowBackground(AppTheme.paperRaised)

                Section {
                    TextField("電話番号", text: $phone)
                        .keyboardType(.phonePad)
                        .focused($isTextInputFocused)
                        .accessibilityIdentifier("personForm.phone")
                    TextField("メールアドレス", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isTextInputFocused)
                        .accessibilityIdentifier("personForm.email")
                } header: {
                    Text("連絡先")
                } footer: {
                    Text("どちらも任意です。登録すると人物詳細から電話・メールを開けます。")
                }
                .listRowBackground(AppTheme.paperRaised)

                Section("居住地") {
                    TextField("例: 名古屋", text: $livingArea)
                        .focused($isTextInputFocused)
                        .accessibilityIdentifier("personForm.livingArea")
                }
                .listRowBackground(AppTheme.paperRaised)

                Section("最後に会った日") {
                    Toggle("記録する", isOn: $hasLastMet)
                        .accessibilityIdentifier("personForm.lastMetToggle")
                    if hasLastMet {
                        DatePicker("日付", selection: Binding(
                            get: { lastMetDate ?? .now },
                            set: { lastMetDate = $0 }
                        ), displayedComponents: .date)
                        .accessibilityIdentifier("personForm.lastMetDate")
                        TextField("場所(例: 祖母の一周忌)", text: $lastMetPlace)
                            .focused($isTextInputFocused)
                            .accessibilityIdentifier("personForm.lastMetPlace")
                    }
                }
                .listRowBackground(AppTheme.paperRaised)

                DisclosureGroup(isExpanded: $showingDetails) {
                    TextField("住所（郵便番号・番地など）", text: $postalAddress, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($isTextInputFocused)
                        .accessibilityIdentifier("personForm.postalAddress")

                    Toggle("誕生日を記録する", isOn: $hasBirthday)
                        .accessibilityIdentifier("personForm.birthdayToggle")
                    if hasBirthday {
                        DatePicker("誕生日", selection: Binding(
                            get: { birthday ?? .now },
                            set: { birthday = $0 }
                        ), displayedComponents: .date)
                        .accessibilityIdentifier("personForm.birthday")
                    }

                    TextField("好きなもの・苦手なもの", text: $favorites, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($isTextInputFocused)
                        .accessibilityIdentifier("personForm.favorites")

                    TextField("アレルギー・食事の配慮", text: $dietaryNotes, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($isTextInputFocused)
                        .accessibilityIdentifier("personForm.dietaryNotes")

                    TextField("会話メモ（次に会うときの話のきっかけなど）", text: $memo, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($isTextInputFocused)
                        .accessibilityIdentifier("personForm.memo")
                } label: {
                    Text("くわしく登録する（任意）")
                        .accessibilityIdentifier("personForm.detailsDisclosure")
                        .accessibilityValue(showingDetails ? "展開中" : "折りたたみ")
                }
                .listRowBackground(AppTheme.paperRaised)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.paper)
            .navigationTitle(isEditing ? "編集" : "親戚を登録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("personForm.saveButton")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") { isTextInputFocused = false }
                        .accessibilityIdentifier("personForm.dismissKeyboard")
                }
            }
            .onAppear {
                if let p = personToEdit {
                    name = p.name
                    kana = p.kana
                    relationNote = p.relationNote
                    phone = p.phone
                    email = p.email
                    livingArea = p.livingArea
                    lastMetDate = p.lastMetDate
                    lastMetPlace = p.lastMetPlace
                    hasLastMet = p.lastMetDate != nil
                    photoData = p.photoData
                    postalAddress = p.postalAddress
                    birthday = p.birthday
                    hasBirthday = p.birthday != nil
                    favorites = p.favorites
                    dietaryNotes = p.dietaryNotes
                    memo = p.memo
                    showingDetails = !postalAddress.isEmpty || hasBirthday
                        || !favorites.isEmpty || !dietaryNotes.isEmpty || !memo.isEmpty
                }
            }
            .onChange(of: photoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        photoData = PersonPhotoSupport.image(from: data) == nil ? nil : data
                    }
                }
            }
            .sheet(isPresented: $showingPurchaseSheet) {
                PurchaseSheet()
            }
        }
    }

    @ViewBuilder
    private var photoPreview: some View {
        Group {
            if let uiImage = PersonPhotoSupport.image(from: photoData) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(AppTheme.ai.opacity(0.06))
                    Image(systemName: "camera")
                        .font(.title2)
                        .foregroundStyle(AppTheme.ai)
                }
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(Circle())
        .overlay(Circle().stroke(AppTheme.ai.opacity(0.35), lineWidth: 1))
    }

    private func save() {
        guard trialManager.canEdit else {
            showingPurchaseSheet = true
            return
        }
        let finalLastMetDate = hasLastMet ? (lastMetDate ?? .now) : nil
        let finalBirthday = hasBirthday ? (birthday ?? .now) : nil
        let validatedPhotoData = PersonPhotoSupport.image(from: photoData) == nil ? nil : photoData
        if let p = personToEdit {
            p.name = name
            p.kana = kana
            p.relationNote = relationNote
            p.phone = phone
            p.email = email
            p.livingArea = livingArea
            p.lastMetDate = finalLastMetDate
            p.lastMetPlace = hasLastMet ? lastMetPlace : ""
            p.photoData = validatedPhotoData
            p.postalAddress = postalAddress
            p.birthday = finalBirthday
            p.favorites = favorites
            p.dietaryNotes = dietaryNotes
            p.memo = memo
        } else {
            let p = Person(
                name: name, kana: kana, relationNote: relationNote,
                photoData: validatedPhotoData, phone: phone, email: email,
                livingArea: livingArea, lastMetDate: finalLastMetDate,
                lastMetPlace: hasLastMet ? lastMetPlace : "",
                postalAddress: postalAddress, birthday: finalBirthday,
                favorites: favorites, dietaryNotes: dietaryNotes, memo: memo
            )
            context.insert(p)
        }
        try? context.save()
        dismiss()
    }
}
