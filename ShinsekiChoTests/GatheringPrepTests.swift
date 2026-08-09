import XCTest
import SwiftData
@testable import ShinsekiCho

@MainActor
final class GatheringPrepTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Person.self,
            Gathering.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func insert(
        people: [Person],
        gatherings: [Gathering] = [],
        into context: ModelContext
    ) throws {
        people.forEach(context.insert)
        gatherings.forEach(context.insert)
        try context.save()
    }

    func testEmptyAttendeesProducesNoReviewTargets() {
        XCTAssertEqual(GatheringPrepBuilder.make(attendees: []).count, 0)
    }

    func testSelfOnlyProducesNoReviewTargets() {
        let selfPerson = Person(name: "自分", isSelf: true)
        XCTAssertEqual(GatheringPrepBuilder.make(attendees: [selfPerson]).count, 0)
    }

    func testSelfIsExcludedFromMixedAttendees() {
        let selfPerson = Person(name: "自分", isSelf: true)
        let relative = Person(name: "親戚")
        let session = GatheringPrepBuilder.make(attendees: [relative, selfPerson])
        XCTAssertEqual(session.count, 1)
        XCTAssertEqual(session.currentPerson?.name, "親戚")
    }

    func testThreePeopleSortByKanaThenNameDeterministically() {
        let hana = Person(name: "花子", kana: "やまだ はなこ")
        let kenta = Person(name: "健太", kana: "さとう けんた")
        let shuichi = Person(name: "修一", kana: "さとう しゅういち")
        let session = GatheringPrepBuilder.make(attendees: [hana, shuichi, kenta])
        XCTAssertEqual(session.entries.map(\.person.name), ["健太", "修一", "花子"])
    }

    func testEmptyKanaUsesNameForStableTieBreaking() {
        let beta = Person(name: "いちろう")
        let alpha = Person(name: "あきら")
        let kanaPerson = Person(name: "健太", kana: "さとう けんた")
        let session = GatheringPrepBuilder.make(attendees: [beta, kanaPerson, alpha])
        XCTAssertEqual(session.entries.map(\.person.name), ["あきら", "いちろう", "健太"])
    }

    func testEqualKanaAndNameFallsBackToCreationOrder() {
        let older = Person(name: "同名", kana: "どうめい")
        let newer = Person(name: "同名", kana: "どうめい")
        older.createdAt = Date(timeIntervalSince1970: 10)
        newer.createdAt = Date(timeIntervalSince1970: 20)
        let session = GatheringPrepBuilder.make(attendees: [newer, older])
        XCTAssertTrue(session.entries.first?.person === older)
    }

    func testInitialIndexIsZero() {
        let session = GatheringPrepBuilder.make(attendees: [Person(name: "人")])
        XCTAssertEqual(session.currentIndex, 0)
    }

    func testFirstEntryCannotGoPrevious() {
        let session = GatheringPrepBuilder.make(attendees: [Person(name: "人")])
        XCTAssertFalse(session.canGoPrevious)
    }

    func testMiddleEntryCanGoPreviousAndNext() {
        var session = GatheringPrepBuilder.make(attendees: [
            Person(name: "A"), Person(name: "B"), Person(name: "C")
        ])
        session.moveNext()
        XCTAssertTrue(session.canGoPrevious)
        XCTAssertTrue(session.canGoNext)
    }

    func testLastEntryCannotGoNext() {
        var session = GatheringPrepBuilder.make(attendees: [Person(name: "A"), Person(name: "B")])
        session.moveNext()
        XCTAssertFalse(session.canGoNext)
    }

    func testProgressTextUsesOneBasedIndex() {
        let session = GatheringPrepBuilder.make(attendees: [
            Person(name: "A"), Person(name: "B"), Person(name: "C")
        ])
        XCTAssertEqual(session.progressText, "1 / 3")
    }

    func testNextIncrementsIndex() {
        var session = GatheringPrepBuilder.make(attendees: [Person(name: "A"), Person(name: "B")])
        session.moveNext()
        XCTAssertEqual(session.currentIndex, 1)
    }

    func testPreviousDecrementsIndex() {
        var session = GatheringPrepBuilder.make(attendees: [Person(name: "A"), Person(name: "B")])
        session.moveNext()
        session.movePrevious()
        XCTAssertEqual(session.currentIndex, 0)
    }

    func testNavigationNeverExceedsBounds() {
        var session = GatheringPrepBuilder.make(attendees: [Person(name: "A"), Person(name: "B")])
        session.movePrevious()
        XCTAssertEqual(session.currentIndex, 0)
        session.moveNext()
        session.moveNext()
        XCTAssertEqual(session.currentIndex, 1)
    }

    func testInitializerClampsIndexToBounds() {
        let entry = GatheringPrepEntry(person: Person(name: "A"))
        XCTAssertEqual(GatheringPrepSession(entries: [entry], currentIndex: -2).currentIndex, 0)
        XCTAssertEqual(GatheringPrepSession(entries: [entry], currentIndex: 5).currentIndex, 0)
    }

    func testDisconnectedPersonUsesMemorySummaryFallback() throws {
        let container = try makeContainer()
        let selfPerson = Person(name: "自分", isSelf: true)
        let target = Person(name: "未接続")
        try insert(people: [selfPerson, target], into: container.mainContext)

        let summary = PersonMemorySummaryBuilder.make(selfPerson: selfPerson, target: target)
        XCTAssertEqual(summary.relationship.status, .disconnected)
        XCTAssertEqual(summary.relationship.breadcrumb, "自分とのつながりはまだ登録されていません")
    }

    func testRelationshipSummaryReusesExistingRouteLogic() throws {
        let container = try makeContainer()
        let selfPerson = Person(name: "自分", isSelf: true)
        let spouse = Person(name: "美咲", relationNote: "配偶者")
        try insert(people: [selfPerson, spouse], into: container.mainContext)
        XCTAssertTrue(RelationshipManager.setSpouse(selfPerson, spouse))

        let summary = PersonMemorySummaryBuilder.make(selfPerson: selfPerson, target: spouse)
        XCTAssertEqual(summary.relationship.breadcrumb, "自分 → 配偶者（美咲）")
        XCTAssertEqual(summary.relationship.structuredLabel, "配偶者")
    }

    func testCurrentGatheringIsExcludedFromLatestGathering() throws {
        let container = try makeContainer()
        let person = Person(name: "人")
        let current = Gathering(title: "今回", date: Date(timeIntervalSince1970: 300))
        try insert(people: [person], gatherings: [current], into: container.mainContext)
        current.attendees.append(person)
        try container.mainContext.save()

        let summary = PersonMemorySummaryBuilder.make(
            selfPerson: person,
            target: person,
            excludingGathering: current,
            latestGatheringBefore: current.date
        )
        XCTAssertNil(summary.latestGathering)
    }

    func testLatestGatheringBeforeCurrentIsSelected() throws {
        let container = try makeContainer()
        let person = Person(name: "人")
        let old = Gathering(title: "新年会", date: Date(timeIntervalSince1970: 100))
        let recent = Gathering(title: "帰省", date: Date(timeIntervalSince1970: 200))
        let current = Gathering(title: "法事", date: Date(timeIntervalSince1970: 300))
        try insert(people: [person], gatherings: [old, recent, current], into: container.mainContext)
        [old, recent, current].forEach { $0.attendees.append(person) }
        try container.mainContext.save()

        let summary = PersonMemorySummaryBuilder.make(
            selfPerson: person,
            target: person,
            excludingGathering: current,
            latestGatheringBefore: current.date
        )
        XCTAssertEqual(summary.latestGathering?.title, "帰省")
    }

    func testFutureOtherGatheringIsNotRecentForPrep() throws {
        let container = try makeContainer()
        let person = Person(name: "人")
        let prior = Gathering(title: "過去", date: Date(timeIntervalSince1970: 100))
        let current = Gathering(title: "今回", date: Date(timeIntervalSince1970: 200))
        let future = Gathering(title: "未来", date: Date(timeIntervalSince1970: 400))
        try insert(people: [person], gatherings: [prior, current, future], into: container.mainContext)
        [prior, current, future].forEach { $0.attendees.append(person) }
        try container.mainContext.save()

        let summary = PersonMemorySummaryBuilder.make(
            selfPerson: person,
            target: person,
            excludingGathering: current,
            latestGatheringBefore: current.date
        )
        XCTAssertEqual(summary.latestGathering?.title, "過去")
    }

    func testLastMetRemainsIndependentFromGatherings() throws {
        let container = try makeContainer()
        let lastMet = Date(timeIntervalSince1970: 50)
        let person = Person(name: "人", lastMetDate: lastMet, lastMetPlace: "実家")
        let current = Gathering(title: "未来の予定", date: Date(timeIntervalSince1970: 300))
        try insert(people: [person], gatherings: [current], into: container.mainContext)
        current.attendees.append(person)
        try container.mainContext.save()

        let summary = PersonMemorySummaryBuilder.make(
            selfPerson: person,
            target: person,
            excludingGathering: current,
            latestGatheringBefore: current.date
        )
        XCTAssertEqual(summary.lastMet?.date, lastMet)
        XCTAssertEqual(summary.lastMet?.place, "実家")
    }

    func testSessionNavigationDoesNotMutatePersonOrGathering() throws {
        let container = try makeContainer()
        let first = Person(name: "A", memo: "保存済み")
        let second = Person(name: "B")
        let gathering = Gathering(title: "集まり", date: Date(timeIntervalSince1970: 300))
        try insert(people: [first, second], gatherings: [gathering], into: container.mainContext)
        gathering.attendees.append(contentsOf: [first, second])
        try container.mainContext.save()
        let originalNames = gathering.attendees.map(\.name).sorted()
        let originalDate = gathering.date
        let originalMemo = first.memo

        var session = GatheringPrepBuilder.make(gathering: gathering)
        session.moveNext()
        session.movePrevious()

        XCTAssertEqual(gathering.attendees.map(\.name).sorted(), originalNames)
        XCTAssertEqual(gathering.date, originalDate)
        XCTAssertEqual(first.memo, originalMemo)
        XCTAssertFalse(container.mainContext.hasChanges)
    }
}
