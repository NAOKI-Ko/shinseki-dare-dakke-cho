import XCTest
import SwiftData
@testable import ShinsekiCho

@MainActor
final class OnboardingTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Person.self,
            Gathering.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeExistingFamily(in context: ModelContext) throws -> (
        selfPerson: Person,
        father: Person,
        mother: Person,
        spouse: Person,
        grandfather: Person
    ) {
        let selfPerson = Person(name: "山田 太郎", relationNote: "自分", isSelf: true)
        let father = Person(name: "山田 一郎", relationNote: "父")
        let mother = Person(name: "山田 花子", relationNote: "母")
        let spouse = Person(name: "佐藤 美咲", relationNote: "配偶者")
        let grandfather = Person(name: "山田 源治", relationNote: "父方祖父")
        [selfPerson, father, mother, spouse, grandfather].forEach(context.insert)
        XCTAssertTrue(RelationshipManager.addParentChild(parent: father, child: selfPerson))
        XCTAssertTrue(RelationshipManager.addParentChild(parent: mother, child: selfPerson))
        XCTAssertTrue(RelationshipManager.setSpouse(selfPerson, spouse))
        XCTAssertTrue(RelationshipManager.addParentChild(parent: grandfather, child: father))
        try context.save()
        return (selfPerson, father, mother, spouse, grandfather)
    }

    func testFirstLaunchWithoutSelfPresentsOnboarding() {
        let progress = OnboardingProgress(
            hasStarted: false,
            hasCompleted: false,
            isReplayRequested: false
        )

        XCTAssertTrue(progress.shouldPresent(hasRegisteredSelf: false))
        XCTAssertFalse(progress.shouldPresent(hasRegisteredSelf: true))
    }

    func testCompletedOnboardingDoesNotPresentAgain() {
        let progress = OnboardingProgress(
            hasStarted: true,
            hasCompleted: true,
            isReplayRequested: false
        )

        XCTAssertFalse(progress.shouldPresent(hasRegisteredSelf: false))
        XCTAssertFalse(progress.shouldPresent(hasRegisteredSelf: true))
    }

    func testSettingsReplayPresentsEvenAfterCompletion() {
        var progress = OnboardingProgress(
            hasStarted: true,
            hasCompleted: true,
            isReplayRequested: false
        )

        progress.requestReplay()

        XCTAssertTrue(progress.shouldPresent(hasRegisteredSelf: true))
    }

    func testSkipCompletesFirstExperienceWithoutReappearing() {
        var progress = OnboardingProgress(
            hasStarted: false,
            hasCompleted: false,
            isReplayRequested: false
        )

        progress.start()
        progress.finishOrSkip()

        XCTAssertTrue(progress.hasCompleted)
        XCTAssertFalse(progress.isReplayRequested)
        XCTAssertFalse(progress.shouldPresent(hasRegisteredSelf: false))
    }

    func testRegistrationCreatesSelfAndSelectedFamilyThroughRelationshipManager() throws {
        let container = try makeContainer()
        let context = container.mainContext
        var draft = OnboardingDraft()
        draft.selfName = "山田 太郎"
        draft.father = OnboardingRelativeDraft(isSelected: true, name: "山田 一郎")
        draft.mother = OnboardingRelativeDraft(isSelected: true, name: "山田 花子")
        draft.spouse = OnboardingRelativeDraft(isSelected: true, name: "佐藤 美咲")
        draft.sibling = OnboardingRelativeDraft(isSelected: true, name: "山田 次郎")
        draft.paternalGrandfather = OnboardingRelativeDraft(
            isSelected: true,
            name: "山田 源治"
        )

        let selfPerson = try OnboardingRegistrationService.register(
            draft: draft,
            existingSelf: nil,
            in: context
        )

        XCTAssertTrue(selfPerson.isSelf)
        XCTAssertEqual(Set(selfPerson.parents.map(\.name)), Set(["山田 一郎", "山田 花子"]))
        XCTAssertEqual(selfPerson.spouse?.name, "佐藤 美咲")
        let sibling = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Person>()).first { $0.name == "山田 次郎" }
        )
        XCTAssertEqual(Set(sibling.parents.map(\.name)), Set(["山田 一郎", "山田 花子"]))
        let father = try XCTUnwrap(selfPerson.parents.first { $0.name == "山田 一郎" })
        XCTAssertEqual(father.parents.map(\.name), ["山田 源治"])
    }

    func testFirstRunCompletionStillCreatesSelectedFamily() throws {
        let container = try makeContainer()
        let context = container.mainContext
        var draft = OnboardingDraft()
        draft.selfName = "初回 太郎"
        draft.father = OnboardingRelativeDraft(isSelected: true, name: "初回 一郎")
        draft.mother = OnboardingRelativeDraft(isSelected: true, name: "初回 花子")
        draft.spouse = OnboardingRelativeDraft(isSelected: true, name: "初回 美咲")

        let result = try OnboardingCompletionService.complete(
            mode: .firstRun,
            draft: draft,
            existingSelf: nil,
            in: context
        )

        let selfPerson = try XCTUnwrap(result)
        XCTAssertEqual(Set(selfPerson.parents.map(\.name)), Set(["初回 一郎", "初回 花子"]))
        XCTAssertEqual(selfPerson.spouse?.name, "初回 美咲")
    }

    func testReplayWithExistingSelfDoesNotCreateNewPerson() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let family = try makeExistingFamily(in: context)
        let beforeCount = try context.fetchCount(FetchDescriptor<Person>())

        let result = try OnboardingCompletionService.complete(
            mode: .replay,
            draft: OnboardingDraft(existingSelf: family.selfPerson),
            existingSelf: family.selfPerson,
            in: context
        )

        XCTAssertNil(result)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Person>()), beforeCount)
    }

    func testReplayWithExistingParentsDoesNotDuplicateOrHitParentLimit() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let family = try makeExistingFamily(in: context)
        var draft = OnboardingDraft(existingSelf: family.selfPerson)
        draft.father = OnboardingRelativeDraft(isSelected: true, name: family.father.name)
        draft.mother = OnboardingRelativeDraft(isSelected: true, name: family.mother.name)

        XCTAssertNoThrow(
            try OnboardingCompletionService.complete(
                mode: .replay,
                draft: draft,
                existingSelf: family.selfPerson,
                in: context
            )
        )
        XCTAssertEqual(family.selfPerson.parents.count, 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Person>()), 5)
    }

    func testReplayWithExistingSpouseDoesNotFailOrDuplicate() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let family = try makeExistingFamily(in: context)
        var draft = OnboardingDraft(existingSelf: family.selfPerson)
        draft.spouse = OnboardingRelativeDraft(isSelected: true, name: family.spouse.name)

        XCTAssertNoThrow(
            try OnboardingCompletionService.complete(
                mode: .replay,
                draft: draft,
                existingSelf: family.selfPerson,
                in: context
            )
        )
        XCTAssertEqual(family.selfPerson.spouse?.persistentModelID, family.spouse.persistentModelID)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Person>()), 5)
    }

    func testReplayCompletionDoesNotMutateRelationships() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let family = try makeExistingFamily(in: context)
        let parentIDs = Set(family.selfPerson.parents.map(\.persistentModelID))
        let spouseID = family.selfPerson.spouse?.persistentModelID
        let grandfatherChildren = Set(family.grandfather.children.map(\.persistentModelID))

        try OnboardingCompletionService.complete(
            mode: .replay,
            draft: OnboardingDraft(existingSelf: family.selfPerson),
            existingSelf: family.selfPerson,
            in: context
        )

        XCTAssertEqual(Set(family.selfPerson.parents.map(\.persistentModelID)), parentIDs)
        XCTAssertEqual(family.selfPerson.spouse?.persistentModelID, spouseID)
        XCTAssertEqual(Set(family.grandfather.children.map(\.persistentModelID)), grandfatherChildren)
    }

    func testReplayCompletionLeavesModelContextClean() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let family = try makeExistingFamily(in: context)
        XCTAssertFalse(context.hasChanges)

        try OnboardingCompletionService.complete(
            mode: .replay,
            draft: OnboardingDraft(existingSelf: family.selfPerson),
            existingSelf: family.selfPerson,
            in: context
        )

        XCTAssertFalse(context.hasChanges)
    }

    func testReplaySnapshotShowsExistingFamilyAndGrandparentsWithoutMutation() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let family = try makeExistingFamily(in: context)

        let snapshot = OnboardingFamilySnapshot(existingSelf: family.selfPerson)

        XCTAssertEqual(snapshot.selfName, "山田 太郎")
        XCTAssertEqual(Set(snapshot.familyItems.map(\.name)), Set(["山田 一郎", "山田 花子", "佐藤 美咲"]))
        XCTAssertEqual(snapshot.grandparentItems.map(\.name), ["山田 源治"])
        XCTAssertFalse(context.hasChanges)
    }
}
