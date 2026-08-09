import XCTest
import SwiftData
@testable import ShinsekiCho

@MainActor
final class PersonMergeTests: XCTestCase {
    private enum ForcedSaveFailure: Error { case failed }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Person.self,
            Gathering.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func insert(_ people: [Person], into context: ModelContext) throws {
        people.forEach(context.insert)
        try context.save()
    }

    private func survivorChoices(_ plan: PersonMergePlan) -> [PersonMergeField: PersonMergeSide] {
        Dictionary(uniqueKeysWithValues: plan.conflicts.map { ($0.field, .survivor) })
    }

    @discardableResult
    private func merge(
        _ survivor: Person,
        _ duplicate: Person,
        in context: ModelContext
    ) throws -> Person {
        let plan = PersonMergePlan.make(survivor: survivor, duplicate: duplicate)
        return try PersonMergeService.merge(
            plan: plan,
            choices: survivorChoices(plan),
            in: context
        )
    }

    private func contains(_ people: [Person], _ target: Person) -> Bool {
        people.contains { $0.persistentModelID == target.persistentModelID }
    }

    // MARK: Duplicate Detector

    func testDetectorMatchesTrimmedName() throws {
        let container = try makeContainer()
        let survivor = Person(name: " 山田 花子 ")
        let duplicate = Person(name: "山田 花子")
        try insert([survivor, duplicate], into: container.mainContext)
        XCTAssertTrue(PersonDuplicateDetector.isCandidate(duplicate, for: survivor))
    }

    func testDetectorMatchesSafeFullWidthNormalization() throws {
        let container = try makeContainer()
        let survivor = Person(name: "YAMADA 1")
        let duplicate = Person(name: "ｙａｍａｄａ　１")
        try insert([survivor, duplicate], into: container.mainContext)
        XCTAssertTrue(PersonDuplicateDetector.isCandidate(duplicate, for: survivor))
    }

    func testDetectorMatchesNonEmptyNormalizedKana() throws {
        let container = try makeContainer()
        let survivor = Person(name: "山田 花子", kana: "やまだ はなこ")
        let duplicate = Person(name: "佐藤 花子", kana: "やまだ　はなこ")
        try insert([survivor, duplicate], into: container.mainContext)
        XCTAssertTrue(PersonDuplicateDetector.isCandidate(duplicate, for: survivor))
    }

    func testDetectorDoesNotMatchUnrelatedName() throws {
        let container = try makeContainer()
        let survivor = Person(name: "山田 花子")
        let unrelated = Person(name: "山田 華子")
        try insert([survivor, unrelated], into: container.mainContext)
        XCTAssertFalse(PersonDuplicateDetector.isCandidate(unrelated, for: survivor))
    }

    func testDetectorExcludesSurvivorItself() throws {
        let container = try makeContainer()
        let survivor = Person(name: "山田 花子")
        try insert([survivor], into: container.mainContext)
        XCTAssertTrue(PersonDuplicateDetector.candidates(for: survivor, among: [survivor]).isEmpty)
    }

    // MARK: Merge Plan

    func testPlanCompletesEmptySurvivorFieldFromDuplicate() throws {
        let container = try makeContainer()
        let survivor = Person(name: "同名", phone: "")
        let duplicate = Person(name: "同名", phone: "090-1111-2222")
        try insert([survivor, duplicate], into: container.mainContext)
        let plan = PersonMergePlan.make(survivor: survivor, duplicate: duplicate)
        XCTAssertEqual(plan.automaticProfile.phone, "090-1111-2222")
        XCTAssertTrue(plan.addedFields.contains(.phone))
    }

    func testPlanKeepsNonEmptySurvivorWhenDuplicateIsEmpty() throws {
        let container = try makeContainer()
        let survivor = Person(name: "同名", email: "keep@example.com")
        let duplicate = Person(name: "同名")
        try insert([survivor, duplicate], into: container.mainContext)
        let plan = PersonMergePlan.make(survivor: survivor, duplicate: duplicate)
        XCTAssertEqual(plan.automaticProfile.email, "keep@example.com")
        XCTAssertFalse(plan.conflicts.contains { $0.field == .email })
    }

    func testPlanTreatsSameValueAsNoConflict() throws {
        let container = try makeContainer()
        let survivor = Person(name: "同名", livingArea: "東京")
        let duplicate = Person(name: "同名", livingArea: "東京")
        try insert([survivor, duplicate], into: container.mainContext)
        XCTAssertFalse(PersonMergePlan.make(survivor: survivor, duplicate: duplicate).conflicts.contains {
            $0.field == .livingArea
        })
    }

    func testPlanMarksDifferentNonEmptyValuesAsConflict() throws {
        let container = try makeContainer()
        let survivor = Person(name: "同名", postalAddress: "東京都")
        let duplicate = Person(name: "同名", postalAddress: "大阪府")
        try insert([survivor, duplicate], into: container.mainContext)
        XCTAssertTrue(PersonMergePlan.make(survivor: survivor, duplicate: duplicate).conflicts.contains {
            $0.field == .postalAddress
        })
    }

    func testPlanMarksDifferentPhotosAsConflict() throws {
        let container = try makeContainer()
        let survivor = Person(name: "同名", photoData: Data([1]))
        let duplicate = Person(name: "同名", photoData: Data([2]))
        try insert([survivor, duplicate], into: container.mainContext)
        XCTAssertTrue(PersonMergePlan.make(survivor: survivor, duplicate: duplicate).conflicts.contains {
            $0.field == .photoData
        })
    }

    func testPlanTreatsLastMetDateAndPlaceAsOneConflict() throws {
        let container = try makeContainer()
        let survivor = Person(
            name: "同名",
            lastMetDate: Date(timeIntervalSince1970: 100),
            lastMetPlace: "東京"
        )
        let duplicate = Person(
            name: "同名",
            lastMetDate: Date(timeIntervalSince1970: 200),
            lastMetPlace: "大阪"
        )
        try insert([survivor, duplicate], into: container.mainContext)
        let plan = PersonMergePlan.make(survivor: survivor, duplicate: duplicate)
        XCTAssertEqual(plan.conflicts.filter { $0.field == .lastMet }.count, 1)
        let resolved = try plan.resolvedProfile(using: [.lastMet: .duplicate])
        XCTAssertEqual(resolved.lastMet.date, duplicate.lastMetDate)
        XCTAssertEqual(resolved.lastMet.place, "大阪")
    }

    func testPlanKeepsOlderCreatedAt() throws {
        let container = try makeContainer()
        let survivor = Person(name: "同名")
        let duplicate = Person(name: "同名")
        survivor.createdAt = Date(timeIntervalSince1970: 200)
        duplicate.createdAt = Date(timeIntervalSince1970: 100)
        try insert([survivor, duplicate], into: container.mainContext)
        XCTAssertEqual(
            PersonMergePlan.make(survivor: survivor, duplicate: duplicate).automaticProfile.createdAt,
            Date(timeIntervalSince1970: 100)
        )
    }

    // MARK: Relationship merge

    func testSameSpouseIsDeduplicated() throws {
        let container = try makeContainer()
        let survivor = Person(name: "残す")
        let duplicate = Person(name: "重複")
        let spouse = Person(name: "配偶者")
        try insert([survivor, duplicate, spouse], into: container.mainContext)
        survivor.spouse = spouse
        duplicate.spouse = spouse
        spouse.spouse = duplicate
        try container.mainContext.save()

        try merge(survivor, duplicate, in: container.mainContext)
        XCTAssertEqual(survivor.spouse?.persistentModelID, spouse.persistentModelID)
        XCTAssertEqual(spouse.spouse?.persistentModelID, survivor.persistentModelID)
    }

    func testDuplicateOnlySpouseMovesToSurvivor() throws {
        let container = try makeContainer()
        let survivor = Person(name: "残す")
        let duplicate = Person(name: "重複")
        let spouse = Person(name: "配偶者")
        try insert([survivor, duplicate, spouse], into: container.mainContext)
        XCTAssertTrue(RelationshipManager.setSpouse(duplicate, spouse))
        try container.mainContext.save()

        try merge(survivor, duplicate, in: container.mainContext)
        XCTAssertEqual(survivor.spouse?.persistentModelID, spouse.persistentModelID)
        XCTAssertEqual(spouse.spouse?.persistentModelID, survivor.persistentModelID)
    }

    func testDifferentSpousesBlockPreflight() throws {
        let container = try makeContainer()
        let survivor = Person(name: "残す")
        let duplicate = Person(name: "重複")
        let spouseA = Person(name: "配偶者A")
        let spouseB = Person(name: "配偶者B")
        try insert([survivor, duplicate, spouseA, spouseB], into: container.mainContext)
        XCTAssertTrue(RelationshipManager.setSpouse(survivor, spouseA))
        XCTAssertTrue(RelationshipManager.setSpouse(duplicate, spouseB))
        let plan = PersonMergePlan.make(survivor: survivor, duplicate: duplicate)
        XCTAssertTrue(plan.structuralIssues.contains(.differentSpouses))
        XCTAssertThrowsError(try PersonMergeService.merge(
            plan: plan,
            choices: survivorChoices(plan),
            in: container.mainContext
        ))
    }

    func testParentsUnionAtMostTwoIsAllowed() throws {
        let container = try makeContainer()
        let survivor = Person(name: "残す")
        let duplicate = Person(name: "重複")
        let parentA = Person(name: "親A")
        let parentB = Person(name: "親B")
        try insert([survivor, duplicate, parentA, parentB], into: container.mainContext)
        XCTAssertTrue(RelationshipManager.addParentChild(parent: parentA, child: survivor))
        XCTAssertTrue(RelationshipManager.addParentChild(parent: parentB, child: duplicate))
        try container.mainContext.save()

        try merge(survivor, duplicate, in: container.mainContext)
        XCTAssertEqual(Set(survivor.parents.map(\.persistentModelID)), Set([parentA.persistentModelID, parentB.persistentModelID]))
    }

    func testParentsUnionOverTwoBlocksPreflight() throws {
        let container = try makeContainer()
        let survivor = Person(name: "残す")
        let duplicate = Person(name: "重複")
        let parents = [Person(name: "親A"), Person(name: "親B"), Person(name: "親C")]
        try insert([survivor, duplicate] + parents, into: container.mainContext)
        XCTAssertTrue(RelationshipManager.addParentChild(parent: parents[0], child: survivor))
        XCTAssertTrue(RelationshipManager.addParentChild(parent: parents[1], child: survivor))
        // 既存2人制約の範囲でduplicate側に別の親を持たせる。
        XCTAssertTrue(RelationshipManager.addParentChild(parent: parents[2], child: duplicate))
        let plan = PersonMergePlan.make(survivor: survivor, duplicate: duplicate)
        XCTAssertTrue(plan.structuralIssues.contains(.tooManyParents))
    }

    func testDuplicateChildRelationshipMovesToSurvivor() throws {
        let container = try makeContainer()
        let survivor = Person(name: "残す")
        let duplicate = Person(name: "重複")
        let child = Person(name: "子")
        try insert([survivor, duplicate, child], into: container.mainContext)
        XCTAssertTrue(RelationshipManager.addParentChild(parent: duplicate, child: child))
        try container.mainContext.save()

        try merge(survivor, duplicate, in: container.mainContext)
        XCTAssertTrue(contains(survivor.children, child))
        XCTAssertTrue(contains(child.parents, survivor))
        XCTAssertFalse(contains(child.parents, duplicate))
    }

    func testExistingSurvivorChildIsDeduplicated() throws {
        let container = try makeContainer()
        let survivor = Person(name: "残す")
        let duplicate = Person(name: "重複")
        let child = Person(name: "子")
        try insert([survivor, duplicate, child], into: container.mainContext)
        XCTAssertTrue(RelationshipManager.addParentChild(parent: survivor, child: child))
        XCTAssertTrue(RelationshipManager.addParentChild(parent: duplicate, child: child))
        try container.mainContext.save()

        try merge(survivor, duplicate, in: container.mainContext)
        XCTAssertEqual(survivor.children.filter { $0.persistentModelID == child.persistentModelID }.count, 1)
        XCTAssertEqual(child.parents.filter { $0.persistentModelID == survivor.persistentModelID }.count, 1)
    }

    func testMergeThatCreatesAncestryCycleIsBlocked() throws {
        let container = try makeContainer()
        let survivor = Person(name: "残す")
        let duplicate = Person(name: "重複")
        let ancestor = Person(name: "祖先")
        try insert([survivor, duplicate, ancestor], into: container.mainContext)
        XCTAssertTrue(RelationshipManager.addParentChild(parent: ancestor, child: survivor))
        XCTAssertTrue(RelationshipManager.addParentChild(parent: duplicate, child: ancestor))
        let plan = PersonMergePlan.make(survivor: survivor, duplicate: duplicate)
        XCTAssertTrue(plan.structuralIssues.contains(.ancestryCycle))
    }

    func testDirectSpouseBetweenSourceAndTargetDoesNotBecomeSelfSpouse() throws {
        let container = try makeContainer()
        let survivor = Person(name: "残す")
        let duplicate = Person(name: "重複")
        try insert([survivor, duplicate], into: container.mainContext)
        XCTAssertTrue(RelationshipManager.setSpouse(survivor, duplicate))
        try container.mainContext.save()

        try merge(survivor, duplicate, in: container.mainContext)
        XCTAssertNil(survivor.spouse)
    }

    func testDirectParentChildBetweenSourceAndTargetDoesNotBecomeSelfParent() throws {
        let container = try makeContainer()
        let survivor = Person(name: "残す")
        let duplicate = Person(name: "重複")
        try insert([survivor, duplicate], into: container.mainContext)
        XCTAssertTrue(RelationshipManager.addParentChild(parent: duplicate, child: survivor))
        try container.mainContext.save()

        try merge(survivor, duplicate, in: container.mainContext)
        XCTAssertFalse(contains(survivor.parents, survivor))
        XCTAssertFalse(contains(survivor.children, survivor))
    }

    // MARK: Gathering merge

    func testGatheringsAreUnioned() throws {
        let (container, survivor, duplicate, first, second) = try gatheringFixture()
        try merge(survivor, duplicate, in: container.mainContext)
        XCTAssertEqual(Set(survivor.gatherings.map(\.persistentModelID)), Set([first.persistentModelID, second.persistentModelID]))
    }

    func testDuplicateAttendeeIsRemovedFromGathering() throws {
        let (container, survivor, duplicate, _, second) = try gatheringFixture()
        try merge(survivor, duplicate, in: container.mainContext)
        XCTAssertFalse(contains(second.attendees, duplicate))
        XCTAssertTrue(contains(second.attendees, survivor))
    }

    func testSurvivorAttendeeIsNotDuplicated() throws {
        let (container, survivor, duplicate, first, _) = try gatheringFixture()
        try merge(survivor, duplicate, in: container.mainContext)
        XCTAssertEqual(first.attendees.filter { $0.persistentModelID == survivor.persistentModelID }.count, 1)
    }

    private func gatheringFixture() throws -> (ModelContainer, Person, Person, Gathering, Gathering) {
        let container = try makeContainer()
        let survivor = Person(name: "残す")
        let duplicate = Person(name: "重複")
        let first = Gathering(title: "新年会")
        let second = Gathering(title: "一周忌")
        try insert([survivor, duplicate], into: container.mainContext)
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        first.attendees.append(survivor)
        first.attendees.append(duplicate)
        second.attendees.append(duplicate)
        try container.mainContext.save()
        return (container, survivor, duplicate, first, second)
    }

    // MARK: Atomicity

    func testSuccessfulMergeDeletesOnlyDuplicatePerson() throws {
        let container = try makeContainer()
        let survivor = Person(name: "残す")
        let duplicate = Person(name: "重複")
        try insert([survivor, duplicate], into: container.mainContext)
        try merge(survivor, duplicate, in: container.mainContext)
        let people = try container.mainContext.fetch(FetchDescriptor<Person>())
        XCTAssertEqual(people.map(\.persistentModelID), [survivor.persistentModelID])
    }

    func testSuccessfulMergeKeepsSurvivorPersistentIdentifier() throws {
        let container = try makeContainer()
        let survivor = Person(name: "残す")
        let duplicate = Person(name: "重複")
        try insert([survivor, duplicate], into: container.mainContext)
        let originalID = survivor.persistentModelID
        try merge(survivor, duplicate, in: container.mainContext)
        XCTAssertEqual(survivor.persistentModelID, originalID)
    }

    func testSaveFailureRollsBackProfileChanges() throws {
        let fixture = try atomicFixture()
        try assertForcedFailure(fixture)
        XCTAssertEqual(fixture.survivor.phone, "")
    }

    func testSaveFailureRollsBackRelationshipChanges() throws {
        let fixture = try atomicFixture()
        try assertForcedFailure(fixture)
        XCTAssertTrue(contains(fixture.duplicate.children, fixture.child))
        XCTAssertFalse(contains(fixture.survivor.children, fixture.child))
        XCTAssertTrue(contains(fixture.child.parents, fixture.duplicate))
    }

    func testSaveFailureRollsBackGatheringChanges() throws {
        let fixture = try atomicFixture()
        try assertForcedFailure(fixture)
        XCTAssertTrue(contains(fixture.gathering.attendees, fixture.duplicate))
        XCTAssertFalse(contains(fixture.gathering.attendees, fixture.survivor))
    }

    func testSaveFailureRestoresDuplicatePerson() throws {
        let fixture = try atomicFixture()
        try assertForcedFailure(fixture)
        let people = try fixture.container.mainContext.fetch(FetchDescriptor<Person>())
        XCTAssertTrue(contains(people, fixture.duplicate))
        XCTAssertEqual(people.count, 3)
    }

    private typealias AtomicFixture = (
        container: ModelContainer,
        survivor: Person,
        duplicate: Person,
        child: Person,
        gathering: Gathering,
        plan: PersonMergePlan
    )

    private func atomicFixture() throws -> AtomicFixture {
        let container = try makeContainer()
        let survivor = Person(name: "同名")
        let duplicate = Person(name: "同名", phone: "090-0000-0000")
        let child = Person(name: "子")
        let gathering = Gathering(title: "集まり")
        try insert([survivor, duplicate, child], into: container.mainContext)
        container.mainContext.insert(gathering)
        XCTAssertTrue(RelationshipManager.addParentChild(parent: duplicate, child: child))
        gathering.attendees.append(duplicate)
        try container.mainContext.save()
        return (
            container, survivor, duplicate, child, gathering,
            PersonMergePlan.make(survivor: survivor, duplicate: duplicate)
        )
    }

    private func assertForcedFailure(_ fixture: AtomicFixture) throws {
        XCTAssertThrowsError(try PersonMergeService.merge(
            plan: fixture.plan,
            choices: survivorChoices(fixture.plan),
            in: fixture.container.mainContext,
            save: { _ in throw ForcedSaveFailure.failed }
        ))
    }

    // MARK: isSelf

    func testDuplicateCanMergeIntoSelfSurvivor() throws {
        let container = try makeContainer()
        let survivor = Person(name: "自分", isSelf: true)
        let duplicate = Person(name: "自分の重複")
        try insert([survivor, duplicate], into: container.mainContext)
        let plan = PersonMergePlan.make(survivor: survivor, duplicate: duplicate)
        XCTAssertFalse(plan.structuralIssues.contains(.selfMustSurvive))
        try merge(survivor, duplicate, in: container.mainContext)
        XCTAssertTrue(survivor.isSelf)
    }

    func testSelfPersonCannotBeDeletedAsDuplicate() throws {
        let container = try makeContainer()
        let survivor = Person(name: "別人")
        let duplicate = Person(name: "自分", isSelf: true)
        try insert([survivor, duplicate], into: container.mainContext)
        let plan = PersonMergePlan.make(survivor: survivor, duplicate: duplicate)
        XCTAssertTrue(plan.structuralIssues.contains(.selfMustSurvive))
        XCTAssertThrowsError(try PersonMergeService.merge(
            plan: plan,
            choices: survivorChoices(plan),
            in: container.mainContext
        ))
    }

    func testMergeLeavesExactlyOneSelfPerson() throws {
        let container = try makeContainer()
        let survivor = Person(name: "自分", isSelf: true)
        let duplicate = Person(name: "自分の重複")
        try insert([survivor, duplicate], into: container.mainContext)
        try merge(survivor, duplicate, in: container.mainContext)
        let selfPeople = try container.mainContext.fetch(
            FetchDescriptor<Person>(predicate: #Predicate { $0.isSelf })
        )
        XCTAssertEqual(selfPeople.count, 1)
        XCTAssertEqual(selfPeople.first?.persistentModelID, survivor.persistentModelID)
    }

    // MARK: Graph

    func testTransferredRelationshipAppearsAsSurvivorEdge() throws {
        let container = try makeContainer()
        let survivor = Person(name: "残す", isSelf: true)
        let duplicate = Person(name: "重複")
        let child = Person(name: "子")
        try insert([survivor, duplicate, child], into: container.mainContext)
        XCTAssertTrue(RelationshipManager.addParentChild(parent: duplicate, child: child))
        try container.mainContext.save()
        try merge(survivor, duplicate, in: container.mainContext)

        let store = FamilyGraphStore()
        store.reset(with: survivor)
        store.expand(survivor)
        XCTAssertTrue(store.edges.contains {
            Set([$0.from, $0.to]) == Set([
                PersistentModelIDBox(survivor.persistentModelID),
                PersistentModelIDBox(child.persistentModelID)
            ])
        })
    }

    func testDuplicateNodeDisappearsFromRebuiltGraph() throws {
        let container = try makeContainer()
        let survivor = Person(name: "残す", isSelf: true)
        let duplicate = Person(name: "重複")
        let child = Person(name: "子")
        try insert([survivor, duplicate, child], into: container.mainContext)
        let duplicateID = PersistentModelIDBox(duplicate.persistentModelID)
        XCTAssertTrue(RelationshipManager.addParentChild(parent: duplicate, child: child))
        try container.mainContext.save()
        try merge(survivor, duplicate, in: container.mainContext)

        let store = FamilyGraphStore()
        store.reset(with: survivor)
        store.expand(survivor)
        XCTAssertNil(store.nodes[duplicateID])
    }

    func testCoupleKnotIsRecomputedAfterMerge() throws {
        let container = try makeContainer()
        let survivor = Person(name: "残す", isSelf: true)
        let duplicate = Person(name: "重複")
        let spouse = Person(name: "配偶者")
        let child = Person(name: "共同子")
        try insert([survivor, duplicate, spouse, child], into: container.mainContext)
        XCTAssertTrue(RelationshipManager.setSpouse(survivor, spouse))
        XCTAssertTrue(RelationshipManager.addParentChild(parent: duplicate, child: child))
        XCTAssertTrue(RelationshipManager.addParentChild(parent: spouse, child: child))
        try container.mainContext.save()
        try merge(survivor, duplicate, in: container.mainContext)

        let store = FamilyGraphStore()
        store.reset(with: survivor)
        store.expand(survivor)
        XCTAssertEqual(
            store.coupleRenderModel.knots.first?.commonChildren,
            [PersistentModelIDBox(child.persistentModelID)]
        )
    }
}
