import Foundation

/// A relationship component discovered from one root, represented only by layout IDs.
struct FamilyGraphLayoutTopology: Equatable {
  let rootID: PersistentModelIDBox
  let personIDs: Set<PersistentModelIDBox>
  let parentChildEdges: Set<GraphLayoutParentChildEdge<PersistentModelIDBox>>
  let spouseEdges: Set<GraphLayoutSpouseEdge<PersistentModelIDBox>>

  var input: GraphLayoutInput<PersistentModelIDBox> {
    GraphLayoutInput(
      rootID: rootID,
      visiblePersonIDs: personIDs,
      parentChildEdges: Array(parentChildEdges),
      spouseEdges: Array(spouseEdges)
    )
  }
}

/// A full reachable layout derived for one FamilyGraph session.
struct FamilyGraphLayoutUniverse: Equatable {
  let rootID: PersistentModelIDBox
  let input: GraphLayoutInput<PersistentModelIDBox>
  let result: GraphHorizontalLayoutResult<PersistentModelIDBox>
}

struct FamilyGraphLayoutUniverseFailure: Equatable {
  let rootID: PersistentModelIDBox
  let input: GraphLayoutInput<PersistentModelIDBox>
  let diagnostics: Set<GraphLayoutDiagnostic<PersistentModelIDBox>>
}

enum FamilyGraphLayoutUniverseState: Equatable {
  case ready(FamilyGraphLayoutUniverse)
  case inconsistent(FamilyGraphLayoutUniverseFailure)
}

enum FamilyGraphLayoutUniverseBuilder {
  static func build(from root: Person) -> FamilyGraphLayoutUniverseState {
    let topology = discover(from: root)
    let input = topology.input
    let result = FamilyGraphHorizontalLayout.layout(input)
    let hasGenerationContradiction = result.diagnostics.contains { diagnostic in
      if case .inconsistentGeneration = diagnostic { return true }
      return false
    }

    guard !hasGenerationContradiction,
      result.positionsByPersonID.count == topology.personIDs.count
    else {
      return .inconsistent(
        FamilyGraphLayoutUniverseFailure(
          rootID: topology.rootID,
          input: input,
          diagnostics: result.diagnostics
        )
      )
    }

    return .ready(
      FamilyGraphLayoutUniverse(
        rootID: topology.rootID,
        input: input,
        result: result
      )
    )
  }

  static func discover(from root: Person) -> FamilyGraphLayoutTopology {
    let rootID = PersistentModelIDBox(root.persistentModelID)
    var peopleByID: [PersistentModelIDBox: Person] = [rootID: root]
    var visited: Set<PersistentModelIDBox> = []
    var queue = [rootID]
    var queueIndex = 0
    var parentChildEdges: Set<GraphLayoutParentChildEdge<PersistentModelIDBox>> = []
    var spouseEdges: Set<GraphLayoutSpouseEdge<PersistentModelIDBox>> = []

    while queueIndex < queue.count {
      let currentID = queue[queueIndex]
      queueIndex += 1
      guard visited.insert(currentID).inserted,
        let current = peopleByID[currentID]
      else { continue }

      for parent in current.parents {
        let parentID = enqueue(parent, peopleByID: &peopleByID, queue: &queue)
        parentChildEdges.insert(
          GraphLayoutParentChildEdge(parentID: parentID, childID: currentID)
        )
      }

      for child in current.children {
        let childID = enqueue(child, peopleByID: &peopleByID, queue: &queue)
        parentChildEdges.insert(
          GraphLayoutParentChildEdge(parentID: currentID, childID: childID)
        )
      }

      if let spouse = current.spouse {
        let spouseID = enqueue(spouse, peopleByID: &peopleByID, queue: &queue)
        spouseEdges.insert(GraphLayoutSpouseEdge(currentID, spouseID))
      }
    }

    return FamilyGraphLayoutTopology(
      rootID: rootID,
      personIDs: Set(peopleByID.keys),
      parentChildEdges: parentChildEdges,
      spouseEdges: spouseEdges
    )
  }

  private static func enqueue(
    _ person: Person,
    peopleByID: inout [PersistentModelIDBox: Person],
    queue: inout [PersistentModelIDBox]
  ) -> PersistentModelIDBox {
    let id = PersistentModelIDBox(person.persistentModelID)
    if peopleByID[id] == nil {
      peopleByID[id] = person
      queue.append(id)
    }
    return id
  }
}
