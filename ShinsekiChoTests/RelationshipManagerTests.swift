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

    func testSetSpouseReflectsBothDirectionsAndClearsOldSpouses() throws {
        let container = try makeContainer()
        let a = Person(name: "A")
        let oldA = Person(name: "Aの旧配偶者")
        let b = Person(name: "B")
        let oldB = Person(name: "Bの旧配偶者")
        try insert([a, oldA, b, oldB], into: container.mainContext)
        RelationshipManager.setSpouse(a, oldA)
        RelationshipManager.setSpouse(b, oldB)

        RelationshipManager.setSpouse(a, b)

        XCTAssertEqual(a.spouse?.persistentModelID, b.persistentModelID)
        XCTAssertEqual(b.spouse?.persistentModelID, a.persistentModelID)
        XCTAssertNil(oldA.spouse)
        XCTAssertNil(oldB.spouse)
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
