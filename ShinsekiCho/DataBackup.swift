import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Archive schema

struct BackupArchive: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let exportedAt: Date
    let people: [BackupPerson]
    let gatherings: [BackupGathering]
    let spouseLinks: [BackupSpouseLink]
    let parentChildLinks: [BackupParentChildLink]

    init(
        formatVersion: Int = Self.currentFormatVersion,
        exportedAt: Date,
        people: [BackupPerson],
        gatherings: [BackupGathering],
        spouseLinks: [BackupSpouseLink],
        parentChildLinks: [BackupParentChildLink]
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.people = people
        self.gatherings = gatherings
        self.spouseLinks = spouseLinks
        self.parentChildLinks = parentChildLinks
    }
}

struct BackupPerson: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let kana: String
    let relationNote: String
    let isSelf: Bool
    let photoData: Data?
    let createdAt: Date
    let phone: String
    let email: String
    let livingArea: String
    let lastMetDate: Date?
    let lastMetPlace: String
    let postalAddress: String
    let birthday: Date?
    let favorites: String
    let dietaryNotes: String
    let memo: String
}

struct BackupGathering: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let date: Date
    let place: String
    let note: String
    let attendeeIDs: [String]
}

struct BackupSpouseLink: Codable, Equatable, Hashable, Sendable {
    let personA: String
    let personB: String
}

struct BackupParentChildLink: Codable, Equatable, Hashable, Sendable {
    let parent: String
    let child: String
}

// MARK: - Codec

enum BackupCodec {
    static func encode(_ archive: BackupArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dataEncodingStrategy = .base64
        encoder.dateEncodingStrategy = dateEncodingStrategy
        return try encoder.encode(archive)
    }

    static func decode(_ data: Data) throws -> BackupArchive {
        let decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .base64
        decoder.dateDecodingStrategy = dateDecodingStrategy
        return try decoder.decode(BackupArchive.self, from: data)
    }

    /// DateのDouble表現を1箇所に集約し、fractional secondsをround-tripする。
    private static var dateEncodingStrategy: JSONEncoder.DateEncodingStrategy {
        .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSince1970)
        }
    }

    private static var dateDecodingStrategy: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            return Date(timeIntervalSince1970: try container.decode(Double.self))
        }
    }
}

// MARK: - Export

@MainActor
enum BackupExporter {
    static func makeArchive(
        people: [Person],
        gatherings: [Gathering],
        exportedAt: Date = .now
    ) throws -> BackupArchive {
        let sortedPeople = people.sorted(by: personPrecedes)
        var personIDByModelID: [PersistentIdentifier: String] = [:]
        for (index, person) in sortedPeople.enumerated() {
            personIDByModelID[person.persistentModelID] = archiveID(prefix: "person", index: index)
        }

        let backupPeople = sortedPeople.compactMap { person -> BackupPerson? in
            guard let id = personIDByModelID[person.persistentModelID] else { return nil }
            return BackupPerson(
                id: id,
                name: person.name,
                kana: person.kana,
                relationNote: person.relationNote,
                isSelf: person.isSelf,
                photoData: person.photoData,
                createdAt: person.createdAt,
                phone: person.phone,
                email: person.email,
                livingArea: person.livingArea,
                lastMetDate: person.lastMetDate,
                lastMetPlace: person.lastMetPlace,
                postalAddress: person.postalAddress,
                birthday: person.birthday,
                favorites: person.favorites,
                dietaryNotes: person.dietaryNotes,
                memo: person.memo
            )
        }

        var spousePairs = Set<BackupSpouseLink>()
        for person in sortedPeople {
            guard let spouse = person.spouse,
                  let firstID = personIDByModelID[person.persistentModelID],
                  let secondID = personIDByModelID[spouse.persistentModelID]
            else { continue }
            let ordered = [firstID, secondID].sorted()
            spousePairs.insert(BackupSpouseLink(personA: ordered[0], personB: ordered[1]))
        }

        // parents/children双方の保存状態をunionし、archiveでは1 edgeだけをsource of truthにする。
        var parentChildEdges = Set<BackupParentChildLink>()
        for person in sortedPeople {
            guard let personID = personIDByModelID[person.persistentModelID] else { continue }
            for child in person.children {
                guard let childID = personIDByModelID[child.persistentModelID] else { continue }
                parentChildEdges.insert(BackupParentChildLink(parent: personID, child: childID))
            }
            for parent in person.parents {
                guard let parentID = personIDByModelID[parent.persistentModelID] else { continue }
                parentChildEdges.insert(BackupParentChildLink(parent: parentID, child: personID))
            }
        }

        let sortedGatherings = gatherings.sorted(by: gatheringPrecedes)
        let backupGatherings = sortedGatherings.enumerated().map { index, gathering in
            let attendeeIDs = Set(gathering.attendees.compactMap {
                personIDByModelID[$0.persistentModelID]
            }).sorted()
            return BackupGathering(
                id: archiveID(prefix: "gathering", index: index),
                title: gathering.title,
                date: gathering.date,
                place: gathering.place,
                note: gathering.note,
                attendeeIDs: attendeeIDs
            )
        }

        let archive = BackupArchive(
            exportedAt: exportedAt,
            people: backupPeople,
            gatherings: backupGatherings,
            spouseLinks: spousePairs.sorted {
                ($0.personA, $0.personB) < ($1.personA, $1.personB)
            },
            parentChildLinks: parentChildEdges.sorted {
                ($0.parent, $0.child) < ($1.parent, $1.child)
            }
        )
        try BackupValidator.validate(archive)
        return archive
    }

    static func encode(
        people: [Person],
        gatherings: [Gathering],
        exportedAt: Date = .now
    ) throws -> Data {
        try BackupCodec.encode(
            makeArchive(people: people, gatherings: gatherings, exportedAt: exportedAt)
        )
    }

    private static func archiveID(prefix: String, index: Int) -> String {
        String(format: "%@_%06d", prefix, index + 1)
    }

    private static func personPrecedes(_ lhs: Person, _ rhs: Person) -> Bool {
        let kana = lhs.kana.localizedStandardCompare(rhs.kana)
        if kana != .orderedSame { return kana == .orderedAscending }
        let name = lhs.name.localizedStandardCompare(rhs.name)
        if name != .orderedSame { return name == .orderedAscending }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return String(describing: lhs.persistentModelID)
            < String(describing: rhs.persistentModelID)
    }

    private static func gatheringPrecedes(_ lhs: Gathering, _ rhs: Gathering) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        let title = lhs.title.localizedStandardCompare(rhs.title)
        if title != .orderedSame { return title == .orderedAscending }
        let place = lhs.place.localizedStandardCompare(rhs.place)
        if place != .orderedSame { return place == .orderedAscending }
        return String(describing: lhs.persistentModelID)
            < String(describing: rhs.persistentModelID)
    }
}

// MARK: - Validation

enum BackupValidationError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case emptyIdentifier
    case duplicatePersonIdentifier
    case duplicateGatheringIdentifier
    case unknownReference
    case multipleSelfPeople
    case selfSpouse
    case multipleSpouses
    case duplicateSpouseLink
    case selfParentChild
    case duplicateParentChildLink
    case tooManyParents
    case ancestryCycle
    case incompatibleRelationship
    case duplicateAttendee

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion:
            "対応していないバージョンのバックアップです。"
        case .emptyIdentifier, .duplicatePersonIdentifier, .duplicateGatheringIdentifier,
             .unknownReference:
            "バックアップ内のデータ参照が壊れています。"
        case .multipleSelfPeople, .selfSpouse, .multipleSpouses, .duplicateSpouseLink,
             .selfParentChild, .duplicateParentChildLink, .tooManyParents, .ancestryCycle,
             .incompatibleRelationship:
            "バックアップ内の関係情報に矛盾があります。"
        case .duplicateAttendee:
            "バックアップ内の集まり情報に矛盾があります。"
        }
    }
}

enum BackupValidator {
    static func validate(_ archive: BackupArchive) throws {
        guard archive.formatVersion == BackupArchive.currentFormatVersion else {
            throw BackupValidationError.unsupportedVersion(archive.formatVersion)
        }

        let personIDs = archive.people.map(\.id)
        guard personIDs.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw BackupValidationError.emptyIdentifier
        }
        guard Set(personIDs).count == personIDs.count else {
            throw BackupValidationError.duplicatePersonIdentifier
        }
        guard archive.people.filter(\.isSelf).count <= 1 else {
            throw BackupValidationError.multipleSelfPeople
        }

        let gatheringIDs = archive.gatherings.map(\.id)
        guard gatheringIDs.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw BackupValidationError.emptyIdentifier
        }
        guard Set(gatheringIDs).count == gatheringIDs.count else {
            throw BackupValidationError.duplicateGatheringIdentifier
        }

        let validPersonIDs = Set(personIDs)
        var canonicalSpouses = Set<BackupSpouseLink>()
        var spouseByPerson: [String: String] = [:]
        for link in archive.spouseLinks {
            guard validPersonIDs.contains(link.personA), validPersonIDs.contains(link.personB) else {
                throw BackupValidationError.unknownReference
            }
            guard link.personA != link.personB else { throw BackupValidationError.selfSpouse }
            let pair = canonicalSpouse(link.personA, link.personB)
            guard canonicalSpouses.insert(pair).inserted else {
                throw BackupValidationError.duplicateSpouseLink
            }
            guard spouseByPerson[pair.personA] == nil, spouseByPerson[pair.personB] == nil else {
                throw BackupValidationError.multipleSpouses
            }
            spouseByPerson[pair.personA] = pair.personB
            spouseByPerson[pair.personB] = pair.personA
        }

        var edges = Set<BackupParentChildLink>()
        var parentCountByChild: [String: Int] = [:]
        var childrenByParent: [String: Set<String>] = [:]
        for link in archive.parentChildLinks {
            guard validPersonIDs.contains(link.parent), validPersonIDs.contains(link.child) else {
                throw BackupValidationError.unknownReference
            }
            guard link.parent != link.child else { throw BackupValidationError.selfParentChild }
            guard edges.insert(link).inserted else {
                throw BackupValidationError.duplicateParentChildLink
            }
            parentCountByChild[link.child, default: 0] += 1
            guard parentCountByChild[link.child, default: 0] <= 2 else {
                throw BackupValidationError.tooManyParents
            }
            childrenByParent[link.parent, default: []].insert(link.child)
        }

        guard !containsCycle(personIDs: personIDs, childrenByParent: childrenByParent) else {
            throw BackupValidationError.ancestryCycle
        }

        for spouse in canonicalSpouses {
            if edges.contains(BackupParentChildLink(parent: spouse.personA, child: spouse.personB))
                || edges.contains(BackupParentChildLink(parent: spouse.personB, child: spouse.personA)) {
                throw BackupValidationError.incompatibleRelationship
            }
            if isReachable(from: spouse.personA, to: spouse.personB, childrenByParent: childrenByParent)
                || isReachable(from: spouse.personB, to: spouse.personA, childrenByParent: childrenByParent) {
                throw BackupValidationError.incompatibleRelationship
            }
        }

        for gathering in archive.gatherings {
            guard gathering.attendeeIDs.allSatisfy(validPersonIDs.contains) else {
                throw BackupValidationError.unknownReference
            }
            guard Set(gathering.attendeeIDs).count == gathering.attendeeIDs.count else {
                throw BackupValidationError.duplicateAttendee
            }
        }
    }

    private static func canonicalSpouse(_ a: String, _ b: String) -> BackupSpouseLink {
        a < b
            ? BackupSpouseLink(personA: a, personB: b)
            : BackupSpouseLink(personA: b, personB: a)
    }

    private static func containsCycle(
        personIDs: [String],
        childrenByParent: [String: Set<String>]
    ) -> Bool {
        enum VisitState { case visiting, complete }
        var states: [String: VisitState] = [:]

        func visit(_ id: String) -> Bool {
            if states[id] == .visiting { return true }
            if states[id] == .complete { return false }
            states[id] = .visiting
            for child in childrenByParent[id, default: []] where visit(child) { return true }
            states[id] = .complete
            return false
        }

        return personIDs.contains(where: visit)
    }

    private static func isReachable(
        from start: String,
        to target: String,
        childrenByParent: [String: Set<String>]
    ) -> Bool {
        var visited = Set<String>()
        var pending = [start]
        while let current = pending.popLast() {
            guard visited.insert(current).inserted else { continue }
            for child in childrenByParent[current, default: []] {
                if child == target { return true }
                pending.append(child)
            }
        }
        return false
    }
}

// MARK: - Restore

struct BackupRestorePlan: Equatable, Sendable {
    let archive: BackupArchive

    var personCount: Int { archive.people.count }
    var gatheringCount: Int { archive.gatherings.count }
    var exportedAt: Date { archive.exportedAt }
}

enum BackupRestoreError: LocalizedError {
    case relationshipRestoreFailed

    var errorDescription: String? {
        "関係情報を復元できませんでした。現在の記録は復元前の状態に戻されました。"
    }
}

@MainActor
enum BackupRestoreService {
    static func makePlan(from data: Data) throws -> BackupRestorePlan {
        let archive = try BackupCodec.decode(data)
        try BackupValidator.validate(archive)
        return BackupRestorePlan(archive: archive)
    }

    static func restore(data: Data, in context: ModelContext) throws {
        try restore(plan: makePlan(from: data), in: context)
    }

    static func restore(plan: BackupRestorePlan, in context: ModelContext) throws {
        try restore(plan: plan, in: context, save: { try $0.save() })
    }

    static func restore(
        plan: BackupRestorePlan,
        in context: ModelContext,
        save: (ModelContext) throws -> Void
    ) throws {
        // UI preview後にデータが変わっていても、mutation直前にarchiveを再検証する。
        try BackupValidator.validate(plan.archive)

        try RelationshipTransaction.perform(in: context, save: save) {
            let oldGatherings = try context.fetch(FetchDescriptor<Gathering>())
            let oldPeople = try context.fetch(FetchDescriptor<Person>())
            for gathering in oldGatherings { context.delete(gathering) }
            for person in oldPeople { RelationshipManager.delete(person, from: context) }

            var peopleByID: [String: Person] = [:]
            for backup in plan.archive.people {
                let person = Person(
                    name: backup.name,
                    kana: backup.kana,
                    relationNote: backup.relationNote,
                    isSelf: backup.isSelf,
                    photoData: backup.photoData,
                    phone: backup.phone,
                    email: backup.email,
                    livingArea: backup.livingArea,
                    lastMetDate: backup.lastMetDate,
                    lastMetPlace: backup.lastMetPlace,
                    postalAddress: backup.postalAddress,
                    birthday: backup.birthday,
                    favorites: backup.favorites,
                    dietaryNotes: backup.dietaryNotes,
                    memo: backup.memo
                )
                person.createdAt = backup.createdAt
                context.insert(person)
                peopleByID[backup.id] = person
            }

            var gatheringsByID: [String: Gathering] = [:]
            for backup in plan.archive.gatherings {
                let gathering = Gathering(
                    title: backup.title,
                    date: backup.date,
                    place: backup.place,
                    note: backup.note
                )
                context.insert(gathering)
                gatheringsByID[backup.id] = gathering
            }

            for link in plan.archive.spouseLinks {
                guard let a = peopleByID[link.personA],
                      let b = peopleByID[link.personB],
                      RelationshipManager.setSpouse(a, b)
                else { throw BackupRestoreError.relationshipRestoreFailed }
            }
            for link in plan.archive.parentChildLinks {
                guard let parent = peopleByID[link.parent],
                      let child = peopleByID[link.child],
                      RelationshipManager.addParentChild(parent: parent, child: child)
                else { throw BackupRestoreError.relationshipRestoreFailed }
            }
            for backup in plan.archive.gatherings {
                guard let gathering = gatheringsByID[backup.id] else {
                    throw BackupRestoreError.relationshipRestoreFailed
                }
                for attendeeID in backup.attendeeIDs {
                    guard let person = peopleByID[attendeeID] else {
                        throw BackupRestoreError.relationshipRestoreFailed
                    }
                    gathering.attendees.append(person)
                }
            }
        }
    }
}

// MARK: - File document

struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
