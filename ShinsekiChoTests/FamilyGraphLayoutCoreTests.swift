import XCTest

@testable import ShinsekiCho

final class FamilyGraphLayoutCoreTests: XCTestCase {
  typealias ID = String
  typealias ParentChild = GraphLayoutParentChildEdge<ID>
  typealias Spouse = GraphLayoutSpouseEdge<ID>

  private func parent(_ parentID: ID, _ childID: ID) -> ParentChild {
    ParentChild(parentID: parentID, childID: childID)
  }

  private func spouse(_ firstID: ID, _ secondID: ID) -> Spouse {
    Spouse(firstID, secondID)
  }

  private func normalized(
    rootID: ID = "Self",
    visible: Set<ID>,
    parents: [ParentChild] = [],
    spouses: [Spouse] = []
  ) -> NormalizedGraphLayoutInput<ID> {
    FamilyGraphLayoutCore.normalize(
      GraphLayoutInput(
        rootID: rootID,
        visiblePersonIDs: visible,
        parentChildEdges: parents,
        spouseEdges: spouses
      )
    )
  }

  func testNormalizeRemovesDuplicateParentChildEdges() {
    let edge = parent("Parent", "Self")
    let graph = normalized(visible: ["Parent", "Self"], parents: [edge, edge, edge])

    XCTAssertEqual(graph.parentChildEdges, [edge])
  }

  func testNormalizeTreatsSpouseEdgesAsUndirectedAndDeduplicatesThem() {
    let graph = normalized(
      visible: ["Self", "Spouse"],
      spouses: [spouse("Self", "Spouse"), spouse("Spouse", "Self")]
    )

    XCTAssertEqual(graph.spouseEdges, [spouse("Self", "Spouse")])
  }

  func testNormalizeFiltersEdgesWithInvisibleEndpoints() {
    let graph = normalized(
      visible: ["Self"],
      parents: [parent("Invisible", "Self"), parent("Self", "InvisibleChild")],
      spouses: [spouse("Self", "InvisibleSpouse")]
    )

    XCTAssertTrue(graph.parentChildEdges.isEmpty)
    XCTAssertTrue(graph.spouseEdges.isEmpty)
  }

  func testNormalizeDiagnosesAndRemovesSelfEdges() {
    let graph = normalized(
      visible: ["Self"],
      parents: [parent("Self", "Self")],
      spouses: [spouse("Self", "Self")]
    )

    XCTAssertEqual(
      graph.diagnostics,
      [
        .invalidSelfEdge(personID: "Self", kind: .parentChild),
        .invalidSelfEdge(personID: "Self", kind: .spouse),
      ]
    )
    XCTAssertTrue(graph.parentChildEdges.isEmpty)
    XCTAssertTrue(graph.spouseEdges.isEmpty)
  }

  func testDirectGenerations() {
    let graph = normalized(
      visible: ["Parent", "Self", "Child"],
      parents: [parent("Parent", "Self"), parent("Self", "Child")]
    )

    let solution = FamilyGraphLayoutCore.solveGenerations(graph)

    XCTAssertEqual(solution.generations, ["Parent": -1, "Self": 0, "Child": 1])
    XCTAssertTrue(solution.diagnostics.isEmpty)
  }

  func testGrandparentGenerations() {
    let graph = normalized(
      visible: ["Grandparent", "Parent", "Self"],
      parents: [parent("Grandparent", "Parent"), parent("Parent", "Self")]
    )

    XCTAssertEqual(
      FamilyGraphLayoutCore.solveGenerations(graph).generations,
      ["Grandparent": -2, "Parent": -1, "Self": 0]
    )
  }

  func testSpousesHaveSameGeneration() {
    let graph = normalized(
      visible: ["Self", "Spouse"],
      spouses: [spouse("Self", "Spouse")]
    )

    XCTAssertEqual(
      FamilyGraphLayoutCore.solveGenerations(graph).generations,
      ["Self": 0, "Spouse": 0]
    )
  }

  func testConsistentMultiplePathsProduceOneGeneration() {
    let graph = normalized(
      visible: ["Self", "Spouse", "Child"],
      parents: [parent("Self", "Child"), parent("Spouse", "Child")],
      spouses: [spouse("Self", "Spouse")]
    )

    let solution = FamilyGraphLayoutCore.solveGenerations(graph)

    XCTAssertEqual(solution.generations["Child"], 1)
    XCTAssertTrue(solution.diagnostics.isEmpty)
  }

  func testInconsistentGenerationIsDiagnosedWithoutReturningArbitraryValues() {
    let constraints = [parent("A", "B"), parent("B", "C"), parent("A", "C")]
    let graph = normalized(rootID: "A", visible: ["A", "B", "C"], parents: constraints)

    let solution = FamilyGraphLayoutCore.solveGenerations(graph)

    XCTAssertTrue(solution.generations.isEmpty)
    XCTAssertTrue(
      solution.diagnostics.contains {
        guard case .inconsistentGeneration(let personIDs, let edgeContext) = $0 else {
          return false
        }
        return personIDs == ["A", "B", "C"] && edgeContext.count == 3
      })
  }

  func testSemanticResultsAreIndependentOfInputOrderAndEdgeDirection() {
    let visible: Set<ID> = ["Self", "Spouse", "Child1", "Child2"]
    let parentEdges = [
      parent("Self", "Child1"), parent("Spouse", "Child1"),
      parent("Self", "Child2"), parent("Spouse", "Child2"),
    ]
    let first = normalized(
      visible: visible,
      parents: parentEdges,
      spouses: [spouse("Self", "Spouse")]
    )
    let second = normalized(
      visible: visible,
      parents: Array(parentEdges.reversed()),
      spouses: [spouse("Spouse", "Self")]
    )

    XCTAssertEqual(first, second)
    let firstGenerations = FamilyGraphLayoutCore.solveGenerations(first)
    let secondGenerations = FamilyGraphLayoutCore.solveGenerations(second)
    XCTAssertEqual(firstGenerations, secondGenerations)
    XCTAssertEqual(
      FamilyGraphLayoutCore.buildCoupleUnits(from: first, generations: firstGenerations),
      FamilyGraphLayoutCore.buildCoupleUnits(from: second, generations: secondGenerations)
    )
    XCTAssertEqual(
      FamilyGraphLayoutCore.buildParentGroups(from: first),
      FamilyGraphLayoutCore.buildParentGroups(from: second)
    )
  }

  func testVisibleSpousePairFormsOneCoupleUnit() {
    let graph = normalized(
      visible: ["Self", "Spouse"],
      spouses: [spouse("Self", "Spouse")]
    )
    let solution = FamilyGraphLayoutCore.solveGenerations(graph)

    XCTAssertEqual(
      FamilyGraphLayoutCore.buildCoupleUnits(from: graph, generations: solution).units,
      [LayoutCoupleUnit(memberIDs: ["Self", "Spouse"])]
    )
  }

  func testPersonWithInvisibleSpouseFormsSingletonUnit() {
    let graph = normalized(
      visible: ["Self"],
      spouses: [spouse("Self", "Invisible")]
    )
    let solution = FamilyGraphLayoutCore.solveGenerations(graph)

    XCTAssertEqual(
      FamilyGraphLayoutCore.buildCoupleUnits(from: graph, generations: solution).units,
      [LayoutCoupleUnit(memberIDs: ["Self"])]
    )
  }

  func testEveryPersonBelongsToExactlyOneCoupleOrSingletonUnit() {
    let graph = normalized(
      visible: ["Self", "Spouse", "Singleton"],
      spouses: [spouse("Self", "Spouse")]
    )
    let solution = FamilyGraphLayoutCore.solveGenerations(graph)
    let units = FamilyGraphLayoutCore.buildCoupleUnits(
      from: graph,
      generations: solution
    ).units

    let memberships = units.flatMap(\.memberIDs)
    XCTAssertEqual(memberships.count, graph.visiblePersonIDs.count)
    XCTAssertEqual(Set(memberships), graph.visiblePersonIDs)
  }

  func testCoupleBuilderPreservesGenerationContradictionDiagnostic() {
    let graph = normalized(
      rootID: "A",
      visible: ["A", "B", "C"],
      parents: [parent("A", "B"), parent("B", "C"), parent("A", "C")]
    )
    let solution = FamilyGraphLayoutCore.solveGenerations(graph)
    let result = FamilyGraphLayoutCore.buildCoupleUnits(
      from: graph,
      generations: solution
    )

    XCTAssertEqual(result.diagnostics, solution.diagnostics)
    XCTAssertFalse(result.diagnostics.isEmpty)
  }

  func testSingleParentGroup() {
    let graph = normalized(
      visible: ["Self", "Child"],
      parents: [parent("Self", "Child")]
    )

    XCTAssertEqual(
      FamilyGraphLayoutCore.buildParentGroups(from: graph),
      [LayoutParentGroup(parentIDs: ["Self"], childIDs: ["Child"])]
    )
  }

  func testTwoParentGroup() {
    let graph = normalized(
      visible: ["ParentA", "ParentB", "Child"],
      parents: [parent("ParentA", "Child"), parent("ParentB", "Child")]
    )

    XCTAssertEqual(
      FamilyGraphLayoutCore.buildParentGroups(from: graph),
      [LayoutParentGroup(parentIDs: ["ParentA", "ParentB"], childIDs: ["Child"])]
    )
  }

  func testNonSpouseCoParentsStillFormParentGroup() {
    let graph = normalized(
      visible: ["ParentA", "ParentB", "Child"],
      parents: [parent("ParentA", "Child"), parent("ParentB", "Child")]
    )

    let group = FamilyGraphLayoutCore.buildParentGroups(from: graph).first
    XCTAssertEqual(group?.parentIDs, ["ParentA", "ParentB"])
    XCTAssertTrue(graph.spouseEdges.isEmpty)
  }

  func testSharedChildrenAreGroupedByTheSameParentSet() {
    let graph = normalized(
      visible: ["ParentA", "ParentB", "Child1", "Child2"],
      parents: [
        parent("ParentA", "Child1"), parent("ParentB", "Child1"),
        parent("ParentA", "Child2"), parent("ParentB", "Child2"),
      ]
    )

    XCTAssertEqual(
      FamilyGraphLayoutCore.buildParentGroups(from: graph),
      [
        LayoutParentGroup(
          parentIDs: ["ParentA", "ParentB"],
          childIDs: ["Child1", "Child2"]
        )
      ]
    )
  }

  func testDisconnectedVisiblePeopleAreDiagnosedAndRemainUnassigned() {
    let graph = normalized(
      visible: ["Self", "Child", "DisconnectedA", "DisconnectedB"],
      parents: [parent("Self", "Child"), parent("DisconnectedA", "DisconnectedB")]
    )

    let solution = FamilyGraphLayoutCore.solveGenerations(graph)

    XCTAssertEqual(solution.generations, ["Self": 0, "Child": 1])
    XCTAssertTrue(
      solution.diagnostics.contains(
        .disconnectedVisibleComponent(personIDs: ["DisconnectedA", "DisconnectedB"])
      )
    )
  }

  func testMalformedRootIsDiagnosedAndNoGenerationIsAssigned() {
    let graph = normalized(rootID: "Missing", visible: ["Visible"])

    let solution = FamilyGraphLayoutCore.solveGenerations(graph)

    XCTAssertTrue(solution.generations.isEmpty)
    XCTAssertTrue(solution.diagnostics.contains(.malformedInput(.rootIsNotVisible)))
  }

  func testMultipleVisibleSpousesAreDiagnosedWithoutDuplicateMembership() {
    let graph = normalized(
      rootID: "A",
      visible: ["A", "B", "C"],
      spouses: [spouse("A", "B"), spouse("A", "C")]
    )
    let solution = FamilyGraphLayoutCore.solveGenerations(graph)
    let result = FamilyGraphLayoutCore.buildCoupleUnits(
      from: graph,
      generations: solution
    )

    XCTAssertTrue(
      result.diagnostics.contains {
        if case .invalidSpouseConstraint = $0 { return true }
        return false
      })
    XCTAssertEqual(
      result.units,
      [
        LayoutCoupleUnit(memberIDs: ["A"]),
        LayoutCoupleUnit(memberIDs: ["B"]),
        LayoutCoupleUnit(memberIDs: ["C"]),
      ])
  }
}
