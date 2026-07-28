import SwiftData
import XCTest

@testable import ShinsekiCho

@MainActor
final class FamilyGraphStoreTests: XCTestCase {
  private struct Fixture {
    let container: ModelContainer
    let a: Person
    let b: Person
    let c: Person
    let d: Person
  }

  private func makeFixture() throws -> Fixture {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: Person.self,
      Gathering.self,
      configurations: configuration
    )
    let a = Person(name: "A", isSelf: true)
    let b = Person(name: "B")
    let c = Person(name: "C")
    let d = Person(name: "D")
    [a, b, c, d].forEach(container.mainContext.insert)
    try container.mainContext.save()
    RelationshipManager.addParentChild(parent: b, child: a)
    RelationshipManager.setSpouse(a, c)
    RelationshipManager.addParentChild(parent: a, child: d)
    return Fixture(container: container, a: a, b: b, c: c, d: d)
  }

  private func key(_ person: Person) -> PersistentModelIDBox {
    PersistentModelIDBox(person.persistentModelID)
  }

  private func hasEdge(
    _ store: FamilyGraphStore,
    _ first: Person,
    _ second: Person,
    kind: GraphEdge.Kind
  ) -> Bool {
    let a = key(first)
    let b = key(second)
    return store.edges.contains { edge in
      let endpointsMatch =
        (edge.from == a && edge.to == b) || (edge.from == b && edge.to == a)
      guard endpointsMatch else { return false }
      switch (edge.kind, kind) {
      case (.parentChild, .parentChild), (.spouse, .spouse):
        return true
      default:
        return false
      }
    }
  }

  func testResetAndExpandAddsAllDirectRelationsEdgesAndLevels() throws {
    let fixture = try makeFixture()
    let store = FamilyGraphStore()

    store.reset(with: fixture.a)
    store.expand(fixture.a)

    XCTAssertEqual(store.nodes.count, 4)
    XCTAssertNotNil(store.nodes[key(fixture.a)])
    XCTAssertNotNil(store.nodes[key(fixture.b)])
    XCTAssertNotNil(store.nodes[key(fixture.c)])
    XCTAssertNotNil(store.nodes[key(fixture.d)])
    XCTAssertEqual(store.edges.count, 3)
    XCTAssertTrue(hasEdge(store, fixture.a, fixture.b, kind: .parentChild))
    XCTAssertTrue(hasEdge(store, fixture.a, fixture.c, kind: .spouse))
    XCTAssertTrue(hasEdge(store, fixture.a, fixture.d, kind: .parentChild))
    XCTAssertEqual(store.nodes[key(fixture.a)]?.level, 0)
    XCTAssertEqual(store.nodes[key(fixture.b)]?.level, -1)
    XCTAssertEqual(store.nodes[key(fixture.c)]?.level, 0)
    XCTAssertEqual(store.nodes[key(fixture.d)]?.level, 1)
    XCTAssertEqual(store.nodes[key(fixture.a)]?.path, [])
    XCTAssertEqual(store.nodes[key(fixture.b)]?.path, [.parent])
    XCTAssertEqual(store.nodes[key(fixture.c)]?.path, [.spouse])
    XCTAssertEqual(store.nodes[key(fixture.d)]?.path, [.child])
  }

  func testExpandingRelatedParentDoesNotDuplicateExistingCommonChild() throws {
    let fixture = try makeFixture()
    let store = FamilyGraphStore()
    store.reset(with: fixture.a)
    store.expand(fixture.a)
    let dPositionBefore = store.nodes[key(fixture.d)].map { ($0.level, $0.slot) }

    // B・Cを配偶者かつDの共通の親にした後にBを展開する。
    // DはすでにAの子として配置済みなので、ノードは増やさず既存Dへ接続する。
    fixture.b.spouse = fixture.c
    fixture.c.spouse = fixture.b
    RelationshipManager.addParentChild(parent: fixture.b, child: fixture.d)
    RelationshipManager.addParentChild(parent: fixture.c, child: fixture.d)
    store.expand(fixture.b)

    XCTAssertEqual(
      store.nodes.values.filter {
        $0.person.persistentModelID == fixture.d.persistentModelID
      }.count, 1)
    XCTAssertTrue(hasEdge(store, fixture.b, fixture.d, kind: .parentChild))
    XCTAssertTrue(hasEdge(store, fixture.b, fixture.c, kind: .spouse))
    let dPositionAfter = store.nodes[key(fixture.d)].map { ($0.level, $0.slot) }
    XCTAssertEqual(dPositionBefore?.0, dPositionAfter?.0)
    XCTAssertEqual(dPositionBefore?.1, dPositionAfter?.1)
    XCTAssertEqual(store.nodes[key(fixture.d)]?.path, [.child])
  }

  func testPreviouslyPlacedNodeLevelsAndSlotsNeverChange() throws {
    let fixture = try makeFixture()
    let store = FamilyGraphStore()
    store.reset(with: fixture.a)
    store.expand(fixture.a)
    let originalPositions = Dictionary(
      uniqueKeysWithValues: store.nodes.map { ($0.key, ($0.value.level, $0.value.slot)) }
    )
    RelationshipManager.addParentChild(parent: fixture.b, child: fixture.d)

    store.expand(fixture.b)
    store.expand(fixture.c)
    store.expand(fixture.d)

    for (id, position) in originalPositions {
      XCTAssertEqual(store.nodes[id]?.level, position.0)
      XCTAssertEqual(store.nodes[id]?.slot, position.1)
    }
  }

  func testShorterPathReplacesLongerPathWithoutMovingNode() throws {
    let fixture = try makeFixture()
    let relative = Person(name: "短い経路を後から得る人物")
    fixture.container.mainContext.insert(relative)
    try fixture.container.mainContext.save()
    RelationshipManager.addParentChild(parent: fixture.b, child: relative)

    let store = FamilyGraphStore()
    store.reset(with: fixture.a)
    store.expand(fixture.a)
    store.expand(fixture.b)

    let relativeKey = key(relative)
    XCTAssertEqual(store.nodes[relativeKey]?.path, [.parent, .child])
    let positionBefore = store.nodes[relativeKey].map { ($0.level, $0.slot) }

    RelationshipManager.addParentChild(parent: fixture.a, child: relative)
    store.expand(fixture.a)

    XCTAssertEqual(store.nodes[relativeKey]?.path, [.child])
    XCTAssertEqual(store.nodes[relativeKey]?.level, positionBefore?.0)
    XCTAssertEqual(store.nodes[relativeKey]?.slot, positionBefore?.1)
  }

  func testRelationLabelerReturnsSupportedLabels() {
    XCTAssertEqual(RelationLabeler.label(for: []), "自分")
    XCTAssertEqual(RelationLabeler.label(for: [.parent]), "親")
    XCTAssertEqual(RelationLabeler.label(for: [.spouse]), "配偶者")
    XCTAssertEqual(RelationLabeler.label(for: [.child]), "子")
    XCTAssertEqual(RelationLabeler.label(for: [.parent, .parent]), "祖父母")
    XCTAssertEqual(RelationLabeler.label(for: [.child, .child]), "孫")
    XCTAssertEqual(RelationLabeler.label(for: [.parent, .child]), "兄弟姉妹")
    XCTAssertEqual(
      RelationLabeler.label(for: [.parent, .parent, .child]),
      "おじ・おば"
    )
    XCTAssertEqual(
      RelationLabeler.label(for: [.parent, .child, .child]),
      "甥・姪"
    )
  }

  func testRelationLabelerLeavesUnsupportedRoutesBlank() {
    XCTAssertEqual(RelationLabeler.label(for: [.spouse, .parent]), "")
    XCTAssertEqual(RelationLabeler.label(for: [.parent, .parent, .parent]), "")
    XCTAssertEqual(RelationLabeler.label(for: [.child, .spouse, .child]), "")
  }

  func testFamilyBranchClassificationUsesOnlyTheThreeApprovedBranches() {
    XCTAssertEqual(FamilyBranch.classify(path: []), .indigo)
    XCTAssertEqual(FamilyBranch.classify(path: [.parent]), .indigo)
    XCTAssertEqual(FamilyBranch.classify(path: [.parent, .parent]), .indigo)
    XCTAssertEqual(FamilyBranch.classify(path: [.child, .child]), .indigo)
    XCTAssertEqual(FamilyBranch.classify(path: [.spouse]), .forest)
    XCTAssertEqual(FamilyBranch.classify(path: [.spouse, .parent]), .forest)
    XCTAssertEqual(FamilyBranch.classify(path: [.parent, .child]), .plum)
    XCTAssertEqual(FamilyBranch.classify(path: [.parent, .parent, .child]), .plum)
  }

  func testEdgeBranchFollowsTheOutwardFamilyBranch() throws {
    let fixture = try makeFixture()
    let outsideRelative = Person(name: "直系外の親戚")
    fixture.container.mainContext.insert(outsideRelative)
    try fixture.container.mainContext.save()
    RelationshipManager.addParentChild(parent: fixture.b, child: outsideRelative)

    let store = FamilyGraphStore()
    store.reset(with: fixture.a)
    store.expand(fixture.a)
    store.expand(fixture.b)

    let spouseEdge = try XCTUnwrap(
      store.edges.first {
        Set([$0.from, $0.to]) == Set([key(fixture.a), key(fixture.c)])
      })
    let outsideEdge = try XCTUnwrap(
      store.edges.first {
        Set([$0.from, $0.to]) == Set([key(fixture.b), key(outsideRelative)])
      })
    XCTAssertEqual(store.branch(for: spouseEdge), .forest)
    XCTAssertEqual(store.branch(for: outsideEdge), .plum)
    XCTAssertEqual(store.branch(for: key(fixture.d)), .indigo)
  }

  func testExpandingTwentyFiveNodesCompletesPromptlyWithoutDuplicates() throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: Person.self,
      Gathering.self,
      configurations: configuration
    )
    let root = Person(name: "性能確認の自分", isSelf: true)
    container.mainContext.insert(root)
    let relatives = (1...24).map { Person(name: "親戚\($0)") }
    relatives.forEach(container.mainContext.insert)
    try container.mainContext.save()
    relatives.forEach { RelationshipManager.addParentChild(parent: root, child: $0) }

    let store = FamilyGraphStore()
    let startedAt = ProcessInfo.processInfo.systemUptime
    store.reset(with: root)
    store.expand(root)
    relatives.forEach(store.expand)
    let elapsed = ProcessInfo.processInfo.systemUptime - startedAt

    XCTAssertEqual(store.nodes.count, 25)
    XCTAssertEqual(store.edges.count, 24)
    XCTAssertEqual(Set(store.nodes.keys).count, 25)
    XCTAssertLessThan(elapsed, 0.5)
  }

  func testShortestPathExpansionShowsSpousesBrothersChildAndEveryIntermediate() throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: Person.self,
      Gathering.self,
      configurations: configuration
    )
    let me = Person(name: "山田 太郎", isSelf: true)
    let spouse = Person(name: "佐藤 美咲")
    let spouseParent = Person(name: "佐藤 修一")
    let spouseBrother = Person(name: "佐藤 健太")
    let nephew = Person(name: "佐藤 蓮")
    [me, spouse, spouseParent, spouseBrother, nephew]
      .forEach(container.mainContext.insert)
    try container.mainContext.save()
    RelationshipManager.setSpouse(me, spouse)
    RelationshipManager.addParentChild(parent: spouseParent, child: spouse)
    RelationshipManager.addParentChild(parent: spouseParent, child: spouseBrother)
    RelationshipManager.addParentChild(parent: spouseBrother, child: nephew)

    let route = try XCTUnwrap(RelationLabeler.shortestRoute(from: me, to: nephew))
    XCTAssertEqual(
      route.people.map(\.name),
      [
        "山田 太郎", "佐藤 美咲", "佐藤 修一", "佐藤 健太", "佐藤 蓮",
      ])
    XCTAssertEqual(route.steps, [.spouse, .parent, .child, .child])

    let store = FamilyGraphStore()
    store.reset(with: me)
    let expanded = store.expandShortestPath(to: nephew)

    XCTAssertEqual(expanded, Set([me, spouse, spouseParent, spouseBrother].map(key)))
    XCTAssertNotNil(store.nodes[key(nephew)])
    XCTAssertEqual(store.nodes[key(nephew)]?.path, route.steps)
  }

  func testPathEmphasisContainsOnlyEdgesOnShortestRoute() throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: Person.self,
      Gathering.self,
      configurations: configuration
    )
    let me = Person(name: "山田 太郎", isSelf: true)
    let myParent = Person(name: "山田 一郎")
    let spouse = Person(name: "佐藤 美咲")
    let spouseParent = Person(name: "佐藤 修一")
    let spouseBrother = Person(name: "佐藤 健太")
    [me, myParent, spouse, spouseParent, spouseBrother]
      .forEach(container.mainContext.insert)
    try container.mainContext.save()
    RelationshipManager.addParentChild(parent: myParent, child: me)
    RelationshipManager.setSpouse(me, spouse)
    RelationshipManager.addParentChild(parent: spouseParent, child: spouse)
    RelationshipManager.addParentChild(parent: spouseParent, child: spouseBrother)

    let route = try XCTUnwrap(RelationLabeler.shortestRoute(from: me, to: spouseBrother))
    let emphasized = try XCTUnwrap(GraphPathEmphasis.edgeEndpoints(for: route))

    XCTAssertEqual(emphasized.count, 3)
    XCTAssertTrue(emphasized.contains(GraphEdgeEndpoints(key(me), key(spouse))))
    XCTAssertTrue(emphasized.contains(GraphEdgeEndpoints(key(spouse), key(spouseParent))))
    XCTAssertTrue(emphasized.contains(GraphEdgeEndpoints(key(spouseParent), key(spouseBrother))))
    XCTAssertFalse(emphasized.contains(GraphEdgeEndpoints(key(me), key(myParent))))
  }

  func testPathEmphasisIsDisabledForSelfAndDisconnectedTargets() throws {
    let fixture = try makeFixture()
    let disconnected = Person(name: "未接続")
    fixture.container.mainContext.insert(disconnected)
    try fixture.container.mainContext.save()

    XCTAssertNil(
      GraphPathEmphasis.edgeEndpoints(
        for: RelationLabeler.shortestRoute(from: fixture.a, to: fixture.a)
      ))
    XCTAssertNil(
      GraphPathEmphasis.edgeEndpoints(
        for: RelationLabeler.shortestRoute(from: fixture.a, to: disconnected)
      ))
  }

  func testIntroOverviewFitsTwentyNodesAndCompletesPromptly() {
    let positions = (0..<20).map {
      GraphGridPosition(level: ($0 % 5) - 2, slot: $0 - 10)
    }
    let startedAt = ProcessInfo.processInfo.systemUptime
    let transform = GraphIntroLayout.overview(
      positions: positions,
      viewport: CGSize(width: 390, height: 420),
      slotWidth: 108,
      levelHeight: 120
    )
    let elapsed = ProcessInfo.processInfo.systemUptime - startedAt

    XCTAssertGreaterThan(transform.scale, 0)
    XCTAssertLessThanOrEqual(transform.scale, 0.6)
    for position in positions {
      let x = CGFloat(position.slot) * 108 * transform.scale + transform.offset.width
      let y = CGFloat(position.level) * 120 * transform.scale + transform.offset.height
      XCTAssertLessThanOrEqual(abs(x) + 66 * transform.scale, 183.001)
      XCTAssertLessThanOrEqual(abs(y) + 66 * transform.scale, 166.001)
    }
    XCTAssertLessThan(elapsed, 0.05)
  }

  func testIntroFocusCentersTheDisplayedNode() {
    let transform = GraphIntroLayout.focus(
      position: GraphGridPosition(level: 2, slot: -3),
      slotWidth: 108,
      levelHeight: 120
    )

    XCTAssertEqual(transform.scale, 1)
    XCTAssertEqual(CGFloat(-3 * 108) + transform.offset.width, 0, accuracy: 0.001)
    XCTAssertEqual(CGFloat(2 * 120) + transform.offset.height, 0, accuracy: 0.001)
  }

  func testShortestPathExpansionShowsGrandchildFromDirectDetail() throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: Person.self,
      Gathering.self,
      configurations: configuration
    )
    let me = Person(name: "山田 太郎", isSelf: true)
    let daughter = Person(name: "山田 葵")
    let granddaughter = Person(name: "山田 陽菜")
    [me, daughter, granddaughter].forEach(container.mainContext.insert)
    try container.mainContext.save()
    RelationshipManager.addParentChild(parent: me, child: daughter)
    RelationshipManager.addParentChild(parent: daughter, child: granddaughter)

    let store = FamilyGraphStore()
    store.reset(with: me)
    store.expandShortestPath(to: granddaughter)

    XCTAssertNotNil(store.nodes[key(me)])
    XCTAssertNotNil(store.nodes[key(daughter)])
    XCTAssertNotNil(store.nodes[key(granddaughter)])
    XCTAssertEqual(store.nodes[key(granddaughter)]?.path, [.child, .child])
  }

  func testSelfDetailKeepsTheExistingOneHopInitialExpansion() throws {
    let fixture = try makeFixture()
    let store = FamilyGraphStore()

    store.reset(with: fixture.a)
    let expanded = store.expandShortestPath(to: fixture.a)

    XCTAssertEqual(expanded, [key(fixture.a)])
    XCTAssertEqual(store.nodes.count, 4)
    XCTAssertNotNil(store.nodes[key(fixture.b)])
    XCTAssertNotNil(store.nodes[key(fixture.c)])
    XCTAssertNotNil(store.nodes[key(fixture.d)])
  }

  func testDisconnectedDetailFallsBackToSelfOneHopExpansion() throws {
    let fixture = try makeFixture()
    let disconnected = Person(name: "未接続の人物")
    fixture.container.mainContext.insert(disconnected)
    try fixture.container.mainContext.save()
    let store = FamilyGraphStore()

    store.reset(with: fixture.a)
    store.expandShortestPath(to: disconnected)

    XCTAssertEqual(store.nodes.count, 4)
    XCTAssertNil(store.nodes[key(disconnected)])
  }

  func testSixHopShortestPathExpansionCompletesPromptly() throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: Person.self,
      Gathering.self,
      configurations: configuration
    )
    let people = (0...6).map {
      Person(name: "長距離\($0)", isSelf: $0 == 0)
    }
    people.forEach(container.mainContext.insert)
    try container.mainContext.save()
    for index in 0..<6 {
      RelationshipManager.addParentChild(parent: people[index], child: people[index + 1])
    }

    let store = FamilyGraphStore()
    let startedAt = ProcessInfo.processInfo.systemUptime
    store.reset(with: people[0])
    store.expandShortestPath(to: people[6])
    let elapsed = ProcessInfo.processInfo.systemUptime - startedAt

    XCTAssertNotNil(store.nodes[key(people[6])])
    XCTAssertEqual(store.nodes[key(people[6])]?.path, Array(repeating: .child, count: 6))
    XCTAssertLessThan(elapsed, 0.5)
  }

  func testQuickChildRegistrationCreatesNameOnlyAndConnectsBothDirections() throws {
    let fixture = try makeFixture()

    let child = try QuickRelativeRegistration.create(
      named: "  その場で会った子  ",
      kind: .child,
      for: fixture.a,
      in: fixture.container.mainContext
    )

    XCTAssertEqual(child.name, "その場で会った子")
    XCTAssertTrue(fixture.a.children.contains { key($0) == key(child) })
    XCTAssertTrue(child.parents.contains { key($0) == key(fixture.a) })
    XCTAssertEqual(child.kana, "")
    XCTAssertEqual(child.relationNote, "")
    XCTAssertNil(child.photoData)
    XCTAssertEqual(child.phone, "")
    XCTAssertEqual(child.email, "")
    XCTAssertEqual(child.memo, "")
  }

  func testQuickRegistrationMenuAndSaveBothEnforceSpouseAndParentLimits() throws {
    let fixture = try makeFixture()
    XCTAssertFalse(QuickRelativeRegistration.canAdd(.spouse, to: fixture.a))
    XCTAssertThrowsError(
      try QuickRelativeRegistration.create(
        named: "2人目の配偶者",
        kind: .spouse,
        for: fixture.a,
        in: fixture.container.mainContext
      )
    )

    XCTAssertTrue(QuickRelativeRegistration.canAdd(.parent, to: fixture.a))
    _ = try QuickRelativeRegistration.create(
      named: "2人目の親",
      kind: .parent,
      for: fixture.a,
      in: fixture.container.mainContext
    )
    XCTAssertEqual(fixture.a.parents.count, 2)
    XCTAssertFalse(QuickRelativeRegistration.canAdd(.parent, to: fixture.a))
    XCTAssertThrowsError(
      try QuickRelativeRegistration.create(
        named: "3人目の親",
        kind: .parent,
        for: fixture.a,
        in: fixture.container.mainContext
      )
    )
    XCTAssertEqual(fixture.a.parents.count, 2)
    XCTAssertTrue(QuickRelativeRegistration.canAdd(.child, to: fixture.a))
  }

  func testGraphRenderingContractKeepsEdgesBehindOpaqueNodes() {
    XCTAssertLessThan(
      GraphRenderLayer.edges.rawValue,
      GraphRenderLayer.nodes.rawValue
    )
    XCTAssertEqual(GraphNodeSurfaceContract.baseOpacity, 1.0)
    XCTAssertLessThan(GraphNodeSurfaceContract.inactiveContentOpacity, 1.0)
  }
}
