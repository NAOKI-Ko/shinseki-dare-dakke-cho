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

  func testQuickChildRegistrationCreatesNameOnlyAndLinksSelectedSpouse() throws {
    let fixture = try makeFixture()

    let child = try QuickRelativeRegistration.create(
      named: "  その場で会った子  ",
      kind: .child,
      for: fixture.a,
      in: fixture.container.mainContext,
      includeSpouseForChild: true
    )

    XCTAssertEqual(child.name, "その場で会った子")
    XCTAssertTrue(fixture.a.children.contains { key($0) == key(child) })
    XCTAssertTrue(fixture.c.children.contains { key($0) == key(child) })
    XCTAssertTrue(child.parents.contains { key($0) == key(fixture.a) })
    XCTAssertTrue(child.parents.contains { key($0) == key(fixture.c) })
    XCTAssertEqual(Set(child.parents.map { key($0) }), Set([key(fixture.a), key(fixture.c)]))
    XCTAssertEqual(child.kana, "")
    XCTAssertEqual(child.relationNote, "")
    XCTAssertNil(child.photoData)
    XCTAssertEqual(child.phone, "")
    XCTAssertEqual(child.email, "")
    XCTAssertEqual(child.memo, "")
  }

  func testGraphCanvasUsesOneTransformForNodeAndEdgeCentersAtSupportedScales() {
    let origin = CGPoint(x: 200, y: 300)
    let rawNodeCenter = GraphCanvasGeometry.beadCenter(
      position: GraphGridPosition(level: -2, slot: 3),
      origin: origin,
      slotWidth: 108,
      levelHeight: 120
    )
    let otherCenter = GraphCanvasGeometry.beadCenter(
      position: GraphGridPosition(level: 1, slot: -1),
      origin: origin,
      slotWidth: 108,
      levelHeight: 120
    )
    let anchors = GraphCanvasGeometry.edgeAnchors(
      from: rawNodeCenter,
      to: otherCenter,
      startRadius: 28 * 1.06,
      endRadius: 28 * 0.9
    )

    for scale in [CGFloat(0.4), 0.6, 1.0, 2.5] {
      let transform = GraphViewportTransform(
        scale: scale,
        offset: CGSize(width: 37, height: -19)
      )
      let transformedNodeCenter = transform.applying(to: rawNodeCenter, around: origin)
      let transformedEdgeCenter = transform.applying(to: anchors.startCenter, around: origin)

      XCTAssertEqual(transformedNodeCenter.x, transformedEdgeCenter.x, accuracy: 0.0001)
      XCTAssertEqual(transformedNodeCenter.y, transformedEdgeCenter.y, accuracy: 0.0001)
      XCTAssertEqual(
        hypot(
          transform.applying(to: anchors.start, around: origin).x - transformedNodeCenter.x,
          transform.applying(to: anchors.start, around: origin).y - transformedNodeCenter.y
        ),
        28 * 1.06 * scale,
        accuracy: 0.0001
      )
      let restored = transform.removing(from: transformedNodeCenter, around: origin)
      XCTAssertEqual(restored.x, rawNodeCenter.x, accuracy: 0.0001)
      XCTAssertEqual(restored.y, rawNodeCenter.y, accuracy: 0.0001)
    }
  }

  func testViewportZoomPreservesGestureAnchor() {
    let origin = CGPoint(x: 200, y: 300)
    let anchor = CGPoint(x: 84, y: 142)
    let start = GraphViewportTransform(
      scale: 1.1,
      offset: CGSize(width: 27, height: -13)
    )
    let graphAnchor = start.removing(from: anchor, around: origin)
    let zoomed = start.zoomed(by: 1.7, anchor: anchor, around: origin)
    let restoredScreenAnchor = zoomed.applying(to: graphAnchor, around: origin)

    XCTAssertEqual(restoredScreenAnchor.x, anchor.x, accuracy: 0.0001)
    XCTAssertEqual(restoredScreenAnchor.y, anchor.y, accuracy: 0.0001)
  }

  func testViewportCenterAnchorZoomRemainsCentered() {
    let origin = CGPoint(x: 180, y: 260)
    let start = GraphViewportTransform(
      scale: 0.8,
      offset: CGSize(width: 45, height: -31)
    )
    let graphPointUnderCenter = start.removing(from: origin, around: origin)
    let zoomed = start.zoomed(by: 2, anchor: origin, around: origin)
    let screenPoint = zoomed.applying(to: graphPointUnderCenter, around: origin)

    XCTAssertEqual(screenPoint.x, origin.x, accuracy: 0.0001)
    XCTAssertEqual(screenPoint.y, origin.y, accuracy: 0.0001)
  }

  func testViewportOffCenterAnchorZoomDoesNotDrift() {
    let origin = CGPoint(x: 210, y: 330)
    let anchor = CGPoint(x: 326, y: 92)
    let start = GraphViewportTransform(
      scale: 0.65,
      offset: CGSize(width: -24, height: 38)
    )
    let anchoredGraphPoint = start.removing(from: anchor, around: origin)
    let zoomed = start.zoomed(by: 1.45, anchor: anchor, around: origin)

    XCTAssertEqual(
      zoomed.applying(to: anchoredGraphPoint, around: origin).x,
      anchor.x,
      accuracy: 0.0001
    )
    XCTAssertEqual(
      zoomed.applying(to: anchoredGraphPoint, around: origin).y,
      anchor.y,
      accuracy: 0.0001
    )
  }

  func testViewportCombinesPanAndZoomFromOneStartingTransform() {
    let origin = CGPoint(x: 200, y: 300)
    let anchor = CGPoint(x: 120, y: 210)
    let translation = CGSize(width: 53, height: -28)
    let start = GraphViewportTransform(
      scale: 1.25,
      offset: CGSize(width: 18, height: 22)
    )
    let anchoredGraphPoint = start.removing(from: anchor, around: origin)
    let combined = start
      .zoomed(by: 1.4, anchor: anchor, around: origin)
      .panned(by: translation)
    let screenPoint = combined.applying(to: anchoredGraphPoint, around: origin)

    XCTAssertEqual(screenPoint.x, anchor.x + translation.width, accuracy: 0.0001)
    XCTAssertEqual(screenPoint.y, anchor.y + translation.height, accuracy: 0.0001)
  }

  func testViewportZoomClampPreservesAnchorAtBothBounds() {
    let origin = CGPoint(x: 200, y: 300)
    let anchor = CGPoint(x: 75, y: 510)
    let start = GraphViewportTransform(
      scale: 1,
      offset: CGSize(width: 11, height: -17)
    )
    let graphAnchor = start.removing(from: anchor, around: origin)

    for (magnification, expectedScale) in [(CGFloat(100), CGFloat(2.5)), (0.01, 0.4)] {
      let zoomed = start.zoomed(
        by: magnification,
        anchor: anchor,
        around: origin
      )
      let screenPoint = zoomed.applying(to: graphAnchor, around: origin)
      XCTAssertEqual(zoomed.scale, expectedScale, accuracy: 0.0001)
      XCTAssertEqual(screenPoint.x, anchor.x, accuracy: 0.0001)
      XCTAssertEqual(screenPoint.y, anchor.y, accuracy: 0.0001)
    }
  }

  func testViewportTransformRoundTripsScreenAndGraphCoordinates() {
    let origin = CGPoint(x: 197, y: 281)
    let viewport = GraphViewportTransform(
      scale: 2.3,
      offset: CGSize(width: -83, height: 47)
    )

    for graphPoint in [CGPoint(x: -50, y: 80), origin, CGPoint(x: 640, y: 920)] {
      let screenPoint = viewport.applying(to: graphPoint, around: origin)
      let restored = viewport.removing(from: screenPoint, around: origin)
      XCTAssertEqual(restored.x, graphPoint.x, accuracy: 0.0001)
      XCTAssertEqual(restored.y, graphPoint.y, accuracy: 0.0001)
    }
  }

  func testHitTestInverseUsesTheSameViewportAsRendering() {
    let origin = CGPoint(x: 200, y: 300)
    let graphCenter = CGPoint(x: 92, y: 540)
    let viewport = GraphViewportTransform(
      scale: 0.4,
      offset: CGSize(width: 61, height: -34)
    )
    let screenCenter = viewport.applying(to: graphCenter, around: origin)
    let hitGraphPoint = GraphHitTestGeometry.graphLocation(
      for: screenCenter,
      origin: origin,
      viewport: viewport
    )

    XCTAssertEqual(hitGraphPoint.x, graphCenter.x, accuracy: 0.0001)
    XCTAssertEqual(hitGraphPoint.y, graphCenter.y, accuracy: 0.0001)
  }

  func testExplicitFocusCameraCentersTargetAtCurrentScale() {
    let origin = CGPoint(x: 200, y: 300)
    let position = GraphGridPosition(level: -2, slot: 3)
    let current = GraphViewportTransform(
      scale: 1.4,
      offset: CGSize(width: 90, height: -44)
    )
    let focused = GraphFocusTransition.viewport(
      from: current,
      centeredOn: position,
      slotWidth: 108,
      levelHeight: 120,
      moveCamera: true
    )
    let graphCenter = GraphCanvasGeometry.beadCenter(
      position: position,
      origin: origin,
      slotWidth: 108,
      levelHeight: 120
    )
    let screenCenter = focused.applying(to: graphCenter, around: origin)

    XCTAssertEqual(focused.scale, current.scale, accuracy: 0.0001)
    XCTAssertEqual(screenCenter.x, origin.x, accuracy: 0.0001)
    XCTAssertEqual(screenCenter.y, origin.y, accuracy: 0.0001)
  }

  func testVisualFocusOnlyDoesNotChangeViewportOffset() {
    let current = GraphViewportTransform(
      scale: 0.9,
      offset: CGSize(width: -135, height: 72)
    )
    let result = GraphFocusTransition.viewport(
      from: current,
      centeredOn: GraphGridPosition(level: 4, slot: -3),
      slotWidth: 108,
      levelHeight: 120,
      moveCamera: false
    )

    XCTAssertEqual(result, current)
  }

  func testSemanticZoomCentralPolicyReducesOverviewNoise() {
    XCTAssertEqual(GraphSemanticZoomPolicy.level(for: 0.4), .overview)
    XCTAssertEqual(GraphSemanticZoomPolicy.level(for: 0.6), .overview)
    XCTAssertEqual(GraphSemanticZoomPolicy.level(for: 1), .normal)
    XCTAssertEqual(GraphSemanticZoomPolicy.level(for: 2.5), .close)

    XCTAssertEqual(
      GraphSemanticZoomPolicy.visibility(
        at: .overview,
        isFocused: false,
        focusDistance: 1,
        isExpanded: false
      ),
      GraphSemanticVisibility(
        showsName: false,
        showsRelation: false,
        showsExpansionBadge: false
      )
    )
    XCTAssertEqual(
      GraphSemanticZoomPolicy.visibility(
        at: .normal,
        isFocused: false,
        focusDistance: 2,
        isExpanded: false
      ),
      GraphSemanticVisibility(
        showsName: true,
        showsRelation: false,
        showsExpansionBadge: false
      )
    )
    XCTAssertEqual(
      GraphSemanticZoomPolicy.visibility(
        at: .close,
        isFocused: false,
        focusDistance: 3,
        isExpanded: false
      ),
      GraphSemanticVisibility(
        showsName: true,
        showsRelation: true,
        showsExpansionBadge: true
      )
    )
  }

  func testFocusHierarchyUsesShortestGraphDistanceAndKeepsFurtherNodesVisible() throws {
    let fixture = try makeFixture()
    let distanceTwo = Person(name: "距離2")
    let further = Person(name: "距離3")
    fixture.container.mainContext.insert(distanceTwo)
    fixture.container.mainContext.insert(further)
    try fixture.container.mainContext.save()
    RelationshipManager.addParentChild(parent: fixture.b, child: distanceTwo)
    RelationshipManager.addParentChild(parent: distanceTwo, child: further)

    let store = FamilyGraphStore()
    store.reset(with: fixture.a)
    store.expand(fixture.a)
    store.expand(fixture.b)
    store.expand(distanceTwo)
    let distances = store.distances(from: key(fixture.a))

    XCTAssertEqual(distances[key(fixture.a)], 0)
    XCTAssertEqual(distances[key(fixture.b)], 1)
    XCTAssertEqual(distances[key(distanceTwo)], 2)
    XCTAssertEqual(distances[key(further)], 3)
    XCTAssertEqual(GraphFocusHierarchy.presentation(for: 0).band, .focused)
    XCTAssertEqual(GraphFocusHierarchy.presentation(for: 1).band, .direct)
    XCTAssertEqual(GraphFocusHierarchy.presentation(for: 2).band, .distanceTwo)
    let distantPresentation = GraphFocusHierarchy.presentation(for: 3)
    XCTAssertEqual(distantPresentation.band, .further)
    XCTAssertGreaterThan(distantPresentation.nodeOpacity, 0)
    XCTAssertGreaterThan(distantPresentation.nodeScale, 0)
  }

  func testOnlyFocusedPersonGetsStrongAdornmentAndSelfUsesSubtleMarkerOtherwise() {
    XCTAssertEqual(
      GraphFocusAdornmentPolicy.adornment(isSelf: true, isFocused: true),
      GraphFocusAdornment(showsStrongFocus: true, showsSelfMarker: false)
    )
    XCTAssertEqual(
      GraphFocusAdornmentPolicy.adornment(isSelf: false, isFocused: true),
      GraphFocusAdornment(showsStrongFocus: true, showsSelfMarker: false)
    )
    XCTAssertEqual(
      GraphFocusAdornmentPolicy.adornment(isSelf: true, isFocused: false),
      GraphFocusAdornment(showsStrongFocus: false, showsSelfMarker: true)
    )
    XCTAssertEqual(
      GraphFocusAdornmentPolicy.adornment(isSelf: false, isFocused: false),
      GraphFocusAdornment(showsStrongFocus: false, showsSelfMarker: false)
    )
  }

  func testNodeLODClampsScreenSizeAndKeepsEdgeAnchorOnDisplayedBead() {
    let startCenter = CGPoint(x: 100, y: 100)
    let endCenter = CGPoint(x: 300, y: 100)
    let origin = CGPoint.zero

    for scale: CGFloat in [0.4, 1.0, 2.5] {
      let lod = GraphNodeLODPolicy.presentation(cameraScale: scale, focusScale: 1)
      XCTAssertGreaterThanOrEqual(
        lod.screenDiameter,
        GraphNodeLODPolicy.minimumScreenDiameter
      )
      XCTAssertLessThanOrEqual(
        lod.screenDiameter,
        GraphNodeLODPolicy.maximumScreenDiameter
      )

      let anchors = GraphCanvasGeometry.edgeAnchors(
        from: startCenter,
        to: endCenter,
        startRadius: lod.canvasRadius,
        endRadius: lod.canvasRadius
      )
      let transform = GraphViewportTransform(scale: scale, offset: .zero)
      let displayedCenter = transform.applying(to: startCenter, around: origin)
      let displayedAnchor = transform.applying(to: anchors.start, around: origin)
      XCTAssertEqual(
        hypot(
          displayedAnchor.x - displayedCenter.x,
          displayedAnchor.y - displayedCenter.y
        ),
        lod.screenDiameter / 2,
        accuracy: 0.001
      )
    }

    XCTAssertEqual(
      GraphNodeLODPolicy.presentation(cameraScale: 0.4, focusScale: 1).screenDiameter,
      28,
      accuracy: 0.001
    )
    XCTAssertEqual(
      GraphNodeLODPolicy.presentation(cameraScale: 1, focusScale: 1).screenDiameter,
      56,
      accuracy: 0.001
    )
    XCTAssertEqual(
      GraphNodeLODPolicy.presentation(cameraScale: 2.5, focusScale: 1).screenDiameter,
      78,
      accuracy: 0.001
    )
  }

  func testFocusTransitionCentersTargetWithoutChangingCameraScale() {
    let offset = GraphFocusTransition.centeredOffset(
      position: GraphGridPosition(level: -2, slot: 3),
      cameraScale: 1.4,
      slotWidth: 108,
      levelHeight: 120
    )
    XCTAssertEqual(offset.width, -453.6, accuracy: 0.001)
    XCTAssertEqual(offset.height, 336, accuracy: 0.001)
  }

  func testLineLODUsesStableScreenWidthAcrossCameraScales() {
    for scale: CGFloat in [0.4, 1, 2.5] {
      let canvasWidth = GraphLineLODPolicy.canvasWidth(
        screenWidth: 1.5,
        cameraScale: scale
      )
      XCTAssertEqual(canvasWidth * scale, 1.5, accuracy: 0.001)
    }
  }

  func testCoupleKnotReplacesDuplicateParentChildVisualEdges() throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: Person.self,
      Gathering.self,
      configurations: configuration
    )
    let a = Person(name: "父", isSelf: true)
    let b = Person(name: "母")
    let c = Person(name: "子C")
    let d = Person(name: "子D")
    [a, b, c, d].forEach(container.mainContext.insert)
    try container.mainContext.save()
    RelationshipManager.setSpouse(a, b)
    RelationshipManager.addChild(c, to: a, includeSpouse: true)
    RelationshipManager.addChild(d, to: a, includeSpouse: true)

    let store = FamilyGraphStore()
    store.reset(with: a)
    store.expand(a)
    let model = store.coupleRenderModel

    XCTAssertEqual(model.knots.count, 1)
    XCTAssertEqual(Set(model.knots[0].commonChildren), Set([key(c), key(d)]))
    XCTAssertEqual(
      model.segments.filter { $0.id.role == .spouseArm }.count,
      2
    )
    XCTAssertEqual(
      model.segments.filter { $0.id.role == .childStem }.count,
      2
    )
    XCTAssertEqual(
      Set(model.segments.filter { $0.id.role == .childStem }.map(\.id.person)),
      Set([key(c), key(d)])
    )

    let remainingIndividualEdges = store.edges.filter {
      !model.suppressedEdgeIDs.contains($0.id)
    }
    XCTAssertFalse(remainingIndividualEdges.contains { edge in
      [key(c), key(d)].contains(edge.from) || [key(c), key(d)].contains(edge.to)
    })
  }

  func testLaterSpouseAndSelectedExistingChildProduceCoupleKnotModel() throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: Person.self,
      Gathering.self,
      configurations: configuration
    )
    let a = Person(name: "A", isSelf: true)
    let b = Person(name: "B")
    let child = Person(name: "C")
    [a, b, child].forEach(container.mainContext.insert)
    try container.mainContext.save()

    XCTAssertTrue(RelationshipManager.addParentChild(parent: a, child: child))
    XCTAssertTrue(RelationshipManager.setSpouse(a, b))
    XCTAssertEqual(RelationshipManager.linkSharedChildren([child], of: a, with: b), 1)

    let store = FamilyGraphStore()
    store.reset(with: a)
    store.expand(a)
    let model = store.coupleRenderModel

    XCTAssertEqual(model.knots.count, 1)
    XCTAssertEqual(model.knots[0].commonChildren, [key(child)])
    XCTAssertEqual(
      model.segments.filter { $0.id.role == .spouseArm }.count,
      2
    )
    XCTAssertEqual(
      model.segments.filter { $0.id.role == .childStem }.map(\.id.person),
      [key(child)]
    )
    XCTAssertTrue(
      store.edges
        .filter { model.suppressedEdgeIDs.contains($0.id) }
        .contains { edge in
          (edge.from == key(a) || edge.from == key(b)) && edge.to == key(child)
        }
    )
  }

  func testLocalLayoutKeepsSpouseAndSiblingsHorizontalAndGenerationsVertical() throws {
    let fixture = try makeFixture()
    let sibling = Person(name: "きょうだい")
    fixture.container.mainContext.insert(sibling)
    try fixture.container.mainContext.save()
    RelationshipManager.addParentChild(parent: fixture.b, child: sibling)

    let store = FamilyGraphStore()
    store.reset(with: fixture.a)
    store.expand(fixture.a)
    let originalPositions = Dictionary(
      uniqueKeysWithValues: store.nodes.map { ($0.key, ($0.value.level, $0.value.slot)) }
    )
    store.expand(fixture.b)

    let selfNode = try XCTUnwrap(store.nodes[key(fixture.a)])
    let spouseNode = try XCTUnwrap(store.nodes[key(fixture.c)])
    let parentNode = try XCTUnwrap(store.nodes[key(fixture.b)])
    let childNode = try XCTUnwrap(store.nodes[key(fixture.d)])
    let siblingNode = try XCTUnwrap(store.nodes[key(sibling)])
    XCTAssertEqual(spouseNode.level, selfNode.level)
    XCTAssertEqual(abs(spouseNode.slot - selfNode.slot), 1)
    XCTAssertLessThan(parentNode.level, selfNode.level)
    XCTAssertGreaterThan(childNode.level, selfNode.level)
    XCTAssertEqual(siblingNode.level, selfNode.level)
    for (id, position) in originalPositions {
      XCTAssertEqual(store.nodes[id]?.level, position.0)
      XCTAssertEqual(store.nodes[id]?.slot, position.1)
    }
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
