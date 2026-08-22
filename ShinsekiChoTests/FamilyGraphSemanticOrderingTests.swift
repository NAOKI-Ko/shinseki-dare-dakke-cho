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

  private func chainInput(count: Int, rootIndex: Int = 0) -> NormalizedGraphLayoutInput<ID> {
    let ids = (0..<count).map { "Chain\($0)" }
    return FamilyGraphLayoutCore.normalize(
      GraphLayoutInput(
        rootID: ids[rootIndex],
        visiblePersonIDs: Set(ids),
        parentChildEdges: (1..<count).map { parent(ids[$0], ids[$0 - 1]) }
      )
    )
  }

  private func isEligible(_ input: NormalizedGraphLayoutInput<ID>) -> Bool {
    FamilyGraphLayoutCore.isSimpleGenerationChain(
      input,
      generations: FamilyGraphLayoutCore.solveGenerations(input)
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

  func testImmediateChildBlocksMatchLegacyContainmentDefinition() {
    let chainIDs = (0..<30).map { "Chain\($0)" }
    let chain = order(
      rootID: chainIDs[0],
      visible: Set(chainIDs),
      parents: (1..<chainIDs.count).map { parent(chainIDs[$0], chainIDs[$0 - 1]) }
    )
    let siblings = order(
      rootID: "Self",
      visible: ["Self", "P", "S1", "S2", "S3", "GP1", "GP2"],
      parents: [
        parent("P", "Self"), parent("P", "S1"), parent("P", "S2"),
        parent("P", "S3"), parent("GP1", "P"), parent("GP2", "P"),
      ],
      spouses: [spouse("GP1", "GP2")]
    )
    let coupleWithChildren = order(
      rootID: "C1",
      visible: ["A", "B", "C1", "C2", "C3", "GP1", "GP2"],
      parents: [
        parent("A", "C1"), parent("B", "C1"),
        parent("A", "C2"), parent("B", "C2"),
        parent("A", "C3"), parent("B", "C3"),
        parent("GP1", "A"), parent("GP2", "A"),
      ],
      spouses: [spouse("A", "B"), spouse("GP1", "GP2")]
    )
    let results = [canonicalGrandparents(), chain, siblings, coupleWithChildren]

    for result in results {
      assertChildBlocksMatchLegacyContainmentDefinition(result)
    }
  }

  func testSimpleGenerationChainFastPathEligibilityIsStrict() {
    XCTAssertTrue(isEligible(chainInput(count: 1)))
    XCTAssertTrue(isEligible(chainInput(count: 2)))
    XCTAssertTrue(isEligible(chainInput(count: 10)))
    XCTAssertTrue(isEligible(chainInput(count: 100)))

    let spouseInput = FamilyGraphLayoutCore.normalize(
      GraphLayoutInput(
        rootID: "A", visiblePersonIDs: ["A", "B"],
        spouseEdges: [spouse("A", "B")]
      )
    )
    XCTAssertFalse(isEligible(spouseInput))

    let siblings = FamilyGraphLayoutCore.normalize(
      GraphLayoutInput(
        rootID: "C1", visiblePersonIDs: ["P", "C1", "C2"],
        parentChildEdges: [parent("P", "C1"), parent("P", "C2")]
      )
    )
    XCTAssertFalse(isEligible(siblings))

    let twoParents = FamilyGraphLayoutCore.normalize(
      GraphLayoutInput(
        rootID: "C", visiblePersonIDs: ["P1", "P2", "C"],
        parentChildEdges: [parent("P1", "C"), parent("P2", "C")]
      )
    )
    XCTAssertFalse(isEligible(twoParents))

    let disconnected = FamilyGraphLayoutCore.normalize(
      GraphLayoutInput(rootID: "A", visiblePersonIDs: ["A", "B"])
    )
    XCTAssertFalse(isEligible(disconnected))

    let contradiction = FamilyGraphLayoutCore.normalize(
      GraphLayoutInput(
        rootID: "A", visiblePersonIDs: ["A", "B"],
        parentChildEdges: [parent("A", "B"), parent("B", "A")]
      )
    )
    XCTAssertFalse(isEligible(contradiction))

    let chain = chainInput(count: 2)
    let sameGeneration = GraphGenerationSolution(
      generations: ["Chain0": 0, "Chain1": 0], diagnostics: []
    )
    XCTAssertFalse(
      FamilyGraphLayoutCore.isSimpleGenerationChain(chain, generations: sameGeneration)
    )
  }

  func testSimpleGenerationChainFastPathMatchesGenericSemanticResult() {
    for rootIndex in [0, 3, 9] {
      let input = chainInput(count: 10, rootIndex: rootIndex)
      let generations = FamilyGraphLayoutCore.solveGenerations(input)
      let fast = FamilyGraphLayoutCore.buildSemanticOrder(
        from: input,
        generations: generations
      )
      let generic = FamilyGraphLayoutCore.buildSemanticOrder(
        from: input,
        generations: generations,
        useSimpleChainFastPath: false
      )
      XCTAssertEqual(fast.unitGraph, generic.unitGraph)
      XCTAssertEqual(fast.diagnostics, generic.diagnostics)
      XCTAssertEqual(
        fast.generationOrderings.mapValues(\.unitIDs),
        generic.generationOrderings.mapValues(\.unitIDs)
      )
      XCTAssertTrue(fast.blocks.isEmpty)
      XCTAssertTrue(
        fast.generationOrderings.values.allSatisfy {
          $0.unitIDs.count == 1
            && $0.contiguityConstraints.isEmpty
            && $0.orderingBuckets.isEmpty
        }
      )
      XCTAssertTrue(
        generic.generationOrderings.values.flatMap(\.contiguityConstraints).allSatisfy {
          $0.memberUnitIDs.count == 1
        }
      )
    }
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

  private func assertChildBlocksMatchLegacyContainmentDefinition(
    _ result: LayoutSemanticOrder<ID>,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    for block in result.blocks {
      let strictSubsets = result.blocks.filter {
        $0.memberUnitIDs != block.memberUnitIDs
          && $0.memberUnitIDs.isSubset(of: block.memberUnitIDs)
      }
      let expectedChildren = strictSubsets.filter { candidate in
        !strictSubsets.contains { other in
          candidate.id != other.id
            && candidate.memberUnitIDs.isSubset(of: other.memberUnitIDs)
        }
      }.map(\.id)
      XCTAssertEqual(block.childBlockIDs, Set(expectedChildren), file: file, line: line)
    }
  }
}
