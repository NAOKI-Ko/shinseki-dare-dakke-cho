import Foundation

/// A stable semantic identity derived only from unit membership. It has no left/right meaning.
struct LayoutUnitID<PersonID: Hashable>: Hashable {
  let personIDs: Set<PersonID>
}

struct LayoutUnitEdge<PersonID: Hashable>: Hashable {
  let parentUnitID: LayoutUnitID<PersonID>
  let childUnitID: LayoutUnitID<PersonID>
}

/// The normalized relationship graph after spouse pairs have been contracted.
struct LayoutUnitGraph<PersonID: Hashable>: Equatable {
  let rootUnitID: LayoutUnitID<PersonID>
  let units: Set<LayoutUnitID<PersonID>>
  let unitIDByPersonID: [PersonID: LayoutUnitID<PersonID>]
  let parentChildEdges: Set<LayoutUnitEdge<PersonID>>
  /// Parent/child edges inside an atomic spouse unit are explicitly suppressed.
  let suppressedSelfEdges: Set<GraphLayoutParentChildEdge<PersonID>>
}

struct LayoutFamilyBlockID<PersonID: Hashable>: Hashable {
  let memberUnitIDs: Set<LayoutUnitID<PersonID>>
}

/// A separable portion of the contracted graph. Child IDs describe strict nesting.
struct LayoutFamilyBlock<PersonID: Hashable>: Hashable {
  let id: LayoutFamilyBlockID<PersonID>
  let memberUnitIDs: Set<LayoutUnitID<PersonID>>
  let memberPersonIDs: Set<PersonID>
  let unitIDsByGeneration: [Int: Set<LayoutUnitID<PersonID>>]
  let childBlockIDs: Set<LayoutFamilyBlockID<PersonID>>
  let separationGatewayUnitIDs: Set<LayoutUnitID<PersonID>>
  /// True when multiple boundary paths enter the block, or overlapping candidates were merged.
  let isShared: Bool
}

struct LayoutContiguityConstraint<PersonID: Hashable>: Hashable {
  enum Source: Hashable {
    case atomicUnit(LayoutUnitID<PersonID>)
    case familyBlock(LayoutFamilyBlockID<PersonID>)
  }

  let generation: Int
  let memberUnitIDs: Set<LayoutUnitID<PersonID>>
  let source: Source
}

/// Peers in a bucket have no semantic left/right order and may be swapped as whole blocks.
struct LayoutOrderingBucket<PersonID: Hashable>: Hashable {
  let blockIDs: Set<LayoutFamilyBlockID<PersonID>>
  let isSwapEquivalent: Bool
}

struct LayoutGenerationOrdering<PersonID: Hashable>: Equatable {
  let generation: Int
  let unitIDs: Set<LayoutUnitID<PersonID>>
  let contiguityConstraints: Set<LayoutContiguityConstraint<PersonID>>
  let orderingBuckets: Set<LayoutOrderingBucket<PersonID>>
}

struct LayoutSemanticOrder<PersonID: Hashable>: Equatable {
  let unitGraph: LayoutUnitGraph<PersonID>?
  let blocks: Set<LayoutFamilyBlock<PersonID>>
  let generationOrderings: [Int: LayoutGenerationOrdering<PersonID>]
  let diagnostics: Set<GraphLayoutDiagnostic<PersonID>>

  var isGenerationConsistent: Bool {
    !diagnostics.contains {
      if case .inconsistentGeneration = $0 { return true }
      return false
    }
  }
}

extension FamilyGraphLayoutCore {
  static func buildSemanticOrder<PersonID: Hashable>(
    from input: NormalizedGraphLayoutInput<PersonID>,
    generations: GraphGenerationSolution<PersonID>,
    useSimpleChainFastPath: Bool = true
  ) -> LayoutSemanticOrder<PersonID> {
    guard generations.isConsistent, !generations.generations.isEmpty,
      generations.generations[input.rootID] != nil
    else {
      return LayoutSemanticOrder(
        unitGraph: nil,
        blocks: [],
        generationOrderings: [:],
        diagnostics: generations.diagnostics
      )
    }

    let unitResult = buildCoupleUnits(from: input, generations: generations)
    let unitGraph = buildUnitGraph(
      from: input,
      units: unitResult.units,
      rootID: input.rootID
    )
    if useSimpleChainFastPath, isSimpleGenerationChain(input, generations: generations) {
      return LayoutSemanticOrder(
        unitGraph: unitGraph,
        blocks: [],
        generationOrderings: buildSimpleChainGenerationOrderings(
          unitGraph: unitGraph,
          generations: generations.generations
        ),
        diagnostics: unitResult.diagnostics
      )
    }
    let rawBlocks = extractBlockCandidates(from: unitGraph)
    let mergedBlocks = mergeCrossingBlocks(rawBlocks)
    let blocks = materializeBlocks(
      mergedBlocks,
      unitGraph: unitGraph,
      generations: generations.generations
    )
    let orderings = buildGenerationOrderings(
      unitGraph: unitGraph,
      blocks: blocks,
      generations: generations.generations
    )

    return LayoutSemanticOrder(
      unitGraph: unitGraph,
      blocks: blocks,
      generationOrderings: orderings,
      diagnostics: unitResult.diagnostics
    )
  }

  private struct BlockCandidate<PersonID: Hashable> {
    var unitIDs: Set<LayoutUnitID<PersonID>>
    var isShared: Bool
    var gatewayUnitIDs: Set<LayoutUnitID<PersonID>>
  }

  static func isSimpleGenerationChain<PersonID: Hashable>(
    _ input: NormalizedGraphLayoutInput<PersonID>,
    generations: GraphGenerationSolution<PersonID>
  ) -> Bool {
    let people = input.visiblePersonIDs
    guard !people.isEmpty, people.contains(input.rootID), input.spouseEdges.isEmpty,
      generations.isConsistent, generations.generations.count == people.count,
      input.parentChildEdges.count == people.count - 1
    else { return false }

    var parentCounts: [PersonID: Int] = [:]
    var childCounts: [PersonID: Int] = [:]
    var adjacency: [PersonID: Set<PersonID>] = [:]
    for edge in input.parentChildEdges {
      parentCounts[edge.childID, default: 0] += 1
      childCounts[edge.parentID, default: 0] += 1
      guard parentCounts[edge.childID, default: 0] <= 1,
        childCounts[edge.parentID, default: 0] <= 1
      else { return false }
      adjacency[edge.parentID, default: []].insert(edge.childID)
      adjacency[edge.childID, default: []].insert(edge.parentID)
    }

    var visited: Set<PersonID> = [input.rootID]
    var queue = [input.rootID]
    var index = 0
    while index < queue.count {
      let personID = queue[index]
      index += 1
      for neighbor in adjacency[personID, default: []] where visited.insert(neighbor).inserted {
        queue.append(neighbor)
      }
    }
    guard visited == people else { return false }

    var countsByGeneration: [Int: Int] = [:]
    for generation in generations.generations.values {
      countsByGeneration[generation, default: 0] += 1
    }
    return countsByGeneration.values.allSatisfy { $0 == 1 }
  }

  private static func buildSimpleChainGenerationOrderings<PersonID: Hashable>(
    unitGraph: LayoutUnitGraph<PersonID>,
    generations: [PersonID: Int]
  ) -> [Int: LayoutGenerationOrdering<PersonID>] {
    Dictionary(
      uniqueKeysWithValues: unitGraph.units.compactMap { unitID in
        guard let personID = unitID.personIDs.first,
          let generation = generations[personID]
        else { return nil }
        return (
          generation,
          LayoutGenerationOrdering(
            generation: generation,
            unitIDs: [unitID],
            contiguityConstraints: [],
            orderingBuckets: []
          )
        )
      }
    )
  }

  private static func buildUnitGraph<PersonID: Hashable>(
    from input: NormalizedGraphLayoutInput<PersonID>,
    units: Set<LayoutCoupleUnit<PersonID>>,
    rootID: PersonID
  ) -> LayoutUnitGraph<PersonID> {
    let unitIDs = Set(units.map { LayoutUnitID(personIDs: $0.memberIDs) })
    var unitByPerson: [PersonID: LayoutUnitID<PersonID>] = [:]
    for unitID in unitIDs {
      for personID in unitID.personIDs {
        unitByPerson[personID] = unitID
      }
    }

    var edges = Set<LayoutUnitEdge<PersonID>>()
    var selfEdges = Set<GraphLayoutParentChildEdge<PersonID>>()
    for edge in input.parentChildEdges {
      guard let parentUnit = unitByPerson[edge.parentID],
        let childUnit = unitByPerson[edge.childID]
      else { continue }
      guard parentUnit != childUnit else {
        selfEdges.insert(edge)
        continue
      }
      edges.insert(LayoutUnitEdge(parentUnitID: parentUnit, childUnitID: childUnit))
    }

    return LayoutUnitGraph(
      rootUnitID: unitByPerson[rootID]!,
      units: unitIDs,
      unitIDByPersonID: unitByPerson,
      parentChildEdges: edges,
      suppressedSelfEdges: selfEdges
    )
  }

  private static func extractBlockCandidates<PersonID: Hashable>(
    from graph: LayoutUnitGraph<PersonID>
  ) -> [BlockCandidate<PersonID>] {
    var adjacency: [LayoutUnitID<PersonID>: Set<LayoutUnitID<PersonID>>] = [:]
    for edge in graph.parentChildEdges {
      adjacency[edge.parentUnitID, default: []].insert(edge.childUnitID)
      adjacency[edge.childUnitID, default: []].insert(edge.parentUnitID)
    }

    let reachable = connectedComponent(
      startingAt: graph.rootUnitID,
      excluding: nil,
      adjacency: adjacency
    )
    var candidatesByMembers:
      [Set<LayoutUnitID<PersonID>>: (isShared: Bool, gateways: Set<LayoutUnitID<PersonID>>)] = [:]

    for gateway in reachable {
      var unseen = reachable.subtracting([gateway])
      var components: [Set<LayoutUnitID<PersonID>>] = []
      while let seed = unseen.first {
        let component = connectedComponent(
          startingAt: seed,
          excluding: gateway,
          adjacency: adjacency
        )
        components.append(component)
        unseen.subtract(component)
      }

      for component in components {
        if gateway != graph.rootUnitID && component.contains(graph.rootUnitID) {
          continue
        }
        let boundaryCount = adjacency[gateway, default: []].intersection(component).count
        let existing = candidatesByMembers[component] ?? (false, [])
        candidatesByMembers[component] = (
          existing.isShared || boundaryCount > 1,
          existing.gateways.union([gateway])
        )
      }
    }

    return candidatesByMembers.map {
      BlockCandidate(
        unitIDs: $0.key,
        isShared: $0.value.isShared,
        gatewayUnitIDs: $0.value.gateways
      )
    }
  }

  private static func connectedComponent<PersonID: Hashable>(
    startingAt start: LayoutUnitID<PersonID>,
    excluding excluded: LayoutUnitID<PersonID>?,
    adjacency: [LayoutUnitID<PersonID>: Set<LayoutUnitID<PersonID>>]
  ) -> Set<LayoutUnitID<PersonID>> {
    var visited: Set<LayoutUnitID<PersonID>> = [start]
    var queue = [start]
    var index = 0
    while index < queue.count {
      let current = queue[index]
      index += 1
      for neighbor in adjacency[current, default: []]
      where neighbor != excluded && !visited.contains(neighbor) {
        visited.insert(neighbor)
        queue.append(neighbor)
      }
    }
    return visited
  }

  /// Crossing ownership cannot be represented by two independent contiguous blocks.
  /// Merge such candidates and mark the union shared; disjoint and nested blocks remain intact.
  private static func mergeCrossingBlocks<PersonID: Hashable>(
    _ input: [BlockCandidate<PersonID>]
  ) -> [BlockCandidate<PersonID>] {
    var blocks = input
    var didMerge = true
    while didMerge {
      didMerge = false
      outer: for firstIndex in blocks.indices {
        for secondIndex in blocks.indices where secondIndex > firstIndex {
          let first = blocks[firstIndex].unitIDs
          let second = blocks[secondIndex].unitIDs
          let overlap = first.intersection(second)
          guard !overlap.isEmpty, !first.isSubset(of: second), !second.isSubset(of: first)
          else { continue }
          let merged = BlockCandidate(
            unitIDs: first.union(second),
            isShared: true,
            gatewayUnitIDs: blocks[firstIndex].gatewayUnitIDs.union(
              blocks[secondIndex].gatewayUnitIDs
            )
          )
          blocks.remove(at: secondIndex)
          blocks.remove(at: firstIndex)
          blocks.append(merged)
          didMerge = true
          break outer
        }
      }
    }
    return blocks
  }

  private static func materializeBlocks<PersonID: Hashable>(
    _ candidates: [BlockCandidate<PersonID>],
    unitGraph: LayoutUnitGraph<PersonID>,
    generations: [PersonID: Int]
  ) -> Set<LayoutFamilyBlock<PersonID>> {
    let unique = Dictionary(
      candidates.map { ($0.unitIDs, ($0.isShared, $0.gatewayUnitIDs)) }
    ) { first, second in
      (first.0 || second.0, first.1.union(second.1))
    }
    let childSetsByParent = immediateChildSets(in: Set(unique.keys))
    return Set(
      unique.map { memberUnits, metadata in
        var byGeneration: [Int: Set<LayoutUnitID<PersonID>>] = [:]
        for unitID in memberUnits {
          guard let personID = unitID.personIDs.first,
            let generation = generations[personID]
          else { continue }
          byGeneration[generation, default: []].insert(unitID)
        }
        return LayoutFamilyBlock(
          id: LayoutFamilyBlockID(memberUnitIDs: memberUnits),
          memberUnitIDs: memberUnits,
          memberPersonIDs: Set(memberUnits.flatMap(\.personIDs)),
          unitIDsByGeneration: byGeneration,
          childBlockIDs: Set(
            childSetsByParent[memberUnits, default: []].map {
              LayoutFamilyBlockID(memberUnitIDs: $0)
            }),
          separationGatewayUnitIDs: metadata.1,
          isShared: metadata.0
        )
      })
  }

  /// Crossing candidates have already been merged, so the remaining block sets are
  /// laminar: every overlapping pair is nested. Indexing by one member therefore
  /// finds every ancestor, and the smallest larger set is the unique direct parent.
  private static func immediateChildSets<PersonID: Hashable>(
    in blockSets: Set<Set<LayoutUnitID<PersonID>>>
  ) -> [Set<LayoutUnitID<PersonID>>: Set<Set<LayoutUnitID<PersonID>>>] {
    var blocksByUnit: [LayoutUnitID<PersonID>: [Set<LayoutUnitID<PersonID>>]] = [:]
    for block in blockSets {
      for unitID in block {
        blocksByUnit[unitID, default: []].append(block)
      }
    }

    var childrenByParent: [Set<LayoutUnitID<PersonID>>: Set<Set<LayoutUnitID<PersonID>>>] = [:]
    for child in blockSets {
      guard let representative = child.first else { continue }
      let parent = blocksByUnit[representative, default: []]
        .filter { $0.count > child.count }
        .min { $0.count < $1.count }
      if let parent {
        childrenByParent[parent, default: []].insert(child)
      }
    }
    return childrenByParent
  }

  private static func buildGenerationOrderings<PersonID: Hashable>(
    unitGraph: LayoutUnitGraph<PersonID>,
    blocks: Set<LayoutFamilyBlock<PersonID>>,
    generations: [PersonID: Int]
  ) -> [Int: LayoutGenerationOrdering<PersonID>] {
    var unitsByGeneration: [Int: Set<LayoutUnitID<PersonID>>] = [:]
    for unitID in unitGraph.units {
      guard let personID = unitID.personIDs.first,
        let generation = generations[personID]
      else { continue }
      unitsByGeneration[generation, default: []].insert(unitID)
    }

    var constraintsByGeneration: [Int: Set<LayoutContiguityConstraint<PersonID>>] = [:]
    for (generation, units) in unitsByGeneration {
      for unitID in units where unitID.personIDs.count == 2 {
        constraintsByGeneration[generation, default: []].insert(
          LayoutContiguityConstraint(
            generation: generation,
            memberUnitIDs: [unitID],
            source: .atomicUnit(unitID)
          )
        )
      }
    }
    for block in blocks {
      for (generation, units) in block.unitIDsByGeneration where !units.isEmpty {
        constraintsByGeneration[generation, default: []].insert(
          LayoutContiguityConstraint(
            generation: generation,
            memberUnitIDs: units,
            source: .familyBlock(block.id)
          )
        )
      }
    }

    var blocksByGateway: [LayoutUnitID<PersonID>: Set<LayoutFamilyBlockID<PersonID>>] = [:]
    for block in blocks {
      for gateway in block.separationGatewayUnitIDs {
        blocksByGateway[gateway, default: []].insert(block.id)
      }
    }

    return Dictionary(
      uniqueKeysWithValues: unitsByGeneration.map { generation, units in
        let relevantBlockIDs = Set(
          blocks.filter { !$0.unitIDsByGeneration[generation, default: []].isEmpty }.map(\.id)
        )
        let buckets = Set<LayoutOrderingBucket<PersonID>>(
          blocksByGateway.values.compactMap { peerIDs -> LayoutOrderingBucket<PersonID>? in
            let relevantPeers = peerIDs.intersection(relevantBlockIDs)
            guard !relevantPeers.isEmpty else { return nil }
            return LayoutOrderingBucket(
              blockIDs: relevantPeers,
              isSwapEquivalent: relevantPeers.count > 1
            )
          })
        return (
          generation,
          LayoutGenerationOrdering(
            generation: generation,
            unitIDs: units,
            contiguityConstraints: constraintsByGeneration[generation, default: []],
            orderingBuckets: buckets
          )
        )
      })
  }
}
