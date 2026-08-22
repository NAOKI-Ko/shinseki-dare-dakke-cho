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

  func testLocalCrossingDeltaMatchesGlobalOracleForEveryLegalAdjacentSwap() throws {
    let fixtures: [(String, ID, Set<ID>, [ParentChild], [Spouse])] = [
      (
        "simple crossing", "C1", ["G", "P1", "P2", "C1", "C2"],
        [
          parent("G", "P1"), parent("G", "P2"),
          parent("P1", "C2"), parent("P2", "C1"),
        ], []
      ),
      (
        "non-crossing", "C1", ["G", "P1", "P2", "C1", "C2"],
        [
          parent("G", "P1"), parent("G", "P2"),
          parent("P1", "C1"), parent("P2", "C2"),
        ], []
      ),
      (
        "shared endpoint", "C1", ["P", "C1", "C2", "C3"],
        [parent("P", "C1"), parent("P", "C2"), parent("P", "C3")], []
      ),
      (
        "multiple parent-child edges", "C1", ["P1", "P2", "P3", "C1", "C2", "C3"],
        [
          parent("P1", "C1"), parent("P1", "C2"), parent("P2", "C2"),
          parent("P2", "C3"), parent("P3", "C1"), parent("P3", "C3"),
        ], []
      ),
      (
        "canonical grandparents", "Self", canonicalVisible(), canonicalParentEdges(),
        canonicalSpouses()
      ),
      (
        "six-person", "Self", ["Self", "Father", "Mother", "PGF", "PGM", "MG"],
        [
          parent("Father", "Self"), parent("Mother", "Self"),
          parent("PGF", "Father"), parent("PGM", "Father"), parent("MG", "Mother"),
        ], [spouse("Father", "Mother"), spouse("PGF", "PGM")]
      ),
      (
        "multiple children and spouse-side", "C1",
        ["A", "B", "C1", "C2", "C3", "S", "SP1", "SP2"],
        [
          parent("A", "C1"), parent("B", "C1"), parent("A", "C2"),
          parent("B", "C2"), parent("A", "C3"), parent("SP1", "S"),
          parent("SP2", "S"),
        ], [spouse("A", "B"), spouse("C1", "S"), spouse("SP1", "SP2")]
      ),
      (
        "shared graph", "Self", ["Self", "A", "B", "Shared", "Other"],
        [
          parent("A", "Self"), parent("B", "Self"), parent("Shared", "A"),
          parent("Shared", "B"), parent("Other", "A"),
        ], []
      ),
    ]

    for (name, root, visible, parents, spouses) in fixtures {
      try assertLocalDeltasMatchGlobalOracle(
        name: name,
        root: root,
        visible: visible,
        parents: parents,
        spouses: spouses
      )
    }
  }

  func testPerformanceFixtures() {
    for count in [100, 300, 500] {
      let fixture = realisticFixture(personCount: count)
      let measurement = measureLayoutStages(
        root: fixture.root,
        visible: fixture.visible,
        parents: fixture.parents,
        spouses: fixture.spouses
      )

      XCTAssertEqual(measurement.result.positionsByPersonID.count, count)
      XCTAssertFalse(measurement.fastPathHit)
      print("FamilyGraphHorizontalLayout realistic \(count) semantic: \(measurement.semantic)")
      print("FamilyGraphHorizontalLayout realistic \(count) horizontal: \(measurement.horizontal)")
      print("FamilyGraphHorizontalLayout realistic \(count) total: \(measurement.total)")
      print("FamilyGraphHorizontalLayout realistic \(count) fast path: \(measurement.fastPathHit)")
    }
  }

  func testDeepChainPerformanceRegression() {
    for count in [50, 100, 200, 300, 500] {
      let ids = (0..<count).map { "Node\($0)" }
      let edges = (1..<count).map { parent(ids[$0], ids[$0 - 1]) }
      let measurement = measureLayoutStages(
        root: ids[0],
        visible: Set(ids),
        parents: edges,
        spouses: []
      )

      XCTAssertEqual(measurement.result.positionsByPersonID.count, count)
      XCTAssertTrue(measurement.fastPathHit)
      print("FamilyGraphHorizontalLayout deep chain \(count) semantic: \(measurement.semantic)")
      print("FamilyGraphHorizontalLayout deep chain \(count) horizontal: \(measurement.horizontal)")
      print("FamilyGraphHorizontalLayout deep chain \(count) total: \(measurement.total)")
      print("FamilyGraphHorizontalLayout deep chain \(count) fast path: \(measurement.fastPathHit)")
    }
  }

  func testSimpleGenerationChainFastPathMatchesGenericHorizontalPositions() {
    let ids = (0..<10).map { "Node\($0)" }
    let input = FamilyGraphLayoutCore.normalize(
      GraphLayoutInput(
        rootID: ids[4],
        visiblePersonIDs: Set(ids),
        parentChildEdges: (1..<ids.count).map { parent(ids[$0], ids[$0 - 1]) }
      )
    )
    let generations = FamilyGraphLayoutCore.solveGenerations(input)
    let fastSemantic = FamilyGraphLayoutCore.buildSemanticOrder(
      from: input, generations: generations
    )
    let genericSemantic = FamilyGraphLayoutCore.buildSemanticOrder(
      from: input, generations: generations, useSimpleChainFastPath: false
    )

    XCTAssertEqual(
      FamilyGraphHorizontalLayout.layout(
        input: input, generations: generations, semanticOrder: fastSemantic
      ),
      FamilyGraphHorizontalLayout.layout(
        input: input, generations: generations, semanticOrder: genericSemantic
      )
    )
  }

  private func measureLayoutStages(
    root: ID,
    visible: Set<ID>,
    parents: [ParentChild],
    spouses: [Spouse]
  ) -> (
    result: GraphHorizontalLayoutResult<ID>,
    semantic: Duration,
    horizontal: Duration,
    total: Duration,
    fastPathHit: Bool
  ) {
    let totalStart = ContinuousClock.now
    let input = GraphLayoutInput(
      rootID: root,
      visiblePersonIDs: visible,
      parentChildEdges: parents,
      spouseEdges: spouses
    )
    let normalized = FamilyGraphLayoutCore.normalize(input)
    let generations = FamilyGraphLayoutCore.solveGenerations(normalized)
    let semanticStart = ContinuousClock.now
    let semantic = FamilyGraphLayoutCore.buildSemanticOrder(
      from: normalized,
      generations: generations
    )
    let semanticElapsed = ContinuousClock.now - semanticStart
    let horizontalStart = ContinuousClock.now
    let result = FamilyGraphHorizontalLayout.layout(
      input: normalized,
      generations: generations,
      semanticOrder: semantic
    )
    return (
      result,
      semanticElapsed,
      ContinuousClock.now - horizontalStart,
      ContinuousClock.now - totalStart,
      FamilyGraphLayoutCore.isSimpleGenerationChain(normalized, generations: generations)
    )
  }

  func testRealistic300PhaseBreakdown() throws {
    let fixture = realisticFixture(personCount: 300)
    let input = GraphLayoutInput(
      rootID: fixture.root,
      visiblePersonIDs: fixture.visible,
      parentChildEdges: fixture.parents,
      spouseEdges: fixture.spouses
    )

    var start = ContinuousClock.now
    let normalized = FamilyGraphLayoutCore.normalize(input)
    let normalizeElapsed = ContinuousClock.now - start
    start = ContinuousClock.now
    let generations = FamilyGraphLayoutCore.solveGenerations(normalized)
    let generationElapsed = ContinuousClock.now - start
    start = ContinuousClock.now
    let semantic = FamilyGraphLayoutCore.buildSemanticOrder(
      from: normalized,
      generations: generations
    )
    let semanticElapsed = ContinuousClock.now - start
    start = ContinuousClock.now
    let result = FamilyGraphHorizontalLayout.layout(
      input: normalized,
      generations: generations,
      semanticOrder: semantic
    )
    let horizontalElapsed = ContinuousClock.now - start

    XCTAssertEqual(result.positionsByPersonID.count, 300)
    print("FamilyGraphHorizontalLayout realistic 300 normalize: \(normalizeElapsed)")
    print("FamilyGraphHorizontalLayout realistic 300 generation: \(generationElapsed)")
    print("FamilyGraphHorizontalLayout realistic 300 semantic: \(semanticElapsed)")
    print("FamilyGraphHorizontalLayout realistic 300 horizontal: \(horizontalElapsed)")
  }

  private func canonicalGrandparents() -> GraphHorizontalLayoutResult<ID> {
    layout(
      visible: canonicalVisible(),
      parents: canonicalParentEdges(),
      spouses: canonicalSpouses()
    )
  }

  private func realisticFixture(personCount: Int) -> (
    root: ID, visible: Set<ID>, parents: [ParentChild], spouses: [Spouse]
  ) {
    let generationRange: ClosedRange<Int>
    switch personCount {
    case ...20: generationRange = -3...2
    case ...50: generationRange = -3...3
    case ...100: generationRange = -4...4
    default: generationRange = -5...5
    }
    let unitCount = personCount / 2
    let generations = Array(generationRange)
    var unitsByGeneration: [Int: [[ID]]] = [:]
    var visible = Set<ID>()
    var spouses: [Spouse] = []
    for unitIndex in 0..<unitCount {
      let generation = generations[unitIndex % generations.count]
      let people = ["G\(generation)U\(unitIndex)A", "G\(generation)U\(unitIndex)B"]
      unitsByGeneration[generation, default: []].append(people)
      visible.formUnion(people)
      spouses.append(spouse(people[0], people[1]))
    }

    var parents: [ParentChild] = []
    for generation in generations.dropFirst() {
      let parentUnits = unitsByGeneration[generation - 1, default: []]
      let childUnits = unitsByGeneration[generation, default: []]
      for (index, childUnit) in childUnits.enumerated() {
        for offset in 0..<min(2, parentUnits.count) {
          let parentUnit = parentUnits[(index + offset) % parentUnits.count]
          for parentID in parentUnit {
            parents.append(parent(parentID, childUnit[offset % childUnit.count]))
          }
        }
      }
    }
    return (unitsByGeneration[0]![0][0], visible, parents, spouses)
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

  private func assertLocalDeltasMatchGlobalOracle(
    name: String,
    root: ID,
    visible: Set<ID>,
    parents: [ParentChild],
    spouses: [Spouse]
  ) throws {
    let input = GraphLayoutInput(
      rootID: root,
      visiblePersonIDs: visible,
      parentChildEdges: parents,
      spouseEdges: spouses
    )
    let normalized = FamilyGraphLayoutCore.normalize(input)
    let generations = FamilyGraphLayoutCore.solveGenerations(normalized)
    let semantic = FamilyGraphLayoutCore.buildSemanticOrder(
      from: normalized,
      generations: generations
    )
    let graph = try XCTUnwrap(semantic.unitGraph, name)
    let orders = FamilyGraphHorizontalLayout.layout(
      input: normalized,
      generations: generations,
      semanticOrder: semantic
    ).orderedUnitIDsByGeneration

    var evaluatedSwapCount = 0
    for (generation, order) in orders where order.count > 1 {
      for index in 0..<(order.count - 1) {
        var swappedOrder = order
        swappedOrder.swapAt(index, index + 1)
        guard
          respectsContiguity(
            swappedOrder,
            ordering: semantic.generationOrderings[generation]
          )
        else { continue }
        evaluatedSwapCount += 1

        let before = FamilyGraphHorizontalLayout.countParentChildCrossings(
          orderedUnitIDsByGeneration: orders,
          edges: graph.parentChildEdges
        )
        var swappedOrders = orders
        swappedOrders[generation] = swappedOrder
        let after = FamilyGraphHorizontalLayout.countParentChildCrossings(
          orderedUnitIDsByGeneration: swappedOrders,
          edges: graph.parentChildEdges
        )
        let delta = try XCTUnwrap(
          FamilyGraphHorizontalLayout.crossingDeltaForAdjacentSwap(
            orderedUnitIDsByGeneration: orders,
            edges: graph.parentChildEdges,
            generation: generation,
            index: index
          ),
          "\(name), generation \(generation), index \(index)"
        )
        XCTAssertEqual(
          delta,
          after - before,
          "\(name), generation \(generation), index \(index)"
        )
      }
    }
    XCTAssertGreaterThan(evaluatedSwapCount, 0, name)
  }

  private func respectsContiguity(
    _ order: [LayoutUnitID<ID>],
    ordering: LayoutGenerationOrdering<ID>?
  ) -> Bool {
    guard let ordering else { return true }
    let indices = Dictionary(
      uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) }
    )
    return ordering.contiguityConstraints.allSatisfy { constraint in
      let memberIndices = constraint.memberUnitIDs.compactMap { indices[$0] }
      guard let minimum = memberIndices.min(), let maximum = memberIndices.max() else {
        return true
      }
      return maximum - minimum + 1 == memberIndices.count
    }
  }
}
