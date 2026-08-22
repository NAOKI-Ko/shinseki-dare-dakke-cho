import XCTest

@testable import ShinsekiCho

final class FamilyGraphHorizontalLayoutTests: XCTestCase {
  typealias ID = String
  typealias ParentChild = GraphLayoutParentChildEdge<ID>
  typealias Spouse = GraphLayoutSpouseEdge<ID>

  private func parent(_ parentID: ID, _ childID: ID) -> ParentChild {
    ParentChild(parentID: parentID, childID: childID)
  }

  private func spouse(_ firstID: ID, _ secondID: ID) -> Spouse {
    Spouse(firstID, secondID)
  }

  private func layout(
    root: ID = "Self",
    visible: Set<ID>,
    parents: [ParentChild],
    spouses: [Spouse] = []
  ) -> GraphHorizontalLayoutResult<ID> {
    FamilyGraphHorizontalLayout.layout(
      GraphLayoutInput(
        rootID: root,
        visiblePersonIDs: visible,
        parentChildEdges: parents,
        spouseEdges: spouses
      )
    )
  }

  func testSimpleParentChildCentersOnRoot() throws {
    let result = layout(visible: ["Parent", "Self"], parents: [parent("Parent", "Self")])

    XCTAssertEqual(result.positionsByPersonID.count, 2)
    XCTAssertEqual(try XCTUnwrap(result.positionsByPersonID["Self"]).x, 0, accuracy: 0.000_001)
    XCTAssertEqual(
      try XCTUnwrap(result.positionsByPersonID["Parent"]).x,
      0,
      accuracy: 0.000_001
    )
  }

  func testCoupleIsAtomicAndChildUsesCoupleCenter() throws {
    let result = layout(
      visible: ["A", "B", "Self"],
      parents: [parent("A", "Self"), parent("B", "Self")],
      spouses: [spouse("A", "B")]
    )
    let a = try XCTUnwrap(result.positionsByPersonID["A"])
    let b = try XCTUnwrap(result.positionsByPersonID["B"])

    XCTAssertEqual(abs(a.x - b.x), 1, accuracy: 0.000_001)
    XCTAssertEqual((a.x + b.x) / 2, 0, accuracy: 0.000_001)
  }

  func testCanonicalGrandparentsHasZeroCrossingsAndSeparatedCouples() throws {
    let result = canonicalGrandparents()

    XCTAssertEqual(result.parentChildCrossingCount, 0)
    XCTAssertEqual(
      try XCTUnwrap(result.positionsByPersonID["Self"]?.x),
      0,
      accuracy: 0.000_001
    )
    assertCouple("PGF", "PGM", result: result)
    assertCouple("MGF", "MGM", result: result)
  }

  func testSixPersonCounterexampleDoesNotInterleaveCouple() throws {
    let result = layout(
      visible: ["Self", "Father", "Mother", "PGF", "PGM", "MG"],
      parents: [
        parent("Father", "Self"), parent("Mother", "Self"),
        parent("PGF", "Father"), parent("PGM", "Father"), parent("MG", "Mother"),
      ],
      spouses: [spouse("Father", "Mother"), spouse("PGF", "PGM")]
    )
    let pgf = try XCTUnwrap(result.positionsByPersonID["PGF"]?.x)
    let pgm = try XCTUnwrap(result.positionsByPersonID["PGM"]?.x)
    let maternal = try XCTUnwrap(result.positionsByPersonID["MG"]?.x)

    XCTAssertFalse(maternal > min(pgf, pgm) && maternal < max(pgf, pgm))
    XCTAssertEqual(result.parentChildCrossingCount, 0)
  }

  func testGreatGrandparentsKeepNestedBlocksContiguous() throws {
    let parents =
      canonicalParentEdges() + [
        parent("PGF1", "PGF"), parent("PGF2", "PGF"),
        parent("PGM1", "PGM"), parent("PGM2", "PGM"),
        parent("MGF1", "MGF"), parent("MGF2", "MGF"),
        parent("MGM1", "MGM"), parent("MGM2", "MGM"),
      ]
    let result = layout(
      visible: Set(parents.flatMap { [$0.parentID, $0.childID] }),
      parents: parents,
      spouses: canonicalSpouses() + [
        spouse("PGF1", "PGF2"), spouse("PGM1", "PGM2"),
        spouse("MGF1", "MGF2"), spouse("MGM1", "MGM2"),
      ]
    )

    XCTAssertEqual(result.parentChildCrossingCount, 0)
    assertAllContiguity(
      result, inputParents: parents,
      spouses: canonicalSpouses() + [
        spouse("PGF1", "PGF2"), spouse("PGM1", "PGM2"),
        spouse("MGF1", "MGF2"), spouse("MGM1", "MGM2"),
      ])
  }

  func testUncleAndSpouseSideAndMultipleChildrenAreSafe() {
    let parents = [
      parent("PGF", "Father"), parent("PGM", "Father"),
      parent("PGF", "Uncle"), parent("PGM", "Uncle"),
      parent("Father", "Self"), parent("Mother", "Self"),
      parent("SP1", "Spouse"), parent("SP2", "Spouse"),
      parent("Self", "C1"), parent("Spouse", "C1"),
      parent("Self", "C2"), parent("Spouse", "C2"),
      parent("Self", "C3"), parent("Spouse", "C3"),
    ]
    let visible = Set(parents.flatMap { [$0.parentID, $0.childID] })
    let result = layout(
      visible: visible,
      parents: parents,
      spouses: [
        spouse("PGF", "PGM"), spouse("Father", "Mother"),
        spouse("Self", "Spouse"), spouse("SP1", "SP2"),
      ]
    )

    XCTAssertEqual(result.positionsByPersonID.count, visible.count)
    XCTAssertTrue(result.positionsByPersonID.values.allSatisfy { $0.x.isFinite })
    XCTAssertEqual(
      result.positionsByPersonID["Self"]!.x + result.positionsByPersonID["Spouse"]!.x, 0,
      accuracy: 0.000_001)
  }

  func testSingleAndNonSpouseParentsCenterChildrenWithoutCreatingCouple() throws {
    let result = layout(
      root: "C1",
      visible: ["A", "B", "C1", "C2", "C3"],
      parents: [
        parent("A", "C1"), parent("B", "C1"), parent("A", "C2"),
        parent("B", "C2"), parent("A", "C3"),
      ]
    )
    let parentOrder = try XCTUnwrap(result.orderedUnitIDsByGeneration[-1])

    XCTAssertEqual(parentOrder.count, 2)
    XCTAssertTrue(parentOrder.allSatisfy { $0.personIDs.count == 1 })
    XCTAssertEqual(result.positionsByPersonID.count, 5)
  }

  func testSharedGraphHasUniqueFinitePositions() {
    let result = layout(
      visible: ["Self", "A", "B", "Shared"],
      parents: [
        parent("A", "Self"), parent("B", "Self"),
        parent("Shared", "A"), parent("Shared", "B"),
      ]
    )

    XCTAssertEqual(result.positionsByPersonID.count, 4)
    XCTAssertTrue(result.positionsByPersonID.values.allSatisfy { $0.x.isFinite })
  }

  func testGenerationConflictReturnsNoPositions() {
    let result = layout(
      root: "A",
      visible: ["A", "B", "C"],
      parents: [parent("A", "B"), parent("B", "C"), parent("A", "C")]
    )

    XCTAssertTrue(result.positionsByPersonID.isEmpty)
    XCTAssertNil(result.bounds)
  }

  func testInputOrderAndSymmetricMirrorAreEquivalent() {
    let first = canonicalGrandparents()
    let second = layout(
      visible: canonicalVisible(),
      parents: Array(canonicalParentEdges().reversed()),
      spouses: canonicalSpouses().reversed().map {
        let people = Array($0.personIDs)
        return spouse(people[1], people[0])
      }
    )

    XCTAssertEqual(first.parentChildCrossingCount, second.parentChildCrossingCount)
    XCTAssertEqual(distanceMultiset(first), distanceMultiset(second))
    XCTAssertFalse(first.swapEquivalences.isEmpty)
  }

  func testMinimumSpacingAndNoOverlap() throws {
    let result = canonicalGrandparents()
    for generation in Set(result.positionsByPersonID.values.map(\.generation)) {
      let xs = result.positionsByPersonID.values.filter { $0.generation == generation }.map(\.x)
        .sorted()
      for index in 1..<xs.count {
        XCTAssertGreaterThanOrEqual(xs[index] - xs[index - 1], 1 - 0.000_001)
      }
    }
  }

  func testPerformanceFixtures() {
    for count in [20, 50, 100, 300] {
      let ids = (0..<count).map { "Node\($0)" }
      let edges = (1..<count).map { parent(ids[$0], ids[$0 - 1]) }
      let start = ContinuousClock.now
      let result = layout(root: ids[0], visible: Set(ids), parents: edges)
      let elapsed = ContinuousClock.now - start

      XCTAssertEqual(result.positionsByPersonID.count, count)
      print("FamilyGraphHorizontalLayout performance \(count) nodes: \(elapsed)")
    }
  }

  private func canonicalGrandparents() -> GraphHorizontalLayoutResult<ID> {
    layout(
      visible: canonicalVisible(),
      parents: canonicalParentEdges(),
      spouses: canonicalSpouses()
    )
  }

  private func canonicalVisible() -> Set<ID> {
    ["Self", "Father", "Mother", "PGF", "PGM", "MGF", "MGM"]
  }

  private func canonicalParentEdges() -> [ParentChild] {
    [
      parent("Father", "Self"), parent("Mother", "Self"),
      parent("PGF", "Father"), parent("PGM", "Father"),
      parent("MGF", "Mother"), parent("MGM", "Mother"),
    ]
  }

  private func canonicalSpouses() -> [Spouse] {
    [spouse("Father", "Mother"), spouse("PGF", "PGM"), spouse("MGF", "MGM")]
  }

  private func assertCouple(
    _ first: ID,
    _ second: ID,
    result: GraphHorizontalLayoutResult<ID>,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(
      abs(result.positionsByPersonID[first]!.x - result.positionsByPersonID[second]!.x),
      1,
      accuracy: 0.000_001,
      file: file,
      line: line
    )
  }

  private func assertAllContiguity(
    _ result: GraphHorizontalLayoutResult<ID>,
    inputParents: [ParentChild],
    spouses: [Spouse]
  ) {
    let visible = Set(inputParents.flatMap { [$0.parentID, $0.childID] })
    let normalized = FamilyGraphLayoutCore.normalize(
      GraphLayoutInput(
        rootID: "Self",
        visiblePersonIDs: visible,
        parentChildEdges: inputParents,
        spouseEdges: spouses
      )
    )
    let generations = FamilyGraphLayoutCore.solveGenerations(normalized)
    let semantic = FamilyGraphLayoutCore.buildSemanticOrder(
      from: normalized,
      generations: generations
    )
    for (generation, ordering) in semantic.generationOrderings {
      let order = result.orderedUnitIDsByGeneration[generation]!
      for constraint in ordering.contiguityConstraints {
        let indices = constraint.memberUnitIDs.compactMap { order.firstIndex(of: $0) }
        XCTAssertEqual(indices.max()! - indices.min()! + 1, indices.count)
      }
    }
  }

  private func distanceMultiset(_ result: GraphHorizontalLayoutResult<ID>) -> [Double] {
    let positions = Array(result.positionsByPersonID.values)
    return positions.indices.flatMap { first in
      positions.indices.compactMap { second in
        second > first ? abs(positions[first].x - positions[second].x) : nil
      }
    }.sorted()
  }
}
