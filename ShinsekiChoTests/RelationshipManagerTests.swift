import XCTest
import SwiftData
import UIKit
@testable import ShinsekiCho

@MainActor
final class RelationshipManagerTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Person.self,
            Gathering.self,
            configurations: configuration
        )
    }

    private func insert(_ people: [Person], into context: ModelContext) throws {
        people.forEach(context.insert)
        try context.save()
    }

    func testAddParentChildReflectsBothDirectionsWithoutDuplicates() throws {
        let container = try makeContainer()
        let parent = Person(name: "親")
        let child = Person(name: "子")
        try insert([parent, child], into: container.mainContext)

        RelationshipManager.addParentChild(parent: parent, child: child)
        RelationshipManager.addParentChild(parent: parent, child: child)

        XCTAssertEqual(parent.children.count, 1)
        XCTAssertEqual(child.parents.count, 1)
        XCTAssertEqual(parent.children.first?.persistentModelID, child.persistentModelID)
        XCTAssertEqual(child.parents.first?.persistentModelID, parent.persistentModelID)
    }

    func testAddChildConnectsBothSpousesWithoutDuplicates() throws {
        let container = try makeContainer()
        let a = Person(name: "A")
        let b = Person(name: "B")
        let child = Person(name: "C")
        try insert([a, b, child], into: container.mainContext)
        RelationshipManager.setSpouse(a, b)

        RelationshipManager.addChild(child, to: a, includeSpouse: true)
        RelationshipManager.addChild(child, to: a, includeSpouse: true)

        XCTAssertEqual(a.children.filter { $0.persistentModelID == child.persistentModelID }.count, 1)
        XCTAssertEqual(b.children.filter { $0.persistentModelID == child.persistentModelID }.count, 1)
        XCTAssertEqual(child.parents.filter { $0.persistentModelID == a.persistentModelID }.count, 1)
        XCTAssertEqual(child.parents.filter { $0.persistentModelID == b.persistentModelID }.count, 1)
        XCTAssertEqual(Set(child.parents.map(\.persistentModelID)), Set([a.persistentModelID, b.persistentModelID]))
    }

    func testSetSpouseRefusesToReplaceExistingSpouses() throws {
        let container = try makeContainer()
        let a = Person(name: "A")
        let oldA = Person(name: "Aの旧配偶者")
        let b = Person(name: "B")
        let oldB = Person(name: "Bの旧配偶者")
        try insert([a, oldA, b, oldB], into: container.mainContext)
        RelationshipManager.setSpouse(a, oldA)
        RelationshipManager.setSpouse(b, oldB)

        let linked = RelationshipManager.setSpouse(a, b)

        XCTAssertFalse(linked)
        XCTAssertEqual(a.spouse?.persistentModelID, oldA.persistentModelID)
        XCTAssertEqual(oldA.spouse?.persistentModelID, a.persistentModelID)
        XCTAssertEqual(b.spouse?.persistentModelID, oldB.persistentModelID)
        XCTAssertEqual(oldB.spouse?.persistentModelID, b.persistentModelID)
        XCTAssertFalse(RelationshipManager.canLink(.spouse, person: a, relative: b))
    }

    func testSpouseLinkIsBidirectional() throws {
        let container = try makeContainer()
        let a = Person(name: "A")
        let b = Person(name: "B")
        try insert([a, b], into: container.mainContext)

        XCTAssertTrue(try RelationshipManager.link(.spouse, person: a, relative: b))
        XCTAssertEqual(a.spouse?.persistentModelID, b.persistentModelID)
        XCTAssertEqual(b.spouse?.persistentModelID, a.persistentModelID)
    }

    func testExistingChildCanBeSelectedAsSharedChildAfterSpouseIsAdded() throws {
        let container = try makeContainer()
        let a = Person(name: "A")
        let b = Person(name: "B")
        let child = Person(name: "C")
        try insert([a, b, child], into: container.mainContext)
        XCTAssertTrue(RelationshipManager.addParentChild(parent: a, child: child))
        XCTAssertTrue(RelationshipManager.setSpouse(a, b))

        XCTAssertEqual(
            RelationshipManager.sharedChildCandidates(of: a, with: b).map(\.persistentModelID),
            [child.persistentModelID]
        )
        XCTAssertEqual(
            RelationshipManager.linkSharedChildren([child, child], of: a, with: b),
            1
        )

        XCTAssertEqual(a.children.filter { $0.persistentModelID == child.persistentModelID }.count, 1)
        XCTAssertEqual(b.children.filter { $0.persistentModelID == child.persistentModelID }.count, 1)
        XCTAssertEqual(
            Set(child.parents.map(\.persistentModelID)),
            Set([a.persistentModelID, b.persistentModelID])
        )
    }

    func testUnselectedExistingChildIsNotInferredAsSharedChild() throws {
        let container = try makeContainer()
        let a = Person(name: "A")
        let b = Person(name: "B")
        let child = Person(name: "C")
        try insert([a, b, child], into: container.mainContext)
        RelationshipManager.addParentChild(parent: a, child: child)
        RelationshipManager.setSpouse(a, b)

        XCTAssertEqual(RelationshipManager.linkSharedChildren([], of: a, with: b), 0)
        XCTAssertTrue(b.children.isEmpty)
        XCTAssertEqual(child.parents.map(\.persistentModelID), [a.persistentModelID])
    }

    func testChildLinkDoesNotInferSpouseUnlessExplicitlyRequested() throws {
        let container = try makeContainer()
        let a = Person(name: "A")
        let b = Person(name: "B")
        let child = Person(name: "C")
        try insert([a, b, child], into: container.mainContext)
        RelationshipManager.setSpouse(a, b)

        XCTAssertTrue(
            try RelationshipManager.link(
                .child,
                person: a,
                relative: child,
                includeSpouseForChild: false
            )
        )
        XCTAssertTrue(a.children.contains { $0.persistentModelID == child.persistentModelID })
        XCTAssertFalse(b.children.contains { $0.persistentModelID == child.persistentModelID })
        XCTAssertEqual(child.parents.map(\.persistentModelID), [a.persistentModelID])
    }

    func testSelfRelationsAreRejectedByAPIAndCandidateFilter() throws {
        let container = try makeContainer()
        let person = Person(name: "本人")
        try insert([person], into: container.mainContext)

        XCTAssertFalse(RelationshipManager.setSpouse(person, person))
        XCTAssertFalse(RelationshipManager.addParentChild(parent: person, child: person))
        XCTAssertFalse(RelationshipManager.canLink(.spouse, person: person, relative: person))
        XCTAssertFalse(RelationshipManager.canLink(.parent, person: person, relative: person))
        XCTAssertFalse(RelationshipManager.canLink(.child, person: person, relative: person))
        XCTAssertThrowsError(
            try RelationshipManager.link(.child, person: person, relative: person)
        ) { error in
            XCTAssertEqual(error as? RelationshipLinkError, .selfRelation)
        }
    }

    func testParentLimitIsEnforcedByAPIAndCandidateFilter() throws {
        let container = try makeContainer()
        let child = Person(name: "子")
        let parent1 = Person(name: "親1")
        let parent2 = Person(name: "親2")
        let parent3 = Person(name: "親3")
        try insert([child, parent1, parent2, parent3], into: container.mainContext)

        XCTAssertTrue(RelationshipManager.addParentChild(parent: parent1, child: child))
        XCTAssertTrue(RelationshipManager.addParentChild(parent: parent2, child: child))
        XCTAssertFalse(RelationshipManager.addParentChild(parent: parent3, child: child))
        XCTAssertFalse(RelationshipManager.canLink(.parent, person: child, relative: parent3))
        XCTAssertEqual(child.parents.count, 2)
        XCTAssertThrowsError(
            try RelationshipManager.link(.parent, person: child, relative: parent3)
        ) { error in
            XCTAssertEqual(error as? RelationshipLinkError, .parentLimit)
        }
    }

    func testParentCannotBeLinkedAsSpouse() throws {
        let container = try makeContainer()
        let parent = Person(name: "親")
        let child = Person(name: "子")
        try insert([parent, child], into: container.mainContext)
        RelationshipManager.addParentChild(parent: parent, child: child)

        XCTAssertFalse(RelationshipManager.canSetSpouse(parent, child))
        XCTAssertFalse(RelationshipManager.canLink(.spouse, person: child, relative: parent))
        XCTAssertFalse(RelationshipManager.setSpouse(child, parent))
        XCTAssertThrowsError(
            try RelationshipManager.link(.spouse, person: child, relative: parent)
        ) { error in
            XCTAssertEqual(error as? RelationshipLinkError, .incompatibleRelationship)
        }
    }

    func testChildCannotBeLinkedAsSpouse() throws {
        let container = try makeContainer()
        let parent = Person(name: "親")
        let child = Person(name: "子")
        try insert([parent, child], into: container.mainContext)
        RelationshipManager.addParentChild(parent: parent, child: child)

        XCTAssertFalse(RelationshipManager.canLink(.spouse, person: parent, relative: child))
        XCTAssertThrowsError(
            try RelationshipManager.link(.spouse, person: parent, relative: child)
        ) { error in
            XCTAssertEqual(error as? RelationshipLinkError, .incompatibleRelationship)
        }
    }

    func testAncestorCannotBeLinkedAsSpouse() throws {
        let container = try makeContainer()
        let grandparent = Person(name: "祖先")
        let parent = Person(name: "親")
        let child = Person(name: "本人")
        try insert([grandparent, parent, child], into: container.mainContext)
        RelationshipManager.addParentChild(parent: grandparent, child: parent)
        RelationshipManager.addParentChild(parent: parent, child: child)

        XCTAssertTrue(RelationshipManager.isAncestor(grandparent, of: child))
        XCTAssertFalse(RelationshipManager.canLink(.spouse, person: child, relative: grandparent))
        XCTAssertFalse(
            QuickRelativeRegistration.candidates(
                for: .spouse,
                person: child,
                from: [child, grandparent]
            ).contains { $0.persistentModelID == grandparent.persistentModelID }
        )
    }

    func testDescendantCannotBeLinkedAsSpouse() throws {
        let container = try makeContainer()
        let grandparent = Person(name: "本人")
        let parent = Person(name: "子")
        let grandchild = Person(name: "子孫")
        try insert([grandparent, parent, grandchild], into: container.mainContext)
        RelationshipManager.addParentChild(parent: grandparent, child: parent)
        RelationshipManager.addParentChild(parent: parent, child: grandchild)

        XCTAssertTrue(RelationshipManager.isDescendant(grandchild, of: grandparent))
        XCTAssertFalse(RelationshipManager.canLink(.spouse, person: grandparent, relative: grandchild))
        XCTAssertThrowsError(
            try RelationshipManager.link(.spouse, person: grandparent, relative: grandchild)
        ) { error in
            XCTAssertEqual(error as? RelationshipLinkError, .incompatibleRelationship)
        }
    }

    func testDirectParentChildReversalIsRejected() throws {
        let container = try makeContainer()
        let a = Person(name: "A")
        let b = Person(name: "B")
        try insert([a, b], into: container.mainContext)
        RelationshipManager.addParentChild(parent: a, child: b)

        XCTAssertTrue(RelationshipManager.wouldCreateAncestryCycle(parent: b, child: a))
        XCTAssertFalse(RelationshipManager.addParentChild(parent: b, child: a))
        XCTAssertFalse(RelationshipManager.canLink(.child, person: b, relative: a))
        XCTAssertThrowsError(
            try RelationshipManager.link(.child, person: b, relative: a)
        ) { error in
            XCTAssertEqual(error as? RelationshipLinkError, .invalidFamilyCycle)
        }
        XCTAssertEqual(a.parents.count, 0)
        XCTAssertEqual(b.parents.map(\.persistentModelID), [a.persistentModelID])
    }

    func testThreeGenerationAncestryCycleIsRejected() throws {
        let container = try makeContainer()
        let a = Person(name: "A")
        let b = Person(name: "B")
        let c = Person(name: "C")
        try insert([a, b, c], into: container.mainContext)
        RelationshipManager.addParentChild(parent: a, child: b)
        RelationshipManager.addParentChild(parent: b, child: c)

        XCTAssertTrue(RelationshipManager.wouldCreateAncestryCycle(parent: c, child: a))
        XCTAssertFalse(RelationshipManager.canLink(.child, person: c, relative: a))
        XCTAssertFalse(RelationshipManager.addParentChild(parent: c, child: a))
        XCTAssertThrowsError(
            try RelationshipManager.link(.child, person: c, relative: a)
        ) { error in
            XCTAssertEqual(error as? RelationshipLinkError, .invalidFamilyCycle)
        }
        XCTAssertTrue(a.parents.isEmpty)
        XCTAssertTrue(c.children.isEmpty)
    }

    func testExistingSpousesCannotAlsoBeLinkedAsParentAndChild() throws {
        let container = try makeContainer()
        let a = Person(name: "A")
        let b = Person(name: "B")
        try insert([a, b], into: container.mainContext)
        XCTAssertTrue(RelationshipManager.setSpouse(a, b))

        XCTAssertFalse(RelationshipManager.canLink(.parent, person: a, relative: b))
        XCTAssertFalse(RelationshipManager.canLink(.child, person: a, relative: b))
        XCTAssertFalse(RelationshipManager.addParentChild(parent: a, child: b))
        XCTAssertThrowsError(
            try RelationshipManager.link(.parent, person: a, relative: b)
        ) { error in
            XCTAssertEqual(error as? RelationshipLinkError, .incompatibleRelationship)
        }
        XCTAssertThrowsError(
            try RelationshipManager.link(.child, person: a, relative: b)
        ) { error in
            XCTAssertEqual(error as? RelationshipLinkError, .incompatibleRelationship)
        }
        XCTAssertTrue(a.parents.isEmpty)
        XCTAssertTrue(a.children.isEmpty)
        XCTAssertTrue(b.parents.isEmpty)
        XCTAssertTrue(b.children.isEmpty)
    }

    func testJointChildPreflightPreventsPartialThirdParentMutation() throws {
        let container = try makeContainer()
        let a = Person(name: "A")
        let b = Person(name: "B")
        let existingParent = Person(name: "既存の親")
        let child = Person(name: "子")
        try insert([a, b, existingParent, child], into: container.mainContext)
        XCTAssertTrue(RelationshipManager.setSpouse(a, b))
        XCTAssertTrue(RelationshipManager.addParentChild(parent: existingParent, child: child))

        XCTAssertThrowsError(
            try RelationshipManager.link(
                .child,
                person: a,
                relative: child,
                includeSpouseForChild: true
            )
        ) { error in
            XCTAssertEqual(error as? RelationshipLinkError, .parentLimit)
        }
        XCTAssertFalse(a.children.contains { $0.persistentModelID == child.persistentModelID })
        XCTAssertFalse(b.children.contains { $0.persistentModelID == child.persistentModelID })
        XCTAssertEqual(child.parents.map(\.persistentModelID), [existingParent.persistentModelID])
    }

    func testNormalUnrelatedRelationshipsRemainLinkable() throws {
        let container = try makeContainer()
        let person = Person(name: "本人")
        let spouse = Person(name: "配偶者")
        let parent = Person(name: "親")
        let child = Person(name: "子")
        try insert([person, spouse, parent, child], into: container.mainContext)

        XCTAssertTrue(try RelationshipManager.link(.spouse, person: person, relative: spouse))
        XCTAssertTrue(try RelationshipManager.link(.parent, person: person, relative: parent))
        XCTAssertTrue(try RelationshipManager.link(.child, person: person, relative: child))
        XCTAssertEqual(person.spouse?.persistentModelID, spouse.persistentModelID)
        XCTAssertEqual(person.parents.map(\.persistentModelID), [parent.persistentModelID])
        XCTAssertEqual(person.children.map(\.persistentModelID), [child.persistentModelID])
    }

    func testRelationshipTransactionRollsBackSpouseParentAndChildMutations() throws {
        enum ForcedFailure: Error { case saveFailed }
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(name: "本人")
        let spouse = Person(name: "配偶者")
        let parent = Person(name: "親")
        let child = Person(name: "子")
        try insert([person, spouse, parent, child], into: context)

        XCTAssertThrowsError(
            try RelationshipTransaction.perform(in: context) {
                try RelationshipManager.link(.spouse, person: person, relative: spouse)
                throw ForcedFailure.saveFailed
            }
        )
        XCTAssertNil(person.spouse)
        XCTAssertNil(spouse.spouse)

        XCTAssertThrowsError(
            try RelationshipTransaction.perform(in: context) {
                try RelationshipManager.link(.parent, person: person, relative: parent)
                throw ForcedFailure.saveFailed
            }
        )
        XCTAssertTrue(person.parents.isEmpty)
        XCTAssertTrue(parent.children.isEmpty)

        XCTAssertThrowsError(
            try RelationshipTransaction.perform(in: context) {
                try RelationshipManager.link(.child, person: person, relative: child)
                throw ForcedFailure.saveFailed
            }
        )
        XCTAssertTrue(person.children.isEmpty)
        XCTAssertTrue(child.parents.isEmpty)
    }

    func testRelationshipTransactionRollsBackSharedChildMutation() throws {
        enum ForcedFailure: Error { case saveFailed }
        let container = try makeContainer()
        let context = container.mainContext
        let a = Person(name: "A")
        let b = Person(name: "B")
        let child = Person(name: "C")
        try insert([a, b, child], into: context)
        RelationshipManager.addParentChild(parent: a, child: child)
        RelationshipManager.setSpouse(a, b)
        try context.save()

        XCTAssertThrowsError(
            try RelationshipTransaction.perform(in: context) {
                RelationshipManager.linkSharedChildren([child], of: a, with: b)
                throw ForcedFailure.saveFailed
            }
        )

        XCTAssertTrue(b.children.isEmpty)
        XCTAssertEqual(child.parents.map(\.persistentModelID), [a.persistentModelID])
        XCTAssertEqual(a.spouse?.persistentModelID, b.persistentModelID)
        XCTAssertEqual(b.spouse?.persistentModelID, a.persistentModelID)
    }

    func testExistingPeopleCanBeLinkedWithoutCreatingDuplicatePersonRecords() throws {
        let container = try makeContainer()
        let person = Person(name: "本人")
        let spouse = Person(name: "登録済み配偶者")
        let parent = Person(name: "登録済み親")
        let child = Person(name: "登録済み子")
        try insert([person, spouse, parent, child], into: container.mainContext)

        try QuickRelativeRegistration.linkExisting(
            spouse,
            kind: .spouse,
            for: person,
            in: container.mainContext
        )
        try QuickRelativeRegistration.linkExisting(
            parent,
            kind: .parent,
            for: person,
            in: container.mainContext
        )
        try QuickRelativeRegistration.linkExisting(
            child,
            kind: .child,
            for: person,
            in: container.mainContext,
            includeSpouseForChild: false
        )

        XCTAssertEqual(
            try container.mainContext.fetch(FetchDescriptor<Person>()).count,
            4
        )
        XCTAssertEqual(person.spouse?.persistentModelID, spouse.persistentModelID)
        XCTAssertTrue(person.parents.contains { $0.persistentModelID == parent.persistentModelID })
        XCTAssertTrue(parent.children.contains { $0.persistentModelID == person.persistentModelID })
        XCTAssertTrue(person.children.contains { $0.persistentModelID == child.persistentModelID })
        XCTAssertTrue(child.parents.contains { $0.persistentModelID == person.persistentModelID })
        XCTAssertFalse(spouse.children.contains { $0.persistentModelID == child.persistentModelID })
    }

    func testDetachAllRemovesEveryReciprocalRelationship() throws {
        let container = try makeContainer()
        let person = Person(name: "本人")
        let spouse = Person(name: "配偶者")
        let parent1 = Person(name: "親1")
        let parent2 = Person(name: "親2")
        let child1 = Person(name: "子1")
        let child2 = Person(name: "子2")
        try insert([person, spouse, parent1, parent2, child1, child2], into: container.mainContext)
        RelationshipManager.setSpouse(person, spouse)
        RelationshipManager.addParentChild(parent: parent1, child: person)
        RelationshipManager.addParentChild(parent: parent2, child: person)
        RelationshipManager.addParentChild(parent: person, child: child1)
        RelationshipManager.addParentChild(parent: person, child: child2)

        RelationshipManager.detachAll(person)

        XCTAssertNil(person.spouse)
        XCTAssertNil(spouse.spouse)
        XCTAssertTrue(person.parents.isEmpty)
        XCTAssertTrue(person.children.isEmpty)
        XCTAssertFalse(parent1.children.contains { $0.persistentModelID == person.persistentModelID })
        XCTAssertFalse(parent2.children.contains { $0.persistentModelID == person.persistentModelID })
        XCTAssertFalse(child1.parents.contains { $0.persistentModelID == person.persistentModelID })
        XCTAssertFalse(child2.parents.contains { $0.persistentModelID == person.persistentModelID })
    }

    func testSiblingsAreDerivedFromSharedParentsAndDeduplicated() throws {
        let container = try makeContainer()
        let parent1 = Person(name: "親1")
        let parent2 = Person(name: "親2")
        let child = Person(name: "本人")
        let sibling = Person(name: "きょうだい")
        let unrelated = Person(name: "他人")
        try insert([parent1, parent2, child, sibling, unrelated], into: container.mainContext)
        RelationshipManager.addParentChild(parent: parent1, child: child)
        RelationshipManager.addParentChild(parent: parent2, child: child)
        RelationshipManager.addParentChild(parent: parent1, child: sibling)
        RelationshipManager.addParentChild(parent: parent2, child: sibling)
        RelationshipManager.addParentChild(parent: parent2, child: unrelated)

        let siblingIDs = Set(child.siblings.map(\.persistentModelID))

        XCTAssertEqual(siblingIDs.count, 2)
        XCTAssertTrue(siblingIDs.contains(sibling.persistentModelID))
        XCTAssertTrue(siblingIDs.contains(unrelated.persistentModelID))
    }

    func testRelationshipsPersistAfterContainerRecreation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShinsekiCho-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("relationships.store")
        let configuration = ModelConfiguration(url: storeURL)

        do {
            let container = try ModelContainer(
                for: Person.self,
                Gathering.self,
                configurations: configuration
            )
            let parent = Person(name: "保存親")
            let child = Person(name: "保存子", isSelf: true)
            let spouse = Person(name: "保存配偶者")
            try insert([parent, child, spouse], into: container.mainContext)
            RelationshipManager.addParentChild(parent: parent, child: child)
            RelationshipManager.setSpouse(child, spouse)
            try container.mainContext.save()
        }

        let reopened = try ModelContainer(
            for: Person.self,
            Gathering.self,
            configurations: configuration
        )
        let people = try reopened.mainContext.fetch(FetchDescriptor<Person>())
        let child = try XCTUnwrap(people.first { $0.name == "保存子" })
        let parent = try XCTUnwrap(people.first { $0.name == "保存親" })
        let spouse = try XCTUnwrap(people.first { $0.name == "保存配偶者" })

        XCTAssertEqual(child.parents.map(\.name), ["保存親"])
        XCTAssertEqual(parent.children.map(\.name), ["保存子"])
        XCTAssertEqual(child.spouse?.name, "保存配偶者")
        XCTAssertEqual(spouse.spouse?.name, "保存子")
        XCTAssertTrue(child.isSelf)
    }

    func testTwoParentsAndCommonChildPersistAfterContainerRecreation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShinsekiCho-ManyToMany-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(
            url: directory.appendingPathComponent("many-to-many.store")
        )

        do {
            let container = try ModelContainer(
                for: Person.self,
                Gathering.self,
                configurations: configuration
            )
            let parent1 = Person(name: "親A")
            let parent2 = Person(name: "親B")
            let child1 = Person(name: "子A", isSelf: true)
            let child2 = Person(name: "共通の子B")
            try insert([parent1, parent2, child1, child2], into: container.mainContext)
            RelationshipManager.setSpouse(parent1, parent2)
            RelationshipManager.addParentChild(parent: parent1, child: child1)
            RelationshipManager.addParentChild(parent: parent2, child: child1)
            RelationshipManager.addParentChild(parent: parent1, child: child2)
            RelationshipManager.addParentChild(parent: parent2, child: child2)
            try container.mainContext.save()
        }

        let reopened = try ModelContainer(
            for: Person.self,
            Gathering.self,
            configurations: configuration
        )
        let people = try reopened.mainContext.fetch(FetchDescriptor<Person>())
        let parent1 = try XCTUnwrap(people.first { $0.name == "親A" })
        let parent2 = try XCTUnwrap(people.first { $0.name == "親B" })
        let child1 = try XCTUnwrap(people.first { $0.name == "子A" })
        let child2 = try XCTUnwrap(people.first { $0.name == "共通の子B" })

        XCTAssertEqual(Set(child1.parents.map(\.name)), Set(["親A", "親B"]))
        XCTAssertEqual(Set(child2.parents.map(\.name)), Set(["親A", "親B"]))
        XCTAssertEqual(Set(parent1.children.map(\.name)), Set(["子A", "共通の子B"]))
        XCTAssertEqual(Set(parent2.children.map(\.name)), Set(["子A", "共通の子B"]))
        XCTAssertEqual(parent1.spouse?.name, "親B")
        XCTAssertEqual(parent2.spouse?.name, "親A")
    }

    func testPhotoDecoderReturnsNilForMissingAndCorruptedData() {
        XCTAssertNil(PersonPhotoSupport.image(from: nil))
        XCTAssertNil(PersonPhotoSupport.image(from: Data()))
        XCTAssertNil(PersonPhotoSupport.image(from: Data([0x00, 0x01, 0x02])))
    }

    func testPhotoDecoderAcceptsValidImageData() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12))
        let data = renderer.pngData { context in
            UIColor(AppTheme.ai).setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
        }

        XCTAssertNotNil(PersonPhotoSupport.image(from: data))
    }

    func testHasContactAndContactURLs() throws {
        let person = Person(name: "連絡先テスト")
        XCTAssertFalse(person.hasContact)

        person.phone = "  "
        person.email = "\n"
        XCTAssertFalse(person.hasContact)

        person.phone = "03-1234-5678"
        XCTAssertTrue(person.hasContact)
        XCTAssertEqual(
            PersonContactURL.phone(from: person.phone)?.absoluteString,
            "tel://0312345678"
        )
        XCTAssertNil(PersonContactURL.phone(from: "内線のみ"))

        person.email = "zukan@example.com"
        let emailURL = try XCTUnwrap(PersonContactURL.email(from: person.email))
        XCTAssertEqual(emailURL.scheme, "mailto")
        XCTAssertTrue(emailURL.absoluteString.contains("zukan@example.com"))
    }

    func testV3ProfileFieldsPersistAfterContainerRecreation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShinsekiCho-V3-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(
            url: directory.appendingPathComponent("v3-profile.store")
        )
        let birthday = Date(timeIntervalSince1970: 315_532_800)
        let lastMetDate = Date(timeIntervalSince1970: 1_735_689_600)

        do {
            let container = try ModelContainer(
                for: Person.self,
                Gathering.self,
                configurations: configuration
            )
            let person = Person(
                name: "図鑑 花子",
                kana: "ずかん はなこ",
                relationNote: "いとこ",
                phone: "03-1234-5678",
                email: "hanako@example.com",
                livingArea: "横浜",
                lastMetDate: lastMetDate,
                lastMetPlace: "新年会",
                postalAddress: "〒100-0001 東京都千代田区1-1",
                birthday: birthday,
                favorites: "和菓子・猫",
                dietaryNotes: "落花生アレルギー",
                memo: "次は旅行の話を聞く"
            )
            container.mainContext.insert(person)
            try container.mainContext.save()
        }

        let reopened = try ModelContainer(
            for: Person.self,
            Gathering.self,
            configurations: configuration
        )
        let person = try XCTUnwrap(
            reopened.mainContext.fetch(FetchDescriptor<Person>()).first
        )

        XCTAssertEqual(person.phone, "03-1234-5678")
        XCTAssertEqual(person.email, "hanako@example.com")
        XCTAssertEqual(person.livingArea, "横浜")
        XCTAssertEqual(person.lastMetDate, lastMetDate)
        XCTAssertEqual(person.lastMetPlace, "新年会")
        XCTAssertEqual(person.postalAddress, "〒100-0001 東京都千代田区1-1")
        XCTAssertEqual(person.birthday, birthday)
        XCTAssertEqual(person.favorites, "和菓子・猫")
        XCTAssertEqual(person.dietaryNotes, "落花生アレルギー")
        XCTAssertEqual(person.memo, "次は旅行の話を聞く")
        XCTAssertTrue(person.hasContact)
    }
}
