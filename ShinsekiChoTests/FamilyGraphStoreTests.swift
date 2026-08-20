import SwiftData
import UIKit
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

  func testFamilyGraphPhotoCacheDecodesUnchangedPhotoOnlyOnce() throws {
    let fixture = try makeFixture()
    var decodeCount = 0
    let cache = FamilyGraphPhotoCache { _, _ in
      decodeCount += 1
      return UIImage()
    }
    let data = Data([0x01, 0x02, 0x03])

    for _ in 0..<300 {
      _ = cache.image(for: key(fixture.a), photoData: data)
    }

    XCTAssertEqual(decodeCount, 1)
  }

  func testFamilyGraphPhotoCacheInvalidatesChangedAndDeletedPhoto() throws {
    let fixture = try makeFixture()
    var decodeCount = 0
    let cache = FamilyGraphPhotoCache { _, _ in
      decodeCount += 1
      return UIImage()
    }
    let first = Data([0x01, 0x02])
    let second = Data([0x03, 0x04])

    XCTAssertNotNil(cache.image(for: key(fixture.a), photoData: first))
    XCTAssertNotNil(cache.image(for: key(fixture.a), photoData: second))
    XCTAssertEqual(decodeCount, 2)

    XCTAssertNil(cache.image(for: key(fixture.a), photoData: nil))
    XCTAssertNotNil(cache.image(for: key(fixture.a), photoData: first))
    XCTAssertEqual(decodeCount, 3)
  }

  func testFamilyGraphPhotoCacheAlsoCachesDecodeFailure() throws {
    let fixture = try makeFixture()
    var decodeCount = 0
    let cache = FamilyGraphPhotoCache { _, _ in
      decodeCount += 1
      return nil
    }
    let brokenData = Data([0x00, 0x01, 0x02])

    for _ in 0..<100 {
      XCTAssertNil(cache.image(for: key(fixture.b), photoData: brokenData))
    }

    XCTAssertEqual(decodeCount, 1)
  }

  func testRenderSnapshotRefreshesOnlyFromCurrentGraphStructure() throws {
    let fixture = try makeFixture()
    let store = FamilyGraphStore()
    store.reset(with: fixture.a)

    XCTAssertEqual(store.renderSnapshot.nodes.map(\.id), [key(fixture.a)])
    XCTAssertTrue(store.renderSnapshot.edges.isEmpty)

    store.expand(fixture.a)
    XCTAssertEqual(store.renderSnapshot.nodes.count, store.nodes.count)
    XCTAssertEqual(store.renderSnapshot.edges.count, store.edges.count)
    XCTAssertEqual(
      store.renderSnapshot.nodes.first(where: { $0.id == key(fixture.d) })?.relationLabel,
      "子"
    )

    RelationshipManager.addParentChild(parent: fixture.c, child: fixture.d)
    store.expand(fixture.a)
    let coupleModel = store.renderSnapshot.coupleRenderModel
    let knot = try XCTUnwrap(coupleModel.knots.first)
    XCTAssertEqual(store.renderSnapshot.knotsByID[knot.id], knot)
    XCTAssertTrue(
      store.renderSnapshot.edges.allSatisfy {
        !coupleModel.suppressedEdgeIDs.contains($0.id)
      }
    )
  }

  func testViewportCullingKeepsVisibleAndCrossingContent() {
    let viewport = CGSize(width: 400, height: 600)

    XCTAssertTrue(
      GraphViewportCulling.isNodeVisible(
        center: CGPoint(x: 200, y: 300),
        radius: 40,
        viewportSize: viewport
      )
    )
    XCTAssertFalse(
      GraphViewportCulling.isNodeVisible(
        center: CGPoint(x: -260, y: 300),
        radius: 40,
        viewportSize: viewport
      )
    )
    XCTAssertTrue(
      GraphViewportCulling.isEdgeVisible(
        start: CGPoint(x: -500, y: 300),
        end: CGPoint(x: 900, y: 300),
        viewportSize: viewport
      )
    )
    XCTAssertFalse(
      GraphViewportCulling.isEdgeVisible(
        start: CGPoint(x: -500, y: -500),
        end: CGPoint(x: -300, y: -300),
        viewportSize: viewport
      )
    )
  }

  func testViewportCullingReducesFiftyOffscreenNodesDeterministically() {
    let viewport = CGSize(width: 400, height: 600)
    let centers = (0..<50).map { index in
      CGPoint(x: -2450 + CGFloat(index * 100), y: 300)
    }

    let visibleCount = centers.filter {
      GraphViewportCulling.isNodeVisible(
        center: $0,
        radius: 50,
        viewportSize: viewport
      )
    }.count

    XCTAssertEqual(visibleCount, 8)
    XCTAssertLessThan(visibleCount, centers.count)
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

  func testPureDragZeroPointsKeepsViewportUnchanged() {
    let start = GraphViewportTransform(
      scale: 1.2,
      offset: CGSize(width: 24, height: -18)
    )

    let result = gestureTransform(from: start, translation: .zero)

    XCTAssertEqual(result, start)
  }

  func testPureDragFivePointsKeepsViewportUnchanged() {
    let start = GraphViewportTransform(
      scale: 0.8,
      offset: CGSize(width: -31, height: 42)
    )

    let result = gestureTransform(
      from: start,
      translation: CGSize(width: 3, height: 4)
    )

    XCTAssertEqual(result, start)
  }

  func testPureDragNinePointNinePointsKeepsViewportUnchanged() {
    let start = GraphViewportTransform(
      scale: 2,
      offset: CGSize(width: 70, height: -52)
    )

    let result = gestureTransform(
      from: start,
      translation: CGSize(width: 9.9, height: 0)
    )

    XCTAssertEqual(result, start)
  }

  func testPureDragAtThresholdPansViewport() {
    let start = GraphViewportTransform(
      scale: 0.6,
      offset: CGSize(width: 17, height: 29)
    )
    let translation = CGSize(width: 6, height: 8)

    let result = gestureTransform(from: start, translation: translation)

    XCTAssertEqual(result.scale, start.scale, accuracy: 0.0001)
    XCTAssertEqual(result.offset.width, 23, accuracy: 0.0001)
    XCTAssertEqual(result.offset.height, 37, accuracy: 0.0001)
  }

  func testTapLikeDragThenNodeExpansionKeepsViewportUnchanged() {
    let start = GraphViewportTransform(
      scale: 1.35,
      offset: CGSize(width: -48, height: 63)
    )
    let afterTapLikeDrag = gestureTransform(
      from: start,
      translation: CGSize(width: 5, height: 4)
    )
    let afterExpansion = GraphFocusTransition.viewport(
      from: afterTapLikeDrag,
      centeredOn: GraphGridPosition(level: 2, slot: -1),
      slotWidth: 108,
      levelHeight: 120,
      moveCamera: false
    )

    XCTAssertEqual(afterExpansion, start)
  }

  func testLongPressLikeMicroTranslationKeepsViewportUnchanged() {
    let start = GraphViewportTransform(
      scale: 2.1,
      offset: CGSize(width: 91, height: -76)
    )

    let duringLongPress = gestureTransform(
      from: start,
      translation: CGSize(width: 7, height: 6)
    )

    XCTAssertEqual(duringLongPress, start)
  }

  func testMagnifyWithTranslationPreservesAnchorAndAppliesTranslation() {
    let origin = CGPoint(x: 200, y: 300)
    let anchor = CGPoint(x: 118, y: 176)
    let translation = CGSize(width: 21, height: -14)
    let start = GraphViewportTransform(
      scale: 0.9,
      offset: CGSize(width: -33, height: 46)
    )
    let graphAnchor = start.removing(from: anchor, around: origin)

    let result = GraphViewportGesturePolicy.transform(
      from: start,
      magnification: 1.6,
      anchor: anchor,
      origin: origin,
      translation: translation,
      isMagnifying: true
    )
    let screenPoint = result.applying(to: graphAnchor, around: origin)

    XCTAssertEqual(screenPoint.x, anchor.x + translation.width, accuracy: 0.0001)
    XCTAssertEqual(screenPoint.y, anchor.y + translation.height, accuracy: 0.0001)
  }

  private func gestureTransform(
    from start: GraphViewportTransform,
    translation: CGSize
  ) -> GraphViewportTransform {
    GraphViewportGesturePolicy.transform(
      from: start,
      magnification: 1,
      anchor: CGPoint(x: 200, y: 300),
      origin: CGPoint(x: 200, y: 300),
      translation: translation,
      isMagnifying: false
    )
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

  func testNodeScreenGeometryKeepsCardBeadAnchorAtTransformedCenterAcrossScales() {
    let origin = CGPoint(x: 196, y: 322)
    let logicalCenter = CGPoint(x: 412, y: 82)

    for scale: CGFloat in [0.4, 0.6, 1, 2.5] {
      let viewport = GraphViewportTransform(
        scale: scale,
        offset: CGSize(width: 41, height: -27)
      )
      let geometry = GraphNodeScreenGeometry.resolve(
        logicalCenter: logicalCenter,
        origin: origin,
        viewport: viewport,
        focusScale: 1.06,
        beadDiameter: 56,
        cardHeight: 102
      )
      let expectedCenter = viewport.applying(to: logicalCenter, around: origin)
      let unscaledCardTop = geometry.cardPosition.y - 102 / 2
      let beadAnchorY = unscaledCardTop + 56 / 2

      XCTAssertEqual(geometry.center.x, expectedCenter.x, accuracy: 0.0001)
      XCTAssertEqual(geometry.center.y, expectedCenter.y, accuracy: 0.0001)
      XCTAssertEqual(geometry.cardPosition.x, expectedCenter.x, accuracy: 0.0001)
      XCTAssertEqual(beadAnchorY, expectedCenter.y, accuracy: 0.0001)
      XCTAssertEqual(geometry.scaleAnchor.x, 0.5, accuracy: 0.0001)
      XCTAssertEqual(geometry.scaleAnchor.y, 28 / 102, accuracy: 0.0001)
    }
  }

  func testNodeVisualRadiusChangesWithoutMovingCenter() {
    let origin = CGPoint(x: 200, y: 300)
    let logicalCenter = CGPoint(x: 92, y: 540)
    let viewport = GraphViewportTransform(
      scale: 1,
      offset: CGSize(width: -18, height: 33)
    )
    let normal = GraphNodeScreenGeometry.resolve(
      logicalCenter: logicalCenter,
      origin: origin,
      viewport: viewport,
      focusScale: 1,
      beadDiameter: 56,
      cardHeight: 102
    )
    let focused = GraphNodeScreenGeometry.resolve(
      logicalCenter: logicalCenter,
      origin: origin,
      viewport: viewport,
      focusScale: 1.06,
      beadDiameter: 56,
      cardHeight: 102
    )

    XCTAssertEqual(normal.center, focused.center)
    XCTAssertGreaterThan(focused.radius, normal.radius)
  }

  func testScreenEdgeEndpointMatchesCurrentVisualRadiusAcrossZoomAndPan() {
    let origin = CGPoint(x: 210, y: 350)
    let startLogical = CGPoint(x: 102, y: 230)
    let endLogical = CGPoint(x: 426, y: 590)

    for scale: CGFloat in [0.4, 0.6, 1, 2.5] {
      let viewport = GraphViewportTransform(
        scale: scale,
        offset: CGSize(width: 73, height: -48)
      )
      let startNode = GraphNodeScreenGeometry.resolve(
        logicalCenter: startLogical,
        origin: origin,
        viewport: viewport,
        focusScale: 1.06,
        beadDiameter: 56,
        cardHeight: 102
      )
      let endNode = GraphNodeScreenGeometry.resolve(
        logicalCenter: endLogical,
        origin: origin,
        viewport: viewport,
        focusScale: 0.9,
        beadDiameter: 56,
        cardHeight: 102
      )
      let anchors = GraphCanvasGeometry.screenEdgeAnchors(
        from: startLogical,
        to: endLogical,
        origin: origin,
        viewport: viewport,
        startRadius: startNode.radius,
        endRadius: endNode.radius
      )

      XCTAssertEqual(anchors.startCenter.x, startNode.center.x, accuracy: 0.0001)
      XCTAssertEqual(anchors.startCenter.y, startNode.center.y, accuracy: 0.0001)
      XCTAssertEqual(anchors.endCenter.x, endNode.center.x, accuracy: 0.0001)
      XCTAssertEqual(anchors.endCenter.y, endNode.center.y, accuracy: 0.0001)
      XCTAssertEqual(
        hypot(
          anchors.start.x - startNode.center.x,
          anchors.start.y - startNode.center.y
        ),
        startNode.radius,
        accuracy: 0.5
      )
      XCTAssertEqual(
        hypot(
          anchors.end.x - endNode.center.x,
          anchors.end.y - endNode.center.y
        ),
        endNode.radius,
        accuracy: 0.5
      )
    }
  }

  func testSpouseEdgeUsesEachSpouseCurrentScreenRadius() {
    let origin = CGPoint(x: 180, y: 260)
    let first = CGPoint(x: 72, y: 260)
    let second = CGPoint(x: 288, y: 260)
    let viewport = GraphViewportTransform(
      scale: 2.5,
      offset: CGSize(width: -31, height: 22)
    )
    let firstNode = GraphNodeScreenGeometry.resolve(
      logicalCenter: first,
      origin: origin,
      viewport: viewport,
      focusScale: 1.06,
      beadDiameter: 56,
      cardHeight: 102
    )
    let secondNode = GraphNodeScreenGeometry.resolve(
      logicalCenter: second,
      origin: origin,
      viewport: viewport,
      focusScale: 0.94,
      beadDiameter: 56,
      cardHeight: 102
    )
    let anchors = GraphCanvasGeometry.screenEdgeAnchors(
      from: first,
      to: second,
      origin: origin,
      viewport: viewport,
      startRadius: firstNode.radius,
      endRadius: secondNode.radius
    )

    XCTAssertEqual(anchors.start.x - anchors.startCenter.x, firstNode.radius, accuracy: 0.5)
    XCTAssertEqual(anchors.endCenter.x - anchors.end.x, secondNode.radius, accuracy: 0.5)
  }

  func testCoupleKnotCenterUsesLogicalMidpointAndSharedViewport() {
    let origin = CGPoint(x: 200, y: 300)
    let first = CGPoint(x: 92, y: 180)
    let second = CGPoint(x: 308, y: 180)
    let viewport = GraphViewportTransform(
      scale: 0.6,
      offset: CGSize(width: 44, height: -29)
    )
    let logicalKnot = GraphCanvasGeometry.coupleKnotCenter(first: first, second: second)
    let screenKnot = viewport.applying(to: logicalKnot, around: origin)
    let transformedFirst = viewport.applying(to: first, around: origin)
    let transformedSecond = viewport.applying(to: second, around: origin)

    XCTAssertEqual(
      screenKnot.x,
      (transformedFirst.x + transformedSecond.x) / 2,
      accuracy: 0.0001
    )
    XCTAssertEqual(
      screenKnot.y,
      (transformedFirst.y + transformedSecond.y) / 2,
      accuracy: 0.0001
    )
  }

  func testSharedChildSegmentConnectsKnotAndChildAtTheirScreenRadii() {
    let origin = CGPoint(x: 200, y: 300)
    let knot = CGPoint(x: 200, y: 180)
    let child = CGPoint(x: 308, y: 420)
    let viewport = GraphViewportTransform(
      scale: 0.4,
      offset: CGSize(width: -22, height: 36)
    )
    let childNode = GraphNodeScreenGeometry.resolve(
      logicalCenter: child,
      origin: origin,
      viewport: viewport,
      focusScale: 1,
      beadDiameter: 56,
      cardHeight: 102
    )
    let anchors = GraphCanvasGeometry.screenEdgeAnchors(
      from: knot,
      to: child,
      origin: origin,
      viewport: viewport,
      startRadius: 4.5,
      endRadius: childNode.radius
    )

    XCTAssertEqual(
      hypot(
        anchors.start.x - anchors.startCenter.x,
        anchors.start.y - anchors.startCenter.y
      ),
      4.5,
      accuracy: 0.5
    )
    XCTAssertEqual(
      hypot(
        anchors.end.x - childNode.center.x,
        anchors.end.y - childNode.center.y
      ),
      childNode.radius,
      accuracy: 0.5
    )
  }

  func testCullingDoesNotAlterScreenEdgeEndpointGeometry() {
    let origin = CGPoint(x: 200, y: 300)
    let viewport = GraphViewportTransform(
      scale: 2.5,
      offset: CGSize(width: 800, height: -650)
    )
    let anchors = GraphCanvasGeometry.screenEdgeAnchors(
      from: CGPoint(x: 92, y: 180),
      to: CGPoint(x: 308, y: 420),
      origin: origin,
      viewport: viewport,
      startRadius: 39,
      endRadius: 32
    )
    let before = anchors

    _ = GraphViewportCulling.isEdgeVisible(
      start: anchors.start,
      end: anchors.end,
      viewportSize: CGSize(width: 393, height: 620)
    )

    XCTAssertEqual(anchors.start, before.start)
    XCTAssertEqual(anchors.end, before.end)
    XCTAssertEqual(anchors.startCenter, before.startCenter)
    XCTAssertEqual(anchors.endCenter, before.endCenter)
  }

  func testNodeGeometryIsIndependentOfDynamicTypeMetrics() {
    let geometry = GraphNodeScreenGeometry.resolve(
      logicalCenter: CGPoint(x: 250, y: 420),
      origin: CGPoint(x: 200, y: 300),
      viewport: GraphViewportTransform(
        scale: 0.6,
        offset: CGSize(width: 18, height: -11)
      ),
      focusScale: 1,
      beadDiameter: 56,
      cardHeight: 102
    )

    XCTAssertEqual(geometry.radius, 16.8, accuracy: 0.0001)
    XCTAssertEqual(geometry.cardPosition.y - geometry.center.y, 23, accuracy: 0.0001)
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

  func testRebuiltGraphRemovesUnlinkedSpouseEdgeAndCoupleKnot() throws {
    let fixture = try makeFixture()
    let before = FamilyGraphStore()
    before.reset(with: fixture.a)
    before.expand(fixture.a)
    XCTAssertTrue(hasEdge(before, fixture.a, fixture.c, kind: .spouse))

    XCTAssertTrue(try RelationshipManager.unlink(
      .spouse,
      person: fixture.a,
      relative: fixture.c
    ))
    let rebuilt = FamilyGraphStore()
    rebuilt.reset(with: fixture.a)
    rebuilt.expand(fixture.a)

    XCTAssertFalse(hasEdge(rebuilt, fixture.a, fixture.c, kind: .spouse))
    XCTAssertNil(rebuilt.nodes[key(fixture.c)])
    XCTAssertTrue(rebuilt.coupleRenderModel.knots.isEmpty)
  }

  func testRebuiltGraphRemovesUnlinkedParentChildEdge() throws {
    let fixture = try makeFixture()
    let before = FamilyGraphStore()
    before.reset(with: fixture.a)
    before.expand(fixture.a)
    XCTAssertTrue(hasEdge(before, fixture.a, fixture.b, kind: .parentChild))

    XCTAssertTrue(try RelationshipManager.unlink(
      .parent,
      person: fixture.a,
      relative: fixture.b
    ))
    let rebuilt = FamilyGraphStore()
    rebuilt.reset(with: fixture.a)
    rebuilt.expand(fixture.a)

    XCTAssertFalse(hasEdge(rebuilt, fixture.a, fixture.b, kind: .parentChild))
    XCTAssertNil(rebuilt.nodes[key(fixture.b)])
  }

  func testRemovingOneParentLinkMovesChildOutOfCoupleKnot() throws {
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
    XCTAssertTrue(RelationshipManager.setSpouse(a, b))
    XCTAssertTrue(RelationshipManager.addChild(child, to: a, includeSpouse: true))

    let before = FamilyGraphStore()
    before.reset(with: a)
    before.expand(a)
    XCTAssertEqual(before.coupleRenderModel.knots.first?.commonChildren, [key(child)])

    XCTAssertTrue(try RelationshipManager.unlink(.parent, person: child, relative: b))
    let rebuilt = FamilyGraphStore()
    rebuilt.reset(with: a)
    rebuilt.expand(a)

    XCTAssertTrue(rebuilt.coupleRenderModel.knots.isEmpty)
    XCTAssertTrue(hasEdge(rebuilt, a, child, kind: .parentChild))
    XCTAssertFalse(hasEdge(rebuilt, b, child, kind: .parentChild))
    XCTAssertFalse(rebuilt.coupleRenderModel.suppressedEdgeIDs.contains(where: { edgeID in
      rebuilt.edges.contains { edge in
        edge.id == edgeID
          && ((edge.from == key(a) && edge.to == key(child))
            || (edge.from == key(child) && edge.to == key(a)))
      }
    }))
  }
}

// MARK: - Family graph layout investigation (diagnostic-only)

/// Human-readable layout invariants. These tests intentionally describe the desired
/// family grouping, even when the current placement algorithm does not satisfy it.
@MainActor
final class FamilyGraphLayoutDiagnosticTests: XCTestCase {
  private struct CanonicalFixture {
    let container: ModelContainer
    let selfPerson: Person
    let father: Person
    let mother: Person
    let paternalGrandfather: Person
    let paternalGrandmother: Person
    let maternalGrandfather: Person
    let maternalGrandmother: Person
  }

  private struct ExtendedFixture {
    let canonical: CanonicalFixture
    let paternalGreatGrandparents: [Person]
    let maternalGreatGrandparents: [Person]
  }

  private func makeContainer() throws -> ModelContainer {
    try ModelContainer(
      for: Person.self,
      Gathering.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
  }

  private func makeCanonicalFixture() throws -> CanonicalFixture {
    let container = try makeContainer()
    let fixture = CanonicalFixture(
      container: container,
      selfPerson: Person(name: "Self", isSelf: true),
      father: Person(name: "Father"),
      mother: Person(name: "Mother"),
      paternalGrandfather: Person(name: "PaternalGrandfather"),
      paternalGrandmother: Person(name: "PaternalGrandmother"),
      maternalGrandfather: Person(name: "MaternalGrandfather"),
      maternalGrandmother: Person(name: "MaternalGrandmother")
    )
    let people = [
      fixture.selfPerson,
      fixture.father,
      fixture.mother,
      fixture.paternalGrandfather,
      fixture.paternalGrandmother,
      fixture.maternalGrandfather,
      fixture.maternalGrandmother,
    ]
    people.forEach(container.mainContext.insert)
    try container.mainContext.save()

    XCTAssertTrue(RelationshipManager.addParentChild(
      parent: fixture.father,
      child: fixture.selfPerson
    ))
    XCTAssertTrue(RelationshipManager.addParentChild(
      parent: fixture.mother,
      child: fixture.selfPerson
    ))
    XCTAssertTrue(RelationshipManager.setSpouse(
      fixture.paternalGrandfather,
      fixture.paternalGrandmother
    ))
    XCTAssertTrue(RelationshipManager.addParentChild(
      parent: fixture.paternalGrandfather,
      child: fixture.father
    ))
    XCTAssertTrue(RelationshipManager.addParentChild(
      parent: fixture.paternalGrandmother,
      child: fixture.father
    ))
    XCTAssertTrue(RelationshipManager.setSpouse(
      fixture.maternalGrandfather,
      fixture.maternalGrandmother
    ))
    XCTAssertTrue(RelationshipManager.addParentChild(
      parent: fixture.maternalGrandfather,
      child: fixture.mother
    ))
    XCTAssertTrue(RelationshipManager.addParentChild(
      parent: fixture.maternalGrandmother,
      child: fixture.mother
    ))
    return fixture
  }

  private func makeExtendedFixture() throws -> ExtendedFixture {
    let canonical = try makeCanonicalFixture()
    let paternal = (1...4).map { Person(name: "PaternalGreatGrandparent\($0)") }
    let maternal = (1...4).map { Person(name: "MaternalGreatGrandparent\($0)") }
    (paternal + maternal).forEach(canonical.container.mainContext.insert)
    try canonical.container.mainContext.save()

    XCTAssertTrue(RelationshipManager.setSpouse(paternal[0], paternal[1]))
    XCTAssertTrue(RelationshipManager.setSpouse(paternal[2], paternal[3]))
    XCTAssertTrue(RelationshipManager.setSpouse(maternal[0], maternal[1]))
    XCTAssertTrue(RelationshipManager.setSpouse(maternal[2], maternal[3]))
    for parent in paternal[0...1] {
      XCTAssertTrue(RelationshipManager.addParentChild(
        parent: parent,
        child: canonical.paternalGrandfather
      ))
    }
    for parent in paternal[2...3] {
      XCTAssertTrue(RelationshipManager.addParentChild(
        parent: parent,
        child: canonical.paternalGrandmother
      ))
    }
    for parent in maternal[0...1] {
      XCTAssertTrue(RelationshipManager.addParentChild(
        parent: parent,
        child: canonical.maternalGrandfather
      ))
    }
    for parent in maternal[2...3] {
      XCTAssertTrue(RelationshipManager.addParentChild(
        parent: parent,
        child: canonical.maternalGrandmother
      ))
    }
    return ExtendedFixture(
      canonical: canonical,
      paternalGreatGrandparents: paternal,
      maternalGreatGrandparents: maternal
    )
  }

  private func key(_ person: Person) -> PersistentModelIDBox {
    PersistentModelIDBox(person.persistentModelID)
  }

  private func node(_ person: Person, in store: FamilyGraphStore) -> GraphNode? {
    store.nodes[key(person)]
  }

  private func positionedPeople(
    in store: FamilyGraphStore,
    level: Int
  ) -> [(person: Person, level: Int, slot: Int)] {
    store.nodes.values
      .filter { $0.level == level }
      .sorted {
        if $0.slot != $1.slot { return $0.slot < $1.slot }
        return $0.person.name < $1.person.name
      }
      .map { ($0.person, $0.level, $0.slot) }
  }

  private func layoutDump(_ store: FamilyGraphStore, level: Int) -> String {
    let lines = positionedPeople(in: store, level: level).map {
      "slot \($0.slot): \($0.person.name) (level \($0.level))"
    }
    return "level \(level):\n" + lines.joined(separator: "\n")
  }

  private func branchSequence(
    store: FamilyGraphStore,
    level: Int,
    first: Set<PersistentModelIDBox>,
    second: Set<PersistentModelIDBox>
  ) -> [Character] {
    positionedPeople(in: store, level: level).compactMap { entry in
      let id = key(entry.person)
      if first.contains(id) { return "P" }
      if second.contains(id) { return "M" }
      return nil
    }
  }

  private func isContiguous(_ sequence: [Character]) -> Bool {
    var closed = Set<Character>()
    var previous: Character?
    for value in sequence {
      if value != previous {
        if closed.contains(value) { return false }
        if let previous { closed.insert(previous) }
        previous = value
      }
    }
    return true
  }

  private func areAdjacent(_ first: Person, _ second: Person, in store: FamilyGraphStore) -> Bool {
    guard let firstNode = node(first, in: store), let secondNode = node(second, in: store),
      firstNode.level == secondNode.level
    else { return false }
    let levelSlots = positionedPeople(in: store, level: firstNode.level).map(\.slot)
    guard let firstIndex = levelSlots.firstIndex(of: firstNode.slot),
      let secondIndex = levelSlots.firstIndex(of: secondNode.slot)
    else { return false }
    return abs(firstIndex - secondIndex) == 1
  }

  private func canonicalStore(
    _ fixture: CanonicalFixture,
    parentOrder: [Person]
  ) -> FamilyGraphStore {
    let store = FamilyGraphStore()
    store.reset(with: fixture.selfPerson)
    store.expand(fixture.selfPerson)
    parentOrder.forEach(store.expand)
    return store
  }

  private func namedPositions(_ store: FamilyGraphStore) -> [String: GraphGridPosition] {
    Dictionary(uniqueKeysWithValues: store.nodes.values.map {
      ($0.person.name, GraphGridPosition(level: $0.level, slot: $0.slot))
    })
  }

  func testDiagnosticCanonicalGenerationCorrectness() throws {
    let fixture = try makeCanonicalFixture()
    let store = canonicalStore(fixture, parentOrder: [fixture.father, fixture.mother])

    XCTAssertEqual(node(fixture.selfPerson, in: store)?.level, 0)
    XCTAssertEqual(node(fixture.father, in: store)?.level, -1)
    XCTAssertEqual(node(fixture.mother, in: store)?.level, -1)
    for grandparent in [
      fixture.paternalGrandfather,
      fixture.paternalGrandmother,
      fixture.maternalGrandfather,
      fixture.maternalGrandmother,
    ] {
      XCTAssertEqual(
        node(grandparent, in: store)?.level,
        -2,
        "\(grandparent.name)\n\(layoutDump(store, level: -2))"
      )
    }
  }

  func testDiagnosticSlotsAreUniqueWithinEveryGeneration() throws {
    let fixture = try makeCanonicalFixture()
    let store = canonicalStore(fixture, parentOrder: [fixture.mother, fixture.father])

    for level in Set(store.nodes.values.map(\.level)) {
      let slots = positionedPeople(in: store, level: level).map(\.slot)
      XCTAssertEqual(
        Set(slots).count,
        slots.count,
        layoutDump(store, level: level)
      )
    }
  }

  func testDiagnosticGrandparentCouplesRemainAdjacentWhenMaternalBranchExpandsFirst() throws {
    let fixture = try makeCanonicalFixture()
    let store = canonicalStore(fixture, parentOrder: [fixture.mother, fixture.father])

    XCTAssertTrue(
      areAdjacent(fixture.paternalGrandfather, fixture.paternalGrandmother, in: store),
      "Paternal couple was split.\n\(layoutDump(store, level: -2))"
    )
    XCTAssertTrue(
      areAdjacent(fixture.maternalGrandfather, fixture.maternalGrandmother, in: store),
      "Maternal couple was split.\n\(layoutDump(store, level: -2))"
    )
  }

  func testDiagnosticGrandparentFamilyBlocksRemainContiguous() throws {
    let fixture = try makeCanonicalFixture()
    let store = canonicalStore(fixture, parentOrder: [fixture.mother, fixture.father])
    let paternal = Set([fixture.paternalGrandfather, fixture.paternalGrandmother].map(key))
    let maternal = Set([fixture.maternalGrandfather, fixture.maternalGrandmother].map(key))
    let sequence = branchSequence(
      store: store,
      level: -2,
      first: paternal,
      second: maternal
    )

    XCTAssertTrue(
      isContiguous(sequence),
      "branch sequence = \(String(sequence))\n\(layoutDump(store, level: -2))"
    )
  }

  func testDiagnosticGreatGrandparentSubtreesRemainContiguous() throws {
    let fixture = try makeExtendedFixture()
    let canonical = fixture.canonical
    let store = canonicalStore(canonical, parentOrder: [canonical.mother, canonical.father])
    [
      canonical.maternalGrandfather,
      canonical.paternalGrandfather,
      canonical.maternalGrandmother,
      canonical.paternalGrandmother,
    ].forEach(store.expand)
    let paternal = Set(fixture.paternalGreatGrandparents.map(key))
    let maternal = Set(fixture.maternalGreatGrandparents.map(key))
    let sequence = branchSequence(
      store: store,
      level: -3,
      first: paternal,
      second: maternal
    )

    XCTAssertTrue(
      isContiguous(sequence),
      "branch sequence = \(String(sequence))\n\(layoutDump(store, level: -3))"
    )
  }

  func testDiagnosticSemanticLayoutIsIndependentOfExpansionOrder() throws {
    let fixture = try makeCanonicalFixture()
    let fatherFirst = canonicalStore(
      fixture,
      parentOrder: [fixture.father, fixture.mother]
    )
    let motherFirst = canonicalStore(
      fixture,
      parentOrder: [fixture.mother, fixture.father]
    )
    let shortestPathDiscovery = FamilyGraphStore()
    shortestPathDiscovery.reset(with: fixture.selfPerson)
    shortestPathDiscovery.expandShortestPath(to: fixture.maternalGrandmother)
    shortestPathDiscovery.expandShortestPath(to: fixture.paternalGrandfather)
    let paternal = Set([fixture.paternalGrandfather, fixture.paternalGrandmother].map(key))
    let maternal = Set([fixture.maternalGrandfather, fixture.maternalGrandmother].map(key))

    for (label, store) in [
      ("father-first", fatherFirst),
      ("mother-first", motherFirst),
      ("shortest-path maternal-first", shortestPathDiscovery),
    ] {
      let sequence = branchSequence(
        store: store,
        level: -2,
        first: paternal,
        second: maternal
      )
      XCTAssertTrue(
        isContiguous(sequence),
        "\(label) sequence = \(String(sequence))\n\(layoutDump(store, level: -2))"
      )
      XCTAssertTrue(
        areAdjacent(fixture.paternalGrandfather, fixture.paternalGrandmother, in: store),
        "\(label): paternal couple split\n\(layoutDump(store, level: -2))"
      )
      XCTAssertTrue(
        areAdjacent(fixture.maternalGrandfather, fixture.maternalGrandmother, in: store),
        "\(label): maternal couple split\n\(layoutDump(store, level: -2))"
      )
    }
  }

  func testDiagnosticLateDiscoveredBranchDoesNotSplitExistingFamilyBlock() throws {
    let fixture = try makeCanonicalFixture()
    let store = FamilyGraphStore()
    store.reset(with: fixture.selfPerson)
    store.expand(fixture.selfPerson)
    store.expand(fixture.mother)
    let maternalBefore = [fixture.maternalGrandfather, fixture.maternalGrandmother]
      .compactMap { node($0, in: store)?.slot }
    store.expand(fixture.father)
    let paternal = Set([fixture.paternalGrandfather, fixture.paternalGrandmother].map(key))
    let maternal = Set([fixture.maternalGrandfather, fixture.maternalGrandmother].map(key))
    let sequence = branchSequence(
      store: store,
      level: -2,
      first: paternal,
      second: maternal
    )

    XCTAssertEqual(
      maternalBefore,
      [fixture.maternalGrandfather, fixture.maternalGrandmother]
        .compactMap { node($0, in: store)?.slot },
      "Previously placed maternal slots moved"
    )
    XCTAssertTrue(
      isContiguous(sequence),
      "late paternal discovery sequence = \(String(sequence))\n\(layoutDump(store, level: -2))"
    )

    let reverseStore = FamilyGraphStore()
    reverseStore.reset(with: fixture.selfPerson)
    reverseStore.expand(fixture.selfPerson)
    reverseStore.expand(fixture.father)
    let paternalBefore = [fixture.paternalGrandfather, fixture.paternalGrandmother]
      .compactMap { node($0, in: reverseStore)?.slot }
    reverseStore.expand(fixture.mother)
    let reverseSequence = branchSequence(
      store: reverseStore,
      level: -2,
      first: paternal,
      second: maternal
    )
    XCTAssertEqual(
      paternalBefore,
      [fixture.paternalGrandfather, fixture.paternalGrandmother]
        .compactMap { node($0, in: reverseStore)?.slot },
      "Previously placed paternal slots moved"
    )
    XCTAssertTrue(
      isContiguous(reverseSequence),
      "late maternal discovery sequence = \(String(reverseSequence))\n"
        + layoutDump(reverseStore, level: -2)
    )
  }

  func testDiagnosticParentGenerationWithUnclesAndAuntsKeepsBranchesContiguous() throws {
    let fixture = try makeCanonicalFixture()
    let paternalUncle = Person(name: "PaternalUncle")
    let maternalAunt = Person(name: "MaternalAunt")
    [paternalUncle, maternalAunt].forEach(fixture.container.mainContext.insert)
    try fixture.container.mainContext.save()
    XCTAssertTrue(RelationshipManager.addParentChild(
      parent: fixture.paternalGrandfather,
      child: paternalUncle
    ))
    XCTAssertTrue(RelationshipManager.addParentChild(
      parent: fixture.paternalGrandmother,
      child: paternalUncle
    ))
    XCTAssertTrue(RelationshipManager.addParentChild(
      parent: fixture.maternalGrandfather,
      child: maternalAunt
    ))
    XCTAssertTrue(RelationshipManager.addParentChild(
      parent: fixture.maternalGrandmother,
      child: maternalAunt
    ))
    let store = canonicalStore(fixture, parentOrder: [fixture.mother, fixture.father])
    store.expand(fixture.paternalGrandfather)
    store.expand(fixture.maternalGrandfather)
    let paternal = Set([fixture.father, paternalUncle].map(key))
    let maternal = Set([fixture.mother, maternalAunt].map(key))
    let sequence = branchSequence(
      store: store,
      level: -1,
      first: paternal,
      second: maternal
    )

    XCTAssertTrue(
      isContiguous(sequence),
      "branch sequence = \(String(sequence))\n\(layoutDump(store, level: -1))"
    )
  }

  func testDiagnosticSpouseParentsDoNotInterleaveWithSelfParents() throws {
    let fixture = try makeCanonicalFixture()
    let spouse = Person(name: "Spouse")
    let spouseParent1 = Person(name: "SpouseParent1")
    let spouseParent2 = Person(name: "SpouseParent2")
    [spouse, spouseParent1, spouseParent2].forEach(fixture.container.mainContext.insert)
    try fixture.container.mainContext.save()
    XCTAssertTrue(RelationshipManager.setSpouse(fixture.selfPerson, spouse))
    XCTAssertTrue(RelationshipManager.addParentChild(parent: spouseParent1, child: spouse))
    XCTAssertTrue(RelationshipManager.addParentChild(parent: spouseParent2, child: spouse))
    let store = canonicalStore(fixture, parentOrder: [])
    store.expand(spouse)
    let own = Set([fixture.father, fixture.mother].map(key))
    let spouseSide = Set([spouseParent1, spouseParent2].map(key))
    let sequence = branchSequence(
      store: store,
      level: -1,
      first: own,
      second: spouseSide
    )

    XCTAssertTrue(
      isContiguous(sequence),
      "branch sequence = \(String(sequence))\n\(layoutDump(store, level: -1))"
    )
  }

  func testDiagnosticIdenticalGraphAndExpansionSequenceIsDeterministic() throws {
    var runs: [[String: (Int, Int)]] = []
    for _ in 0..<5 {
      let fixture = try makeCanonicalFixture()
      let store = canonicalStore(fixture, parentOrder: [fixture.mother, fixture.father])
      runs.append(Dictionary(uniqueKeysWithValues: namedPositions(store).map {
        ($0.key, ($0.value.level, $0.value.slot))
      }))
    }

    for run in runs.dropFirst() {
      XCTAssertEqual(run.count, runs[0].count)
      for (name, position) in runs[0] {
        XCTAssertEqual(run[name]?.0, position.0, "level differed for \(name)")
        XCTAssertEqual(run[name]?.1, position.1, "slot differed for \(name)")
      }
    }
  }

  func testDiagnosticSixPersonMinimalCounterexampleRemainsContiguous() throws {
    let container = try makeContainer()
    let selfPerson = Person(name: "Self", isSelf: true)
    let father = Person(name: "Father")
    let mother = Person(name: "Mother")
    let paternalGrandfather = Person(name: "PaternalGrandfather")
    let paternalGrandmother = Person(name: "PaternalGrandmother")
    let maternalGrandparent = Person(name: "MaternalGrandparent")
    let people = [
      selfPerson, father, mother, paternalGrandfather, paternalGrandmother,
      maternalGrandparent,
    ]
    people.forEach(container.mainContext.insert)
    try container.mainContext.save()
    XCTAssertTrue(RelationshipManager.addParentChild(parent: father, child: selfPerson))
    XCTAssertTrue(RelationshipManager.addParentChild(parent: mother, child: selfPerson))
    XCTAssertTrue(RelationshipManager.setSpouse(paternalGrandfather, paternalGrandmother))
    XCTAssertTrue(RelationshipManager.addParentChild(parent: paternalGrandfather, child: father))
    XCTAssertTrue(RelationshipManager.addParentChild(parent: paternalGrandmother, child: father))
    XCTAssertTrue(RelationshipManager.addParentChild(parent: maternalGrandparent, child: mother))
    let store = FamilyGraphStore()
    store.reset(with: selfPerson)
    store.expand(selfPerson)
    store.expand(mother)
    store.expand(father)
    let paternal = Set([paternalGrandfather, paternalGrandmother].map(key))
    let maternal = Set([maternalGrandparent].map(key))
    let sequence = branchSequence(
      store: store,
      level: -2,
      first: paternal,
      second: maternal
    )

    XCTAssertTrue(
      isContiguous(sequence),
      "minimal six-person sequence = \(String(sequence))\n\(layoutDump(store, level: -2))"
    )
  }

  func testDiagnosticFixedPositionsAndContiguousFamilyBlocksCanCoexistIncrementally() throws {
    let fixture = try makeCanonicalFixture()
    let store = FamilyGraphStore()
    store.reset(with: fixture.selfPerson)
    store.expand(fixture.selfPerson)
    store.expand(fixture.mother)
    let before = layoutDump(store, level: -2)
    let fixedPositions = Dictionary(uniqueKeysWithValues: store.nodes.map {
      ($0.key, ($0.value.level, $0.value.slot))
    })
    store.expand(fixture.father)
    for (id, position) in fixedPositions {
      XCTAssertEqual(store.nodes[id]?.level, position.0)
      XCTAssertEqual(store.nodes[id]?.slot, position.1)
    }
    let paternal = Set([fixture.paternalGrandfather, fixture.paternalGrandmother].map(key))
    let maternal = Set([fixture.maternalGrandfather, fixture.maternalGrandmother].map(key))
    let sequence = branchSequence(
      store: store,
      level: -2,
      first: paternal,
      second: maternal
    )

    XCTAssertTrue(
      isContiguous(sequence),
      "Step before late branch:\n\(before)\nStep after late branch, sequence = \(String(sequence)):\n\(layoutDump(store, level: -2))"
    )
  }

  func testDiagnosticParentChildEdgesDoNotCross() throws {
    let fixture = try makeCanonicalFixture()
    let store = canonicalStore(fixture, parentOrder: [fixture.mother, fixture.father])
    let parentChildEdges = store.edges.compactMap { edge -> (GraphNode, GraphNode)? in
      guard case .parentChild = edge.kind,
        let first = store.nodes[edge.from],
        let second = store.nodes[edge.to],
        abs(first.level - second.level) == 1
      else { return nil }
      return first.level < second.level ? (first, second) : (second, first)
    }
    var crossings: [String] = []
    for firstIndex in parentChildEdges.indices {
      for secondIndex in parentChildEdges.indices where secondIndex > firstIndex {
        let first = parentChildEdges[firstIndex]
        let second = parentChildEdges[secondIndex]
        guard first.0.level == second.0.level,
          first.1.level == second.1.level,
          key(first.0.person) != key(second.0.person),
          key(first.1.person) != key(second.1.person)
        else { continue }
        let upperOrder = first.0.slot - second.0.slot
        let lowerOrder = first.1.slot - second.1.slot
        if upperOrder * lowerOrder < 0 {
          crossings.append(
            "\(first.0.person.name)(\(first.0.slot))->\(first.1.person.name)(\(first.1.slot)) crosses "
              + "\(second.0.person.name)(\(second.0.slot))->\(second.1.person.name)(\(second.1.slot))"
          )
        }
      }
    }

    XCTAssertTrue(
      crossings.isEmpty,
      crossings.joined(separator: "\n") + "\n" + layoutDump(store, level: -2)
        + "\n" + layoutDump(store, level: -1)
    )
  }

  func testDiagnosticPathEmphasisDirectParentIsOrderedAndExclusive() throws {
    let fixture = try makeCanonicalFixture()
    try assertOrderedPath(
      from: fixture.selfPerson,
      to: fixture.father,
      expectedPeople: [fixture.selfPerson, fixture.father]
    )
  }

  func testDiagnosticPathEmphasisGrandparentIsOrderedAndExclusive() throws {
    let fixture = try makeCanonicalFixture()
    try assertOrderedPath(
      from: fixture.selfPerson,
      to: fixture.paternalGrandfather,
      expectedPeople: [fixture.selfPerson, fixture.father, fixture.paternalGrandfather]
    )
  }

  func testDiagnosticPathEmphasisSpouseIsOrderedAndExclusive() throws {
    let fixture = try makeCanonicalFixture()
    let spouse = Person(name: "Spouse")
    fixture.container.mainContext.insert(spouse)
    try fixture.container.mainContext.save()
    XCTAssertTrue(RelationshipManager.setSpouse(fixture.selfPerson, spouse))
    try assertOrderedPath(
      from: fixture.selfPerson,
      to: spouse,
      expectedPeople: [fixture.selfPerson, spouse]
    )
  }

  func testDiagnosticPathEmphasisSpouseSideRelativeIsOrderedAndExclusive() throws {
    let fixture = try makeCanonicalFixture()
    let spouse = Person(name: "Spouse")
    let spouseParent = Person(name: "SpouseParent")
    [spouse, spouseParent].forEach(fixture.container.mainContext.insert)
    try fixture.container.mainContext.save()
    XCTAssertTrue(RelationshipManager.setSpouse(fixture.selfPerson, spouse))
    XCTAssertTrue(RelationshipManager.addParentChild(parent: spouseParent, child: spouse))
    try assertOrderedPath(
      from: fixture.selfPerson,
      to: spouseParent,
      expectedPeople: [fixture.selfPerson, spouse, spouseParent]
    )
  }

  private func assertOrderedPath(
    from root: Person,
    to target: Person,
    expectedPeople: [Person],
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let route = try XCTUnwrap(
      RelationLabeler.shortestRoute(from: root, to: target),
      file: file,
      line: line
    )
    XCTAssertEqual(route.people.map(\.name), expectedPeople.map(\.name), file: file, line: line)
    let actual = GraphPathEmphasis.orderedEdgeEndpoints(for: route)
    let expected = zip(expectedPeople, expectedPeople.dropFirst()).map {
      GraphEdgeEndpoints(key($0.0), key($0.1))
    }
    XCTAssertEqual(actual, expected, file: file, line: line)
    XCTAssertEqual(actual.first, GraphEdgeEndpoints(key(root), key(expectedPeople[1])), file: file, line: line)
    XCTAssertEqual(actual.last, GraphEdgeEndpoints(key(expectedPeople[expectedPeople.count - 2]), key(target)), file: file, line: line)
    XCTAssertEqual(Set(actual), Set(expected), file: file, line: line)
  }
}
