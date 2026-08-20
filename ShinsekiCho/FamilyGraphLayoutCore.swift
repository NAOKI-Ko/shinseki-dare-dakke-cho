import Foundation

/// A directed parent-to-child relationship used only by semantic layout.
struct GraphLayoutParentChildEdge<PersonID: Hashable>: Hashable {
  let parentID: PersonID
  let childID: PersonID
}

/// An undirected spouse relationship. The set deliberately has no left/right meaning.
struct GraphLayoutSpouseEdge<PersonID: Hashable>: Hashable {
  let personIDs: Set<PersonID>

  init(_ firstID: PersonID, _ secondID: PersonID) {
    personIDs = [firstID, secondID]
  }
}

struct GraphLayoutInput<PersonID: Hashable>: Equatable {
  let rootID: PersonID
  let visiblePersonIDs: Set<PersonID>
  let parentChildEdges: [GraphLayoutParentChildEdge<PersonID>]
  let spouseEdges: [GraphLayoutSpouseEdge<PersonID>]

  init(
    rootID: PersonID,
    visiblePersonIDs: Set<PersonID>,
    parentChildEdges: [GraphLayoutParentChildEdge<PersonID>] = [],
    spouseEdges: [GraphLayoutSpouseEdge<PersonID>] = []
  ) {
    self.rootID = rootID
    self.visiblePersonIDs = visiblePersonIDs
    self.parentChildEdges = parentChildEdges
    self.spouseEdges = spouseEdges
  }
}

enum GraphLayoutMalformedInputReason: Hashable {
  case rootIsNotVisible
}

enum GraphLayoutGenerationConstraint<PersonID: Hashable>: Hashable {
  case parentChild(GraphLayoutParentChildEdge<PersonID>)
  case spouse(GraphLayoutSpouseEdge<PersonID>)
}

/// Machine-readable diagnostics. Associated sets keep symmetric graphs unordered.
enum GraphLayoutDiagnostic<PersonID: Hashable>: Hashable {
  case inconsistentGeneration(
    personIDs: Set<PersonID>,
    constraints: Set<GraphLayoutGenerationConstraint<PersonID>>
  )
  case disconnectedVisibleComponent(personIDs: Set<PersonID>)
  case invalidSelfEdge(personID: PersonID, kind: GraphLayoutEdgeKind)
  case invalidSpouseConstraint(
    personIDs: Set<PersonID>,
    spouseEdges: Set<GraphLayoutSpouseEdge<PersonID>>
  )
  case malformedInput(GraphLayoutMalformedInputReason)
}

enum GraphLayoutEdgeKind: Hashable {
  case parentChild
  case spouse
}

struct NormalizedGraphLayoutInput<PersonID: Hashable>: Equatable {
  let rootID: PersonID
  let visiblePersonIDs: Set<PersonID>
  let parentChildEdges: Set<GraphLayoutParentChildEdge<PersonID>>
  let spouseEdges: Set<GraphLayoutSpouseEdge<PersonID>>
  let diagnostics: Set<GraphLayoutDiagnostic<PersonID>>
}

struct GraphGenerationSolution<PersonID: Hashable>: Equatable {
  /// Empty for the root component when its constraints are contradictory.
  let generations: [PersonID: Int]
  let diagnostics: Set<GraphLayoutDiagnostic<PersonID>>

  var isConsistent: Bool {
    !diagnostics.contains { diagnostic in
      if case .inconsistentGeneration = diagnostic { return true }
      return false
    }
  }
}

struct LayoutCoupleUnit<PersonID: Hashable>: Hashable {
  /// One member for a singleton, two for a valid visible spouse pair.
  let memberIDs: Set<PersonID>

  var isCouple: Bool { memberIDs.count == 2 }
}

struct LayoutCoupleUnitResult<PersonID: Hashable>: Equatable {
  let units: Set<LayoutCoupleUnit<PersonID>>
  let diagnostics: Set<GraphLayoutDiagnostic<PersonID>>
}

struct LayoutParentGroup<PersonID: Hashable>: Hashable {
  let parentIDs: Set<PersonID>
  let childIDs: Set<PersonID>
}

private struct GraphLayoutGenerationNeighbor<PersonID: Hashable>: Hashable {
  let personID: PersonID
  let generationDelta: Int
}

enum FamilyGraphLayoutCore {
  static func normalize<PersonID: Hashable>(
    _ input: GraphLayoutInput<PersonID>
  ) -> NormalizedGraphLayoutInput<PersonID> {
    var diagnostics = Set<GraphLayoutDiagnostic<PersonID>>()
    if !input.visiblePersonIDs.contains(input.rootID) {
      diagnostics.insert(.malformedInput(.rootIsNotVisible))
    }

    var parentChildEdges = Set<GraphLayoutParentChildEdge<PersonID>>()
    for edge in input.parentChildEdges {
      guard edge.parentID != edge.childID else {
        diagnostics.insert(
          .invalidSelfEdge(personID: edge.parentID, kind: .parentChild)
        )
        continue
      }
      guard input.visiblePersonIDs.contains(edge.parentID),
        input.visiblePersonIDs.contains(edge.childID)
      else { continue }
      parentChildEdges.insert(edge)
    }

    var spouseEdges = Set<GraphLayoutSpouseEdge<PersonID>>()
    for edge in input.spouseEdges {
      guard edge.personIDs.count == 2 else {
        if let personID = edge.personIDs.first {
          diagnostics.insert(.invalidSelfEdge(personID: personID, kind: .spouse))
        }
        continue
      }
      guard edge.personIDs.isSubset(of: input.visiblePersonIDs) else { continue }
      spouseEdges.insert(edge)
    }

    var spouseEdgesByPerson: [PersonID: Set<GraphLayoutSpouseEdge<PersonID>>] = [:]
    for edge in spouseEdges {
      for personID in edge.personIDs {
        spouseEdgesByPerson[personID, default: []].insert(edge)
      }
    }
    for (personID, edges) in spouseEdgesByPerson where edges.count > 1 {
      diagnostics.insert(
        .invalidSpouseConstraint(personIDs: [personID], spouseEdges: edges)
      )
    }

    let parentChildPairs = Set(
      parentChildEdges.map {
        GraphLayoutSpouseEdge($0.parentID, $0.childID)
      })
    for edge in spouseEdges where parentChildPairs.contains(edge) {
      diagnostics.insert(
        .invalidSpouseConstraint(personIDs: edge.personIDs, spouseEdges: [edge])
      )
    }

    return NormalizedGraphLayoutInput(
      rootID: input.rootID,
      visiblePersonIDs: input.visiblePersonIDs,
      parentChildEdges: parentChildEdges,
      spouseEdges: spouseEdges,
      diagnostics: diagnostics
    )
  }

  static func solveGenerations<PersonID: Hashable>(
    _ input: NormalizedGraphLayoutInput<PersonID>
  ) -> GraphGenerationSolution<PersonID> {
    var diagnostics = input.diagnostics
    guard input.visiblePersonIDs.contains(input.rootID) else {
      return GraphGenerationSolution(generations: [:], diagnostics: diagnostics)
    }

    var neighbors: [PersonID: Set<GraphLayoutGenerationNeighbor<PersonID>>] = [:]
    for edge in input.parentChildEdges {
      neighbors[edge.parentID, default: []].insert(
        GraphLayoutGenerationNeighbor(personID: edge.childID, generationDelta: 1)
      )
      neighbors[edge.childID, default: []].insert(
        GraphLayoutGenerationNeighbor(personID: edge.parentID, generationDelta: -1)
      )
    }
    for edge in input.spouseEdges {
      let people = Array(edge.personIDs)
      guard people.count == 2 else { continue }
      neighbors[people[0], default: []].insert(
        GraphLayoutGenerationNeighbor(personID: people[1], generationDelta: 0)
      )
      neighbors[people[1], default: []].insert(
        GraphLayoutGenerationNeighbor(personID: people[0], generationDelta: 0)
      )
    }

    var candidateGenerations: [PersonID: Int] = [input.rootID: 0]
    var queue = [input.rootID]
    var queueIndex = 0
    var hasContradiction = false

    while queueIndex < queue.count {
      let current = queue[queueIndex]
      queueIndex += 1
      guard let currentGeneration = candidateGenerations[current] else { continue }

      for neighbor in neighbors[current, default: []] {
        let requiredGeneration = currentGeneration + neighbor.generationDelta
        if let existingGeneration = candidateGenerations[neighbor.personID] {
          if existingGeneration != requiredGeneration {
            hasContradiction = true
          }
        } else {
          candidateGenerations[neighbor.personID] = requiredGeneration
          queue.append(neighbor.personID)
        }
      }
    }

    let rootComponent = Set(candidateGenerations.keys)
    let disconnected = input.visiblePersonIDs.subtracting(rootComponent)
    if !disconnected.isEmpty {
      diagnostics.insert(.disconnectedVisibleComponent(personIDs: disconnected))
    }

    if hasContradiction {
      var constraints = Set<GraphLayoutGenerationConstraint<PersonID>>()
      constraints.formUnion(
        input.parentChildEdges
          .filter {
            rootComponent.contains($0.parentID) && rootComponent.contains($0.childID)
          }
          .map(GraphLayoutGenerationConstraint.parentChild)
      )
      constraints.formUnion(
        input.spouseEdges
          .filter { $0.personIDs.isSubset(of: rootComponent) }
          .map(GraphLayoutGenerationConstraint.spouse)
      )
      diagnostics.insert(
        .inconsistentGeneration(personIDs: rootComponent, constraints: constraints)
      )
      // A contradictory component has no valid generation function. Returning no
      // values prevents traversal order from becoming an accidental first-wins rule.
      return GraphGenerationSolution(generations: [:], diagnostics: diagnostics)
    }

    return GraphGenerationSolution(
      generations: candidateGenerations,
      diagnostics: diagnostics
    )
  }

  static func buildCoupleUnits<PersonID: Hashable>(
    from input: NormalizedGraphLayoutInput<PersonID>,
    generations: GraphGenerationSolution<PersonID>
  ) -> LayoutCoupleUnitResult<PersonID> {
    var spouseDegree: [PersonID: Int] = [:]
    for edge in input.spouseEdges {
      for personID in edge.personIDs {
        spouseDegree[personID, default: 0] += 1
      }
    }

    var units = Set<LayoutCoupleUnit<PersonID>>()
    var assigned = Set<PersonID>()
    for edge in input.spouseEdges {
      let people = Array(edge.personIDs)
      guard people.count == 2,
        spouseDegree[people[0]] == 1,
        spouseDegree[people[1]] == 1,
        let firstGeneration = generations.generations[people[0]],
        let secondGeneration = generations.generations[people[1]],
        firstGeneration == secondGeneration
      else { continue }

      units.insert(LayoutCoupleUnit(memberIDs: edge.personIDs))
      assigned.formUnion(edge.personIDs)
    }

    for personID in input.visiblePersonIDs.subtracting(assigned) {
      units.insert(LayoutCoupleUnit(memberIDs: [personID]))
    }

    return LayoutCoupleUnitResult(
      units: units,
      diagnostics: generations.diagnostics
    )
  }

  static func buildParentGroups<PersonID: Hashable>(
    from input: NormalizedGraphLayoutInput<PersonID>
  ) -> Set<LayoutParentGroup<PersonID>> {
    var parentsByChild: [PersonID: Set<PersonID>] = [:]
    for edge in input.parentChildEdges {
      parentsByChild[edge.childID, default: []].insert(edge.parentID)
    }

    var childrenByParentSet: [Set<PersonID>: Set<PersonID>] = [:]
    for (childID, parentIDs) in parentsByChild {
      childrenByParentSet[parentIDs, default: []].insert(childID)
    }

    return Set(
      childrenByParentSet.map { parentIDs, childIDs in
        LayoutParentGroup(parentIDs: parentIDs, childIDs: childIDs)
      })
  }
}
