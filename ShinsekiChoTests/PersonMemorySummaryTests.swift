import XCTest
import SwiftData
@testable import ShinsekiCho

@MainActor
final class PersonMemorySummaryTests: XCTestCase {
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

    private func linkParent(_ parent: Person, _ child: Person) {
        XCTAssertTrue(RelationshipManager.addParentChild(parent: parent, child: child))
    }

    func testSelfBreadcrumbIsOnlySelf() throws {
        let container = try makeContainer()
        let selfPerson = Person(name: "自分", relationNote: "自分", isSelf: true)
        try insert([selfPerson], into: container.mainContext)

        let summary = PersonMemorySummaryBuilder.make(selfPerson: selfPerson, target: selfPerson)
        XCTAssertEqual(summary.relationship.breadcrumb, "自分")
        XCTAssertNil(summary.relationship.structuredLabel)
    }

    func testDirectParentBreadcrumbAndStructuredLabel() throws {
        let container = try makeContainer()
        let selfPerson = Person(name: "自分", isSelf: true)
        let parent = Person(name: "一郎", relationNote: "父")
        try insert([selfPerson, parent], into: container.mainContext)
        linkParent(parent, selfPerson)

        let summary = PersonMemorySummaryBuilder.make(selfPerson: selfPerson, target: parent)
        XCTAssertEqual(summary.relationship.breadcrumb, "自分 → 父（一郎）")
        XCTAssertEqual(summary.relationship.structuredLabel, "親")
    }

    func testDirectSpouseBreadcrumbAndStructuredLabel() throws {
        let container = try makeContainer()
        let selfPerson = Person(name: "自分", isSelf: true)
        let spouse = Person(name: "美咲", relationNote: "配偶者")
        try insert([selfPerson, spouse], into: container.mainContext)
        XCTAssertTrue(RelationshipManager.setSpouse(selfPerson, spouse))

        let summary = PersonMemorySummaryBuilder.make(selfPerson: selfPerson, target: spouse)
        XCTAssertEqual(summary.relationship.breadcrumb, "自分 → 配偶者（美咲）")
        XCTAssertEqual(summary.relationship.structuredLabel, "配偶者")
    }

    func testDirectChildBreadcrumbAndStructuredLabel() throws {
        let container = try makeContainer()
        let selfPerson = Person(name: "自分", isSelf: true)
        let child = Person(name: "葵", relationNote: "長女")
        try insert([selfPerson, child], into: container.mainContext)
        linkParent(selfPerson, child)

        let summary = PersonMemorySummaryBuilder.make(selfPerson: selfPerson, target: child)
        XCTAssertEqual(summary.relationship.breadcrumb, "自分 → 長女（葵）")
        XCTAssertEqual(summary.relationship.structuredLabel, "子")
    }

    func testTwoHopGrandparentUsesIntermediateNote() throws {
        let container = try makeContainer()
        let selfPerson = Person(name: "自分", isSelf: true)
        let parent = Person(name: "一郎", relationNote: "父")
        let grandparent = Person(name: "源治", relationNote: "父方の祖父")
        try insert([selfPerson, parent, grandparent], into: container.mainContext)
        linkParent(parent, selfPerson)
        linkParent(grandparent, parent)

        let summary = PersonMemorySummaryBuilder.make(selfPerson: selfPerson, target: grandparent)
        XCTAssertEqual(summary.relationship.breadcrumb, "自分 → 父 → 父方の祖父（源治）")
        XCTAssertEqual(summary.relationship.structuredLabel, "祖父母")
    }

    func testThreeHopBreadcrumbKeepsEveryIntermediatePerson() throws {
        let container = try makeContainer()
        let selfPerson = Person(name: "自分", isSelf: true)
        let parent = Person(name: "一郎", relationNote: "父")
        let grandparent = Person(name: "源治", relationNote: "祖父")
        let aunt = Person(name: "千代", relationNote: "父の妹")
        try insert([selfPerson, parent, grandparent, aunt], into: container.mainContext)
        linkParent(parent, selfPerson)
        linkParent(grandparent, parent)
        linkParent(grandparent, aunt)

        let summary = PersonMemorySummaryBuilder.make(selfPerson: selfPerson, target: aunt)
        XCTAssertEqual(summary.relationship.breadcrumb, "自分 → 父 → 祖父 → 父の妹（千代）")
        XCTAssertEqual(summary.relationship.structuredLabel, "おじ・おば")
    }

    func testSpouseSideBreadcrumbUsesStoredNotes() throws {
        let container = try makeContainer()
        let selfPerson = Person(name: "自分", isSelf: true)
        let spouse = Person(name: "美咲", relationNote: "配偶者")
        let spouseParent = Person(name: "修一", relationNote: "配偶者の父")
        try insert([selfPerson, spouse, spouseParent], into: container.mainContext)
        XCTAssertTrue(RelationshipManager.setSpouse(selfPerson, spouse))
        linkParent(spouseParent, spouse)

        let summary = PersonMemorySummaryBuilder.make(selfPerson: selfPerson, target: spouseParent)
        XCTAssertEqual(summary.relationship.breadcrumb, "自分 → 配偶者 → 配偶者の父（修一）")
        XCTAssertNil(summary.relationship.structuredLabel)
    }

    func testIntermediateFallsBackToNameWhenRelationNoteIsEmpty() throws {
        let container = try makeContainer()
        let selfPerson = Person(name: "自分", isSelf: true)
        let parent = Person(name: "一郎")
        let grandparent = Person(name: "源治", relationNote: "祖父")
        try insert([selfPerson, parent, grandparent], into: container.mainContext)
        linkParent(parent, selfPerson)
        linkParent(grandparent, parent)

        XCTAssertEqual(
            PersonMemorySummaryBuilder.make(selfPerson: selfPerson, target: grandparent)
                .relationship.breadcrumb,
            "自分 → 一郎 → 祖父（源治）"
        )
    }

    func testIntermediateWhitespaceNoteFallsBackToName() throws {
        let container = try makeContainer()
        let selfPerson = Person(name: "自分", isSelf: true)
        let parent = Person(name: "一郎", relationNote: "  \n")
        let grandparent = Person(name: "源治")
        try insert([selfPerson, parent, grandparent], into: container.mainContext)
        linkParent(parent, selfPerson)
        linkParent(grandparent, parent)

        XCTAssertEqual(
            PersonMemorySummaryBuilder.make(selfPerson: selfPerson, target: grandparent)
                .relationship.breadcrumb,
            "自分 → 一郎 → 源治"
        )
    }

    func testTargetWithRelationNoteIncludesNoteAndName() throws {
        let container = try makeContainer()
        let selfPerson = Person(name: "自分", isSelf: true)
        let target = Person(name: "健太", relationNote: "配偶者の兄")
        try insert([selfPerson, target], into: container.mainContext)
        linkParent(selfPerson, target)

        XCTAssertEqual(
            PersonMemorySummaryBuilder.make(selfPerson: selfPerson, target: target)
                .relationship.breadcrumb,
            "自分 → 配偶者の兄（健太）"
        )
    }

    func testTargetWithoutRelationNoteUsesNameOnly() throws {
        let container = try makeContainer()
        let selfPerson = Person(name: "自分", isSelf: true)
        let target = Person(name: "健太")
        try insert([selfPerson, target], into: container.mainContext)
        linkParent(selfPerson, target)

        XCTAssertEqual(
            PersonMemorySummaryBuilder.make(selfPerson: selfPerson, target: target)
                .relationship.breadcrumb,
            "自分 → 健太"
        )
    }

    func testDisconnectedPersonHasExplicitFallback() throws {
        let container = try makeContainer()
        let selfPerson = Person(name: "自分", isSelf: true)
        let target = Person(name: "未接続")
        try insert([selfPerson, target], into: container.mainContext)

        let relationship = PersonMemorySummaryBuilder.make(
            selfPerson: selfPerson,
            target: target
        ).relationship
        XCTAssertEqual(relationship.status, .disconnected)
        XCTAssertEqual(relationship.breadcrumb, "自分とのつながりはまだ登録されていません")
        XCTAssertNil(relationship.structuredLabel)
    }

    func testMissingSelfPersonHasExplicitFallback() throws {
        let container = try makeContainer()
        let target = Person(name: "未接続")
        try insert([target], into: container.mainContext)

        XCTAssertEqual(
            PersonMemorySummaryBuilder.make(selfPerson: nil, target: target)
                .relationship.status,
            .disconnected
        )
    }

    func testUnsupportedRouteDoesNotInventStructuredLabel() throws {
        let container = try makeContainer()
        let selfPerson = Person(name: "自分", isSelf: true)
        let spouse = Person(name: "美咲", relationNote: "配偶者")
        let spouseParent = Person(name: "修一", relationNote: "配偶者の父")
        try insert([selfPerson, spouse, spouseParent], into: container.mainContext)
        XCTAssertTrue(RelationshipManager.setSpouse(selfPerson, spouse))
        linkParent(spouseParent, spouse)

        XCTAssertNil(
            PersonMemorySummaryBuilder.make(selfPerson: selfPerson, target: spouseParent)
                .relationship.structuredLabel
        )
    }

    func testLastMetKeepsDateAndTrimmedPlaceTogether() throws {
        let container = try makeContainer()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let person = Person(name: "人", lastMetDate: date, lastMetPlace: "  名古屋  ")
        try insert([person], into: container.mainContext)

        let lastMet = PersonMemorySummaryBuilder.make(selfPerson: person, target: person).lastMet
        XCTAssertEqual(lastMet?.date, date)
        XCTAssertEqual(lastMet?.place, "名古屋")
    }

    func testLastMetDateWithoutPlaceRemainsVisible() throws {
        let container = try makeContainer()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let person = Person(name: "人", lastMetDate: date, lastMetPlace: " \n ")
        try insert([person], into: container.mainContext)

        let lastMet = PersonMemorySummaryBuilder.make(selfPerson: person, target: person).lastMet
        XCTAssertEqual(lastMet?.date, date)
        XCTAssertNil(lastMet?.place)
    }

    func testPlaceWithoutLastMetDateIsNotPresentedAsLastMet() throws {
        let container = try makeContainer()
        let person = Person(name: "人", lastMetPlace: "名古屋")
        try insert([person], into: container.mainContext)

        XCTAssertNil(PersonMemorySummaryBuilder.make(selfPerson: person, target: person).lastMet)
    }

    func testLivingAreaMemoAndFavoritesNormalizeEmptyValues() throws {
        let container = try makeContainer()
        let person = Person(
            name: "人",
            livingArea: "  横浜 ",
            favorites: "  珈琲と登山  ",
            memo: "  次は山の話を聞く  "
        )
        try insert([person], into: container.mainContext)

        let summary = PersonMemorySummaryBuilder.make(selfPerson: person, target: person)
        XCTAssertEqual(summary.livingArea, "横浜")
        XCTAssertEqual(summary.memo, "次は山の話を聞く")
        XCTAssertEqual(summary.favorites, "珈琲と登山")

        person.livingArea = " "
        person.memo = "\n"
        person.favorites = ""
        let emptySummary = PersonMemorySummaryBuilder.make(selfPerson: person, target: person)
        XCTAssertNil(emptySummary.livingArea)
        XCTAssertNil(emptySummary.memo)
        XCTAssertNil(emptySummary.favorites)
    }

    func testLatestGatheringUsesMostRecentDate() throws {
        let container = try makeContainer()
        let person = Person(name: "人")
        let older = Gathering(title: "古い集まり", date: Date(timeIntervalSince1970: 100))
        let latest = Gathering(title: "新しい集まり", date: Date(timeIntervalSince1970: 300))
        let middle = Gathering(title: "中間の集まり", date: Date(timeIntervalSince1970: 200))
        try insert([person], into: container.mainContext)
        [older, latest, middle].forEach(container.mainContext.insert)
        person.gatherings.append(contentsOf: [older, latest, middle])
        try container.mainContext.save()

        let recall = PersonMemorySummaryBuilder.make(selfPerson: person, target: person)
            .latestGathering
        XCTAssertEqual(recall?.title, "新しい集まり")
        XCTAssertEqual(recall?.date, latest.date)
    }

    func testLatestGatheringNeverBecomesLastMet() throws {
        let container = try makeContainer()
        let person = Person(name: "人", lastMetDate: nil, lastMetPlace: "")
        let gathering = Gathering(title: "お盆", date: Date(timeIntervalSince1970: 300))
        try insert([person], into: container.mainContext)
        container.mainContext.insert(gathering)
        person.gatherings.append(gathering)
        try container.mainContext.save()

        let summary = PersonMemorySummaryBuilder.make(selfPerson: person, target: person)
        XCTAssertNil(summary.lastMet)
        XCTAssertEqual(summary.latestGathering?.title, "お盆")
    }

    func testSummaryRecalculatesAfterRelationshipIsAdded() throws {
        let container = try makeContainer()
        let selfPerson = Person(name: "自分", isSelf: true)
        let target = Person(name: "美咲", relationNote: "配偶者")
        try insert([selfPerson, target], into: container.mainContext)
        XCTAssertEqual(
            PersonMemorySummaryBuilder.make(selfPerson: selfPerson, target: target)
                .relationship.status,
            .disconnected
        )

        XCTAssertTrue(RelationshipManager.setSpouse(selfPerson, target))
        XCTAssertEqual(
            PersonMemorySummaryBuilder.make(selfPerson: selfPerson, target: target)
                .relationship.breadcrumb,
            "自分 → 配偶者（美咲）"
        )
    }
}
