import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Person.kana), SortDescriptor(\Person.name)])
    private var allPersons: [Person]
    @Query(filter: #Predicate<Person> { $0.isSelf }) private var selfPersonQuery: [Person]
    @State private var showingSelfPicker = false

    private var selfPerson: Person? { selfPersonQuery.first }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let selfPerson {
                        LabeledContent("自分", value: selfPerson.name)
                            .accessibilityIdentifier("settings.selfName")
                    } else {
                        Text("未設定")
                            .foregroundStyle(AppTheme.attention)
                    }
                    Button(selfPerson == nil ? "自分を登録する" : "変更する") {
                        showingSelfPicker = true
                    }
                    .foregroundStyle(AppTheme.ai)
                } header: {
                    Text("つながりマップの起点")
                } footer: {
                    Text("つながりマップは、ここで指定した「自分」を中心に表示されます。既に登録済みの人物から選ぶか、新しく登録できます。")
                }
                .listRowBackground(AppTheme.paperRaised)

                Section {
                    LabeledContent("記録の保存場所", value: "この端末の中")
                } footer: {
                    Text("記録はこの端末の中にだけ保存されます。外部に送信されることはありません。")
                }
                .listRowBackground(AppTheme.paperRaised)

                Section("このアプリについて") {
                    LabeledContent("バージョン", value: appVersion)
                }
                .listRowBackground(AppTheme.paperRaised)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.paper)
            .navigationTitle("設定")
            .sheet(isPresented: $showingSelfPicker) {
                SelfPersonPickerView(allPersons: allPersons)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

/// 「自分」を既存の人物から選ぶか、新規登録する画面
private struct SelfPersonPickerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let allPersons: [Person]

    @State private var showingNewPersonForm = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("自分の名前", text: $newName)
                        Button("登録") {
                            markAsSelf(create: true)
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("新しく登録する")
                }
                .listRowBackground(AppTheme.paperRaised)

                if !allPersons.isEmpty {
                    Section("登録済みの人物から選ぶ") {
                        ForEach(allPersons) { p in
                            Button(p.name) {
                                selectExisting(p)
                            }
                            .foregroundStyle(AppTheme.ink)
                        }
                    }
                    .listRowBackground(AppTheme.paperRaised)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.paper)
            .navigationTitle("自分を選ぶ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }

    private func selectExisting(_ person: Person) {
        for p in allPersons where p.isSelf { p.isSelf = false }
        person.isSelf = true
        dismiss()
    }

    private func markAsSelf(create: Bool) {
        for p in allPersons where p.isSelf { p.isSelf = false }
        let person = Person(name: newName, isSelf: true)
        context.insert(person)
        dismiss()
    }
}
