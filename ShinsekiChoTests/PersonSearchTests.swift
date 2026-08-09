import XCTest
import SwiftData
@testable import ShinsekiCho

@MainActor
final class PersonSearchTests: XCTestCase {
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

    private func search(
        _ persons: [Person],
        selfPerson: Person? = nil,
        query: String
    ) -> [PersonSearchResult] {
        PersonSearchEngine.search(persons: persons, selfPerson: selfPerson, query: query)
    }

    func testNamePartialMatch() {
        let target = Person(name: "佐藤 健太")
        XCTAssertEqual(search([target], query: "健太").map(\.person.name), ["佐藤 健太"])
    }

    func testKanaMatch() {
        let target = Person(name: "佐藤 健太", kana: "さとう けんた")
        let result = search([target], query: "けんた")
        XCTAssertEqual(result.first?.primaryMatchReason, .kana)
    }

    func testRelationNoteMatch() {
        let target = Person(name: "健太", relationNote: "配偶者の兄")
        let result = search([target], query: "配偶者の兄")
        XCTAssertEqual(result.first?.primaryMatchReason, .relationNote("配偶者の兄"))
    }

    func testCaseDifferenceIsIgnored() {
        let target = Person(name: "Kenta Sato")
        XCTAssertEqual(search([target], query: "kENTA").count, 1)
    }

    func testFullWidthAndHalfWidthAreEquivalent() {
        let target = Person(name: "サトウ")
        XCTAssertEqual(search([target], query: "ｻﾄｳ").count, 1)
    }

    func testHiraganaAndKatakanaAreEquivalent() {
        let target = Person(name: "佐藤", kana: "サトウ ケンタ")
        XCTAssertEqual(search([target], query: "さとう けんた").count, 1)
    }

    func testNameInternalSpaceDifferenceIsIgnored() {
        let target = Person(name: "山田 太郎")
        XCTAssertEqual(search([target], query: "山田太郎").count, 1)
    }

    func testKanaInternalSpaceDifferenceIsIgnored() {
        let target = Person(name: "健太", kana: "さとう けんた")
        XCTAssertEqual(search([target], query: "さとうけんた").count, 1)
    }

    func testLeadingTrailingAndMultipleWhitespaceAreNormalized() {
        let target = Person(name: "佐藤 健太", livingArea: "横浜")
        XCTAssertEqual(search([target], query: "  横浜   健太 \n").count, 1)
    }

    func testLivingAreaMatch() {
        let target = Person(name: "健太", livingArea: "横浜")
        XCTAssertEqual(search([target], query: "横浜").first?.primaryMatchReason, .livingArea("横浜"))
    }

    func testLastMetPlaceMatch() {
        let target = Person(name: "健太", lastMetPlace: "名古屋")
        XCTAssertEqual(
            search([target], query: "名古屋").first?.primaryMatchReason,
            .lastMetPlace("名古屋")
        )
    }

    func testMemoMatchUsesPrivateReasonInsteadOfFullText() {
        let target = Person(name: "健太", memo: "次は登山の話を聞く")
        XCTAssertEqual(search([target], query: "登山").first?.primaryMatchReason, .memo)
        XCTAssertEqual(PersonSearchMatchReason.memo.displayText, "会話メモに一致")
    }

    func testFavoritesMatch() {
        let target = Person(name: "健太", favorites: "珈琲と登山")
        XCTAssertEqual(search([target], query: "珈琲").first?.primaryMatchReason, .favorites)
    }

    func testDietaryNotesMatchUsesPrivateReason() {
        let target = Person(name: "健太", dietaryNotes: "甲殻類アレルギー")
        XCTAssertEqual(search([target], query: "甲殻類").first?.primaryMatchReason, .dietaryNotes)
        XCTAssertFalse(PersonSearchMatchReason.dietaryNotes.displayText.contains("甲殻類"))
    }

    func testGatheringTitleMatch() throws {
        let container = try makeContainer()
        let target = Person(name: "健太")
        let gathering = Gathering(title: "祖母の一周忌", place: "東京")
        try insert(people: [target], gatherings: [gathering], into: container.mainContext)
        gathering.attendees.append(target)
        try container.mainContext.save()

        XCTAssertEqual(
            search([target], query: "一周忌").first?.primaryMatchReason,
            .gatheringTitle("祖母の一周忌")
        )
    }

    func testGatheringPlaceMatch() throws {
        let container = try makeContainer()
        let target = Person(name: "健太")
        let gathering = Gathering(title: "親族会", place: "横浜")
        try insert(people: [target], gatherings: [gathering], into: container.mainContext)
        gathering.attendees.append(target)
        try container.mainContext.save()

        XCTAssertEqual(
            search([target], query: "横浜").first?.primaryMatchReason,
            .gatheringPlace("横浜")
        )
    }

    func testStructuredRelationshipLabelMatch() {
        let selfPerson = Person(name: "自分", isSelf: true)
        let parent = Person(name: "一郎")
        XCTAssertTrue(RelationshipManager.addParentChild(parent: parent, child: selfPerson))

        XCTAssertEqual(
            search([parent], selfPerson: selfPerson, query: "親").first?.primaryMatchReason,
            .structuredRelationship("親")
        )
    }

    func testBreadcrumbIntermediateRelationNoteMatch() {
        let selfPerson = Person(name: "自分", isSelf: true)
        let spouse = Person(name: "美咲", relationNote: "配偶者")
        let spouseParent = Person(name: "修一", relationNote: "義父")
        XCTAssertTrue(RelationshipManager.setSpouse(selfPerson, spouse))
        XCTAssertTrue(RelationshipManager.addParentChild(parent: spouseParent, child: spouse))

        XCTAssertEqual(
            search([spouseParent], selfPerson: selfPerson, query: "配偶者").first?.primaryMatchReason,
            .relationshipPath("配偶者")
        )
    }

    func testBreadcrumbIntermediatePersonNameMatch() {
        let selfPerson = Person(name: "自分", isSelf: true)
        let spouse = Person(name: "美咲")
        let spouseParent = Person(name: "修一", relationNote: "義父")
        XCTAssertTrue(RelationshipManager.setSpouse(selfPerson, spouse))
        XCTAssertTrue(RelationshipManager.addParentChild(parent: spouseParent, child: spouse))

        XCTAssertEqual(
            search([spouseParent], selfPerson: selfPerson, query: "美咲").first?.primaryMatchReason,
            .relationshipPath("美咲")
        )
    }

    func testSpouseSideKeywordMatchesOnlyRouteContainingSpouse() {
        let selfPerson = Person(name: "自分", isSelf: true)
        let spouse = Person(name: "美咲")
        let spouseParent = Person(name: "修一")
        let directParent = Person(name: "一郎")
        XCTAssertTrue(RelationshipManager.setSpouse(selfPerson, spouse))
        XCTAssertTrue(RelationshipManager.addParentChild(parent: spouseParent, child: spouse))
        XCTAssertTrue(RelationshipManager.addParentChild(parent: directParent, child: selfPerson))

        let results = search(
            [selfPerson, spouseParent, directParent],
            selfPerson: selfPerson,
            query: "配偶者側"
        )
        XCTAssertEqual(results.map(\.person.name), ["修一"])
        XCTAssertEqual(results.first?.primaryMatchReason, .spouseSide)
    }

    func testDirectKeywordMatchesParentOnlyRoute() {
        let selfPerson = Person(name: "自分", isSelf: true)
        let parent = Person(name: "一郎")
        XCTAssertTrue(RelationshipManager.addParentChild(parent: parent, child: selfPerson))

        XCTAssertEqual(
            search([parent], selfPerson: selfPerson, query: "直系").first?.primaryMatchReason,
            .directLine
        )
    }

    func testFatherOrMotherSideIsNotInferredFromParentArray() {
        let selfPerson = Person(name: "自分", isSelf: true)
        let parent = Person(name: "一郎")
        XCTAssertTrue(RelationshipManager.addParentChild(parent: parent, child: selfPerson))

        XCTAssertTrue(search([parent], selfPerson: selfPerson, query: "父方").isEmpty)
        XCTAssertTrue(search([parent], selfPerson: selfPerson, query: "母方").isEmpty)
    }

    func testTokensCanMatchSeparateFields() {
        let target = Person(name: "佐藤 健太", livingArea: "横浜")
        XCTAssertEqual(search([target], query: "横浜 健太").count, 1)
    }

    func testAllTokensAreRequired() {
        let target = Person(name: "佐藤 健太", livingArea: "横浜")
        XCTAssertTrue(search([target], query: "横浜 花子").isEmpty)
    }

    func testUnmatchedTokenRemovesOtherwiseMatchingResult() {
        let target = Person(name: "佐藤 健太", livingArea: "横浜")
        XCTAssertEqual(search([target], query: "健太").count, 1)
        XCTAssertTrue(search([target], query: "健太 存在しない").isEmpty)
    }

    func testNameMatchRanksAboveMemoOnlyMatch() {
        let nameMatch = Person(name: "登山")
        let memoMatch = Person(name: "健太", memo: "登山の話")
        let results = search([memoMatch, nameMatch], query: "登山")
        XCTAssertTrue(results.first?.person === nameMatch)
        XCTAssertGreaterThan(results[0].score, results[1].score)
    }

    func testExactNameRanksAboveContainsName() {
        let exact = Person(name: "健太")
        let contains = Person(name: "佐藤 健太")
        let results = search([contains, exact], query: "健太")
        XCTAssertTrue(results.first?.person === exact)
        XCTAssertGreaterThan(results[0].score, results[1].score)
    }

    func testEqualScoresUseDeterministicKanaThenNameOrder() {
        let later = Person(name: "乙", kana: "あ", memo: "共通語")
        let earlier = Person(name: "甲", kana: "か", memo: "共通語")
        let results = search([earlier, later], query: "共通語")
        XCTAssertEqual(results.map(\.person.name), ["乙", "甲"])
        XCTAssertEqual(results[0].score, results[1].score)
    }

    func testEmptyQueryPreservesInputOrder() {
        let first = Person(name: "Z")
        let second = Person(name: "A")
        let third = Person(name: "M")
        XCTAssertEqual(search([first, second, third], query: "").map(\.person.name), ["Z", "A", "M"])
    }

    func testSelfPersonNilStillSearchesDirectFields() {
        let target = Person(name: "健太", livingArea: "横浜")
        XCTAssertEqual(search([target], selfPerson: nil, query: "横浜").count, 1)
    }

    func testMultipleGatheringMatchesReturnPersonOnlyOnce() throws {
        let container = try makeContainer()
        let target = Person(name: "健太")
        let first = Gathering(title: "親族の集まり", place: "東京")
        let second = Gathering(title: "夏の集まり", place: "横浜")
        try insert(people: [target], gatherings: [first, second], into: container.mainContext)
        first.attendees.append(target)
        second.attendees.append(target)
        try container.mainContext.save()

        let results = search([target], query: "集まり")
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results.first?.person === target)
    }

    func testSearchDoesNotMutateSwiftDataObjects() throws {
        let container = try makeContainer()
        let selfPerson = Person(name: "自分", isSelf: true)
        let target = Person(
            name: "佐藤 健太",
            kana: "さとう けんた",
            relationNote: "配偶者の兄",
            livingArea: "横浜",
            memo: "登山"
        )
        let gathering = Gathering(title: "親族の集まり", place: "名古屋")
        try insert(
            people: [selfPerson, target],
            gatherings: [gathering],
            into: container.mainContext
        )
        gathering.attendees.append(target)
        try container.mainContext.save()
        let originalName = target.name
        let originalGatherings = target.gatherings.map(\.title)

        _ = search([target], selfPerson: selfPerson, query: "横浜 登山")

        XCTAssertEqual(target.name, originalName)
        XCTAssertEqual(target.gatherings.map(\.title), originalGatherings)
        XCTAssertFalse(container.mainContext.hasChanges)
    }
}
