import Foundation

struct LayoutPosition: Equatable {
  let generation: Int
  let x: Double
}

struct GraphHorizontalLayoutMetrics: Equatable {
  let minimumPersonGap: Double
  let coupleGap: Double
  let familyBlockGap: Double
  let refinementIterations: Int

  static let `default` = GraphHorizontalLayoutMetrics(
    minimumPersonGap: 1,
    coupleGap: 1,
    familyBlockGap: 1,
    refinementIterations: 6
  )
}

struct GraphHorizontalLayoutBounds: Equatable {
  let minimumX: Double
  let maximumX: Double
}

struct LayoutSwapEquivalence<PersonID: Hashable>: Hashable {
  let generation: Int
  let blockIDs: Set<LayoutFamilyBlockID<PersonID>>
}

struct GraphHorizontalLayoutResult<PersonID: Hashable>: Equatable {
  let positionsByPersonID: [PersonID: LayoutPosition]
  let orderedUnitIDsByGeneration: [Int: [LayoutUnitID<PersonID>]]
  let bounds: GraphHorizontalLayoutBounds?
  let diagnostics: Set<GraphLayoutDiagnostic<PersonID>>
  let parentChildCrossingCount: Int
  let swapEquivalences: Set<LayoutSwapEquivalence<PersonID>>
}

enum FamilyGraphHorizontalLayout {
  static func layout<PersonID: Hashable>(
    input: NormalizedGraphLayoutInput<PersonID>,
    generations: GraphGenerationSolution<PersonID>,
    semanticOrder: LayoutSemanticOrder<PersonID>,
    metrics: GraphHorizontalLayoutMetrics = .default
  ) -> GraphHorizontalLayoutResult<PersonID> {
    guard generations.isConsistent, let graph = semanticOrder.unitGraph,
      generations.generations[input.rootID] != nil
    else {
      return emptyResult(diagnostics: semanticOrder.diagnostics)
    }

    var orders = initialOrders(semanticOrder: semanticOrder, graph: graph)
    orders = reduceCrossings(
      orders: orders,
      graph: graph,
      orderings: semanticOrder.generationOrderings,
      iterations: metrics.refinementIterations
    )
    let unitCenters = assignUnitCenters(
      orders: orders,
      graph: graph,
      blocks: semanticOrder.blocks,
      metrics: metrics
    )
    let centered = refineCenters(
      unitCenters,
      orders: orders,
      graph: graph,
      blocks: semanticOrder.blocks,
      metrics: metrics
    )
    let rootOffset = -(centered[graph.rootUnitID] ?? 0)
    let shifted = centered.mapValues { $0 + rootOffset }
    let positions = personPositions(
      unitCenters: shifted,
      orders: orders,
      generations: generations.generations,
      metrics: metrics
    )
    let xs = positions.values.map(\.x)
    let bounds =
      xs.isEmpty
      ? nil
      : GraphHorizontalLayoutBounds(minimumX: xs.min()!, maximumX: xs.max()!)
    let crossingCount = countParentChildCrossings(
      orderedUnitIDsByGeneration: orders,
      edges: graph.parentChildEdges
    )
    let equivalences = Set(
      semanticOrder.generationOrderings.values.flatMap { ordering in
        ordering.orderingBuckets.compactMap { bucket in
          bucket.isSwapEquivalent
            ? LayoutSwapEquivalence(
              generation: ordering.generation,
              blockIDs: bucket.blockIDs
            ) : nil
        }
      })

    return GraphHorizontalLayoutResult(
      positionsByPersonID: positions,
      orderedUnitIDsByGeneration: orders,
      bounds: bounds,
      diagnostics: semanticOrder.diagnostics,
      parentChildCrossingCount: crossingCount,
      swapEquivalences: equivalences
    )
  }

  static func layout<PersonID: Hashable>(
    _ input: GraphLayoutInput<PersonID>,
    metrics: GraphHorizontalLayoutMetrics = .default
  ) -> GraphHorizontalLayoutResult<PersonID> {
    let normalized = FamilyGraphLayoutCore.normalize(input)
    let generations = FamilyGraphLayoutCore.solveGenerations(normalized)
    let semanticOrder = FamilyGraphLayoutCore.buildSemanticOrder(
      from: normalized,
      generations: generations
    )
    return layout(
      input: normalized,
      generations: generations,
      semanticOrder: semanticOrder,
      metrics: metrics
    )
  }

  static func countParentChildCrossings<PersonID: Hashable>(
    orderedUnitIDsByGeneration orders: [Int: [LayoutUnitID<PersonID>]],
    edges: Set<LayoutUnitEdge<PersonID>>
  ) -> Int {
    let indices = Dictionary(
      uniqueKeysWithValues: orders.flatMap { generation, units in
        units.enumerated().map { (UnitGenerationKey(generation, $0.element), $0.offset) }
      })
    let generationByUnit = Dictionary(
      uniqueKeysWithValues: orders.flatMap { generation, units in
        units.map { ($0, generation) }
      })
    var count = 0
    let edgeArray = Array(edges)
    for firstIndex in edgeArray.indices {
      let first = edgeArray[firstIndex]
      for secondIndex in edgeArray.indices where secondIndex > firstIndex {
        let second = edgeArray[secondIndex]
        guard first.parentUnitID != second.parentUnitID,
          first.childUnitID != second.childUnitID
        else { continue }
        guard let generation = generationByUnit[first.parentUnitID],
          generationByUnit[second.parentUnitID] == generation,
          generationByUnit[first.childUnitID] == generation + 1,
          generationByUnit[second.childUnitID] == generation + 1,
          let firstTop = indices[UnitGenerationKey(generation, first.parentUnitID)],
          let secondTop = indices[UnitGenerationKey(generation, second.parentUnitID)],
          let firstBottom = indices[UnitGenerationKey(generation + 1, first.childUnitID)],
          let secondBottom = indices[UnitGenerationKey(generation + 1, second.childUnitID)]
        else { continue }
        if (firstTop < secondTop) != (firstBottom < secondBottom) { count += 1 }
      }
    }
    return count
  }

  private struct UnitGenerationKey<PersonID: Hashable>: Hashable {
    let generation: Int
    let unitID: LayoutUnitID<PersonID>

    init(_ generation: Int, _ unitID: LayoutUnitID<PersonID>) {
      self.generation = generation
      self.unitID = unitID
    }
  }

  private struct GenerationPair: Hashable {
    let parent: Int
  }

  private struct CrossingEvaluationContext<PersonID: Hashable> {
    let generationByUnit: [LayoutUnitID<PersonID>: Int]
    let edgesByGenerationPair: [GenerationPair: [LayoutUnitEdge<PersonID>]]
    let incidentEdgesByUnit: [LayoutUnitID<PersonID>: Set<LayoutUnitEdge<PersonID>>]
    var indices: [UnitGenerationKey<PersonID>: Int]

    init(
      orders: [Int: [LayoutUnitID<PersonID>]],
      edges: Set<LayoutUnitEdge<PersonID>>
    ) {
      generationByUnit = Dictionary(
        uniqueKeysWithValues: orders.flatMap { generation, units in
          units.map { ($0, generation) }
        })
      indices = Dictionary(
        uniqueKeysWithValues: orders.flatMap { generation, units in
          units.enumerated().map { (UnitGenerationKey(generation, $0.element), $0.offset) }
        })

      var edgesByGenerationPair: [GenerationPair: [LayoutUnitEdge<PersonID>]] = [:]
      var incidentEdgesByUnit: [LayoutUnitID<PersonID>: Set<LayoutUnitEdge<PersonID>>] = [:]
      for edge in edges {
        incidentEdgesByUnit[edge.parentUnitID, default: []].insert(edge)
        incidentEdgesByUnit[edge.childUnitID, default: []].insert(edge)
        guard let parentGeneration = generationByUnit[edge.parentUnitID],
          generationByUnit[edge.childUnitID] == parentGeneration + 1
        else { continue }
        edgesByGenerationPair[GenerationPair(parent: parentGeneration), default: []].append(edge)
      }
      self.edgesByGenerationPair = edgesByGenerationPair
      self.incidentEdgesByUnit = incidentEdgesByUnit
    }

    func crossingDelta(
      swapping first: LayoutUnitID<PersonID>,
      with second: LayoutUnitID<PersonID>,
      in generation: Int
    ) -> Int {
      let affectedEdges = incidentEdgesByUnit[first, default: []]
        .union(incidentEdgesByUnit[second, default: []])
      guard !affectedEdges.isEmpty,
        let firstIndex = indices[UnitGenerationKey(generation, first)],
        let secondIndex = indices[UnitGenerationKey(generation, second)]
      else { return 0 }

      var before = 0
      var after = 0
      for pair in [GenerationPair(parent: generation - 1), GenerationPair(parent: generation)] {
        guard let pairEdges = edgesByGenerationPair[pair] else { continue }
        let affectedIndices = Set(
          pairEdges.indices.filter { affectedEdges.contains(pairEdges[$0]) })
        for firstEdgeIndex in affectedIndices {
          let firstEdge = pairEdges[firstEdgeIndex]
          for secondEdgeIndex in pairEdges.indices
          where secondEdgeIndex != firstEdgeIndex
            && (!affectedIndices.contains(secondEdgeIndex) || secondEdgeIndex > firstEdgeIndex)
          {
            let secondEdge = pairEdges[secondEdgeIndex]
            before +=
              Self.crosses(
                firstEdge,
                secondEdge,
                generation: pair.parent,
                indices: indices
              ) ? 1 : 0
            after +=
              Self.crosses(
                firstEdge,
                secondEdge,
                generation: pair.parent,
                indices: indices,
                swapping: (first, firstIndex, second, secondIndex),
                in: generation
              ) ? 1 : 0
          }
        }
      }
      return after - before
    }

    mutating func recordSwap(
      _ first: LayoutUnitID<PersonID>,
      _ second: LayoutUnitID<PersonID>,
      generation: Int
    ) {
      let firstKey = UnitGenerationKey(generation, first)
      let secondKey = UnitGenerationKey(generation, second)
      let firstIndex = indices[firstKey]
      indices[firstKey] = indices[secondKey]
      indices[secondKey] = firstIndex
    }

    private static func crosses(
      _ first: LayoutUnitEdge<PersonID>,
      _ second: LayoutUnitEdge<PersonID>,
      generation: Int,
      indices: [UnitGenerationKey<PersonID>: Int],
      swapping swap: (
        first: LayoutUnitID<PersonID>, firstIndex: Int,
        second: LayoutUnitID<PersonID>, secondIndex: Int
      )? = nil,
      in swappedGeneration: Int? = nil
    ) -> Bool {
      guard first.parentUnitID != second.parentUnitID,
        first.childUnitID != second.childUnitID,
        let firstTop = index(
          of: first.parentUnitID, generation: generation, indices: indices,
          swapping: swap, in: swappedGeneration),
        let secondTop = index(
          of: second.parentUnitID, generation: generation, indices: indices,
          swapping: swap, in: swappedGeneration),
        let firstBottom = index(
          of: first.childUnitID, generation: generation + 1, indices: indices,
          swapping: swap, in: swappedGeneration),
        let secondBottom = index(
          of: second.childUnitID, generation: generation + 1, indices: indices,
          swapping: swap, in: swappedGeneration)
      else { return false }
      return (firstTop < secondTop) != (firstBottom < secondBottom)
    }

    private static func index(
      of unit: LayoutUnitID<PersonID>,
      generation: Int,
      indices: [UnitGenerationKey<PersonID>: Int],
      swapping swap: (
        first: LayoutUnitID<PersonID>, firstIndex: Int,
        second: LayoutUnitID<PersonID>, secondIndex: Int
      )?,
      in swappedGeneration: Int?
    ) -> Int? {
      if generation == swappedGeneration, let swap {
        if unit == swap.first { return swap.secondIndex }
        if unit == swap.second { return swap.firstIndex }
      }
      return indices[UnitGenerationKey(generation, unit)]
    }
  }

  static func crossingDeltaForAdjacentSwap<PersonID: Hashable>(
    orderedUnitIDsByGeneration orders: [Int: [LayoutUnitID<PersonID>]],
    edges: Set<LayoutUnitEdge<PersonID>>,
    generation: Int,
    index: Int
  ) -> Int? {
    guard let order = orders[generation], order.indices.contains(index),
      order.indices.contains(index + 1)
    else { return nil }
    let context = CrossingEvaluationContext(orders: orders, edges: edges)
    return context.crossingDelta(
      swapping: order[index],
      with: order[index + 1],
      in: generation
    )
  }

  private static func emptyResult<PersonID: Hashable>(
    diagnostics: Set<GraphLayoutDiagnostic<PersonID>>
  ) -> GraphHorizontalLayoutResult<PersonID> {
    GraphHorizontalLayoutResult(
      positionsByPersonID: [:],
      orderedUnitIDsByGeneration: [:],
      bounds: nil,
      diagnostics: diagnostics,
      parentChildCrossingCount: 0,
      swapEquivalences: []
    )
  }

  private static func initialOrders<PersonID: Hashable>(
    semanticOrder: LayoutSemanticOrder<PersonID>,
    graph: LayoutUnitGraph<PersonID>
  ) -> [Int: [LayoutUnitID<PersonID>]] {
    var result: [Int: [LayoutUnitID<PersonID>]] = [:]
    let generations = semanticOrder.generationOrderings.keys.sorted {
      let firstDistance = abs($0)
      let secondDistance = abs($1)
      return firstDistance == secondDistance ? $0 < $1 : firstDistance < secondDistance
    }
    for generation in generations {
      guard let ordering = semanticOrder.generationOrderings[generation] else { continue }
      let constraints = ordering.contiguityConstraints.map(\.memberUnitIDs)
      let neighboringCenters = neighborRanks(
        generation: generation,
        orders: result,
        graph: graph
      )
      result[generation] = flatten(
        units: ordering.unitIDs,
        constraints: constraints,
        neighborRanks: neighboringCenters,
        graph: graph
      )
    }
    return result
  }

  private static func flatten<PersonID: Hashable>(
    units: Set<LayoutUnitID<PersonID>>,
    constraints: [Set<LayoutUnitID<PersonID>>],
    neighborRanks: [LayoutUnitID<PersonID>: Double],
    graph: LayoutUnitGraph<PersonID>
  ) -> [LayoutUnitID<PersonID>] {
    let children = maximalProperSubsets(of: units, candidates: constraints)
    var parts = children
    let covered = children.reduce(into: Set<LayoutUnitID<PersonID>>()) { $0.formUnion($1) }
    parts += units.subtracting(covered).map { [$0] }
    let decorated: [(part: Set<LayoutUnitID<PersonID>>, rank: Double?, signature: [Int])] =
      parts.map { part in
        let ranks = part.compactMap { neighborRanks[$0] }
        return (
          part: part,
          rank: ranks.isEmpty ? nil : ranks.average,
          signature: structuralSignature(part, graph: graph)
        )
      }
    let sorted = decorated.sorted(by: { first, second in
      switch (first.rank, second.rank) {
      case (let left?, let right?) where left != right: return left < right
      case (_?, nil): return true
      case (nil, _?): return false
      default: return first.signature.lexicographicallyPrecedes(second.signature)
      }
    })
    return sorted.flatMap { item -> [LayoutUnitID<PersonID>] in
      guard item.part.count > 1 else { return Array(item.part) }
      return flatten(
        units: item.part,
        constraints: constraints.filter { $0.isSubset(of: item.part) },
        neighborRanks: neighborRanks,
        graph: graph
      )
    }
  }

  private static func maximalProperSubsets<PersonID: Hashable>(
    of units: Set<LayoutUnitID<PersonID>>,
    candidates: [Set<LayoutUnitID<PersonID>>]
  ) -> [Set<LayoutUnitID<PersonID>>] {
    let proper = Set(candidates.filter { !$0.isEmpty && $0 != units && $0.isSubset(of: units) })
    return proper.filter { candidate in
      !proper.contains { candidate != $0 && candidate.isSubset(of: $0) }
    }
  }

  private static func structuralSignature<PersonID: Hashable>(
    _ units: Set<LayoutUnitID<PersonID>>,
    graph: LayoutUnitGraph<PersonID>
  ) -> [Int] {
    let degrees = units.map { unit in
      graph.parentChildEdges.reduce(0) { partial, edge in
        partial + ((edge.parentUnitID == unit || edge.childUnitID == unit) ? 1 : 0)
      }
    }.sorted()
    return [units.count, units.reduce(0) { $0 + $1.personIDs.count }] + degrees
  }

  private static func neighborRanks<PersonID: Hashable>(
    generation: Int,
    orders: [Int: [LayoutUnitID<PersonID>]],
    graph: LayoutUnitGraph<PersonID>
  ) -> [LayoutUnitID<PersonID>: Double] {
    var values: [LayoutUnitID<PersonID>: [Double]] = [:]
    for adjacent in [generation - 1, generation + 1] {
      guard let order = orders[adjacent] else { continue }
      let ranks = Dictionary(
        uniqueKeysWithValues: order.enumerated().map { ($0.element, Double($0.offset)) })
      for edge in graph.parentChildEdges {
        if let rank = ranks[edge.parentUnitID] {
          values[edge.childUnitID, default: []].append(rank)
        }
        if let rank = ranks[edge.childUnitID] {
          values[edge.parentUnitID, default: []].append(rank)
        }
      }
    }
    return values.mapValues(\.average)
  }

  private static func reduceCrossings<PersonID: Hashable>(
    orders: [Int: [LayoutUnitID<PersonID>]],
    graph: LayoutUnitGraph<PersonID>,
    orderings: [Int: LayoutGenerationOrdering<PersonID>],
    iterations: Int
  ) -> [Int: [LayoutUnitID<PersonID>]] {
    var result = orders
    var crossingContext = CrossingEvaluationContext(
      orders: orders,
      edges: graph.parentChildEdges
    )
    for _ in 0..<max(0, iterations) {
      var improved = false
      for generation in result.keys.sorted() {
        guard var order = result[generation], order.count > 1 else { continue }
        for index in 0..<(order.count - 1) {
          let first = order[index]
          let second = order[index + 1]
          let delta = crossingContext.crossingDelta(
            swapping: first,
            with: second,
            in: generation
          )
          order.swapAt(index, index + 1)
          guard respectsContiguity(order, ordering: orderings[generation]) else {
            order.swapAt(index, index + 1)
            continue
          }
          if delta < 0 {
            result[generation] = order
            crossingContext.recordSwap(first, second, generation: generation)
            improved = true
          } else {
            order.swapAt(index, index + 1)
          }
        }
      }
      if !improved { break }
    }
    return result
  }

  private static func respectsContiguity<PersonID: Hashable>(
    _ order: [LayoutUnitID<PersonID>],
    ordering: LayoutGenerationOrdering<PersonID>?
  ) -> Bool {
    guard let ordering else { return true }
    let indices = Dictionary(
      uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
    return ordering.contiguityConstraints.allSatisfy { constraint in
      let memberIndices = constraint.memberUnitIDs.compactMap { indices[$0] }
      guard let minimum = memberIndices.min(), let maximum = memberIndices.max() else {
        return true
      }
      return maximum - minimum + 1 == memberIndices.count
    }
  }

  private static func assignUnitCenters<PersonID: Hashable>(
    orders: [Int: [LayoutUnitID<PersonID>]],
    graph: LayoutUnitGraph<PersonID>,
    blocks: Set<LayoutFamilyBlock<PersonID>>,
    metrics: GraphHorizontalLayoutMetrics
  ) -> [LayoutUnitID<PersonID>: Double] {
    var centers: [LayoutUnitID<PersonID>: Double] = [:]
    for (generation, order) in orders {
      var cursor = 0.0
      for (index, unit) in order.enumerated() {
        let halfWidth = unit.personIDs.count == 2 ? metrics.coupleGap / 2 : 0
        if index == 0 {
          cursor = halfWidth
        } else {
          let previous = order[index - 1]
          let previousHalfWidth = previous.personIDs.count == 2 ? metrics.coupleGap / 2 : 0
          let boundaryGap =
            isFamilyBoundary(
              previous,
              unit,
              generation: generation,
              blocks: blocks
            ) ? metrics.familyBlockGap : 0
          cursor += previousHalfWidth + metrics.minimumPersonGap + boundaryGap + halfWidth
        }
        centers[unit] = cursor
      }
    }
    return centers
  }

  private static func refineCenters<PersonID: Hashable>(
    _ initial: [LayoutUnitID<PersonID>: Double],
    orders: [Int: [LayoutUnitID<PersonID>]],
    graph: LayoutUnitGraph<PersonID>,
    blocks: Set<LayoutFamilyBlock<PersonID>>,
    metrics: GraphHorizontalLayoutMetrics
  ) -> [LayoutUnitID<PersonID>: Double] {
    var centers = initial
    for _ in 0..<max(0, metrics.refinementIterations) {
      for generation in orders.keys.sorted() {
        guard let order = orders[generation] else { continue }
        var desired = centers
        for unit in order {
          let neighbors = graph.parentChildEdges.compactMap { edge -> Double? in
            if edge.parentUnitID == unit { return centers[edge.childUnitID] }
            if edge.childUnitID == unit { return centers[edge.parentUnitID] }
            return nil
          }
          if !neighbors.isEmpty { desired[unit] = neighbors.average }
        }
        centers = projectSpacing(
          desired,
          order: order,
          generation: generation,
          blocks: blocks,
          metrics: metrics
        )
      }
    }
    return centers
  }

  private static func projectSpacing<PersonID: Hashable>(
    _ desired: [LayoutUnitID<PersonID>: Double],
    order: [LayoutUnitID<PersonID>],
    generation: Int,
    blocks: Set<LayoutFamilyBlock<PersonID>>,
    metrics: GraphHorizontalLayoutMetrics
  ) -> [LayoutUnitID<PersonID>: Double] {
    guard let first = order.first else { return desired }
    var result = desired
    var values = [desired[first] ?? 0]
    for index in 1..<order.count {
      let previous = order[index - 1]
      let current = order[index]
      let widths =
        (previous.personIDs.count == 2 ? metrics.coupleGap / 2 : 0)
        + (current.personIDs.count == 2 ? metrics.coupleGap / 2 : 0)
      let boundary =
        isFamilyBoundary(previous, current, generation: generation, blocks: blocks)
        ? metrics.familyBlockGap : 0
      values.append(
        max(desired[current] ?? 0, values[index - 1] + widths + metrics.minimumPersonGap + boundary)
      )
    }
    let correction = zip(order, values).map { (desired[$0.0] ?? 0) - $0.1 }.average
    for (unit, value) in zip(order, values) { result[unit] = value + correction }
    return result
  }

  private static func isFamilyBoundary<PersonID: Hashable>(
    _ first: LayoutUnitID<PersonID>,
    _ second: LayoutUnitID<PersonID>,
    generation: Int,
    blocks: Set<LayoutFamilyBlock<PersonID>>
  ) -> Bool {
    let firstBlocks = blocks.filter {
      $0.unitIDsByGeneration[generation, default: []].contains(first)
    }
    let secondBlocks = blocks.filter {
      $0.unitIDsByGeneration[generation, default: []].contains(second)
    }
    return !firstBlocks.isEmpty && !secondBlocks.isEmpty
      && firstBlocks.allSatisfy { !$0.memberUnitIDs.contains(second) }
      && secondBlocks.allSatisfy { !$0.memberUnitIDs.contains(first) }
  }

  private static func personPositions<PersonID: Hashable>(
    unitCenters: [LayoutUnitID<PersonID>: Double],
    orders: [Int: [LayoutUnitID<PersonID>]],
    generations: [PersonID: Int],
    metrics: GraphHorizontalLayoutMetrics
  ) -> [PersonID: LayoutPosition] {
    var result: [PersonID: LayoutPosition] = [:]
    for order in orders.values {
      for unit in order {
        guard let center = unitCenters[unit] else { continue }
        let members = Array(unit.personIDs)
        if members.count == 2 {
          // The set's incidental order is intentionally not semantic. Reversing it is equivalent.
          result[members[0]] = LayoutPosition(
            generation: generations[members[0]]!, x: center - metrics.coupleGap / 2
          )
          result[members[1]] = LayoutPosition(
            generation: generations[members[1]]!, x: center + metrics.coupleGap / 2
          )
        } else if let member = members.first {
          result[member] = LayoutPosition(generation: generations[member]!, x: center)
        }
      }
    }
    return result
  }
}

extension Collection where Element == Double {
  fileprivate var average: Double {
    isEmpty ? 0 : reduce(0, +) / Double(count)
  }
}
