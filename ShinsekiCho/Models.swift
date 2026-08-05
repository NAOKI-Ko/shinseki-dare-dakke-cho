import Foundation
import SwiftData

// MARK: - 人物

@Model
final class Person {
    var name: String            // 名前
    var kana: String            // ふりがな(検索・並び替え用)
    var relationNote: String    // 自分から見た続柄の自由記述(例: 「夫の母の妹」)
    var isSelf: Bool            // つながりマップの起点(自分自身)。常に1人だけ
    @Attribute(.externalStorage) var photoData: Data?  // 顔写真(任意)
    var createdAt: Date

    // 基本情報(常に見える)。既存ストアの軽量移行用に新規文字列は既定値を持つ。
    var phone: String = ""      // 電話番号(任意。あればタップで発信)
    var email: String = ""      // メールアドレス(任意。あればタップでメール作成)
    var livingArea: String      // 居住地域(例: 「名古屋」程度のざっくりした表現)
    var lastMetDate: Date?      // 最後に会った日
    var lastMetPlace: String    // 最後に会った場所(例: 「祖母の一周忌」)

    // 図鑑のくわしい情報(折りたたみ・すべて任意)
    var postalAddress: String = ""  // 郵便番号・番地までの正式な住所(年賀状等)
    var birthday: Date?             // 誕生日
    var favorites: String = ""      // 好きなもの・苦手なもの
    var dietaryNotes: String = ""   // アレルギー・食事の配慮
    var memo: String                 // 会話メモ・次に話すきっかけ

    // 関係(構造化・任意入力)。双方向の整合性は RelationshipManager が保存時に手動同期する。
    // SwiftDataの自動inverseに頼らず、明示的に同期することで循環参照のバグを避ける。
    @Relationship(deleteRule: .nullify) var spouse: Person?
    @Relationship(deleteRule: .nullify, inverse: \Person.children)
    var parents: [Person] = []
    @Relationship(deleteRule: .nullify) var children: [Person] = []

    // この人物が出席した集まり(イベント)
    @Relationship(deleteRule: .nullify, inverse: \Gathering.attendees)
    var gatherings: [Gathering] = []

    init(
        name: String,
        kana: String = "",
        relationNote: String = "",
        isSelf: Bool = false,
        photoData: Data? = nil,
        phone: String = "",
        email: String = "",
        livingArea: String = "",
        lastMetDate: Date? = nil,
        lastMetPlace: String = "",
        postalAddress: String = "",
        birthday: Date? = nil,
        favorites: String = "",
        dietaryNotes: String = "",
        memo: String = ""
    ) {
        self.name = name
        self.kana = kana
        self.relationNote = relationNote
        self.isSelf = isSelf
        self.photoData = photoData
        self.phone = phone
        self.email = email
        self.livingArea = livingArea
        self.lastMetDate = lastMetDate
        self.lastMetPlace = lastMetPlace
        self.postalAddress = postalAddress
        self.birthday = birthday
        self.favorites = favorites
        self.dietaryNotes = dietaryNotes
        self.memo = memo
        self.createdAt = .now
    }

    /// 連絡先(電話・メールのどちらか)が1つでもあるか
    var hasContact: Bool {
        !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 兄弟姉妹(同じ親を1人以上共有する、自分以外の人物)
    var siblings: [Person] {
        guard !parents.isEmpty else { return [] }
        let parentSet = Set(parents.map(\.persistentModelID))
        var seen = Set<PersistentIdentifier>()
        var result: [Person] = []
        for parent in parents {
            for child in parent.children where child.persistentModelID != self.persistentModelID {
                if !seen.contains(child.persistentModelID) {
                    // 自分と共通の親を1人以上持つことを再確認(念のため)
                    let childParentSet = Set(child.parents.map(\.persistentModelID))
                    if !childParentSet.isDisjoint(with: parentSet) {
                        seen.insert(child.persistentModelID)
                        result.append(child)
                    }
                }
            }
        }
        return result
    }
}

// MARK: - 集まり(法事・帰省などのイベント)

@Model
final class Gathering {
    var title: String           // 例: 「祖母の一周忌」
    var date: Date
    var place: String
    var note: String
    var attendees: [Person] = []

    init(title: String, date: Date = .now, place: String = "", note: String = "") {
        self.title = title
        self.date = date
        self.place = place
        self.note = note
    }
}

// MARK: - 関係性の同期ロジック(コア部分)
//
// 親子・配偶者の関係は双方向の整合性が命。ここでの操作はすべて
// 「片方だけ設定して、もう片方が更新されない」事故を防ぐために
// 一箇所に集約する。UIからは直接 person.parents.append(...) 等を
// 呼ばず、必ずこのenumの関数を経由すること。

enum RelationshipKind: String, CaseIterable {
    case spouse
    case parent
    case child
}

enum RelationshipLinkError: LocalizedError, Equatable {
    case selfRelation
    case spouseUnavailable
    case parentLimit
    case alreadyLinked

    var errorDescription: String? {
        switch self {
        case .selfRelation:
            "同じ人物どうしを関係づけることはできません。"
        case .spouseUnavailable:
            "配偶者は1人まで登録できます。"
        case .parentLimit:
            "親は2人まで登録できます。"
        case .alreadyLinked:
            "この関係はすでに登録されています。"
        }
    }
}

enum RelationshipManager {
    private static func isSamePerson(_ a: Person, _ b: Person) -> Bool {
        a.persistentModelID == b.persistentModelID
    }

    /// 新しい配偶者関係を作れるか。既存配偶者の暗黙置換は行わない。
    static func canSetSpouse(_ a: Person, _ b: Person) -> Bool {
        guard !isSamePerson(a, b) else { return false }
        return a.spouse == nil && b.spouse == nil
    }

    /// 配偶者として双方向に結びつける。既存配偶者がいる場合は変更しない。
    @discardableResult
    static func setSpouse(_ a: Person, _ b: Person) -> Bool {
        guard !isSamePerson(a, b) else { return false }
        let alreadyLinked = a.spouse?.persistentModelID == b.persistentModelID
            && b.spouse?.persistentModelID == a.persistentModelID
        if alreadyLinked { return false }

        let aCanLink = a.spouse == nil || a.spouse?.persistentModelID == b.persistentModelID
        let bCanLink = b.spouse == nil || b.spouse?.persistentModelID == a.persistentModelID
        guard aCanLink, bCanLink else { return false }
        a.spouse = b
        b.spouse = a
        return true
    }

    /// 配偶者関係を解消する
    static func removeSpouse(of person: Person) {
        if let partner = person.spouse {
            partner.spouse = nil
        }
        person.spouse = nil
    }

    /// 親子関係を安全に追加できるか。親は最大2人、自己関係は禁止。
    static func canAddParentChild(parent: Person, child: Person) -> Bool {
        guard !isSamePerson(parent, child) else { return false }
        let alreadyParent = child.parents.contains {
            $0.persistentModelID == parent.persistentModelID
        }
        return alreadyParent || child.parents.count < 2
    }

    /// 親子関係を追加する(parentの子・childの親の両方向を同期)。
    @discardableResult
    static func addParentChild(parent: Person, child: Person) -> Bool {
        guard canAddParentChild(parent: parent, child: child) else { return false }
        let hadChild = parent.children.contains {
            $0.persistentModelID == child.persistentModelID
        }
        let hadParent = child.parents.contains {
            $0.persistentModelID == parent.persistentModelID
        }
        if !hadChild {
            parent.children.append(child)
        }
        if !hadParent {
            child.parents.append(parent)
        }
        return !hadChild || !hadParent
    }

    /// childをpersonの子として追加する。配偶者との共同子化は明示指定時のみ行う。
    @discardableResult
    static func addChild(
        _ child: Person,
        to person: Person,
        includeSpouse: Bool
    ) -> Bool {
        let linkedToPerson = addParentChild(parent: person, child: child)
        guard linkedToPerson || person.children.contains(where: {
            $0.persistentModelID == child.persistentModelID
        }) else { return false }

        var linkedToSpouse = false
        if includeSpouse, let spouse = person.spouse {
            linkedToSpouse = addParentChild(parent: spouse, child: child)
        }
        return linkedToPerson || linkedToSpouse
    }

    /// UIから利用する共通の関係作成可否。
    static func canLink(_ kind: RelationshipKind, person: Person, relative: Person) -> Bool {
        guard !isSamePerson(person, relative) else { return false }
        switch kind {
        case .spouse:
            return canSetSpouse(person, relative)
        case .parent:
            let alreadyLinked = person.parents.contains {
                $0.persistentModelID == relative.persistentModelID
            }
            return !alreadyLinked && canAddParentChild(parent: relative, child: person)
        case .child:
            let alreadyLinked = person.children.contains {
                $0.persistentModelID == relative.persistentModelID
            }
            return !alreadyLinked && canAddParentChild(parent: person, child: relative)
        }
    }

    /// 既存Person同士を、指定した関係として安全に結びつける。
    @discardableResult
    static func link(
        _ kind: RelationshipKind,
        person: Person,
        relative: Person,
        includeSpouseForChild: Bool = false
    ) throws -> Bool {
        guard !isSamePerson(person, relative) else {
            throw RelationshipLinkError.selfRelation
        }
        guard canLink(kind, person: person, relative: relative) else {
            switch kind {
            case .spouse:
                throw RelationshipLinkError.spouseUnavailable
            case .parent where person.parents.count >= 2:
                throw RelationshipLinkError.parentLimit
            default:
                throw RelationshipLinkError.alreadyLinked
            }
        }

        switch kind {
        case .spouse:
            return setSpouse(person, relative)
        case .parent:
            return addParentChild(parent: relative, child: person)
        case .child:
            return addChild(
                relative,
                to: person,
                includeSpouse: includeSpouseForChild
            )
        }
    }

    /// 後から配偶者を追加した際、共同子にできる既存子だけを返す。
    static func sharedChildCandidates(of person: Person, with spouse: Person) -> [Person] {
        person.children.filter { child in
            !spouse.children.contains(where: {
                $0.persistentModelID == child.persistentModelID
            }) && canAddParentChild(parent: spouse, child: child)
        }
    }

    /// ユーザーが明示選択した既存子だけを、新しい配偶者の子として結ぶ。
    @discardableResult
    static func linkSharedChildren(
        _ selectedChildren: [Person],
        of person: Person,
        with spouse: Person
    ) -> Int {
        guard person.spouse?.persistentModelID == spouse.persistentModelID,
              spouse.spouse?.persistentModelID == person.persistentModelID
        else { return 0 }

        let eligibleIDs = Set(
            sharedChildCandidates(of: person, with: spouse).map(\.persistentModelID)
        )
        var linkedCount = 0
        var seen = Set<PersistentIdentifier>()
        for child in selectedChildren
        where eligibleIDs.contains(child.persistentModelID)
            && seen.insert(child.persistentModelID).inserted {
            if addParentChild(parent: spouse, child: child) {
                linkedCount += 1
            }
        }
        return linkedCount
    }

    /// 親子関係を解消する
    static func removeParentChild(parent: Person, child: Person) {
        parent.children.removeAll { $0.persistentModelID == child.persistentModelID }
        child.parents.removeAll { $0.persistentModelID == parent.persistentModelID }
    }

    /// personに関わるすべての関係(配偶者・親・子)を解消する。人物削除の前に呼ぶ。
    static func detachAll(_ person: Person) {
        removeSpouse(of: person)
        for parent in person.parents {
            removeParentChild(parent: parent, child: person)
        }
        for child in person.children {
            removeParentChild(parent: person, child: child)
        }
    }
}
