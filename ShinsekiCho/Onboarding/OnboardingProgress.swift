import Foundation
import SwiftData

enum OnboardingStorageKeys {
    static let hasStarted = "onboarding.release.hasStarted"
    static let hasCompleted = "onboarding.release.hasCompleted"
    static let legacyGuidePending = "onboarding.guidePending"
}

enum OnboardingMode: Equatable {
    case firstRun
    case replay

    var allowsRegistration: Bool {
        self == .firstRun
    }
}

/// 初回表示・完了・設定からの再実行を、UIやUserDefaultsから独立して判定する。
struct OnboardingProgress: Equatable {
    var hasStarted: Bool
    var hasCompleted: Bool
    var isReplayRequested: Bool

    func shouldPresent(hasRegisteredSelf: Bool) -> Bool {
        if isReplayRequested { return true }
        if hasCompleted { return false }
        if hasStarted { return true }
        // 旧版ですでに「自分」を登録済みの利用者には、更新後に突然表示しない。
        return !hasRegisteredSelf
    }

    mutating func start() {
        hasStarted = true
    }

    mutating func requestReplay() {
        isReplayRequested = true
    }

    mutating func finishOrSkip() {
        hasStarted = true
        hasCompleted = true
        isReplayRequested = false
    }
}

struct OnboardingRelativeDraft: Equatable {
    var isSelected = false
    var name = ""

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        !isSelected || !trimmedName.isEmpty
    }
}

struct OnboardingDraft: Equatable {
    var selfName = ""
    var selfPhotoData: Data?
    var father = OnboardingRelativeDraft()
    var mother = OnboardingRelativeDraft()
    var spouse = OnboardingRelativeDraft()
    var sibling = OnboardingRelativeDraft()
    var paternalGrandfather = OnboardingRelativeDraft()
    var paternalGrandmother = OnboardingRelativeDraft()
    var maternalGrandfather = OnboardingRelativeDraft()
    var maternalGrandmother = OnboardingRelativeDraft()

    init(existingSelf: Person? = nil) {
        selfName = existingSelf?.name ?? ""
        selfPhotoData = existingSelf?.photoData
    }

    var isSelfValid: Bool {
        !selfName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isFamilyValid: Bool {
        [father, mother, spouse, sibling].allSatisfy(\.isValid)
    }

    var areGrandparentsValid: Bool {
        [
            paternalGrandfather,
            paternalGrandmother,
            maternalGrandfather,
            maternalGrandmother,
        ].allSatisfy(\.isValid)
    }
}

struct OnboardingExistingFamilyItem: Equatable, Identifiable {
    let id: String
    let role: String
    let name: String
}

/// Replayで表示する既存関係の読み取り専用スナップショット。
/// Personを保持しないため、説明画面からrelationshipを変更できない。
struct OnboardingFamilySnapshot: Equatable {
    let selfName: String
    let selfPhotoData: Data?
    let familyItems: [OnboardingExistingFamilyItem]
    let grandparentItems: [OnboardingExistingFamilyItem]

    @MainActor
    init(existingSelf: Person?) {
        guard let existingSelf else {
            selfName = ""
            selfPhotoData = nil
            familyItems = []
            grandparentItems = []
            return
        }

        selfName = existingSelf.name
        selfPhotoData = existingSelf.photoData

        var family: [OnboardingExistingFamilyItem] = []
        for (index, parent) in existingSelf.parents
            .sorted(by: { $0.createdAt < $1.createdAt })
            .enumerated() {
            family.append(
                OnboardingExistingFamilyItem(
                    id: "parent-\(index)-\(parent.persistentModelID)",
                    role: Self.parentRole(for: parent),
                    name: parent.name
                )
            )
        }
        if let spouse = existingSelf.spouse {
            family.append(
                OnboardingExistingFamilyItem(
                    id: "spouse-\(spouse.persistentModelID)",
                    role: "配偶者",
                    name: spouse.name
                )
            )
        }
        for (index, sibling) in existingSelf.siblings
            .sorted(by: { $0.createdAt < $1.createdAt })
            .enumerated() {
            family.append(
                OnboardingExistingFamilyItem(
                    id: "sibling-\(index)-\(sibling.persistentModelID)",
                    role: "兄弟・姉妹",
                    name: sibling.name
                )
            )
        }
        familyItems = family

        var grandparents: [OnboardingExistingFamilyItem] = []
        for (parentIndex, parent) in existingSelf.parents
            .sorted(by: { $0.createdAt < $1.createdAt })
            .enumerated() {
            for (grandparentIndex, grandparent) in parent.parents
                .sorted(by: { $0.createdAt < $1.createdAt })
                .enumerated() {
                grandparents.append(
                    OnboardingExistingFamilyItem(
                        id: "grandparent-\(parentIndex)-\(grandparentIndex)-\(grandparent.persistentModelID)",
                        role: Self.grandparentRole(for: grandparent, parent: parent),
                        name: grandparent.name
                    )
                )
            }
        }
        grandparentItems = grandparents
    }

    private static func parentRole(for person: Person) -> String {
        let note = person.relationNote.trimmingCharacters(in: .whitespacesAndNewlines)
        return note == "父" || note == "母" ? note : "親"
    }

    private static func grandparentRole(for person: Person, parent: Person) -> String {
        let note = person.relationNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if note.contains("祖父") || note.contains("祖母") { return note }
        return "\(parent.name)の親"
    }
}

enum OnboardingRegistrationError: LocalizedError {
    case emptySelfName
    case invalidRelationship

    var errorDescription: String? {
        switch self {
        case .emptySelfName:
            "あなたのお名前を入力してください。"
        case .invalidRelationship:
            "家族の関係を保存できませんでした。入力内容を確認してください。"
        }
    }
}

@MainActor
enum OnboardingCompletionService {
    /// Replayは説明の再表示だけなので、ModelContextへ一切書き込まない。
    @discardableResult
    static func complete(
        mode: OnboardingMode,
        draft: OnboardingDraft,
        existingSelf: Person?,
        in context: ModelContext
    ) throws -> Person? {
        switch mode {
        case .firstRun:
            return try OnboardingRegistrationService.register(
                draft: draft,
                existingSelf: existingSelf,
                in: context
            )
        case .replay:
            return nil
        }
    }
}

/// オンボーディングの入力をPersonへ変換する唯一の入口。
/// ViewはPersonのrelationshipを直接変更せず、既存のRelationshipManagerを利用する。
@MainActor
enum OnboardingRegistrationService {
    @discardableResult
    static func register(
        draft: OnboardingDraft,
        existingSelf: Person?,
        in context: ModelContext
    ) throws -> Person {
        let selfName = draft.selfName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selfName.isEmpty else { throw OnboardingRegistrationError.emptySelfName }
        guard draft.isFamilyValid, draft.areGrandparentsValid else {
            throw OnboardingRegistrationError.invalidRelationship
        }

        return try RelationshipTransaction.perform(in: context) {
            let selfPerson: Person
            if let existingSelf {
                selfPerson = existingSelf
                selfPerson.name = selfName
                selfPerson.photoData = draft.selfPhotoData
                selfPerson.isSelf = true
            } else {
                selfPerson = Person(
                    name: selfName,
                    isSelf: true,
                    photoData: draft.selfPhotoData
                )
                context.insert(selfPerson)
            }

            let father = makePerson(from: draft.father, relationNote: "父", in: context)
            let mother = makePerson(from: draft.mother, relationNote: "母", in: context)
            let spouse = makePerson(from: draft.spouse, relationNote: "配偶者", in: context)
            let sibling = makePerson(from: draft.sibling, relationNote: "兄弟・姉妹", in: context)

            if let father {
                guard RelationshipManager.addParentChild(parent: father, child: selfPerson) else {
                    throw OnboardingRegistrationError.invalidRelationship
                }
            }
            if let mother {
                guard RelationshipManager.addParentChild(parent: mother, child: selfPerson) else {
                    throw OnboardingRegistrationError.invalidRelationship
                }
            }
            if let spouse {
                guard RelationshipManager.setSpouse(selfPerson, spouse) else {
                    throw OnboardingRegistrationError.invalidRelationship
                }
            }
            if let sibling {
                // 兄弟姉妹は共有する親が登録されている場合だけ構造化する。
                // 親を推測・自動生成せず、人物自体は後から編集できる状態で残す。
                if let father {
                    guard RelationshipManager.addParentChild(parent: father, child: sibling) else {
                        throw OnboardingRegistrationError.invalidRelationship
                    }
                }
                if let mother {
                    guard RelationshipManager.addParentChild(parent: mother, child: sibling) else {
                        throw OnboardingRegistrationError.invalidRelationship
                    }
                }
            }

            try addGrandparents(
                draft.paternalGrandfather,
                draft.paternalGrandmother,
                to: father,
                prefix: "父方",
                in: context
            )
            try addGrandparents(
                draft.maternalGrandfather,
                draft.maternalGrandmother,
                to: mother,
                prefix: "母方",
                in: context
            )
            return selfPerson
        }
    }

    private static func makePerson(
        from draft: OnboardingRelativeDraft,
        relationNote: String,
        in context: ModelContext
    ) -> Person? {
        guard draft.isSelected, !draft.trimmedName.isEmpty else { return nil }
        let person = Person(name: draft.trimmedName, relationNote: relationNote)
        context.insert(person)
        return person
    }

    private static func addGrandparents(
        _ grandfatherDraft: OnboardingRelativeDraft,
        _ grandmotherDraft: OnboardingRelativeDraft,
        to parent: Person?,
        prefix: String,
        in context: ModelContext
    ) throws {
        // 対応する親がいない場合、祖父母を誰かへ推測で結びつけない。
        guard let parent else { return }
        for (draft, note) in [
            (grandfatherDraft, "\(prefix)祖父"),
            (grandmotherDraft, "\(prefix)祖母"),
        ] {
            guard let grandparent = makePerson(from: draft, relationNote: note, in: context)
            else { continue }
            guard RelationshipManager.addParentChild(parent: grandparent, child: parent) else {
                throw OnboardingRegistrationError.invalidRelationship
            }
        }
    }
}
