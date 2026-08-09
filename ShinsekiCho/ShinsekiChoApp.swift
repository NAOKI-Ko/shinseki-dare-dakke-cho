import SwiftUI
import SwiftData

@main
struct ShinsekiChoApp: App {
    private let container: ModelContainer
    @State private var trialManager: TrialManager

    init() {
        do {
            let arguments = ProcessInfo.processInfo.arguments
            let isUITesting = arguments.contains("-ui-testing-reset")
                || arguments.contains("-ui-testing-seed")
                || arguments.contains("-ui-testing")
            let container: ModelContainer
            if isUITesting {
                let supportDirectory = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                let storeURL = supportDirectory.appendingPathComponent("ui-test.store")
                if arguments.contains("-ui-testing-reset") {
                    for url in [
                        storeURL,
                        URL(fileURLWithPath: storeURL.path + "-shm"),
                        URL(fileURLWithPath: storeURL.path + "-wal")
                    ] {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
                container = try ModelContainer(
                    for: Person.self,
                    Gathering.self,
                    configurations: ModelConfiguration(url: storeURL)
                )
            } else {
                container = try ModelContainer(for: Person.self, Gathering.self)
            }
            if arguments.contains("-ui-testing-seed") {
                try Self.seedUITestData(in: container.mainContext)
            }
            self.container = container

            #if DEBUG
            if arguments.contains("-ui-testing-reset") {
                try? KeychainStore().removeValue(forKey: TrialManager.firstLaunchDateKey)
                UserDefaults.standard.removeObject(forKey: TrialManager.firstLaunchDateKey)
                UserDefaults.standard.removeObject(forKey: "onboarding.guidePending")
            }
            if arguments.contains("-ui-testing-trial-expired") {
                UserDefaults.standard.set(
                    Date().addingTimeInterval(-8 * 24 * 60 * 60),
                    forKey: TrialManager.firstLaunchDateKey
                )
            }
            let isPurchasedUITest = arguments.contains("-ui-testing-purchased")
            let usesLiveStoreKit = arguments.contains("-ui-testing-live-storekit")
            if isUITesting, !usesLiveStoreKit {
                _trialManager = State(
                    initialValue: TrialManager(
                        entitlementChecker: { isPurchasedUITest },
                        productLoader: { nil }
                    )
                )
            } else {
                _trialManager = State(initialValue: TrialManager())
            }
            #else
            _trialManager = State(initialValue: TrialManager())
            #endif
        } catch {
            fatalError("SwiftDataコンテナを作成できませんでした: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(AppTheme.ai)
                .environment(trialManager)
                .task { await trialManager.prepare() }
        }
        .modelContainer(container)
    }

    private static func seedUITestData(in context: ModelContext) throws {
        let selfPerson = Person(
            name: "山田 太郎",
            kana: "やまだ たろう",
            relationNote: "自分"
        )
        selfPerson.isSelf = true
        let father = Person(name: "山田 一郎", kana: "やまだ いちろう", relationNote: "父")
        // 破損した写真データでも、各画面が頭文字表示へ安全に戻ることをUI上で確認する。
        let mother = Person(
            name: "山田 花子",
            kana: "やまだ はなこ",
            relationNote: "母",
            photoData: Data([0x00, 0x01, 0x02])
        )
        let spouse = Person(
            name: "佐藤 美咲",
            kana: "さとう みさき",
            relationNote: "配偶者"
        )
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-family-graph-ux") {
            spouse.photoData = UIImage(systemName: "person.crop.circle.fill")?.pngData()
        }
        #endif
        let spouseFather = Person(
            name: "佐藤 修一",
            kana: "さとう しゅういち",
            relationNote: "配偶者の父"
        )
        let spouseBrother = Person(
            name: "佐藤 健太",
            kana: "さとう けんた",
            relationNote: "配偶者の兄"
        )
        let nephew = Person(
            name: "佐藤 蓮",
            kana: "さとう れん",
            relationNote: "配偶者の兄の子"
        )
        let child = Person(name: "山田 葵", kana: "やまだ あおい", relationNote: "子")
        let uncle = Person(name: "山田 次郎", kana: "やまだ じろう", relationNote: "叔父")
        var mergeDuplicate: Person?
        var mergeDuplicateChild: Person?
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-person-merge") {
            mergeDuplicate = Person(
                name: "山田　花子",
                kana: "やまだ はなこ",
                relationNote: "母",
                phone: "052-123-4567",
                memo: "重複側にだけある会話メモ"
            )
            mergeDuplicateChild = Person(
                name: "重複側の子",
                kana: "ちょうふくがわのこ",
                relationNote: "子"
            )
        }
        #endif
        var people = [
            selfPerson, father, mother, spouse, spouseFather, spouseBrother, nephew, child, uncle
        ]
        if let mergeDuplicate { people.append(mergeDuplicate) }
        if let mergeDuplicateChild { people.append(mergeDuplicateChild) }
        people.forEach(context.insert)
        try context.save()

        RelationshipManager.setSpouse(father, mother)
        RelationshipManager.addParentChild(parent: father, child: selfPerson)
        RelationshipManager.addParentChild(parent: mother, child: selfPerson)
        RelationshipManager.setSpouse(selfPerson, spouse)
        RelationshipManager.addParentChild(parent: selfPerson, child: child)
        RelationshipManager.addParentChild(parent: spouse, child: child)
        RelationshipManager.addParentChild(parent: spouseFather, child: spouse)
        RelationshipManager.addParentChild(parent: spouseFather, child: spouseBrother)
        RelationshipManager.addParentChild(parent: spouseBrother, child: nephew)
        RelationshipManager.addParentChild(parent: father, child: uncle)
        RelationshipManager.addParentChild(parent: mother, child: uncle)
        if let mergeDuplicate, let mergeDuplicateChild {
            RelationshipManager.addParentChild(parent: mergeDuplicate, child: mergeDuplicateChild)
        }

        let gathering = Gathering(
            title: "祖母の一周忌",
            date: Date(timeIntervalSince1970: 1_735_689_600),
            place: "東京",
            note: "UIテスト用"
        )
        context.insert(gathering)
        gathering.attendees.append(selfPerson)
        if let mergeDuplicate { gathering.attendees.append(mergeDuplicate) }
        try context.save()
    }

}

// MARK: - テーマ「和帳モダン」(おつきあい帳・命日帳と共通)
// 紙の帳面の語彙(生成りの紙・罫線・明朝の文字・印鑑の朱)で統一。
// 色はここに定義した組以外を増やさない。色だけで意味を伝えない。

enum AppTheme {
    // 紙
    static let paper = Color(light: rgb(0xF7, 0xF4, 0xEB), dark: rgb(0x1C, 0x1B, 0x17))
    static let paperRaised = Color(light: rgb(0xFD, 0xFB, 0xF5), dark: rgb(0x27, 0x25, 0x1F))
    static let rule = Color(light: rgb(0xE3, 0xDC, 0xC9), dark: rgb(0x3A, 0x37, 0x2E))
    static let ruleStrong = Color(light: rgb(0xC9, 0xBF, 0xA4), dark: rgb(0x4E, 0x49, 0x3B))

    // 墨
    static let ink = Color(light: rgb(0x2A, 0x2A, 0x28), dark: rgb(0xEC, 0xE8, 0xDD))
    static let inkSoft = Color(light: rgb(0x6E, 0x6A, 0x5C), dark: rgb(0xA9, 0xA3, 0x8F))

    // 意味色
    static let ai = Color(light: rgb(0x2C, 0x44, 0x67), dark: rgb(0x7C, 0x9C, 0xC9))
    static let attention = Color(light: rgb(0xB3, 0x3A, 0x2F), dark: rgb(0xE0, 0x8A, 0x7C))
    static let done = Color(light: rgb(0x3D, 0x6B, 0x52), dark: rgb(0x8F, 0xC3, 0xA6))

    // つながりマップの家系色。塗りには使わず、線とノードの縁だけに限定する。
    static let branchIndigo = ai
    static let branchForest = Color(light: rgb(0x3D, 0x6B, 0x52), dark: rgb(0x8F, 0xC3, 0xA6))
    static let branchPlum = Color(light: rgb(0x6B, 0x3D, 0x5E), dark: rgb(0xC3, 0x8F, 0xB4))

    static let minchoName = "HiraMinProN-W6"
    static let minchoNameRegular = "HiraMinProN-W3"

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

/// 保存済みデータがnil・空・破損のいずれでも、全画面で同じ判定結果にする。
enum PersonPhotoSupport {
    static func image(from data: Data?) -> UIImage? {
        guard let data, !data.isEmpty, let image = UIImage(data: data),
              image.size.width > 0, image.size.height > 0 else {
            return nil
        }
        return image
    }

    static func initial(for name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).first ?? "?")
    }
}

extension Color {
    init(light: Color, dark: Color) {
        self.init(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

extension Font {
    static func minchoAmount(_ size: CGFloat, relativeTo style: Font.TextStyle = .title2) -> Font {
        .custom(AppTheme.minchoName, size: size, relativeTo: style)
    }
    static func minchoTitle(_ size: CGFloat, relativeTo style: Font.TextStyle = .headline) -> Font {
        .custom(AppTheme.minchoNameRegular, size: size, relativeTo: style)
    }
}

struct HairlineCard<Content: View>: View {
    var content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View {
        content()
            .background(AppTheme.paperRaised)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
