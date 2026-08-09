import Foundation
import SwiftData

// MARK: - Duplicate detection

enum PersonDuplicateDetector {
    /// 表記上安全な差だけを吸収する。文字そのものが異なる曖昧一致は行わない。
    static func normalized(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func isCandidate(_ candidate: Person, for survivor: Person) -> Bool {
        guard candidate.persistentModelID != survivor.persistentModelID else { return false }

        let survivorName = normalized(survivor.name)
        let candidateName = normalized(candidate.name)
        if !survivorName.isEmpty, survivorName == candidateName { return true }

        let survivorKana = normalized(survivor.kana)
        let candidateKana = normalized(candidate.kana)
        return !survivorKana.isEmpty
            && !candidateKana.isEmpty
            && survivorKana == candidateKana
    }

    static func candidates(for survivor: Person, among people: [Person]) -> [Person] {
        people.filter { isCandidate($0, for: survivor) }
    }
}

// MARK: - Profile merge plan

enum PersonMergeField: String, CaseIterable, Identifiable {
    case name
    case kana
    case relationNote
    case photoData
    case phone
    case email
    case livingArea
    case lastMet
    case postalAddress
    case birthday
    case favorites
    case dietaryNotes
    case memo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .name: "名前"
        case .kana: "ふりがな"
        case .relationNote: "続柄メモ"
        case .photoData: "写真"
        case .phone: "電話番号"
        case .email: "メールアドレス"
        case .livingArea: "居住地"
        case .lastMet: "最後に会った情報"
        case .postalAddress: "住所"
        case .birthday: "誕生日"
        case .favorites: "好み"
        case .dietaryNotes: "アレルギー・食事の配慮"
        case .memo: "会話メモ"
        }
    }
}

enum PersonMergeSide: String, CaseIterable {
    case survivor
    case duplicate
}

struct PersonLastMetSnapshot: Equatable {
    var date: Date?
    var place: String
}

struct PersonMergeProfileSnapshot: Equatable {
    var name: String
    var kana: String
    var relationNote: String
    var photoData: Data?
    var phone: String
    var email: String
    var livingArea: String
    var lastMet: PersonLastMetSnapshot
    var postalAddress: String
    var birthday: Date?
    var favorites: String
    var dietaryNotes: String
    var memo: String
    var createdAt: Date

    init(person: Person) {
        name = person.name
        kana = person.kana
        relationNote = person.relationNote
        photoData = person.photoData
        phone = person.phone
        email = person.email
        livingArea = person.livingArea
        lastMet = PersonLastMetSnapshot(date: person.lastMetDate, place: person.lastMetPlace)
        postalAddress = person.postalAddress
        birthday = person.birthday
        favorites = person.favorites
        dietaryNotes = person.dietaryNotes
        memo = person.memo
        createdAt = person.createdAt
    }

    mutating func take(_ field: PersonMergeField, from source: PersonMergeProfileSnapshot) {
        switch field {
        case .name: name = source.name
        case .kana: kana = source.kana
        case .relationNote: relationNote = source.relationNote
        case .photoData: photoData = source.photoData
        case .phone: phone = source.phone
        case .email: email = source.email
        case .livingArea: livingArea = source.livingArea
        case .lastMet: lastMet = source.lastMet
        case .postalAddress: postalAddress = source.postalAddress
        case .birthday: birthday = source.birthday
        case .favorites: favorites = source.favorites
        case .dietaryNotes: dietaryNotes = source.dietaryNotes
        case .memo: memo = source.memo
        }
    }

    func isEmpty(_ field: PersonMergeField) -> Bool {
        switch field {
        case .name: Self.blank(name)
        case .kana: Self.blank(kana)
        case .relationNote: Self.blank(relationNote)
        case .photoData: photoData?.isEmpty != false
        case .phone: Self.blank(phone)
        case .email: Self.blank(email)
        case .livingArea: Self.blank(livingArea)
        case .lastMet: lastMet.date == nil && Self.blank(lastMet.place)
        case .postalAddress: Self.blank(postalAddress)
        case .birthday: birthday == nil
        case .favorites: Self.blank(favorites)
        case .dietaryNotes: Self.blank(dietaryNotes)
        case .memo: Self.blank(memo)
        }
    }

    func hasSameValue(_ field: PersonMergeField, as other: PersonMergeProfileSnapshot) -> Bool {
        switch field {
        case .name:
            PersonDuplicateDetector.normalized(name) == PersonDuplicateDetector.normalized(other.name)
        case .kana:
            PersonDuplicateDetector.normalized(kana) == PersonDuplicateDetector.normalized(other.kana)
        case .relationNote: Self.trimmed(relationNote) == Self.trimmed(other.relationNote)
        case .photoData: photoData == other.photoData
        case .phone: Self.trimmed(phone) == Self.trimmed(other.phone)
        case .email: Self.trimmed(email).lowercased() == Self.trimmed(other.email).lowercased()
        case .livingArea: Self.trimmed(livingArea) == Self.trimmed(other.livingArea)
        case .lastMet:
            lastMet.date == other.lastMet.date
                && Self.trimmed(lastMet.place) == Self.trimmed(other.lastMet.place)
        case .postalAddress: Self.trimmed(postalAddress) == Self.trimmed(other.postalAddress)
        case .birthday: birthday == other.birthday
        case .favorites: Self.trimmed(favorites) == Self.trimmed(other.favorites)
        case .dietaryNotes: Self.trimmed(dietaryNotes) == Self.trimmed(other.dietaryNotes)
        case .memo: Self.trimmed(memo) == Self.trimmed(other.memo)
        }
    }

    func description(for field: PersonMergeField) -> String {
        switch field {
        case .name: return name
        case .kana: return kana
        case .relationNote: return relationNote
        case .photoData: return photoData?.isEmpty == false ? "写真あり" : "写真なし"
        case .phone: return phone
        case .email: return email
        case .livingArea: return livingArea
        case .lastMet:
            let dateText = lastMet.date?.formatted(.dateTime.year().month().day()) ?? "日付なし"
            return lastMet.place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? dateText
                : "\(dateText)・\(lastMet.place)"
        case .postalAddress: return postalAddress
        case .birthday: return birthday?.formatted(.dateTime.year().month().day()) ?? "未設定"
        case .favorites: return favorites
        case .dietaryNotes: return dietaryNotes
        case .memo: return memo
        }
    }

    private static func blank(_ value: String) -> Bool { trimmed(value).isEmpty }
    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct PersonMergeConflict: Identifiable {
    let field: PersonMergeField
    let survivorValue: String
    let duplicateValue: String
    var id: PersonMergeField { field }
}

enum PersonMergeStructuralIssue: Error, Equatable, Identifiable {
    case sameRecord
    case selfMustSurvive
    case differentSpouses
    case tooManyParents
    case childParentLimit(String)
    case ancestryCycle
    case incompatibleRelationship

    var id: String { message }

    var message: String {
        switch self {
        case .sameRecord:
            "同じ人物レコード同士は統合できません。"
        case .selfMustSurvive:
            "自分のレコードを残すため、「自分」の人物詳細から統合してください。"
        case .differentSpouses:
            "配偶者が異なるため統合できません。先に関係を整理してください。"
        case .tooManyParents:
            "親の候補が3人以上になるため統合できません。先に関係を整理してください。"
        case .childParentLimit(let name):
            "\(name)さんの親が3人以上になるため統合できません。先に関係を整理してください。"
        case .ancestryCycle:
            "祖先と子孫が循環するため統合できません。先に関係を整理してください。"
        case .incompatibleRelationship:
            "配偶者・親・子が矛盾するため統合できません。先に関係を整理してください。"
        }
    }
}

struct PersonMergeRelationshipPlan {
    let spouse: Person?
    let parents: [Person]
    let children: [Person]
}

struct PersonMergePreflightResult {
    let relationship: PersonMergeRelationshipPlan
    let issues: [PersonMergeStructuralIssue]
}

enum PersonMergePreflight {
    static func evaluate(survivor: Person, duplicate: Person) -> PersonMergePreflightResult {
        var issues: [PersonMergeStructuralIssue] = []
        let survivorID = survivor.persistentModelID
        let duplicateID = duplicate.persistentModelID

        if survivorID == duplicateID { issues.append(.sameRecord) }
        if duplicate.isSelf && !survivor.isSelf { issues.append(.selfMustSurvive) }

        let survivorSpouse = usableRelative(survivor.spouse, survivorID: survivorID, duplicateID: duplicateID)
        let duplicateSpouse = usableRelative(duplicate.spouse, survivorID: survivorID, duplicateID: duplicateID)
        let spouse: Person?
        if let survivorSpouse, let duplicateSpouse,
           survivorSpouse.persistentModelID != duplicateSpouse.persistentModelID {
            spouse = nil
            issues.append(.differentSpouses)
        } else {
            spouse = survivorSpouse ?? duplicateSpouse
        }

        let parents = uniquePeople(
            survivor.parents + duplicate.parents,
            excluding: [survivorID, duplicateID]
        )
        let children = uniquePeople(
            survivor.children + duplicate.children,
            excluding: [survivorID, duplicateID]
        )

        if parents.count > 2 { issues.append(.tooManyParents) }

        let parentIDs = Set(parents.map(\.persistentModelID))
        let childIDs = Set(children.map(\.persistentModelID))
        if !parentIDs.isDisjoint(with: childIDs) { issues.append(.incompatibleRelationship) }
        if let spouse {
            let spouseID = spouse.persistentModelID
            if parentIDs.contains(spouseID) || childIDs.contains(spouseID) {
                issues.append(.incompatibleRelationship)
            }
            if let existing = spouse.spouse,
               existing.persistentModelID != survivorID,
               existing.persistentModelID != duplicateID {
                issues.append(.differentSpouses)
            }
        }

        for child in children {
            var resultingParentIDs = Set(
                child.parents
                    .map(\.persistentModelID)
                    .filter { $0 != duplicateID && $0 != survivorID }
            )
            resultingParentIDs.insert(survivorID)
            if resultingParentIDs.count > 2 {
                issues.append(.childParentLimit(child.name))
            }
        }

        let relationship = PersonMergeRelationshipPlan(
            spouse: spouse,
            parents: parents,
            children: children
        )
        let virtualAdjacency = virtualChildAdjacency(
            survivor: survivor,
            duplicate: duplicate,
            relationship: relationship
        )
        if hasLinealSpouseConflict(
            survivor: survivor,
            spouse: relationship.spouse,
            adjacency: virtualAdjacency
        ) {
            issues.append(.incompatibleRelationship)
        }
        if createsCycle(
            survivor: survivor,
            relationship: relationship,
            adjacency: virtualAdjacency
        ) {
            issues.append(.ancestryCycle)
        }

        return PersonMergePreflightResult(
            relationship: relationship,
            issues: deduplicatedIssues(issues)
        )
    }

    private static func usableRelative(
        _ person: Person?,
        survivorID: PersistentIdentifier,
        duplicateID: PersistentIdentifier
    ) -> Person? {
        guard let person,
              person.persistentModelID != survivorID,
              person.persistentModelID != duplicateID else { return nil }
        return person
    }

    private static func uniquePeople(
        _ people: [Person],
        excluding excluded: Set<PersistentIdentifier>
    ) -> [Person] {
        var seen = Set<PersistentIdentifier>()
        return people.filter {
            let id = $0.persistentModelID
            return !excluded.contains(id) && seen.insert(id).inserted
        }
    }

    /// duplicateをsurvivorへ置換し、提案する親子edgeを反映した仮想グラフを作る。
    /// Previewと実行時で同じ「merge後」の血縁構造を基準に検証するために使う。
    private static func virtualChildAdjacency(
        survivor: Person,
        duplicate: Person,
        relationship: PersonMergeRelationshipPlan
    ) -> [PersistentIdentifier: Set<PersistentIdentifier>] {
        let survivorID = survivor.persistentModelID
        let duplicateID = duplicate.persistentModelID
        var peopleByID: [PersistentIdentifier: Person] = [:]
        var pending = [survivor, duplicate]

        while let person = pending.popLast() {
            let id = person.persistentModelID
            guard peopleByID[id] == nil else { continue }
            peopleByID[id] = person
            pending.append(contentsOf: person.parents)
            pending.append(contentsOf: person.children)
        }
        for person in relationship.parents + relationship.children {
            peopleByID[person.persistentModelID] = person
        }

        var adjacency: [PersistentIdentifier: Set<PersistentIdentifier>] = [:]
        for (id, person) in peopleByID where id != duplicateID {
            let children: [Person] = id == survivorID ? relationship.children : person.children
            for child in children {
                let rawID = child.persistentModelID
                let childID = rawID == duplicateID ? survivorID : rawID
                if childID != id { adjacency[id, default: []].insert(childID) }
            }
        }
        for parent in relationship.parents {
            adjacency[parent.persistentModelID, default: []].insert(survivorID)
        }

        return adjacency
    }

    /// merge後に配偶者がsurvivorの祖先または子孫になる場合をmutation前に拒否する。
    private static func hasLinealSpouseConflict(
        survivor: Person,
        spouse: Person?,
        adjacency: [PersistentIdentifier: Set<PersistentIdentifier>]
    ) -> Bool {
        guard let spouse else { return false }
        let survivorID = survivor.persistentModelID
        let spouseID = spouse.persistentModelID
        return reaches(spouseID, from: survivorID, adjacency: adjacency)
            || reaches(survivorID, from: spouseID, adjacency: adjacency)
    }

    private static func createsCycle(
        survivor: Person,
        relationship: PersonMergeRelationshipPlan,
        adjacency: [PersistentIdentifier: Set<PersistentIdentifier>]
    ) -> Bool {
        let survivorID = survivor.persistentModelID
        for child in relationship.children {
            if reaches(
                survivorID,
                from: child.persistentModelID,
                adjacency: adjacency
            ) {
                return true
            }
        }
        return false
    }

    private static func reaches(
        _ target: PersistentIdentifier,
        from start: PersistentIdentifier,
        adjacency: [PersistentIdentifier: Set<PersistentIdentifier>]
    ) -> Bool {
        var visited = Set<PersistentIdentifier>()
        var pending = [start]
        while let id = pending.popLast() {
            guard visited.insert(id).inserted else { continue }
            if id == target { return true }
            pending.append(contentsOf: adjacency[id, default: []])
        }
        return false
    }

    private static func deduplicatedIssues(
        _ issues: [PersonMergeStructuralIssue]
    ) -> [PersonMergeStructuralIssue] {
        var seen = Set<String>()
        return issues.filter { seen.insert($0.id).inserted }
    }
}

struct PersonMergePlan {
    let survivor: Person
    let duplicate: Person
    let survivorProfile: PersonMergeProfileSnapshot
    let duplicateProfile: PersonMergeProfileSnapshot
    let automaticProfile: PersonMergeProfileSnapshot
    let addedFields: [PersonMergeField]
    let conflicts: [PersonMergeConflict]
    let relationship: PersonMergeRelationshipPlan
    let structuralIssues: [PersonMergeStructuralIssue]
    let gatherings: [Gathering]

    static func make(survivor: Person, duplicate: Person) -> PersonMergePlan {
        let survivorProfile = PersonMergeProfileSnapshot(person: survivor)
        let duplicateProfile = PersonMergeProfileSnapshot(person: duplicate)
        var automaticProfile = survivorProfile
        automaticProfile.createdAt = min(survivorProfile.createdAt, duplicateProfile.createdAt)
        var addedFields: [PersonMergeField] = []
        var conflicts: [PersonMergeConflict] = []

        for field in PersonMergeField.allCases {
            if survivorProfile.hasSameValue(field, as: duplicateProfile) { continue }
            if survivorProfile.isEmpty(field), !duplicateProfile.isEmpty(field) {
                automaticProfile.take(field, from: duplicateProfile)
                addedFields.append(field)
            } else if !survivorProfile.isEmpty(field), !duplicateProfile.isEmpty(field) {
                conflicts.append(PersonMergeConflict(
                    field: field,
                    survivorValue: survivorProfile.description(for: field),
                    duplicateValue: duplicateProfile.description(for: field)
                ))
            }
        }

        let preflight = PersonMergePreflight.evaluate(survivor: survivor, duplicate: duplicate)
        return PersonMergePlan(
            survivor: survivor,
            duplicate: duplicate,
            survivorProfile: survivorProfile,
            duplicateProfile: duplicateProfile,
            automaticProfile: automaticProfile,
            addedFields: addedFields,
            conflicts: conflicts,
            relationship: preflight.relationship,
            structuralIssues: preflight.issues,
            gatherings: uniqueGatherings(survivor.gatherings + duplicate.gatherings)
        )
    }

    func resolvedProfile(using choices: [PersonMergeField: PersonMergeSide]) throws -> PersonMergeProfileSnapshot {
        var result = automaticProfile
        for conflict in conflicts {
            guard let side = choices[conflict.field] else {
                throw PersonMergeServiceError.unresolvedConflict(conflict.field)
            }
            if side == .duplicate { result.take(conflict.field, from: duplicateProfile) }
        }
        result.createdAt = min(survivorProfile.createdAt, duplicateProfile.createdAt)
        return result
    }

    private static func uniqueGatherings(_ gatherings: [Gathering]) -> [Gathering] {
        var seen = Set<PersistentIdentifier>()
        return gatherings.filter { seen.insert($0.persistentModelID).inserted }
    }
}

// MARK: - Atomic merge

enum PersonMergeServiceError: LocalizedError {
    case structuralConflict([PersonMergeStructuralIssue])
    case unresolvedConflict(PersonMergeField)
    case relationshipMutationFailed

    var errorDescription: String? {
        switch self {
        case .structuralConflict(let issues):
            issues.map(\.message).joined(separator: "\n")
        case .unresolvedConflict(let field):
            "「\(field.displayName)」で残す値を選んでください。"
        case .relationshipMutationFailed:
            "関係の付け替えに失敗しました。データは統合前の状態に戻されました。"
        }
    }
}

enum PersonMergeService {
    @discardableResult
    static func merge(
        plan originalPlan: PersonMergePlan,
        choices: [PersonMergeField: PersonMergeSide],
        in context: ModelContext
    ) throws -> Person {
        try merge(plan: originalPlan, choices: choices, in: context, save: { try $0.save() })
    }

    @discardableResult
    static func merge(
        plan originalPlan: PersonMergePlan,
        choices: [PersonMergeField: PersonMergeSide],
        in context: ModelContext,
        save: (ModelContext) throws -> Void
    ) throws -> Person {
        // UI表示後に関係が変わっていても、実行直前の状態で再preflightする。
        let plan = PersonMergePlan.make(
            survivor: originalPlan.survivor,
            duplicate: originalPlan.duplicate
        )
        guard plan.structuralIssues.isEmpty else {
            throw PersonMergeServiceError.structuralConflict(plan.structuralIssues)
        }
        let profile = try plan.resolvedProfile(using: choices)

        return try RelationshipTransaction.perform(in: context, save: save) {
            apply(profile, to: plan.survivor)
            transferGatherings(plan.gatherings, survivor: plan.survivor, duplicate: plan.duplicate)
            try rewireRelationships(plan)
            RelationshipManager.delete(plan.duplicate, from: context)
            return plan.survivor
        }
    }

    private static func apply(_ profile: PersonMergeProfileSnapshot, to person: Person) {
        person.name = profile.name
        person.kana = profile.kana
        person.relationNote = profile.relationNote
        person.photoData = profile.photoData
        person.phone = profile.phone
        person.email = profile.email
        person.livingArea = profile.livingArea
        person.lastMetDate = profile.lastMet.date
        person.lastMetPlace = profile.lastMet.place
        person.postalAddress = profile.postalAddress
        person.birthday = profile.birthday
        person.favorites = profile.favorites
        person.dietaryNotes = profile.dietaryNotes
        person.memo = profile.memo
        person.createdAt = profile.createdAt
    }

    private static func transferGatherings(
        _ gatherings: [Gathering],
        survivor: Person,
        duplicate: Person
    ) {
        let survivorID = survivor.persistentModelID
        let duplicateID = duplicate.persistentModelID
        for gathering in gatherings {
            gathering.attendees.removeAll {
                let id = $0.persistentModelID
                return id == survivorID || id == duplicateID
            }
            gathering.attendees.append(survivor)
        }
    }

    private static func rewireRelationships(_ plan: PersonMergePlan) throws {
        let survivor = plan.survivor
        let duplicate = plan.duplicate

        // duplicateとの直接関係を含め、移動元の全エッジを先に安全に外す。
        RelationshipManager.detachAll(duplicate)

        if let spouse = plan.relationship.spouse {
            if survivor.spouse?.persistentModelID != spouse.persistentModelID
                || spouse.spouse?.persistentModelID != survivor.persistentModelID {
                _ = RelationshipManager.removeSpouse(of: survivor)
                guard RelationshipManager.setSpouse(survivor, spouse) else {
                    throw PersonMergeServiceError.relationshipMutationFailed
                }
            }
        } else if survivor.spouse?.persistentModelID == duplicate.persistentModelID {
            _ = RelationshipManager.removeSpouse(of: survivor)
        }

        for parent in plan.relationship.parents {
            if !survivor.parents.contains(where: { $0.persistentModelID == parent.persistentModelID }),
               !RelationshipManager.addParentChild(parent: parent, child: survivor) {
                throw PersonMergeServiceError.relationshipMutationFailed
            }
        }
        for child in plan.relationship.children {
            if !survivor.children.contains(where: { $0.persistentModelID == child.persistentModelID }),
               !RelationshipManager.addParentChild(parent: survivor, child: child) {
                throw PersonMergeServiceError.relationshipMutationFailed
            }
        }
    }
}
