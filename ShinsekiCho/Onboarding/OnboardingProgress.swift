import Foundation
import SwiftData

enum OnboardingStorageKeys {
    static let hasStarted = "onboarding.release.hasStarted"
    static let hasCompleted = "onboarding.release.hasCompleted"
    static let legacyGuidePending = "onboarding.guidePending"
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
