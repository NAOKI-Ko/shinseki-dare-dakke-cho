import SwiftData
import XCTest

@testable import ShinsekiCho

@MainActor
final class FamilyGraphLayoutUniverseTests: XCTestCase {
  func testRootOnlyGraphProducesReadyUniverseWithRootPosition() throws {
    let fixture = try makePeople(["Self"])
    let universe = try readyUniverse(from: fixture.people["Self"]!)

    XCTAssertEqual(universe.input.visiblePersonIDs, [id(fixture.people["Self"]!)])
    XCTAssertNotNil(universe.result.positionsByPersonID[id(fixture.people["Self"]!)])
  }

  func testParentsAreDiscoveredAndPositionedBeforeAnyReveal() throws {
    let fixture = try makePeople(["Self", "P1", "P2"])
    linkParent(fixture.people["P1"]!, to: fixture.people["Self"]!)
    linkParent(fixture.people["P2"]!, to: fixture.people["Self"]!)

    let universe = try readyUniverse(from: fixture.people["Self"]!)

    XCTAssertEqual(universe.result.positionsByPersonID.count, 3)
    XCTAssertEqual(universe.result.positionsByPersonID[id(fixture.people["P1"]!)]?.generation, -1)
    XCTAssertEqual(universe.result.positionsByPersonID[id(fixture.people["P2"]!)]?.generation, -1)
  }

  func testGrandparentsAreAllDiscovered() throws {
    let fixture = try canonicalGrandparents()
    let topology = FamilyGraphLayoutUniverseBuilder.discover(from: fixture.people["Self"]!)

    XCTAssertEqual(topology.personIDs, Set(fixture.people.values.map(id)))
    XCTAssertEqual(topology.parentChildEdges.count, 6)
    XCTAssertEqual(topology.spouseEdges.count, 3)
  }

  func testChildrenAreTraversed() throws {
    let fixture = try makePeople(["Self", "Child", "Grandchild"])
    linkParent(fixture.people["Self"]!, to: fixture.people["Child"]!)
    linkParent(fixture.people["Child"]!, to: fixture.people["Grandchild"]!)

    let universe = try readyUniverse(from: fixture.people["Self"]!)

    XCTAssertEqual(universe.result.positionsByPersonID.count, 3)
    XCTAssertEqual(
      universe.result.positionsByPersonID[id(fixture.people["Grandchild"]!)]?.generation,
      2
    )
  }

  func testSpouseIsTraversed() throws {
    let fixture = try makePeople(["Self", "Spouse"])
    linkSpouses(fixture.people["Self"]!, fixture.people["Spouse"]!)

    let topology = FamilyGraphLayoutUniverseBuilder.discover(from: fixture.people["Self"]!)

    XCTAssertEqual(topology.personIDs.count, 2)
    XCTAssertEqual(topology.spouseEdges.count, 1)
  }

  func testParentChildBackReferencesDoNotLoop() throws {
    let fixture = try makePeople(["Self", "Parent"])
    linkParent(fixture.people["Parent"]!, to: fixture.people["Self"]!)

    let topology = FamilyGraphLayoutUniverseBuilder.discover(from: fixture.people["Self"]!)

    XCTAssertEqual(topology.personIDs.count, 2)
    XCTAssertEqual(topology.parentChildEdges.count, 1)
  }

  func testBidirectionalSpouseCycleDoesNotDuplicatePersonOrEdge() throws {
    let fixture = try makePeople(["Self", "Spouse"])
    linkSpouses(fixture.people["Self"]!, fixture.people["Spouse"]!)

    let topology = FamilyGraphLayoutUniverseBuilder.discover(from: fixture.people["Self"]!)

    XCTAssertEqual(topology.personIDs.count, 2)
    XCTAssertEqual(topology.spouseEdges.count, 1)
  }

  func testDuplicateParentChildTraversalProducesOneEdge() throws {
    let fixture = try makePeople(["Self", "Parent"])
    let root = fixture.people["Self"]!
    let parent = fixture.people["Parent"]!
    root.parents = [parent, parent]
    parent.children = [root, root]

    let topology = FamilyGraphLayoutUniverseBuilder.discover(from: root)

    XCTAssertEqual(topology.parentChildEdges.count, 1)
  }

  func testUnreachableComponentIsExcluded() throws {
    let fixture = try makePeople(["Self", "Parent", "OtherA", "OtherB"])
    linkParent(fixture.people["Parent"]!, to: fixture.people["Self"]!)
    linkSpouses(fixture.people["OtherA"]!, fixture.people["OtherB"]!)

    let topology = FamilyGraphLayoutUniverseBuilder.discover(from: fixture.people["Self"]!)

    XCTAssertEqual(topology.personIDs.count, 2)
    XCTAssertFalse(topology.personIDs.contains(id(fixture.people["OtherA"]!)))
    XCTAssertFalse(topology.personIDs.contains(id(fixture.people["OtherB"]!)))
  }

  func testCanonicalGrandparentsHaveAtomicNoninterleavedBranches() throws {
    let fixture = try canonicalGrandparents()
    let result = try readyUniverse(from: fixture.people["Self"]!).result

    XCTAssertEqual(result.positionsByPersonID.count, 7)
    XCTAssertEqual(result.parentChildCrossingCount, 0)
    assertCouple("PGF", "PGM", people: fixture.people, result: result)
    assertCouple("MGF", "MGM", people: fixture.people, result: result)
    assertBranchesDoNotInterleave(people: fixture.people, result: result)
  }

  func testSixPersonCounterexampleKeepsPaternalCoupleAtomic() throws {
    let fixture = try makePeople(["Self", "Father", "Mother", "PGF", "PGM", "MG"])
    linkSpouses(fixture.people["Father"]!, fixture.people["Mother"]!)
    linkSpouses(fixture.people["PGF"]!, fixture.people["PGM"]!)
    linkParent(fixture.people["Father"]!, to: fixture.people["Self"]!)
    linkParent(fixture.people["Mother"]!, to: fixture.people["Self"]!)
    linkParent(fixture.people["PGF"]!, to: fixture.people["Father"]!)
    linkParent(fixture.people["PGM"]!, to: fixture.people["Father"]!)
    linkParent(fixture.people["MG"]!, to: fixture.people["Mother"]!)

    let result = try readyUniverse(from: fixture.people["Self"]!).result
    let pgfX = result.positionsByPersonID[id(fixture.people["PGF"]!)]!.x
    let pgmX = result.positionsByPersonID[id(fixture.people["PGM"]!)]!.x
    let maternalX = result.positionsByPersonID[id(fixture.people["MG"]!)]!.x

    XCTAssertEqual(result.parentChildCrossingCount, 0)
    XCTAssertEqual(abs(pgfX - pgmX), 1, accuracy: 0.000_001)
    XCTAssertFalse(maternalX > min(pgfX, pgmX) && maternalX < max(pgfX, pgmX))
  }

  func testLateDiscoveryEquivalentTopologyIsAlreadyComplete() throws {
    let fixture = try canonicalGrandparents()
    let universe = try readyUniverse(from: fixture.people["Self"]!)

    for name in ["PGF", "PGM", "MGF", "MGM"] {
      XCTAssertNotNil(universe.result.positionsByPersonID[id(fixture.people[name]!)])
    }
  }

  func testSpouseSideRelativeIsReachable() throws {
    let fixture = try makePeople(["Self", "Spouse", "SpouseParent"])
    linkSpouses(fixture.people["Self"]!, fixture.people["Spouse"]!)
    linkParent(fixture.people["SpouseParent"]!, to: fixture.people["Spouse"]!)

    let universe = try readyUniverse(from: fixture.people["Self"]!)

    XCTAssertNotNil(universe.result.positionsByPersonID[id(fixture.people["SpouseParent"]!)])
  }

  func testUncleIsReachableThroughSharedGrandparents() throws {
    let fixture = try makePeople(["Self", "Parent", "Grandparent", "Uncle"])
    linkParent(fixture.people["Parent"]!, to: fixture.people["Self"]!)
    linkParent(fixture.people["Grandparent"]!, to: fixture.people["Parent"]!)
    linkParent(fixture.people["Grandparent"]!, to: fixture.people["Uncle"]!)

    let universe = try readyUniverse(from: fixture.people["Self"]!)

    XCTAssertEqual(universe.result.positionsByPersonID.count, 4)
    XCTAssertNotNil(universe.result.positionsByPersonID[id(fixture.people["Uncle"]!)])
  }

  func testFullLayoutPreservesFractionalAndNegativeCoordinates() throws {
    let fixture = try canonicalGrandparents()
    let positions = try readyUniverse(from: fixture.people["Self"]!).result.positionsByPersonID

    XCTAssertTrue(positions.values.contains { $0.x < 0 })
    XCTAssertTrue(positions.values.contains { $0.x != $0.x.rounded() })
  }

  func testGenerationContradictionReturnsInconsistentState() throws {
    let fixture = try contradictorySpouseParentGraph()

    let state = FamilyGraphLayoutUniverseBuilder.build(from: fixture.people["Self"]!)

    guard case .inconsistent(let failure) = state else {
      return XCTFail("Expected an inconsistent universe")
    }
    XCTAssertTrue(
      failure.diagnostics.contains { diagnostic in
        if case .inconsistentGeneration = diagnostic { return true }
        return false
      })
  }

  func testGenerationContradictionNeverReturnsReadyUniverse() throws {
    let fixture = try contradictorySpouseParentGraph()

    if case .ready = FamilyGraphLayoutUniverseBuilder.build(from: fixture.people["Self"]!) {
      XCTFail("A contradictory graph must not produce a ready universe")
    }
  }

  func testGraphNodeStillContainsOnlyPersonAndPath() throws {
    let fixture = try makePeople(["Self"])
    let node = GraphNode(person: fixture.people["Self"]!, path: [])

    XCTAssertEqual(Set(Mirror(reflecting: node).children.compactMap(\.label)), ["person", "path"])
  }

  func testRepeatedBuildsAreSemanticallyEquivalent() throws {
    let fixture = try canonicalGrandparents()
    let first = try readyUniverse(from: fixture.people["Self"]!).result
    let second = try readyUniverse(from: fixture.people["Self"]!).result

    XCTAssertEqual(
      first.positionsByPersonID.mapValues(\.generation),
      second.positionsByPersonID.mapValues(\.generation)
    )
    XCTAssertEqual(first.parentChildCrossingCount, second.parentChildCrossingCount)
    XCTAssertEqual(distanceMultiset(first), distanceMultiset(second))
  }

  func testRealisticFullGraphDiscoveryAndLayoutMeasurements() throws {
    for count in [100, 300, 500] {
      let fixture = try branchingFixture(personCount: count)
      let totalStart = ContinuousClock.now
      let discoveryStart = ContinuousClock.now
      let topology = FamilyGraphLayoutUniverseBuilder.discover(from: fixture.root)
      let discoveryElapsed = ContinuousClock.now - discoveryStart
      let layoutStart = ContinuousClock.now
      let result = FamilyGraphHorizontalLayout.layout(topology.input)
      let layoutElapsed = ContinuousClock.now - layoutStart
      let totalElapsed = ContinuousClock.now - totalStart

      XCTAssertEqual(topology.personIDs.count, count)
      XCTAssertEqual(result.positionsByPersonID.count, count)
      print("FamilyGraphLayoutUniverse realistic \(count) discovery: \(discoveryElapsed)")
      print("FamilyGraphLayoutUniverse realistic \(count) layout: \(layoutElapsed)")
      print("FamilyGraphLayoutUniverse realistic \(count) total: \(totalElapsed)")
    }
  }

  func testDeepChainFullGraphDiscoveryAndLayoutMeasurements() throws {
    for count in [100, 300, 500] {
      let fixture = try chainFixture(personCount: count)
      let totalStart = ContinuousClock.now
      let discoveryStart = ContinuousClock.now
      let topology = FamilyGraphLayoutUniverseBuilder.discover(from: fixture.root)
      let discoveryElapsed = ContinuousClock.now - discoveryStart
      let layoutStart = ContinuousClock.now
      let result = FamilyGraphHorizontalLayout.layout(topology.input)
      let layoutElapsed = ContinuousClock.now - layoutStart
      let totalElapsed = ContinuousClock.now - totalStart

      XCTAssertEqual(topology.personIDs.count, count)
      XCTAssertEqual(result.positionsByPersonID.count, count)
      print("FamilyGraphLayoutUniverse deep chain \(count) discovery: \(discoveryElapsed)")
      print("FamilyGraphLayoutUniverse deep chain \(count) layout: \(layoutElapsed)")
      print("FamilyGraphLayoutUniverse deep chain \(count) total: \(totalElapsed)")
    }
  }

  private struct Fixture {
    let container: ModelContainer
    let people: [String: Person]
  }

  private func makePeople(_ names: [String]) throws -> Fixture {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: Person.self,
      Gathering.self,
      configurations: configuration
    )
    var people: [String: Person] = [:]
    for name in names {
      let person = Person(name: name, isSelf: name == "Self")
      container.mainContext.insert(person)
      people[name] = person
    }
    try container.mainContext.save()
    return Fixture(container: container, people: people)
  }

  private func canonicalGrandparents() throws -> Fixture {
    let fixture = try makePeople(["Self", "Father", "Mother", "PGF", "PGM", "MGF", "MGM"])
    linkSpouses(fixture.people["Father"]!, fixture.people["Mother"]!)
    linkSpouses(fixture.people["PGF"]!, fixture.people["PGM"]!)
    linkSpouses(fixture.people["MGF"]!, fixture.people["MGM"]!)
    linkParent(fixture.people["Father"]!, to: fixture.people["Self"]!)
    linkParent(fixture.people["Mother"]!, to: fixture.people["Self"]!)
    linkParent(fixture.people["PGF"]!, to: fixture.people["Father"]!)
    linkParent(fixture.people["PGM"]!, to: fixture.people["Father"]!)
    linkParent(fixture.people["MGF"]!, to: fixture.people["Mother"]!)
    linkParent(fixture.people["MGM"]!, to: fixture.people["Mother"]!)
    return fixture
  }

  private func contradictorySpouseParentGraph() throws -> Fixture {
    let fixture = try makePeople(["Self", "Relative"])
    let root = fixture.people["Self"]!
    let relative = fixture.people["Relative"]!
    root.spouse = relative
    relative.spouse = root
    root.parents = [relative]
    relative.children = [root]
    return fixture
  }

  private func branchingFixture(
    personCount: Int
  ) throws -> (container: ModelContainer, root: Person) {
    let fixture = try makePeople((0..<personCount).map { $0 == 0 ? "Self" : "P\($0)" })
    let people = (0..<personCount).map { fixture.people[$0 == 0 ? "Self" : "P\($0)"]! }
    for index in 1..<people.count {
      linkParent(people[index], to: people[(index - 1) / 2])
    }
    return (fixture.container, people[0])
  }

  private func chainFixture(personCount: Int) throws -> (container: ModelContainer, root: Person) {
    let fixture = try makePeople((0..<personCount).map { $0 == 0 ? "Self" : "P\($0)" })
    let people = (0..<personCount).map { fixture.people[$0 == 0 ? "Self" : "P\($0)"]! }
    for index in 1..<people.count {
      linkParent(people[index], to: people[index - 1])
    }
    return (fixture.container, people[0])
  }

  private func linkParent(_ parent: Person, to child: Person) {
    if !parent.children.contains(where: { $0.persistentModelID == child.persistentModelID }) {
      parent.children.append(child)
    }
    if !child.parents.contains(where: { $0.persistentModelID == parent.persistentModelID }) {
      child.parents.append(parent)
    }
  }

  private func linkSpouses(_ first: Person, _ second: Person) {
    first.spouse = second
    second.spouse = first
  }

  private func readyUniverse(
    from root: Person,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws -> FamilyGraphLayoutUniverse {
    let state = FamilyGraphLayoutUniverseBuilder.build(from: root)
    guard case .ready(let universe) = state else {
      XCTFail("Expected a ready universe", file: file, line: line)
      throw TestError.expectedReadyUniverse
    }
    return universe
  }

  private func id(_ person: Person) -> PersistentModelIDBox {
    PersistentModelIDBox(person.persistentModelID)
  }

  private func assertCouple(
    _ first: String,
    _ second: String,
    people: [String: Person],
    result: GraphHorizontalLayoutResult<PersistentModelIDBox>,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let firstX = result.positionsByPersonID[id(people[first]!)]!.x
    let secondX = result.positionsByPersonID[id(people[second]!)]!.x
    XCTAssertEqual(abs(firstX - secondX), 1, accuracy: 0.000_001, file: file, line: line)
  }

  private func assertBranchesDoNotInterleave(
    people: [String: Person],
    result: GraphHorizontalLayoutResult<PersistentModelIDBox>,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let paternal = ["PGF", "PGM"].map { result.positionsByPersonID[id(people[$0]!)]!.x }
    let maternal = ["MGF", "MGM"].map { result.positionsByPersonID[id(people[$0]!)]!.x }
    XCTAssertTrue(
      paternal.max()! < maternal.min()! || maternal.max()! < paternal.min()!,
      file: file,
      line: line
    )
  }

  private func distanceMultiset(
    _ result: GraphHorizontalLayoutResult<PersistentModelIDBox>
  ) -> [Double] {
    let positions = Array(result.positionsByPersonID.values)
    return positions.indices.flatMap { first in
      positions.indices.compactMap { second in
        second > first ? abs(positions[first].x - positions[second].x) : nil
      }
    }.sorted()
  }

  private enum TestError: Error {
    case expectedReadyUniverse
  }
}
