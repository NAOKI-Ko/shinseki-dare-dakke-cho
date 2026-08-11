import SwiftData
import UIKit
import XCTest

@testable import ShinsekiCho

@MainActor
final class PerformanceFixtureTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Person.self,
            Gathering.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    func testFixtureSizesAndPhotoCounts() throws {
        for size in PerformanceFixtureSize.allCases {
            let container = try makeContainer()
            let fixture = try PerformanceFixtureBuilder.build(size, in: container.mainContext)
            XCTAssertEqual(fixture.people.count, size.personCount)
            XCTAssertEqual(fixture.gatherings.count, size.gatheringCount)
            XCTAssertEqual(fixture.people.filter { $0.photoData != nil }.count, size.photoCount)
            XCTAssertEqual(fixture.people.filter(\.isSelf).count, 1)
        }
    }

    func testRelationshipsAreBidirectionalAndWithinLimits() throws {
        let container = try makeContainer()
        let fixture = try PerformanceFixtureBuilder.build(.stress, in: container.mainContext)
        for person in fixture.people {
            XCTAssertLessThanOrEqual(person.parents.count, 2)
            if let spouse = person.spouse {
                XCTAssertTrue(spouse.spouse === person)
                XCTAssertFalse(RelationshipManager.isAncestor(person, of: spouse))
                XCTAssertFalse(RelationshipManager.isAncestor(spouse, of: person))
            }
            for parent in person.parents {
                XCTAssertTrue(parent.children.contains { $0 === person })
            }
            for child in person.children {
                XCTAssertTrue(child.parents.contains { $0 === person })
            }
        }
        XCTAssertFalse(hasAncestryCycle(in: fixture.people))
    }

    func testFixtureIsDeterministic() throws {
        let firstContainer = try makeContainer()
        let secondContainer = try makeContainer()
        let first = try PerformanceFixtureBuilder.build(.stress, in: firstContainer.mainContext)
        let second = try PerformanceFixtureBuilder.build(.stress, in: secondContainer.mainContext)
        XCTAssertEqual(
            PerformanceFixtureBuilder.deterministicSignature(of: first),
            PerformanceFixtureBuilder.deterministicSignature(of: second)
        )
        XCTAssertEqual(first.gatherings.map(\.title), second.gatherings.map(\.title))
        XCTAssertEqual(first.gatherings.map { $0.attendees.map(\.name).sorted() },
                       second.gatherings.map { $0.attendees.map(\.name).sorted() })
    }

    func testSearchRemainsResponsiveAtAllFixtureSizes() throws {
        let queries = ["健太", "横浜", "配偶者側", "法事", "登山", "横浜 健太"]
        for size in PerformanceFixtureSize.allCases {
            let container = try makeContainer()
            let fixture = try PerformanceFixtureBuilder.build(size, in: container.mainContext)
            let start = ContinuousClock.now
            for query in queries {
                XCTAssertFalse(
                    PersonSearchEngine.search(
                        persons: fixture.people,
                        selfPerson: fixture.selfPerson,
                        query: query
                    ).isEmpty,
                    "\(size.rawValue): \(query)"
                )
            }
            let elapsed = start.duration(to: .now)
            print("PERF search \(size.rawValue) \(elapsed)")
        }
    }

    func testStressBackupRoundTripPreservesCountsRelationshipsAndPhotos() throws {
        for size in PerformanceFixtureSize.allCases {
            let sourceContainer = try makeContainer()
            let source = try PerformanceFixtureBuilder.build(size, in: sourceContainer.mainContext)
            let exportStart = ContinuousClock.now
            let data = try BackupExporter.encode(
                people: source.people,
                gatherings: source.gatherings,
                exportedAt: Date(timeIntervalSince1970: 1_767_225_600)
            )
            let exportElapsed = exportStart.duration(to: .now)

            let restoredContainer = try makeContainer()
            let restoreStart = ContinuousClock.now
            try BackupRestoreService.restore(data: data, in: restoredContainer.mainContext)
            let restoreElapsed = restoreStart.duration(to: .now)
            let restoredPeople = try restoredContainer.mainContext.fetch(FetchDescriptor<Person>())
            let restoredGatherings = try restoredContainer.mainContext.fetch(FetchDescriptor<Gathering>())

            XCTAssertEqual(restoredPeople.count, size.personCount)
            XCTAssertEqual(restoredGatherings.count, size.gatheringCount)
            XCTAssertEqual(restoredPeople.filter { $0.photoData != nil }.count, size.photoCount)
            XCTAssertEqual(restoredPeople.filter(\.isSelf).count, 1)
            XCTAssertEqual(parentChildEdgeCount(restoredPeople), parentChildEdgeCount(source.people))
            XCTAssertEqual(spouseEdgeCount(restoredPeople), spouseEdgeCount(source.people))
            print(
                "PERF backup \(size.rawValue) bytes \(data.count) "
                    + "export \(exportElapsed) restore \(restoreElapsed)"
            )
        }
    }

    func testStressGraphSnapshotCullingAndPhotoCache() throws {
        let container = try makeContainer()
        let fixture = try PerformanceFixtureBuilder.build(.stress, in: container.mainContext)
        let store = FamilyGraphStore()
        let graphStart = ContinuousClock.now
        store.reset(with: fixture.selfPerson)
        var expanded = Set<PersistentModelIDBox>()
        while expanded.count < store.nodes.count {
            let pending = store.nodes.values.filter { !expanded.contains($0.id) }
            if pending.isEmpty { break }
            for node in pending {
                expanded.insert(node.id)
                store.expand(node.person)
            }
        }

        XCTAssertEqual(store.nodes.count, 100)
        XCTAssertEqual(store.renderSnapshot.nodes.count, 100)
        XCTAssertGreaterThan(
            store.renderSnapshot.edges.count
                + store.renderSnapshot.coupleRenderModel.segments.count,
            0
        )
        XCTAssertFalse(store.renderSnapshot.coupleRenderModel.knots.isEmpty)
        XCTAssertEqual(
            store.renderSnapshot.knotsByID.count,
            store.renderSnapshot.coupleRenderModel.knots.count
        )

        let viewport = CGSize(width: 393, height: 852)
        let origin = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let visibleCount = store.renderSnapshot.nodes.filter { item in
            let center = CGPoint(
                x: origin.x + CGFloat(item.node.slot) * 108,
                y: origin.y + CGFloat(item.node.level) * 120
            )
            return GraphViewportCulling.isNodeVisible(
                center: center,
                radius: 96,
                viewportSize: viewport
            )
        }.count
        XCTAssertGreaterThan(visibleCount, 0)
        XCTAssertLessThan(visibleCount, 100)

        var decodeCount = 0
        let cache = FamilyGraphPhotoCache { data, _ in
            decodeCount += 1
            return UIImage(data: data)
        }
        let photographed = fixture.people.filter { $0.photoData != nil }
        for _ in 0..<5 {
            for person in photographed {
                XCTAssertNotNil(cache.image(
                    for: PersistentModelIDBox(person.persistentModelID),
                    photoData: person.photoData
                ))
            }
        }
        XCTAssertEqual(decodeCount, 50)
        let graphElapsed = graphStart.duration(to: .now)
        print(
            "PERF graph nodes 100 visible \(visibleCount) "
                + "photoDecodes \(decodeCount) build \(graphElapsed)"
        )
    }

    func testStressRelationshipCandidatesAndDuplicateMerge() throws {
        let container = try makeContainer()
        let fixture = try PerformanceFixtureBuilder.build(.stress, in: container.mainContext)
        let candidateStart = ContinuousClock.now
        let candidateCount = fixture.people.dropFirst().reduce(into: 0) { count, candidate in
            if RelationshipManager.canLink(
                .spouse,
                person: fixture.selfPerson,
                relative: candidate
            ) { count += 1 }
            if RelationshipManager.canLink(
                .parent,
                person: fixture.selfPerson,
                relative: candidate
            ) { count += 1 }
            if RelationshipManager.canLink(
                .child,
                person: fixture.selfPerson,
                relative: candidate
            ) { count += 1 }
        }
        let candidateElapsed = candidateStart.duration(to: .now)
        XCTAssertGreaterThan(candidateCount, 0)

        let duplicate = Person(name: fixture.selfPerson.name, kana: fixture.selfPerson.kana)
        container.mainContext.insert(duplicate)
        try container.mainContext.save()
        XCTAssertTrue(PersonDuplicateDetector.isCandidate(duplicate, for: fixture.selfPerson))
        let mergeStart = ContinuousClock.now
        let plan = PersonMergePlan.make(survivor: fixture.selfPerson, duplicate: duplicate)
        XCTAssertTrue(plan.structuralIssues.isEmpty)
        try PersonMergeService.merge(plan: plan, choices: [:], in: container.mainContext)
        let mergeElapsed = mergeStart.duration(to: .now)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Person>()), 100)
        print(
            "PERF relation candidates \(candidateElapsed) merge \(mergeElapsed)"
        )
    }

    private func parentChildEdgeCount(_ people: [Person]) -> Int {
        Set(people.flatMap { parent in
            parent.children.map { "\(parent.name)->\($0.name)" }
        }).count
    }

    private func spouseEdgeCount(_ people: [Person]) -> Int {
        Set(people.compactMap { person -> String? in
            guard let spouse = person.spouse else { return nil }
            return [person.name, spouse.name].sorted().joined(separator: "<->")
        }).count
    }

    private func hasAncestryCycle(in people: [Person]) -> Bool {
        func visit(_ person: Person, path: Set<PersistentIdentifier>) -> Bool {
            let id = person.persistentModelID
            if path.contains(id) { return true }
            let nextPath = path.union([id])
            return person.children.contains { visit($0, path: nextPath) }
        }
        return people.contains { visit($0, path: []) }
    }
}
