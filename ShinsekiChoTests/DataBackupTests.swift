import XCTest
import SwiftData
@testable import ShinsekiCho

@MainActor
final class DataBackupTests: XCTestCase {
    private enum ForcedSaveFailure: Error { case failed }

    private let fixedDate = Date(timeIntervalSince1970: 1_782_345_678.125)

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Person.self,
            Gathering.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func person(
        _ id: String,
        name: String? = nil,
        isSelf: Bool = false,
        photoData: Data? = nil,
        createdAt: Date? = nil,
        lastMetDate: Date? = nil,
        birthday: Date? = nil
    ) -> BackupPerson {
        BackupPerson(
            id: id,
            name: name ?? id,
            kana: "かな\(id)",
            relationNote: "続柄\(id)",
            isSelf: isSelf,
            photoData: photoData,
            createdAt: createdAt ?? fixedDate,
            phone: "090-\(id)",
            email: "\(id)@example.com",
            livingArea: "東京",
            lastMetDate: lastMetDate,
            lastMetPlace: "実家",
            postalAddress: "東京都千代田区",
            birthday: birthday,
            favorites: "和菓子",
            dietaryNotes: "甲殻類",
            memo: "会話メモ"
        )
    }

    private func archive(
        version: Int = 1,
        people: [BackupPerson] = [],
        gatherings: [BackupGathering] = [],
        spouses: [BackupSpouseLink] = [],
        edges: [BackupParentChildLink] = []
    ) -> BackupArchive {
        BackupArchive(
            formatVersion: version,
            exportedAt: fixedDate,
            people: people,
            gatherings: gatherings,
            spouseLinks: spouses,
            parentChildLinks: edges
        )
    }

    private func gathering(
        _ id: String,
        attendees: [String] = []
    ) -> BackupGathering {
        BackupGathering(
            id: id,
            title: "お盆の帰省",
            date: fixedDate,
            place: "実家",
            note: "手土産を持参",
            attendeeIDs: attendees
        )
    }

    private func insert(_ people: [Person], into context: ModelContext) throws {
        people.forEach(context.insert)
        try context.save()
    }

    private func restore(_ archive: BackupArchive, in context: ModelContext) throws {
        try BackupRestoreService.restore(
            plan: BackupRestorePlan(archive: archive),
            in: context
        )
    }

    private func fetchedPeople(_ context: ModelContext) throws -> [Person] {
        try context.fetch(FetchDescriptor<Person>())
    }

    private func fetchedGatherings(_ context: ModelContext) throws -> [Gathering] {
        try context.fetch(FetchDescriptor<Gathering>())
    }

    private func assertValidationError(
        _ expected: BackupValidationError,
        archive: BackupArchive,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try BackupValidator.validate(archive), file: file, line: line) {
            XCTAssertEqual($0 as? BackupValidationError, expected, file: file, line: line)
        }
    }

    // MARK: Schema and codec

    func test01CurrentFormatVersionIsOne() {
        XCTAssertEqual(BackupArchive.currentFormatVersion, 1)
    }

    func test02CodecRoundTripsEmptyArchive() throws {
        let original = archive()
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(original)), original)
    }

    func test03CodecRoundTripsFractionalDates() throws {
        let original = archive(people: [person("p", createdAt: fixedDate, lastMetDate: fixedDate, birthday: fixedDate)])
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(original)), original)
    }

    func test04CodecRoundTripsPhotoBytesLosslessly() throws {
        let bytes = Data((0...255).map(UInt8.init))
        let decoded = try BackupCodec.decode(BackupCodec.encode(archive(people: [person("p", photoData: bytes)])))
        XCTAssertEqual(decoded.people.first?.photoData, bytes)
    }

    func test05CodecRoundTripsNilOptionalValues() throws {
        let original = archive(people: [person("p", photoData: nil, lastMetDate: nil, birthday: nil)])
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(original)), original)
    }

    func test06PlanReportsCountsAndDate() {
        let plan = BackupRestorePlan(archive: archive(
            people: [person("p")],
            gatherings: [gathering("g")]
        ))
        XCTAssertEqual(plan.personCount, 1)
        XCTAssertEqual(plan.gatheringCount, 1)
        XCTAssertEqual(plan.exportedAt, fixedDate)
    }

    // MARK: Export

    func test07ExporterIncludesEveryPersonScalarField() throws {
        let container = try makeContainer()
        let model = Person(
            name: "山田 太郎", kana: "やまだ たろう", relationNote: "自分", isSelf: true,
            photoData: Data([1, 2, 3]), phone: "090", email: "t@example.com",
            livingArea: "東京", lastMetDate: fixedDate, lastMetPlace: "実家",
            postalAddress: "東京都", birthday: fixedDate, favorites: "猫",
            dietaryNotes: "なし", memo: "メモ"
        )
        model.createdAt = fixedDate
        try insert([model], into: container.mainContext)

        let value = try XCTUnwrap(BackupExporter.makeArchive(people: [model], gatherings: []).people.first)
        XCTAssertEqual(value.name, model.name)
        XCTAssertEqual(value.kana, model.kana)
        XCTAssertEqual(value.relationNote, model.relationNote)
        XCTAssertEqual(value.isSelf, model.isSelf)
        XCTAssertEqual(value.photoData, model.photoData)
        XCTAssertEqual(value.createdAt, model.createdAt)
        XCTAssertEqual(value.phone, model.phone)
        XCTAssertEqual(value.email, model.email)
        XCTAssertEqual(value.livingArea, model.livingArea)
        XCTAssertEqual(value.lastMetDate, model.lastMetDate)
        XCTAssertEqual(value.lastMetPlace, model.lastMetPlace)
        XCTAssertEqual(value.postalAddress, model.postalAddress)
        XCTAssertEqual(value.birthday, model.birthday)
        XCTAssertEqual(value.favorites, model.favorites)
        XCTAssertEqual(value.dietaryNotes, model.dietaryNotes)
        XCTAssertEqual(value.memo, model.memo)
    }

    func test08ExporterUsesArchiveLocalIdentifiers() throws {
        let container = try makeContainer()
        let a = Person(name: "A")
        let b = Person(name: "B")
        try insert([a, b], into: container.mainContext)
        let result = try BackupExporter.makeArchive(people: [a, b], gatherings: [])
        XCTAssertEqual(Set(result.people.map(\.id)), ["person_000001", "person_000002"])
        XCTAssertFalse(result.people.map(\.id).contains(String(describing: a.persistentModelID)))
    }

    func test09ExporterWritesOneCanonicalSpouseLink() throws {
        let container = try makeContainer()
        let a = Person(name: "A")
        let b = Person(name: "B")
        try insert([a, b], into: container.mainContext)
        XCTAssertTrue(RelationshipManager.setSpouse(a, b))
        XCTAssertEqual(try BackupExporter.makeArchive(people: [b, a], gatherings: []).spouseLinks.count, 1)
    }

    func test10ExporterWritesOneParentChildEdge() throws {
        let container = try makeContainer()
        let parent = Person(name: "親")
        let child = Person(name: "子")
        try insert([parent, child], into: container.mainContext)
        XCTAssertTrue(RelationshipManager.addParentChild(parent: parent, child: child))
        XCTAssertEqual(try BackupExporter.makeArchive(people: [parent, child], gatherings: []).parentChildLinks.count, 1)
    }

    func test11ExporterIncludesGatheringFields() throws {
        let container = try makeContainer()
        let event = Gathering(title: "法事", date: fixedDate, place: "実家", note: "メモ")
        container.mainContext.insert(event)
        try container.mainContext.save()
        let value = try XCTUnwrap(BackupExporter.makeArchive(people: [], gatherings: [event]).gatherings.first)
        XCTAssertEqual(value.title, "法事")
        XCTAssertEqual(value.date, fixedDate)
        XCTAssertEqual(value.place, "実家")
        XCTAssertEqual(value.note, "メモ")
    }

    func test12ExporterIncludesGatheringAttendeesWithoutDuplicates() throws {
        let container = try makeContainer()
        let attendee = Person(name: "参加者")
        let event = Gathering(title: "法事", date: fixedDate)
        container.mainContext.insert(attendee)
        container.mainContext.insert(event)
        event.attendees = [attendee, attendee]
        try container.mainContext.save()
        let result = try BackupExporter.makeArchive(people: [attendee], gatherings: [event])
        XCTAssertEqual(result.gatherings.first?.attendeeIDs.count, 1)
    }

    func test13ExporterDoesNotMutateOrSaveContext() throws {
        let container = try makeContainer()
        let model = Person(name: "未保存")
        container.mainContext.insert(model)
        _ = try BackupExporter.makeArchive(people: [model], gatherings: [])
        XCTAssertTrue(container.mainContext.hasChanges)
    }

    func test14ExporterProducesDeterministicOrdering() throws {
        let container = try makeContainer()
        let b = Person(name: "B", kana: "びー")
        let a = Person(name: "A", kana: "えー")
        try insert([b, a], into: container.mainContext)
        let first = try BackupExporter.encode(people: [b, a], gatherings: [], exportedAt: fixedDate)
        let second = try BackupExporter.encode(people: [a, b], gatherings: [], exportedAt: fixedDate)
        XCTAssertEqual(first, second)
    }

    // MARK: Validation

    func test15ValidatorAcceptsEmptyArchive() throws {
        XCTAssertNoThrow(try BackupValidator.validate(archive()))
    }

    func test16ValidatorRejectsUnsupportedVersion() {
        assertValidationError(.unsupportedVersion(2), archive: archive(version: 2))
    }

    func test17ValidatorRejectsEmptyPersonID() {
        assertValidationError(.emptyIdentifier, archive: archive(people: [person(" ")]))
    }

    func test18ValidatorRejectsDuplicatePersonID() {
        assertValidationError(.duplicatePersonIdentifier, archive: archive(people: [person("p"), person("p")]))
    }

    func test19ValidatorRejectsEmptyGatheringID() {
        assertValidationError(.emptyIdentifier, archive: archive(gatherings: [gathering("")]))
    }

    func test20ValidatorRejectsDuplicateGatheringID() {
        assertValidationError(.duplicateGatheringIdentifier, archive: archive(gatherings: [gathering("g"), gathering("g")]))
    }

    func test21ValidatorRejectsMultipleSelfPeople() {
        assertValidationError(.multipleSelfPeople, archive: archive(people: [person("a", isSelf: true), person("b", isSelf: true)]))
    }

    func test22ValidatorAllowsNoSelfPerson() throws {
        XCTAssertNoThrow(try BackupValidator.validate(archive(people: [person("a"), person("b")])))
    }

    func test23ValidatorRejectsUnknownSpouseReference() {
        assertValidationError(.unknownReference, archive: archive(people: [person("a")], spouses: [.init(personA: "a", personB: "missing")]))
    }

    func test24ValidatorRejectsSelfSpouse() {
        assertValidationError(.selfSpouse, archive: archive(people: [person("a")], spouses: [.init(personA: "a", personB: "a")]))
    }

    func test25ValidatorRejectsDuplicateSpouseLinkInReverseOrder() {
        assertValidationError(.duplicateSpouseLink, archive: archive(
            people: [person("a"), person("b")],
            spouses: [.init(personA: "a", personB: "b"), .init(personA: "b", personB: "a")]
        ))
    }

    func test26ValidatorRejectsMultipleSpouses() {
        assertValidationError(.multipleSpouses, archive: archive(
            people: [person("a"), person("b"), person("c")],
            spouses: [.init(personA: "a", personB: "b"), .init(personA: "a", personB: "c")]
        ))
    }

    func test27ValidatorRejectsUnknownParentReference() {
        assertValidationError(.unknownReference, archive: archive(people: [person("c")], edges: [.init(parent: "missing", child: "c")]))
    }

    func test28ValidatorRejectsUnknownChildReference() {
        assertValidationError(.unknownReference, archive: archive(people: [person("p")], edges: [.init(parent: "p", child: "missing")]))
    }

    func test29ValidatorRejectsSelfParentChild() {
        assertValidationError(.selfParentChild, archive: archive(people: [person("p")], edges: [.init(parent: "p", child: "p")]))
    }

    func test30ValidatorRejectsDuplicateParentChildEdge() {
        assertValidationError(.duplicateParentChildLink, archive: archive(
            people: [person("p"), person("c")],
            edges: [.init(parent: "p", child: "c"), .init(parent: "p", child: "c")]
        ))
    }

    func test31ValidatorRejectsMoreThanTwoParents() {
        assertValidationError(.tooManyParents, archive: archive(
            people: [person("p1"), person("p2"), person("p3"), person("c")],
            edges: [.init(parent: "p1", child: "c"), .init(parent: "p2", child: "c"), .init(parent: "p3", child: "c")]
        ))
    }

    func test32ValidatorRejectsDirectAncestryCycle() {
        assertValidationError(.ancestryCycle, archive: archive(
            people: [person("a"), person("b")],
            edges: [.init(parent: "a", child: "b"), .init(parent: "b", child: "a")]
        ))
    }

    func test33ValidatorRejectsMultiGenerationAncestryCycle() {
        assertValidationError(.ancestryCycle, archive: archive(
            people: [person("a"), person("b"), person("c")],
            edges: [.init(parent: "a", child: "b"), .init(parent: "b", child: "c"), .init(parent: "c", child: "a")]
        ))
    }

    func test34ValidatorRejectsDirectParentAsSpouse() {
        assertValidationError(.incompatibleRelationship, archive: archive(
            people: [person("a"), person("b")],
            spouses: [.init(personA: "a", personB: "b")],
            edges: [.init(parent: "a", child: "b")]
        ))
    }

    func test35ValidatorRejectsAncestorAsSpouse() {
        assertValidationError(.incompatibleRelationship, archive: archive(
            people: [person("a"), person("b"), person("c")],
            spouses: [.init(personA: "a", personB: "c")],
            edges: [.init(parent: "a", child: "b"), .init(parent: "b", child: "c")]
        ))
    }

    func test36ValidatorRejectsUnknownAttendeeReference() {
        assertValidationError(.unknownReference, archive: archive(gatherings: [gathering("g", attendees: ["missing"])]))
    }

    func test37ValidatorRejectsDuplicateAttendee() {
        assertValidationError(.duplicateAttendee, archive: archive(
            people: [person("p")], gatherings: [gathering("g", attendees: ["p", "p"])]
        ))
    }

    // MARK: Successful restore

    func test38RestoreCreatesAllPersonFields() throws {
        let container = try makeContainer()
        let backup = person("p", isSelf: true, photoData: Data([9]), createdAt: fixedDate, lastMetDate: fixedDate, birthday: fixedDate)
        try restore(archive(people: [backup]), in: container.mainContext)
        let value = try XCTUnwrap(fetchedPeople(container.mainContext).first)
        XCTAssertEqual(value.name, backup.name)
        XCTAssertEqual(value.kana, backup.kana)
        XCTAssertEqual(value.relationNote, backup.relationNote)
        XCTAssertEqual(value.isSelf, backup.isSelf)
        XCTAssertEqual(value.photoData, backup.photoData)
        XCTAssertEqual(value.createdAt, backup.createdAt)
        XCTAssertEqual(value.phone, backup.phone)
        XCTAssertEqual(value.email, backup.email)
        XCTAssertEqual(value.livingArea, backup.livingArea)
        XCTAssertEqual(value.lastMetDate, backup.lastMetDate)
        XCTAssertEqual(value.lastMetPlace, backup.lastMetPlace)
        XCTAssertEqual(value.postalAddress, backup.postalAddress)
        XCTAssertEqual(value.birthday, backup.birthday)
        XCTAssertEqual(value.favorites, backup.favorites)
        XCTAssertEqual(value.dietaryNotes, backup.dietaryNotes)
        XCTAssertEqual(value.memo, backup.memo)
    }

    func test39RestoreCreatesBidirectionalSpouseLink() throws {
        let container = try makeContainer()
        try restore(archive(
            people: [person("a"), person("b")],
            spouses: [.init(personA: "a", personB: "b")]
        ), in: container.mainContext)
        let values = try fetchedPeople(container.mainContext)
        let a = try XCTUnwrap(values.first { $0.name == "a" })
        let b = try XCTUnwrap(values.first { $0.name == "b" })
        XCTAssertEqual(a.spouse?.persistentModelID, b.persistentModelID)
        XCTAssertEqual(b.spouse?.persistentModelID, a.persistentModelID)
    }

    func test40RestoreCreatesBidirectionalParentChildLink() throws {
        let container = try makeContainer()
        try restore(archive(
            people: [person("p"), person("c")],
            edges: [.init(parent: "p", child: "c")]
        ), in: container.mainContext)
        let values = try fetchedPeople(container.mainContext)
        let parent = try XCTUnwrap(values.first { $0.name == "p" })
        let child = try XCTUnwrap(values.first { $0.name == "c" })
        XCTAssertEqual(parent.children.first?.persistentModelID, child.persistentModelID)
        XCTAssertEqual(child.parents.first?.persistentModelID, parent.persistentModelID)
    }

    func test41RestoreSupportsTwoParents() throws {
        let container = try makeContainer()
        try restore(archive(
            people: [person("a"), person("b"), person("c")],
            edges: [.init(parent: "a", child: "c"), .init(parent: "b", child: "c")]
        ), in: container.mainContext)
        let child = try XCTUnwrap(fetchedPeople(container.mainContext).first { $0.name == "c" })
        XCTAssertEqual(Set(child.parents.map(\.name)), ["a", "b"])
    }

    func test42RestoreSupportsMultipleGenerations() throws {
        let container = try makeContainer()
        try restore(archive(
            people: [person("g"), person("p"), person("c")],
            edges: [.init(parent: "g", child: "p"), .init(parent: "p", child: "c")]
        ), in: container.mainContext)
        let values = try fetchedPeople(container.mainContext)
        XCTAssertEqual(values.first { $0.name == "g" }?.children.first?.name, "p")
        XCTAssertEqual(values.first { $0.name == "p" }?.children.first?.name, "c")
    }

    func test43RestoreCreatesGatheringAndAttendees() throws {
        let container = try makeContainer()
        try restore(archive(
            people: [person("a"), person("b")],
            gatherings: [gathering("g", attendees: ["a", "b"])]
        ), in: container.mainContext)
        let event = try XCTUnwrap(fetchedGatherings(container.mainContext).first)
        XCTAssertEqual(event.title, "お盆の帰省")
        XCTAssertEqual(event.date, fixedDate)
        XCTAssertEqual(event.place, "実家")
        XCTAssertEqual(event.note, "手土産を持参")
        XCTAssertEqual(Set(event.attendees.map(\.name)), ["a", "b"])
    }

    func test44RestoreSupportsMultipleGatherings() throws {
        let container = try makeContainer()
        try restore(archive(gatherings: [gathering("g1"), gathering("g2")]), in: container.mainContext)
        XCTAssertEqual(try fetchedGatherings(container.mainContext).count, 2)
    }

    func test45RestoreSupportsEmptyArchive() throws {
        let container = try makeContainer()
        let old = Person(name: "旧")
        try insert([old], into: container.mainContext)
        try restore(archive(), in: container.mainContext)
        XCTAssertTrue(try fetchedPeople(container.mainContext).isEmpty)
        XCTAssertTrue(try fetchedGatherings(container.mainContext).isEmpty)
    }

    func test46ExportRestoreRoundTripPreservesGraphAndGathering() throws {
        let source = try makeContainer()
        let a = Person(name: "A", isSelf: true, photoData: Data([1, 2]))
        let b = Person(name: "B")
        let c = Person(name: "C")
        let event = Gathering(title: "集まり", date: fixedDate, place: "東京", note: "メモ")
        [a, b, c].forEach(source.mainContext.insert)
        source.mainContext.insert(event)
        XCTAssertTrue(RelationshipManager.setSpouse(a, b))
        XCTAssertTrue(RelationshipManager.addParentChild(parent: a, child: c))
        XCTAssertTrue(RelationshipManager.addParentChild(parent: b, child: c))
        event.attendees = [a, c]
        try source.mainContext.save()
        let data = try BackupExporter.encode(people: [a, b, c], gatherings: [event], exportedAt: fixedDate)

        let destination = try makeContainer()
        try BackupRestoreService.restore(data: data, in: destination.mainContext)
        let people = try fetchedPeople(destination.mainContext)
        let restoredA = try XCTUnwrap(people.first { $0.name == "A" })
        let restoredB = try XCTUnwrap(people.first { $0.name == "B" })
        let restoredC = try XCTUnwrap(people.first { $0.name == "C" })
        XCTAssertTrue(restoredA.isSelf)
        XCTAssertEqual(restoredA.photoData, Data([1, 2]))
        XCTAssertEqual(restoredA.spouse?.persistentModelID, restoredB.persistentModelID)
        XCTAssertEqual(Set(restoredC.parents.map(\.name)), ["A", "B"])
        XCTAssertEqual(Set(try fetchedGatherings(destination.mainContext).first?.attendees.map(\.name) ?? []), ["A", "C"])
    }

    // MARK: Replace-all and rollback

    func test47RestoreReplacesExistingPeople() throws {
        let container = try makeContainer()
        try insert([Person(name: "旧人物")], into: container.mainContext)
        try restore(archive(people: [person("new", name: "新人物")]), in: container.mainContext)
        XCTAssertEqual(try fetchedPeople(container.mainContext).map(\.name), ["新人物"])
    }

    func test48RestoreReplacesExistingGatherings() throws {
        let container = try makeContainer()
        let old = Gathering(title: "旧集まり", date: fixedDate)
        container.mainContext.insert(old)
        try container.mainContext.save()
        try restore(archive(gatherings: [gathering("new")]), in: container.mainContext)
        XCTAssertEqual(try fetchedGatherings(container.mainContext).map(\.title), ["お盆の帰省"])
    }

    func test49DecodeFailureDoesNotMutateExistingData() throws {
        let container = try makeContainer()
        try insert([Person(name: "保持")], into: container.mainContext)
        XCTAssertThrowsError(try BackupRestoreService.restore(data: Data("not-json".utf8), in: container.mainContext))
        XCTAssertEqual(try fetchedPeople(container.mainContext).map(\.name), ["保持"])
    }

    func test50ValidationFailureDoesNotMutateExistingData() throws {
        let container = try makeContainer()
        try insert([Person(name: "保持")], into: container.mainContext)
        let invalid = archive(version: 99, people: [person("new")])
        XCTAssertThrowsError(try BackupRestoreService.restore(
            plan: BackupRestorePlan(archive: invalid), in: container.mainContext
        ))
        XCTAssertEqual(try fetchedPeople(container.mainContext).map(\.name), ["保持"])
    }

    func test51SaveFailureRollsBackExistingPeople() throws {
        let container = try makeContainer()
        try insert([Person(name: "保持")], into: container.mainContext)
        let plan = BackupRestorePlan(archive: archive(people: [person("new", name: "新規")]))
        XCTAssertThrowsError(try BackupRestoreService.restore(plan: plan, in: container.mainContext) { _ in
            throw ForcedSaveFailure.failed
        })
        XCTAssertEqual(try fetchedPeople(container.mainContext).map(\.name), ["保持"])
    }

    func test52SaveFailureRollsBackExistingRelationships() throws {
        let container = try makeContainer()
        let a = Person(name: "A")
        let b = Person(name: "B")
        try insert([a, b], into: container.mainContext)
        XCTAssertTrue(RelationshipManager.setSpouse(a, b))
        try container.mainContext.save()
        let plan = BackupRestorePlan(archive: archive(people: [person("new")]))
        XCTAssertThrowsError(try BackupRestoreService.restore(plan: plan, in: container.mainContext) { _ in
            throw ForcedSaveFailure.failed
        })
        let values = try fetchedPeople(container.mainContext)
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(values.first { $0.name == "A" }?.spouse?.name, "B")
        XCTAssertEqual(values.first { $0.name == "B" }?.spouse?.name, "A")
    }

    func test53SaveFailureRollsBackExistingGatheringsAndAttendees() throws {
        let container = try makeContainer()
        let attendee = Person(name: "参加者")
        let event = Gathering(title: "保持する集まり", date: fixedDate)
        container.mainContext.insert(attendee)
        container.mainContext.insert(event)
        event.attendees = [attendee]
        try container.mainContext.save()
        let plan = BackupRestorePlan(archive: archive())
        XCTAssertThrowsError(try BackupRestoreService.restore(plan: plan, in: container.mainContext) { _ in
            throw ForcedSaveFailure.failed
        })
        XCTAssertEqual(try fetchedPeople(container.mainContext).map(\.name), ["参加者"])
        let restoredEvent = try XCTUnwrap(fetchedGatherings(container.mainContext).first)
        XCTAssertEqual(restoredEvent.title, "保持する集まり")
        XCTAssertEqual(restoredEvent.attendees.first?.name, "参加者")
    }

    func test54SaveFailureRemovesImportedPeopleFromContext() throws {
        let container = try makeContainer()
        let plan = BackupRestorePlan(archive: archive(people: [person("new", name: "一時人物")]))
        XCTAssertThrowsError(try BackupRestoreService.restore(plan: plan, in: container.mainContext) { _ in
            throw ForcedSaveFailure.failed
        })
        XCTAssertTrue(try fetchedPeople(container.mainContext).isEmpty)
    }

    func test55SaveFailureRemovesImportedGatheringsFromContext() throws {
        let container = try makeContainer()
        let plan = BackupRestorePlan(archive: archive(gatherings: [gathering("new")]))
        XCTAssertThrowsError(try BackupRestoreService.restore(plan: plan, in: container.mainContext) { _ in
            throw ForcedSaveFailure.failed
        })
        XCTAssertTrue(try fetchedGatherings(container.mainContext).isEmpty)
    }

    func test56SuccessfulRestoreLeavesContextWithoutUnsavedChanges() throws {
        let container = try makeContainer()
        try restore(archive(people: [person("p")]), in: container.mainContext)
        XCTAssertFalse(container.mainContext.hasChanges)
    }
}
