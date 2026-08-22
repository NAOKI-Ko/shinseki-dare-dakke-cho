import XCTest

@testable import ShinsekiCho

final class FamilyGraphSemanticOrderingTests: XCTestCase {
  typealias ID = String
  typealias ParentChild = GraphLayoutParentChildEdge<ID>
  typealias Spouse = GraphLayoutSpouseEdge<ID>

  private func parent(_ parentID: ID, _ childID: ID) -> ParentChild {
    ParentChild(parentID: parentID, childID: childID)
  }

  private func spouse(_ firstID: ID, _ secondID: ID) -> Spouse {
    Spouse(firstID, secondID)
  }

  private func order(
    rootID: ID = "Self",
    visible: Set<ID>,
    parents: [ParentChild],
    spouses: [Spouse] = []
  ) -> LayoutSemanticOrder<ID> {
    let normalized = FamilyGraphLayoutCore.normalize(
      GraphLayoutInput(
        rootID: rootID,
        visiblePersonIDs: visible,
        parentChildEdges: parents,
        spouseEdges: spouses
      )
    )
    return FamilyGraphLayoutCore.buildSemanticOrder(
      from: normalized,
      generations: FamilyGraphLayoutCore.solveGenerations(normalized)
    )
  }

  private func canonicalGrandparents(
    parents: [ParentChild]? = nil,
    spouses: [Spouse]? = nil
  ) -> LayoutSemanticOrder<ID> {
    let parentEdges =
      parents ?? [
        parent("Father", "Self"), parent("Mother", "Self"),
        parent("PaternalGrandfather", "Father"),
        parent("PaternalGrandmother", "Father"),
        parent("MaternalGrandfather", "Mother"),
        parent("MaternalGrandmother", "Mother"),
      ]
    let spouseEdges =
      spouses ?? [
        spouse("Father", "Mother"),
        spouse("PaternalGrandfather", "PaternalGrandmother"),
        spouse("MaternalGrandfather", "MaternalGrandmother"),
      ]
    return order(
      visible: [
        "Self", "Father", "Mother", "PaternalGrandfather",
        "PaternalGrandmother", "MaternalGrandfather", "MaternalGrandmother",
      ],
      parents: parentEdges,
      spouses: spouseEdges
    )
  }

  func testCanonicalGrandparentsFormTwoAtomicContiguousBlocks() throws {
    let result = canonicalGrandparents()
    let graph = try XCTUnwrap(result.unitGraph)
    let paternal = try XCTUnwrap(graph.unitIDByPersonID["PaternalGrandfather"])
    let maternal = try XCTUnwrap(graph.unitIDByPersonID["MaternalGrandfather"])

    XCTAssertEqual(paternal.personIDs, ["PaternalGrandfather", "PaternalGrandmother"])
    XCTAssertEqual(maternal.personIDs, ["MaternalGrandfather", "MaternalGrandmother"])
    XCTAssertEqual(result.generationOrderings[-2]?.unitIDs, [paternal, maternal])
    XCTAssertTrue(hasBlock(result, containing: [paternal], excluding: [maternal]))
    XCTAssertTrue(hasBlock(result, containing: [maternal], excluding: [paternal]))
    XCTAssertTrue(
      result.generationOrderings[-2]!.contiguityConstraints.contains {
        $0.memberUnitIDs == [paternal] && $0.source == .atomicUnit(paternal)
      })
  }

  func testSixPersonCounterexampleKeepsPaternalCoupleAtomic() throws {
    let result = order(
      visible: [
        "Self", "Father", "Mother", "PaternalGrandfather",
        "PaternalGrandmother", "MaternalGrandparent",
      ],
      parents: [
        parent("Father", "Self"), parent("Mother", "Self"),
        parent("PaternalGrandfather", "Father"),
        parent("PaternalGrandmother", "Father"),
        parent("MaternalGrandparent", "Mother"),
      ],
      spouses: [
        spouse("Father", "Mother"),
        spouse("PaternalGrandfather", "PaternalGrandmother"),
      ]
    )
    let graph = try XCTUnwrap(result.unitGraph)
    let paternal = try XCTUnwrap(graph.unitIDByPersonID["PaternalGrandfather"])
    let maternal = try XCTUnwrap(graph.unitIDByPersonID["MaternalGrandparent"])

    XCTAssertEqual(result.generationOrderings[-2]?.unitIDs, [paternal, maternal])
    XCTAssertEqual(paternal.personIDs.count, 2)
    XCTAssertTrue(hasBlock(result, containing: [paternal], excluding: [maternal]))
  }

  func testUnitGraphProjectsAndDeduplicatesEdges() throws {
    let result = order(
      rootID: "A",
      visible: ["A", "B", "Child"],
      parents: [parent("A", "Child"), parent("B", "Child")],
      spouses: [spouse("A", "B")]
    )
    let graph = try XCTUnwrap(result.unitGraph)

    XCTAssertEqual(graph.units.count, 2)
    XCTAssertEqual(graph.parentChildEdges.count, 1)
    XCTAssertTrue(graph.suppressedSelfEdges.isEmpty)
    XCTAssertEqual(graph.unitIDByPersonID.count, 3)
  }

  func testInputAndLateDiscoveryOrderDoNotChangeSemanticResult() {
    let edges = [
      parent("Father", "Self"), parent("Mother", "Self"),
      parent("PaternalGrandfather", "Father"),
      parent("PaternalGrandmother", "Father"),
      parent("MaternalGrandfather", "Mother"),
      parent("MaternalGrandmother", "Mother"),
    ]
    let spouses = [
      spouse("Father", "Mother"),
      spouse("PaternalGrandfather", "PaternalGrandmother"),
      spouse("MaternalGrandfather", "MaternalGrandmother"),
    ]
    let first = canonicalGrandparents(parents: edges, spouses: spouses)
    let second = canonicalGrandparents(
      parents: Array(edges.reversed()),
      spouses: [
        spouse("MaternalGrandmother", "MaternalGrandfather"),
        spouse("PaternalGrandmother", "PaternalGrandfather"),
        spouse("Mother", "Father"),
      ]
    )

    XCTAssertEqual(first, second)
  }

  func testUncleSharesGrandparentParentGroupAndStaysInThatBranch() throws {
    let parents = [
      parent("Father", "Self"), parent("Mother", "Self"),
      parent("PGF", "Father"), parent("PGM", "Father"),
      parent("PGF", "FatherSibling"), parent("PGM", "FatherSibling"),
      parent("MGF", "Mother"), parent("MGM", "Mother"),
    ]
    let visible: Set<ID> = [
      "Self", "Father", "Mother", "FatherSibling", "PGF", "PGM", "MGF", "MGM",
    ]
    let normalized = FamilyGraphLayoutCore.normalize(
      GraphLayoutInput(
        rootID: "Self",
        visiblePersonIDs: visible,
        parentChildEdges: parents,
        spouseEdges: [spouse("Father", "Mother"), spouse("PGF", "PGM"), spouse("MGF", "MGM")]
      )
    )
    let result = FamilyGraphLayoutCore.buildSemanticOrder(
      from: normalized,
      generations: FamilyGraphLayoutCore.solveGenerations(normalized)
    )
    let group = FamilyGraphLayoutCore.buildParentGroups(from: normalized).first {
      $0.parentIDs == ["PGF", "PGM"]
    }
    let graph = try XCTUnwrap(result.unitGraph)
    let paternal = try XCTUnwrap(graph.unitIDByPersonID["PGF"])
    let uncle = try XCTUnwrap(graph.unitIDByPersonID["FatherSibling"])
    let maternal = try XCTUnwrap(graph.unitIDByPersonID["MGF"])

    XCTAssertEqual(group?.childIDs, ["Father", "FatherSibling"])
    XCTAssertTrue(hasBlock(result, containing: [paternal, uncle], excluding: [maternal]))
  }

  func testSpouseSideParentsAreASeparateRootBlock() throws {
    let result = order(
      visible: ["Self", "Spouse", "SelfParent", "SpouseParent1", "SpouseParent2"],
      parents: [
        parent("SelfParent", "Self"),
        parent("SpouseParent1", "Spouse"), parent("SpouseParent2", "Spouse"),
      ],
      spouses: [spouse("Self", "Spouse"), spouse("SpouseParent1", "SpouseParent2")]
    )
    let graph = try XCTUnwrap(result.unitGraph)
    let own = try XCTUnwrap(graph.unitIDByPersonID["SelfParent"])
    let spouseSide = try XCTUnwrap(graph.unitIDByPersonID["SpouseParent1"])

    XCTAssertTrue(hasBlock(result, containing: [own], excluding: [spouseSide]))
    XCTAssertTrue(hasBlock(result, containing: [spouseSide], excluding: [own]))
  }

  func testGreatGrandparentsProduceNestedContiguity() throws {
    var parents = [
      parent("Father", "Self"), parent("Mother", "Self"),
      parent("PGF", "Father"), parent("PGM", "Father"),
      parent("MGF", "Mother"), parent("MGM", "Mother"),
    ]
    parents += [
      parent("PGF1", "PGF"), parent("PGF2", "PGF"),
      parent("PGM1", "PGM"), parent("PGM2", "PGM"),
      parent("MGF1", "MGF"), parent("MGF2", "MGF"),
      parent("MGM1", "MGM"), parent("MGM2", "MGM"),
    ]
    let visible = Set(parents.flatMap { [$0.parentID, $0.childID] })
    let result = order(
      visible: visible,
      parents: parents,
      spouses: [
        spouse("Father", "Mother"), spouse("PGF", "PGM"), spouse("MGF", "MGM"),
        spouse("PGF1", "PGF2"), spouse("PGM1", "PGM2"),
        spouse("MGF1", "MGF2"), spouse("MGM1", "MGM2"),
      ]
    )
    let graph = try XCTUnwrap(result.unitGraph)
    let paternalGreat = Set(["PGF1", "PGM1"].compactMap { graph.unitIDByPersonID[$0] })
    let maternalGreat = Set(["MGF1", "MGM1"].compactMap { graph.unitIDByPersonID[$0] })
    let constraints = result.generationOrderings[-3]!.contiguityConstraints

    XCTAssertTrue(constraints.contains { $0.memberUnitIDs == paternalGreat })
    XCTAssertTrue(constraints.contains { $0.memberUnitIDs == maternalGreat })
    XCTAssertTrue(result.blocks.contains { !$0.childBlockIDs.isEmpty })
  }

  func testOverlappingBranchIsMergedAndPeopleAreNeverDuplicated() throws {
    let result = order(
      visible: ["Self", "A", "B", "Shared"],
      parents: [
        parent("A", "Self"), parent("B", "Self"),
        parent("Shared", "A"), parent("Shared", "B"),
      ]
    )
    let graph = try XCTUnwrap(result.unitGraph)
    let sharedRootBlock = result.blocks.first {
      $0.memberUnitIDs == graph.units.subtracting([graph.rootUnitID])
    }

    XCTAssertEqual(graph.unitIDByPersonID.count, 4)
    XCTAssertEqual(Set(graph.unitIDByPersonID.values).count, 4)
    XCTAssertEqual(sharedRootBlock?.isShared, true)
  }

  func testSymmetricPeersAreSwapEquivalentWithoutAbsoluteSide() {
    let result = canonicalGrandparents()
    let buckets = result.generationOrderings[-2]!.orderingBuckets

    XCTAssertTrue(buckets.contains { $0.isSwapEquivalent && $0.blockIDs.count == 2 })
  }

  func testGenerationConflictReturnsNoFabricatedSemanticOrder() {
    let result = order(
      rootID: "A",
      visible: ["A", "B", "C"],
      parents: [parent("A", "B"), parent("B", "C"), parent("A", "C")]
    )

    XCTAssertNil(result.unitGraph)
    XCTAssertTrue(result.blocks.isEmpty)
    XCTAssertTrue(result.generationOrderings.isEmpty)
    XCTAssertFalse(result.isGenerationConsistent)
  }

  private func hasBlock(
    _ result: LayoutSemanticOrder<ID>,
    containing included: Set<LayoutUnitID<ID>>,
    excluding excluded: Set<LayoutUnitID<ID>>
  ) -> Bool {
    result.blocks.contains {
      included.isSubset(of: $0.memberUnitIDs)
        && excluded.isDisjoint(with: $0.memberUnitIDs)
    }
  }
}
