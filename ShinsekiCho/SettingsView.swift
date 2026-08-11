import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(TrialManager.self) private var trialManager
    @Query(sort: [SortDescriptor(\Person.kana), SortDescriptor(\Person.name)])
    private var allPersons: [Person]
    @Query(sort: [SortDescriptor(\Gathering.date)]) private var allGatherings: [Gathering]
    @Query(filter: #Predicate<Person> { $0.isSelf }) private var selfPersonQuery: [Person]
    @State private var showingSelfPicker = false
    @State private var showingPurchaseSheet = false
    @State private var showingBackupExporter = false
    @State private var showingBackupImporter = false
    @State private var exportDocument = BackupFileDocument()
    @State private var exportFilename = "親戚だれだっけ帳_バックアップ"
    @State private var restorePresentation: BackupRestorePresentation?
    @State private var backupAlert: SettingsBackupAlert?

    var onReplayOnboarding: () -> Void = {}

    private var selfPerson: Person? { selfPersonQuery.first }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("利用状況", value: trialManager.status.settingsText)
                        .accessibilityIdentifier("settings.trialStatus")
                    if trialManager.status != .purchased {
                        Button("フルアクセスを購入") {
                            showingPurchaseSheet = true
                        }
                        .foregroundStyle(AppTheme.ai)
                        .accessibilityIdentifier("settings.purchaseButton")
                    }
                } header: {
                    Text("7日間無料トライアル")
                } footer: {
                    Text("試用期間が終わっても、登録済みデータの閲覧は引き続き無料です。")
                }
                .listRowBackground(AppTheme.paperRaised)

                Section {
                    if let selfPerson {
                        LabeledContent("自分", value: selfPerson.name)
                            .accessibilityIdentifier("settings.selfName")
                    } else {
                        Text("未設定")
                            .foregroundStyle(AppTheme.attention)
                    }
                    Button(selfPerson == nil ? "自分を登録する" : "変更する") {
                        if trialManager.canEdit {
                            showingSelfPicker = true
                        } else {
                            showingPurchaseSheet = true
                        }
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
                    Text("記録は通常、この端末の中だけに保存されます。バックアップを書き出した場合のみ、ユーザーが選んだ保存先へコピーされます。アプリが自動で外部へ送信することはありません。")
                }
                .listRowBackground(AppTheme.paperRaised)

                Section {
                    Button {
                        prepareBackupExport()
                    } label: {
                        Label("バックアップを書き出す", systemImage: "square.and.arrow.up")
                    }
                    .foregroundStyle(AppTheme.ai)
                    .accessibilityIdentifier("settings.backup.export")

                    Button {
                        beginBackupRestore()
                    } label: {
                        Label("バックアップから復元", systemImage: "square.and.arrow.down")
                    }
                    .foregroundStyle(AppTheme.ai)
                    .accessibilityIdentifier("settings.backup.restore")
                } header: {
                    Text("データのバックアップ")
                        .accessibilityIdentifier("settings.backup.section")
                } footer: {
                    Text("バックアップには登録した個人情報が含まれます。保存先や共有先にご注意ください。復元すると、現在の人物・関係・集まりはバックアップの内容に置き換わります。")
                        .accessibilityIdentifier("settings.backup.privacy")
                }
                .listRowBackground(AppTheme.paperRaised)

                Section("このアプリについて") {
                    LabeledContent("バージョン", value: appVersion)
                    Button {
                        onReplayOnboarding()
                    } label: {
                        Label("オンボーディングをもう一度見る", systemImage: "sparkles.rectangle.stack")
                    }
                    .foregroundStyle(AppTheme.ai)
                    .accessibilityIdentifier("settings.onboarding.replay")
                }
                .listRowBackground(AppTheme.paperRaised)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.paper)
            .navigationTitle("設定")
            .sheet(isPresented: $showingSelfPicker) {
                SelfPersonPickerView(allPersons: allPersons)
            }
            .sheet(isPresented: $showingPurchaseSheet) {
                PurchaseSheet()
            }
            .sheet(item: $restorePresentation) { presentation in
                BackupRestorePreviewView(
                    plan: presentation.plan,
                    currentPersonCount: allPersons.count,
                    currentGatheringCount: allGatherings.count,
                    onRestore: { restore(presentation.plan) }
                )
            }
            .fileExporter(
                isPresented: $showingBackupExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: exportFilename
            ) { result in
                if case .failure(let error) = result {
                    backupAlert = .error("バックアップを書き出せません", error.localizedDescription)
                }
            }
            .fileImporter(
                isPresented: $showingBackupImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImportResult(result)
            }
            .alert(item: $backupAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("閉じる"))
                )
            }
        }
    }

    private func prepareBackupExport() {
        do {
            exportDocument = BackupFileDocument(
                data: try BackupExporter.encode(
                    people: allPersons,
                    gatherings: allGatherings
                )
            )
            exportFilename = "親戚だれだっけ帳_バックアップ_\(Self.filenameDateFormatter.string(from: .now))"
            showingBackupExporter = true
        } catch {
            backupAlert = .error(
                "バックアップを書き出せません",
                "ファイルを作成できませんでした。保存先を確認して、もう一度お試しください。"
            )
        }
    }

    private func beginBackupRestore() {
        guard trialManager.canEdit else {
            showingPurchaseSheet = true
            return
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-backup-preview") {
            do {
                let archive = try BackupExporter.makeArchive(
                    people: allPersons,
                    gatherings: allGatherings
                )
                restorePresentation = BackupRestorePresentation(
                    plan: BackupRestorePlan(archive: archive)
                )
            } catch {
                backupAlert = .error(
                    "このバックアップは復元できません",
                    "バックアップの内容を確認して、もう一度お試しください。"
                )
            }
            return
        }
        #endif
        showingBackupImporter = true
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
            let plan = try BackupRestoreService.makePlan(from: Data(contentsOf: url))
            restorePresentation = BackupRestorePresentation(plan: plan)
        } catch let error as BackupValidationError {
            backupAlert = .error("このバックアップは復元できません", error.localizedDescription)
        } catch {
            backupAlert = .error(
                "このバックアップは復元できません",
                "JSONファイルを読み込めませんでした。選択したファイルを確認してください。"
            )
        }
    }

    private func restore(_ plan: BackupRestorePlan) {
        do {
            try BackupRestoreService.restore(plan: plan, in: context)
            restorePresentation = nil
            backupAlert = .success("復元が完了しました", "人物・関係・集まりをバックアップの内容へ置き換えました。")
        } catch let error as BackupRestoreError {
            backupAlert = .error("復元できませんでした", error.localizedDescription)
        } catch let error as BackupValidationError {
            backupAlert = .error("復元できませんでした", error.localizedDescription)
        } catch {
            backupAlert = .error(
                "復元できませんでした",
                "現在の記録は変更されていません。もう一度お試しください。"
            )
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct BackupRestorePresentation: Identifiable {
    let id = UUID()
    let plan: BackupRestorePlan
}

private struct SettingsBackupAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    static func error(_ title: String, _ message: String) -> Self {
        Self(title: title, message: message)
    }

    static func success(_ title: String, _ message: String) -> Self {
        Self(title: title, message: message)
    }
}

private struct BackupRestorePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let plan: BackupRestorePlan
    let currentPersonCount: Int
    let currentGatheringCount: Int
    let onRestore: () -> Void

    @State private var showingFinalConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("バックアップ") {
                    LabeledContent("人物", value: "\(plan.personCount)人")
                        .accessibilityIdentifier("backup.preview.people")
                    LabeledContent("集まり", value: "\(plan.gatheringCount)件")
                        .accessibilityIdentifier("backup.preview.gatherings")
                    LabeledContent("作成日時", value: plan.exportedAt.formatted(date: .numeric, time: .shortened))
                    if plan.personCount == 0 {
                        Text("このバックアップには人物が登録されていません。")
                            .foregroundStyle(AppTheme.attention)
                    }
                }
                .listRowBackground(AppTheme.paperRaised)

                Section("現在") {
                    LabeledContent("人物", value: "\(currentPersonCount)人")
                    LabeledContent("集まり", value: "\(currentGatheringCount)件")
                }
                .listRowBackground(AppTheme.paperRaised)

                Section {
                    Text("現在の記録は、このバックアップの内容に置き換わります。")
                        .foregroundStyle(AppTheme.attention)
                        .accessibilityIdentifier("backup.preview.warning")
                        .accessibilityLabel(
                            "警告、現在の記録は、このバックアップの内容に置き換わります"
                        )
                }
                .listRowBackground(AppTheme.paperRaised)

                Button("復元内容を確認") {
                    showingFinalConfirmation = true
                }
                .foregroundStyle(AppTheme.attention)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityHint("復元前の最終確認を表示します")
                .accessibilityIdentifier("backup.preview.confirm")
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.paper)
            .navigationTitle("バックアップから復元")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .accessibilityIdentifier("backup.preview.cancel")
                }
            }
            .confirmationDialog(
                "現在の記録を置き換えますか？",
                isPresented: $showingFinalConfirmation,
                titleVisibility: .visible
            ) {
                Button("復元する", role: .destructive) { onRestore() }
                    .accessibilityIdentifier("backup.confirm.restore")
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("現在の人物・関係・集まりをすべて削除し、選択したバックアップから復元します。この操作は元に戻せません。")
            }
        }
    }
}

/// 「自分」を既存の人物から選ぶか、新規登録する画面
private struct SelfPersonPickerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(TrialManager.self) private var trialManager
    let allPersons: [Person]

    @State private var showingNewPersonForm = false
    @State private var newName = ""
    @State private var showingPurchaseSheet = false

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
            .sheet(isPresented: $showingPurchaseSheet) {
                PurchaseSheet()
            }
        }
    }

    private func selectExisting(_ person: Person) {
        guard trialManager.canEdit else {
            showingPurchaseSheet = true
            return
        }
        for p in allPersons where p.isSelf { p.isSelf = false }
        person.isSelf = true
        dismiss()
    }

    private func markAsSelf(create: Bool) {
        guard trialManager.canEdit else {
            showingPurchaseSheet = true
            return
        }
        for p in allPersons where p.isSelf { p.isSelf = false }
        let person = Person(name: newName, isSelf: true)
        context.insert(person)
        dismiss()
    }
}
