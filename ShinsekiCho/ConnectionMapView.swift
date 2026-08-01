import SwiftData
import SwiftUI

// MARK: - グラフ上のノード・エッジ

/// キャンバス上に配置された1人分の情報。
/// levelは自分を0とした世代(親方向は負、子方向は正)。
/// slotは同じlevel内での横方向の並び順(整数の並び)。
struct GraphNode: Identifiable {
  let person: Person
  var level: Int
  var slot: Int
  var path: [RelationStep]
  var id: PersistentModelIDBox { PersistentModelIDBox(person.persistentModelID) }
}

/// PersistentIdentifierをDictionaryのキー・Identifiableのidとして使うためのラッパー
struct PersistentModelIDBox: Hashable {
  let raw: PersistentIdentifier
  init(_ raw: PersistentIdentifier) { self.raw = raw }
  static func == (l: Self, r: Self) -> Bool { l.raw == r.raw }
  func hash(into hasher: inout Hasher) { hasher.combine(raw) }
}

struct GraphEdge: Identifiable {
  let id = UUID()
  let from: PersistentModelIDBox
  let to: PersistentModelIDBox
  let kind: Kind
  enum Kind { case parentChild, spouse }

  var endpoints: GraphEdgeEndpoints {
    GraphEdgeEndpoints(from, to)
  }
}

/// エッジの向きに依存せず、2人の組を最短経路の照合に使う。
struct GraphEdgeEndpoints: Hashable {
  let people: Set<PersistentModelIDBox>

  init(_ first: PersistentModelIDBox, _ second: PersistentModelIDBox) {
    people = [first, second]
  }
}

/// 人物詳細で強調する「自分から表示中人物まで」の線だけを抽出する。
enum GraphPathEmphasis {
  static func edgeEndpoints(for route: RelationRoute?) -> Set<GraphEdgeEndpoints>? {
    guard let route, route.people.count > 1 else { return nil }
    return Set(
      zip(route.people, route.people.dropFirst()).map { first, second in
        GraphEdgeEndpoints(
          PersistentModelIDBox(first.persistentModelID),
          PersistentModelIDBox(second.persistentModelID)
        )
      })
  }
}

struct GraphGridPosition {
  let level: Int
  let slot: Int
}

struct GraphViewportTransform {
  let scale: CGFloat
  let offset: CGSize

  /// 未変換のグラフ座標を、表示中のキャンバス座標へ変換する。
  /// ノードとエッジの双方がこの同じ変換を参照する。
  func applying(to point: CGPoint, around origin: CGPoint) -> CGPoint {
    CGPoint(
      x: origin.x + (point.x - origin.x) * scale + offset.width,
      y: origin.y + (point.y - origin.y) * scale + offset.height
    )
  }

  func removing(from point: CGPoint, around origin: CGPoint) -> CGPoint {
    guard scale != 0 else { return origin }
    return CGPoint(
      x: origin.x + (point.x - origin.x - offset.width) / scale,
      y: origin.y + (point.y - origin.y - offset.height) / scale
    )
  }
}

struct GraphEdgeAnchors {
  let startCenter: CGPoint
  let endCenter: CGPoint
  let start: CGPoint
  let end: CGPoint
}

/// ノードとエッジが共有する、パン・ズーム前のキャンバス座標。
enum GraphCanvasGeometry {
  static func beadCenter(
    position: GraphGridPosition,
    origin: CGPoint,
    slotWidth: CGFloat,
    levelHeight: CGFloat
  ) -> CGPoint {
    CGPoint(
      x: origin.x + CGFloat(position.slot) * slotWidth,
      y: origin.y + CGFloat(position.level) * levelHeight
    )
  }

  static func edgeAnchors(
    from startCenter: CGPoint,
    to endCenter: CGPoint,
    beadRadius: CGFloat
  ) -> GraphEdgeAnchors {
    let dx = endCenter.x - startCenter.x
    let dy = endCenter.y - startCenter.y
    let distance = hypot(dx, dy)
    guard distance > beadRadius * 2, distance > 0 else {
      return GraphEdgeAnchors(
        startCenter: startCenter,
        endCenter: endCenter,
        start: startCenter,
        end: endCenter
      )
    }
    let unitX = dx / distance
    let unitY = dy / distance
    return GraphEdgeAnchors(
      startCenter: startCenter,
      endCenter: endCenter,
      start: CGPoint(
        x: startCenter.x + unitX * beadRadius,
        y: startCenter.y + unitY * beadRadius
      ),
      end: CGPoint(
        x: endCenter.x - unitX * beadRadius,
        y: endCenter.y - unitY * beadRadius
      )
    )
  }
}

/// 導入時の全体俯瞰と、完了時のフォーカス位置を軽量な算術だけで求める。
enum GraphIntroLayout {
  static func overview(
    positions: [GraphGridPosition],
    viewport: CGSize,
    slotWidth: CGFloat,
    levelHeight: CGFloat,
    haloDiameter: CGFloat = 132
  ) -> GraphViewportTransform {
    guard !positions.isEmpty, viewport.width > 0, viewport.height > 0 else {
      return GraphViewportTransform(scale: 0.6, offset: .zero)
    }

    let xs = positions.map { CGFloat($0.slot) * slotWidth }
    let ys = positions.map { CGFloat($0.level) * levelHeight }
    let minX = xs.min() ?? 0
    let maxX = xs.max() ?? 0
    let minY = ys.min() ?? 0
    let maxY = ys.max() ?? 0
    let contentWidth = maxX - minX + haloDiameter
    let contentHeight = maxY - minY + haloDiameter
    let availableWidth = max(viewport.width - 24, 1)
    // 下部の凡例と四辺フェードを避ける分を確保する。
    let availableHeight = max(viewport.height - 88, 1)
    let fittedScale = min(
      0.6,
      availableWidth / max(contentWidth, 1),
      availableHeight / max(contentHeight, 1)
    )
    let centerX = (minX + maxX) / 2
    let centerY = (minY + maxY) / 2
    return GraphViewportTransform(
      scale: fittedScale,
      offset: CGSize(width: -centerX * fittedScale, height: -centerY * fittedScale)
    )
  }

  static func focus(
    position: GraphGridPosition,
    slotWidth: CGFloat,
    levelHeight: CGFloat
  ) -> GraphViewportTransform {
    GraphViewportTransform(
      scale: 1,
      offset: CGSize(
        width: -CGFloat(position.slot) * slotWidth,
        height: -CGFloat(position.level) * levelHeight
      )
    )
  }
}

enum QuickRelationKind: String {
  case spouse
  case parent
  case child

  var menuTitle: String {
    switch self {
    case .spouse: "配偶者を追加"
    case .parent: "親を追加"
    case .child: "子を追加"
    }
  }

  var systemImage: String {
    switch self {
    case .spouse: "heart"
    case .parent: "arrow.up"
    case .child: "arrow.down"
    }
  }
}

private struct QuickRelativeRequest: Identifiable {
  let id = UUID()
  let person: Person
  let kind: QuickRelationKind
}

private struct GraphNodeActionRequest: Identifiable {
  let id = UUID()
  let person: Person
}

enum QuickRelativeRegistrationError: LocalizedError {
  case emptyName
  case spouseLimit
  case parentLimit
  case saveFailed

  var errorDescription: String? {
    switch self {
    case .emptyName: "名前を入力してください。"
    case .spouseLimit: "配偶者は1人まで登録できます。"
    case .parentLimit: "親は2人まで登録できます。"
    case .saveFailed: "保存できませんでした。もう一度お試しください。"
    }
  }
}

/// 長押し登録の表示条件と保存時制約を一箇所で管理する。
enum QuickRelativeRegistration {
  static func canAdd(_ kind: QuickRelationKind, to person: Person) -> Bool {
    switch kind {
    case .spouse: person.spouse == nil
    case .parent: person.parents.count < 2
    case .child: true
    }
  }

  @discardableResult
  static func create(
    named rawName: String,
    kind: QuickRelationKind,
    for person: Person,
    in context: ModelContext
  ) throws -> Person {
    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { throw QuickRelativeRegistrationError.emptyName }
    guard canAdd(kind, to: person) else {
      switch kind {
      case .spouse: throw QuickRelativeRegistrationError.spouseLimit
      case .parent: throw QuickRelativeRegistrationError.parentLimit
      case .child: break
      }
      throw QuickRelativeRegistrationError.saveFailed
    }

    let newPerson = Person(name: name)
    context.insert(newPerson)
    switch kind {
    case .spouse:
      RelationshipManager.setSpouse(person, newPerson)
    case .parent:
      RelationshipManager.addParentChild(parent: newPerson, child: person)
    case .child:
      RelationshipManager.addChild(newPerson, to: person)
    }

    do {
      try context.save()
    } catch {
      RelationshipManager.detachAll(newPerson)
      context.delete(newPerson)
      throw QuickRelativeRegistrationError.saveFailed
    }
    return newPerson
  }
}

/// 自分から見た経路を、地図上の3つの家系色へ分類する。
enum FamilyBranch: String, CaseIterable, Hashable {
  case indigo
  case forest
  case plum

  static func classify(path: [RelationStep]) -> Self {
    if path.isEmpty || path.allSatisfy({ $0 == .parent })
      || path.allSatisfy({ $0 == .child })
    {
      return .indigo
    }
    if path.contains(.spouse) {
      return .forest
    }
    return .plum
  }

  var color: Color {
    switch self {
    case .indigo: AppTheme.branchIndigo
    case .forest: AppTheme.branchForest
    case .plum: AppTheme.branchPlum
    }
  }

  var legendLabel: String {
    switch self {
    case .indigo: "直系"
    case .forest: "配偶者側"
    case .plum: "外側の家系"
    }
  }
}

/// Canvasの曲線と同じ制御点を使い、trimで線が描かれる過程を表現する。
private struct GraphEdgeShape: Shape {
  var start: CGPoint
  var end: CGPoint

  func path(in rect: CGRect) -> Path {
    let middleY = (start.y + end.y) / 2
    var path = Path()
    path.move(to: start)
    path.addCurve(
      to: end,
      control1: CGPoint(x: start.x, y: middleY),
      control2: CGPoint(x: end.x, y: middleY)
    )
    return path
  }
}

/// 描画順序を1箇所に固定する契約。ZStack内でも必ずedge→nodeの順に置く。
enum GraphRenderLayer: Double {
  case edges = 0
  case nodes = 1
}

/// 半透明の家系色や写真より下に、必ず不透明な紙面を敷くための契約。
enum GraphNodeSurfaceContract {
  static let baseOpacity = 1.0
  static let inactiveContentOpacity = 0.92
}

// MARK: - グラフの構築・拡張ロジック(コア部分)
//
// 「タップ=画面の置き換え」ではなく「タップ=キャンバスへの追加」。
// 一度配置した人物のlevel/slotは変更しない(位置の安定性を優先)。

@Observable
final class FamilyGraphStore {
  private(set) var nodes: [PersistentModelIDBox: GraphNode] = [:]
  private(set) var edges: [GraphEdge] = []
  private var nextSlot: [Int: Int] = [:]  // level -> 次に使う空きslot
  private var rootID: PersistentModelIDBox?

  /// 自分を起点にグラフを初期化する
  func reset(with selfPerson: Person) {
    nodes = [:]
    edges = []
    nextSlot = [:]
    rootID = PersistentModelIDBox(selfPerson.persistentModelID)
    place(selfPerson, level: 0, path: [])
  }

  /// 指定した人物の直接のつながり(親・子・配偶者)を展開する。
  /// 既にキャンバスにいる人物には新しいノードを作らず、エッジだけ追加する。
  func expand(_ person: Person) {
    guard let center = nodes[PersistentModelIDBox(person.persistentModelID)] else { return }

    for parent in person.parents {
      let node = placeIfNeeded(
        parent,
        level: center.level - 1,
        path: center.path + [.parent]
      )
      addEdgeIfNeeded(from: parent, to: person, kind: .parentChild)
      _ = node
    }
    for child in person.children {
      _ = placeIfNeeded(
        child,
        level: center.level + 1,
        path: center.path + [.child]
      )
      addEdgeIfNeeded(from: person, to: child, kind: .parentChild)
    }
    if let spouse = person.spouse {
      _ = placeIfNeeded(
        spouse,
        level: center.level,
        path: center.path + [.spouse]
      )
      addEdgeIfNeeded(from: person, to: spouse, kind: .spouse)
    }
    // 兄弟姉妹は「共通の親」を介して自動的に見えるようになるため、
    // ここでは明示的なノード追加はしない(親を展開すれば子として現れる)。
    refreshShortestPaths()
  }

  /// 自分から表示対象までの最短経路上にいる人物を順に展開する。
  /// 対象自身は、その直前の人物を展開した時点で表示されるため展開しない。
  /// 自分自身、または経路が見つからない場合は従来通り自分だけを展開する。
  @discardableResult
  func expandShortestPath(to target: Person) -> Set<PersistentModelIDBox> {
    guard let rootID, let root = nodes[rootID]?.person else { return [] }

    let peopleToExpand: [Person]
    if let route = RelationLabeler.shortestRoute(from: root, to: target),
      route.people.count > 1
    {
      peopleToExpand = Array(route.people.dropLast())
    } else {
      peopleToExpand = [root]
    }

    var expanded: Set<PersistentModelIDBox> = []
    for person in peopleToExpand {
      let id = PersistentModelIDBox(person.persistentModelID)
      guard nodes[id] != nil else { continue }
      expand(person)
      expanded.insert(id)
    }
    return expanded
  }

  private func placeIfNeeded(
    _ person: Person,
    level: Int,
    path: [RelationStep]
  ) -> GraphNode {
    let key = PersistentModelIDBox(person.persistentModelID)
    if var existing = nodes[key] {
      // 配置は固定したまま、後からより短い経路が見つかった場合だけ
      // 続柄表示に使う経路を更新する。同じ長さなら最初の経路を保つ。
      if path.count < existing.path.count {
        existing.path = path
        nodes[key] = existing
      }
      return existing
    }
    return place(person, level: level, path: path)
  }

  @discardableResult
  private func place(
    _ person: Person,
    level: Int,
    path: [RelationStep]
  ) -> GraphNode {
    let index = nextSlot[level, default: 0]
    nextSlot[level] = index + 1
    let slot: Int
    if index == 0 {
      slot = 0
    } else {
      let distance = (index + 1) / 2
      slot = index.isMultiple(of: 2) ? distance : -distance
    }
    let node = GraphNode(person: person, level: level, slot: slot, path: path)
    nodes[PersistentModelIDBox(person.persistentModelID)] = node
    return node
  }

  private func addEdgeIfNeeded(from: Person, to: Person, kind: GraphEdge.Kind) {
    let a = PersistentModelIDBox(from.persistentModelID)
    let b = PersistentModelIDBox(to.persistentModelID)
    let exists = edges.contains {
      ($0.from == a && $0.to == b) || ($0.from == b && $0.to == a)
    }
    if !exists {
      edges.append(GraphEdge(from: a, to: b, kind: kind))
    }
  }

  /// 現在表示中のエッジだけを使い、自分から各ノードへの最短経路を再計算する。
  /// 幅優先探索なので、同じ距離の経路が複数ある場合は最初に追加された経路を保つ。
  private func refreshShortestPaths() {
    guard let rootID, nodes[rootID] != nil else { return }

    let traversal = RelationLabeler.breadthFirstPaths(from: rootID) { current in
      var neighbors: [(node: PersistentModelIDBox, step: RelationStep)] = []
      for edge in edges {
        let next: PersistentModelIDBox
        let step: RelationStep

        if edge.from == current {
          next = edge.to
          step = edge.kind == .spouse ? .spouse : .child
        } else if edge.to == current {
          next = edge.from
          step = edge.kind == .spouse ? .spouse : .parent
        } else {
          continue
        }
        neighbors.append((next, step))
      }
      return neighbors
    }

    for (id, path) in traversal.paths {
      guard var node = nodes[id] else { continue }
      node.path = path
      nodes[id] = node
    }
  }

  func branch(for nodeID: PersistentModelIDBox) -> FamilyBranch {
    FamilyBranch.classify(path: nodes[nodeID]?.path ?? [])
  }

  /// 線は原則として自分から遠い側のノードの家系色を引き継ぐ。
  /// 距離が同じ場合は、直系から分岐する側の色を優先する。
  func branch(for edge: GraphEdge) -> FamilyBranch {
    guard let fromNode = nodes[edge.from], let toNode = nodes[edge.to] else {
      return .indigo
    }
    let fromBranch = FamilyBranch.classify(path: fromNode.path)
    let toBranch = FamilyBranch.classify(path: toNode.path)
    if fromNode.path.count != toNode.path.count {
      return fromNode.path.count > toNode.path.count ? fromBranch : toBranch
    }
    if fromBranch == .plum || toBranch == .plum { return .plum }
    if fromBranch == .forest || toBranch == .forest { return .forest }
    return .indigo
  }

  func isExpanded(_ person: Person, expandedSet: Set<PersistentModelIDBox>) -> Bool {
    expandedSet.contains(PersistentModelIDBox(person.persistentModelID))
  }
}

// MARK: - 表示: パン・ズームできる蓄積型キャンバス

struct FamilyGraphView: View {
  let selfPerson: Person
  let displayedPerson: Person
  var viewportHeight: CGFloat? = 420
  var playsIntroAnimation = true
  var canvasIdentifier = "connectionMap.canvas"
  var resetButtonIdentifier = "connectionMap.resetButton"
  var onSelect: (Person) -> Void = { _ in }
  var onShowDetail: (Person) -> Void = { _ in }

  @Environment(\.modelContext) private var modelContext
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(TrialManager.self) private var trialManager

  @State private var store = FamilyGraphStore()
  @State private var expandedIDs: Set<PersistentModelIDBox> = []
  @State private var visibleNodeIDs: Set<PersistentModelIDBox> = []
  @State private var edgeProgress: [UUID: CGFloat] = [:]
  @State private var emphasizedPathEdges: Set<GraphEdgeEndpoints>?
  @State private var bouncingNodeID: PersistentModelIDBox?
  @State private var nodeActionRequest: GraphNodeActionRequest?
  @State private var quickRelativeRequest: QuickRelativeRequest?
  @State private var pendingQuickRelativeRequest: QuickRelativeRequest?
  @State private var pendingDetailPerson: Person?
  @State private var pendingPurchaseAfterNodeAction = false
  @State private var suppressTapAfterLongPress = false
  @State private var showingPurchaseSheet = false
  @State private var pendingExpansionSourceID: PersistentModelIDBox?
  @State private var introAnimationToken = UUID()
  @State private var introPhase = "完了"

  @State private var scale: CGFloat = 1.0
  @GestureState private var pinchDelta: CGFloat = 1.0
  @State private var offset: CGSize = .zero
  @GestureState private var dragDelta: CGSize = .zero

  private let levelHeight: CGFloat = 120
  private let slotWidth: CGFloat = 108
  private let nodeSize: CGFloat = 68
  private let nodeCardWidth: CGFloat = 92
  private let beadDiameter: CGFloat = 56
  private let nodeCardHeight: CGFloat = 102

  var body: some View {
    GeometryReader { geo in
      // 親・本人・子の3世代すべてに、画面端と重ならないタップ余白を確保する。
      let origin = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
      let effectiveScale = scale * pinchDelta
      let liveOffset = CGSize(
        width: offset.width + dragDelta.width,
        height: offset.height + dragDelta.height
      )
      let viewportTransform = GraphViewportTransform(
        scale: effectiveScale,
        offset: liveOffset
      )

      ZStack {
        AppTheme.paper

        ZStack {
          // 線とノードを同じ未変換座標系に置き、親レイヤーへ一度だけ
          // パン・ズームを適用する。線だけ／ノードだけの二重変換を防ぐ。
          ZStack {
            ForEach(store.edges) { edge in
              if let a = store.nodes[edge.from], let b = store.nodes[edge.to] {
                let anchors = edgeAnchors(from: a, to: b, origin: origin)
                let isEmphasized = emphasizedPathEdges?.contains(edge.endpoints) ?? true
                let normalWidth: CGFloat = edge.kind == .spouse ? 2.5 : 1.5
                GraphEdgeShape(start: anchors.start, end: anchors.end)
                  .trim(from: 0, to: edgeProgress[edge.id] ?? 0)
                  .stroke(
                    store.branch(for: edge).color.opacity(isEmphasized ? 1 : 0.35),
                    style: StrokeStyle(
                      lineWidth: isEmphasized ? normalWidth : normalWidth * 0.5,
                      lineCap: .round,
                      lineJoin: .round
                    )
                  )
                  .accessibilityHidden(true)
              }
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .zIndex(GraphRenderLayer.edges.rawValue)
          .accessibilityElement(children: .ignore)
          .accessibilityIdentifier("connectionMap.edgeLayer")
          .accessibilityValue("最背面")

          // ノードは描画順でもzIndexでも接続線より前面に固定する。
          ZStack {
            ForEach(Array(store.nodes.values), id: \.id) { node in
              let beadCenter = graphPosition(node, origin: origin)
              GraphNodeCard(
                person: node.person,
                isSelf: node.person.persistentModelID == selfPerson.persistentModelID,
                isFocused: node.person.persistentModelID == displayedPerson.persistentModelID,
                isExpanded: expandedIDs.contains(node.id),
                relationLabel: RelationLabeler.label(for: node.path),
                branch: store.branch(for: node.id)
              )
              .frame(width: nodeCardWidth, height: nodeCardHeight, alignment: .top)
              .position(
                x: beadCenter.x,
                y: beadCenter.y + (nodeCardHeight - beadDiameter) / 2
              )
              // 登場・バウンスは珠の中心を固定した局所アニメーションに限定する。
              .scaleEffect(
                (visibleNodeIDs.contains(node.id) ? 1 : 0.3)
                  * (bouncingNodeID == node.id ? 1.08 : 1),
                anchor: UnitPoint(x: 0.5, y: (beadDiameter / 2) / nodeCardHeight)
              )
              .opacity(visibleNodeIDs.contains(node.id) ? 1 : 0)
              .accessibilityElement(children: .ignore)
              .accessibilityAddTraits(.isButton)
              .accessibilityIdentifier("connectionMap.node.\(node.person.name)")
              .accessibilityLabel(node.person.name)
              .accessibilityValue(expandedIDs.contains(node.id) ? "展開済み" : "未展開")
              .accessibilityAction {
                expand(node)
              }
              .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.55, maximumDistance: 12)
                  .onEnded { _ in
                    presentNodeActions(for: node.person)
                  }
                )
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .zIndex(GraphRenderLayer.nodes.rawValue)
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier("connectionMap.nodeLayer")
          .accessibilityValue("最前面")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(viewportTransform.scale, anchor: .center)
        .offset(viewportTransform.offset)
      }
      // 子のノードButtonと同時に認識させ、単純なタップを奪わない。
      .simultaneousGesture(
        MagnificationGesture()
          .updating($pinchDelta) { value, state, _ in state = value }
          .onEnded { value in
            cancelIntroAnimation()
            let proposedScale = scale * value
            if proposedScale <= 0.45 {
              scale = 0.4
            } else if proposedScale >= 2.4 {
              scale = 2.5
            } else {
              scale = proposedScale
            }
          }
      )
      .simultaneousGesture(
        DragGesture(minimumDistance: 0)
          .updating($dragDelta) { value, state, _ in
            if hypot(value.translation.width, value.translation.height) >= 10 {
              state = value.translation
            }
          }
          .onEnded { value in
            cancelIntroAnimation()
            if suppressTapAfterLongPress {
              suppressTapAfterLongPress = false
              return
            }
            if hypot(value.translation.width, value.translation.height) < 10 {
              if let node = node(
                at: value.location,
                origin: origin,
                transform: viewportTransform
              ) {
                expand(node)
              }
            } else {
              offset.width += value.translation.width
              offset.height += value.translation.height
            }
          }
      )
      .clipped()
      // パン・ズームするグラフの外側に固定し、四辺で紙色へ自然に溶かす。
      .overlay {
        CanvasEdgeFade()
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
      .onAppear {
        prepareInitialGraph(viewport: geo.size)
      }
    }
    .frame(height: viewportHeight)
    .overlay(alignment: .bottom) {
      FamilyBranchLegend()
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
    .overlay(alignment: .bottomTrailing) {
      Button {
        resetViewport()
      } label: {
        Image(systemName: "scope")
          .padding(10)
          .background(AppTheme.paperRaised, in: Circle())
          .overlay(Circle().stroke(AppTheme.ruleStrong, lineWidth: 1))
      }
      .accessibilityIdentifier(resetButtonIdentifier)
      .highPriorityGesture(
        TapGesture().onEnded { resetViewport() }
      )
      .padding(.trailing, 12)
      .padding(.bottom, 38)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(canvasIdentifier)
    .accessibilityValue(canvasAccessibilityValue)
    .onDisappear { cancelIntroAnimation() }
    .sheet(
      item: $nodeActionRequest,
      onDismiss: performPendingNodeAction
    ) { request in
      GraphNodeActionSheet(
        person: request.person,
        onDetail: { queueDetail(for: request.person) },
        onAdd: { queueQuickAdd($0, for: request.person) }
      )
    }
    .sheet(
      item: $quickRelativeRequest,
      onDismiss: expandPendingQuickRelative
    ) { request in
      QuickRelativeAddSheet(person: request.person, kind: request.kind) { name in
        guard trialManager.canEdit else {
          throw QuickRelativeRegistrationError.saveFailed
        }
        try QuickRelativeRegistration.create(
          named: name,
          kind: request.kind,
          for: request.person,
          in: modelContext
        )
        pendingExpansionSourceID = PersistentModelIDBox(
          request.person.persistentModelID
        )
      }
    }
    .sheet(isPresented: $showingPurchaseSheet) {
      PurchaseSheet()
    }
    // blurを含む後光も最終的なキャンバス境界で合成・切り抜きする。
    // 親のListをスクロールしても、見出しカード側へ描画が漏れない。
    .compositingGroup()
    .clipped()
  }

  private func resetViewport() {
    cancelIntroAnimation()
    scale = 1.0
    offset = .zero
  }

  private var canvasAccessibilityValue: String {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("-ui-testing-family-graph-ux") {
        return "\(introPhase)|scale:\(String(format: "%.2f", scale * pinchDelta))"
      }
    #endif
    return introPhase
  }

  private func graphPosition(_ node: GraphNode, origin: CGPoint) -> CGPoint {
    GraphCanvasGeometry.beadCenter(
      position: GraphGridPosition(level: node.level, slot: node.slot),
      origin: origin,
      slotWidth: slotWidth,
      levelHeight: levelHeight
    )
  }

  private func edgeAnchors(
    from first: GraphNode,
    to second: GraphNode,
    origin: CGPoint
  ) -> GraphEdgeAnchors {
    GraphCanvasGeometry.edgeAnchors(
      from: graphPosition(first, origin: origin),
      to: graphPosition(second, origin: origin),
      beadRadius: beadDiameter / 2
    )
  }

  private func expand(_ node: GraphNode) {
    cancelIntroAnimation()
    let previousNodeIDs = Set(store.nodes.keys)
    let previousEdgeIDs = Set(store.edges.map(\.id))
    store.expand(node.person)
    let addedNodeIDs = Set(store.nodes.keys).subtracting(previousNodeIDs)
    let addedEdgeIDs = Set(store.edges.map(\.id)).subtracting(previousEdgeIDs)

    _ = withAnimation(.easeInOut(duration: reduceMotion ? 0 : 0.2)) {
      expandedIDs.insert(node.id)
    }
    animateNewContent(nodeIDs: addedNodeIDs, edgeIDs: addedEdgeIDs)
    bounce(node.id)
    onSelect(node.person)
  }

  private func presentNodeActions(for person: Person) {
    suppressTapAfterLongPress = true
    nodeActionRequest = GraphNodeActionRequest(person: person)
  }

  private func queueDetail(for person: Person) {
    pendingDetailPerson = person
    nodeActionRequest = nil
  }

  private func queueQuickAdd(_ kind: QuickRelationKind, for person: Person) {
    if trialManager.canEdit {
      pendingQuickRelativeRequest = QuickRelativeRequest(person: person, kind: kind)
    } else {
      pendingPurchaseAfterNodeAction = true
    }
    nodeActionRequest = nil
  }

  private func performPendingNodeAction() {
    suppressTapAfterLongPress = false
    let detail = pendingDetailPerson
    let quickRequest = pendingQuickRelativeRequest
    let showPurchase = pendingPurchaseAfterNodeAction
    pendingDetailPerson = nil
    pendingQuickRelativeRequest = nil
    pendingPurchaseAfterNodeAction = false

    DispatchQueue.main.async {
      if let detail {
        onShowDetail(detail)
      } else if let quickRequest {
        quickRelativeRequest = quickRequest
      } else if showPurchase {
        showingPurchaseSheet = true
      }
    }
  }

  private func expandPendingQuickRelative() {
    guard let sourceID = pendingExpansionSourceID,
      let sourceNode = store.nodes[sourceID]
    else { return }
    pendingExpansionSourceID = nil
    expand(sourceNode)
  }

  private func prepareInitialGraph(viewport: CGSize) {
    let animationToken = UUID()
    introAnimationToken = animationToken
    store.reset(with: selfPerson)
    expandedIDs = []
    visibleNodeIDs = []
    edgeProgress = [:]
    emphasizedPathEdges = GraphPathEmphasis.edgeEndpoints(
      for: RelationLabeler.shortestRoute(from: selfPerson, to: displayedPerson)
    )
    bouncingNodeID = nil

    let selfID = PersistentModelIDBox(selfPerson.persistentModelID)
    visibleNodeIDs.insert(selfID)
    let previousNodeIDs = Set(store.nodes.keys)
    expandedIDs.formUnion(store.expandShortestPath(to: displayedPerson))
    let addedNodeIDs = Set(store.nodes.keys).subtracting(previousNodeIDs)

    if playsIntroAnimation && !reduceMotion {
      let overview = GraphIntroLayout.overview(
        positions: store.nodes.values.map {
          GraphGridPosition(level: $0.level, slot: $0.slot)
        },
        viewport: viewport,
        slotWidth: slotWidth,
        levelHeight: levelHeight
      )
      scale = overview.scale
      offset = overview.offset
      introPhase = "全体表示"
      animateIntroToFocusedPerson(token: animationToken)
    } else {
      scale = 1
      offset = .zero
      introPhase = "完了"
    }

    animateNewContent(
      nodeIDs: addedNodeIDs,
      edgeIDs: Set(store.edges.map(\.id))
    )
  }

  private func animateIntroToFocusedPerson(token: UUID) {
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 450_000_000)
      guard introAnimationToken == token else { return }

      let displayedID = PersistentModelIDBox(displayedPerson.persistentModelID)
      let selfID = PersistentModelIDBox(selfPerson.persistentModelID)
      guard let target = store.nodes[displayedID] ?? store.nodes[selfID] else { return }
      let focused = GraphIntroLayout.focus(
        position: GraphGridPosition(level: target.level, slot: target.slot),
        slotWidth: slotWidth,
        levelHeight: levelHeight
      )
      introPhase = "ズーム中"
      withAnimation(.easeInOut(duration: 0.6)) {
        scale = focused.scale
        offset = focused.offset
      }

      try? await Task.sleep(nanoseconds: 600_000_000)
      guard introAnimationToken == token else { return }
      introPhase = "完了"
    }
  }

  private func cancelIntroAnimation() {
    introAnimationToken = UUID()
    introPhase = "完了"
  }

  private func animateNewContent(
    nodeIDs: Set<PersistentModelIDBox>,
    edgeIDs: Set<UUID>
  ) {
    guard !nodeIDs.isEmpty || !edgeIDs.isEmpty else { return }
    if reduceMotion {
      visibleNodeIDs.formUnion(nodeIDs)
      for id in edgeIDs { edgeProgress[id] = 1 }
      return
    }

    // 初期値(ノード0.3倍、線trim=0)を一度描画してから同時に開始する。
    for id in edgeIDs { edgeProgress[id] = 0 }
    DispatchQueue.main.async {
      withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
        visibleNodeIDs.formUnion(nodeIDs)
      }
      withAnimation(.easeInOut(duration: 0.4)) {
        for id in edgeIDs { edgeProgress[id] = 1 }
      }
    }
  }

  private func bounce(_ nodeID: PersistentModelIDBox) {
    guard !reduceMotion else { return }
    withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
      bouncingNodeID = nodeID
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
      guard bouncingNodeID == nodeID else { return }
      withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
        bouncingNodeID = nil
      }
    }
  }

  private func node(
    at location: CGPoint,
    origin: CGPoint,
    transform: GraphViewportTransform
  ) -> GraphNode? {
    let graphLocation = transform.removing(from: location, around: origin)
    let hitRadius = max(44 / max(transform.scale, 0.01), beadDiameter / 2)
    return store.nodes.values
      .map { node in
        let point = graphPosition(node, origin: origin)
        return (node, hypot(point.x - graphLocation.x, point.y - graphLocation.y))
      }
      .filter { $0.1 <= hitRadius }
      .min { $0.1 < $1.1 }?
      .0
  }
}

private struct GraphNodeActionSheet: View {
  let person: Person
  let onDetail: () -> Void
  let onAdd: (QuickRelationKind) -> Void

  private var availableKinds: [QuickRelationKind] {
    [QuickRelationKind.spouse, .parent, .child].filter {
      QuickRelativeRegistration.canAdd($0, to: person)
    }
  }

  private var sheetHeight: CGFloat {
    100 + CGFloat(1 + availableKinds.count) * 48
  }

  var body: some View {
    VStack(spacing: 0) {
      Capsule()
        .fill(AppTheme.ruleStrong)
        .frame(width: 34, height: 4)
        .padding(.top, 10)
        .padding(.bottom, 14)

      Text(person.name)
        .font(.minchoTitle(19, relativeTo: .headline))
        .foregroundStyle(AppTheme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 10)

      actionButton(
        title: "詳細を見る",
        systemImage: "person.text.rectangle",
        identifier: "connectionMap.menu.detail",
        action: onDetail
      )

      ForEach(availableKinds, id: \.rawValue) { kind in
        actionButton(
          title: kind.menuTitle,
          systemImage: kind.systemImage,
          identifier: "connectionMap.menu.\(kind.rawValue)"
        ) {
          onAdd(kind)
        }
      }
    }
    .padding(.bottom, 16)
    .background(AppTheme.paper)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("connectionMap.actionSheet")
    .presentationDetents([.height(sheetHeight)])
    .presentationDragIndicator(.hidden)
    .presentationBackground(AppTheme.paper)
  }

  private func actionButton(
    title: String,
    systemImage: String,
    identifier: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: systemImage)
          .frame(width: 22)
          .foregroundStyle(AppTheme.ai)
        Text(title)
          .foregroundStyle(AppTheme.ink)
        Spacer()
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(AppTheme.inkSoft)
      }
      .padding(.horizontal, 20)
      .frame(minHeight: 48)
      .background(AppTheme.paperRaised)
    }
    .buttonStyle(.plain)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(AppTheme.rule)
        .frame(height: 1)
        .padding(.leading, 54)
    }
    .accessibilityIdentifier(identifier)
  }
}

private struct QuickRelativeAddSheet: View {
  @Environment(\.dismiss) private var dismiss
  let person: Person
  let kind: QuickRelationKind
  let onSave: (String) throws -> Void

  @State private var name = ""
  @State private var errorMessage: String?
  @FocusState private var isNameFocused: Bool

  var body: some View {
    NavigationStack {
      VStack(spacing: 18) {
        Text("\(person.name)の\(kind.menuTitle.replacingOccurrences(of: "を追加", with: ""))")
          .font(.subheadline)
          .foregroundStyle(AppTheme.inkSoft)

        TextField("名前", text: $name)
          .textInputAutocapitalization(.never)
          .textFieldStyle(.roundedBorder)
          .focused($isNameFocused)
          .submitLabel(.done)
          .onSubmit(save)
          .accessibilityIdentifier("quickRelative.name")

        if let errorMessage {
          Text(errorMessage)
            .font(.footnote)
            .foregroundStyle(AppTheme.attention)
        }

        Button(action: save) {
          Text("保存")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.ai)
        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("quickRelative.save")
      }
      .padding(24)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background(AppTheme.paper)
      .navigationTitle(kind.menuTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
      }
      .onAppear { isNameFocused = true }
    }
    .presentationDetents([.height(260)])
  }

  private func save() {
    do {
      try onSave(name)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

/// 地図の表示窓に固定する四辺のフェード。グラフ本体の座標変換には含めない。
private struct CanvasEdgeFade: View {
  private let fadeDepth: CGFloat = 32

  var body: some View {
    ZStack {
      VStack(spacing: 0) {
        LinearGradient(
          colors: [AppTheme.paper, AppTheme.paper.opacity(0)],
          startPoint: .top,
          endPoint: .bottom
        )
        .frame(height: fadeDepth)
        Spacer(minLength: 0)
        LinearGradient(
          colors: [AppTheme.paper.opacity(0), AppTheme.paper],
          startPoint: .top,
          endPoint: .bottom
        )
        .frame(height: fadeDepth)
      }

      HStack(spacing: 0) {
        LinearGradient(
          colors: [AppTheme.paper, AppTheme.paper.opacity(0)],
          startPoint: .leading,
          endPoint: .trailing
        )
        .frame(width: fadeDepth)
        Spacer(minLength: 0)
        LinearGradient(
          colors: [AppTheme.paper.opacity(0), AppTheme.paper],
          startPoint: .leading,
          endPoint: .trailing
        )
        .frame(width: fadeDepth)
      }
    }
  }
}

// MARK: - ノード1個の見た目

private struct GraphNodeCard: View {
  let person: Person
  var isSelf: Bool
  var isFocused: Bool
  var isExpanded: Bool
  var relationLabel: String
  var branch: FamilyBranch

  private var photoImage: UIImage? {
    PersonPhotoSupport.image(from: person.photoData)
  }

  private var contentOpacity: Double {
    isExpanded ? 1 : GraphNodeSurfaceContract.inactiveContentOpacity
  }

  var body: some View {
    VStack(spacing: 4) {
      ZStack {
        Circle()
          .fill(
            AppTheme.paperRaised.opacity(GraphNodeSurfaceContract.baseOpacity)
          )

        // 未展開時の質感差は内容だけに適用する。不透明な紙面は薄くせず、
        // 写真なし・透過写真・破損写真のすべてで線を確実に遮蔽する。
        Group {
          if let uiImage = photoImage {
            Image(uiImage: uiImage).resizable().scaledToFill()
          } else {
            Circle().fill(AppTheme.ai.opacity(0.08))
          }

          Circle()
            .fill((isSelf ? AppTheme.attention : branch.color).opacity(0.08))

          if photoImage == nil {
            Text(PersonPhotoSupport.initial(for: person.name))
              .font(.minchoTitle(20, relativeTo: .headline))
              .foregroundStyle(AppTheme.ai)
          }
        }
        .opacity(contentOpacity)
      }
      .frame(width: 56, height: 56)
      .clipShape(Circle())
      .overlay(
        Circle().stroke(
          branch.color,
          lineWidth: isSelf ? 2.5 : (photoImage == nil ? 1 : 1.5)
        )
        .opacity(contentOpacity)
      )
      // 未展開のノードには、まだ辿れることを示す小さな＋バッジ
      .overlay(alignment: .bottomTrailing) {
        if !isExpanded {
          Image(systemName: "plus.circle.fill")
            .font(.caption)
            .foregroundStyle(AppTheme.ai)
            .background(Circle().fill(AppTheme.paper))
            .opacity(contentOpacity)
        }
      }

      Text(person.name)
        .font(.caption2.weight(isSelf ? .bold : .medium))
        .foregroundStyle(AppTheme.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .allowsTightening(true)
        .frame(width: 92)
        .opacity(contentOpacity)

      if !relationLabel.isEmpty {
        Text("(\(relationLabel))")
          .font(.system(size: 9, weight: .medium))
          .foregroundStyle(AppTheme.inkSoft)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
          .allowsTightening(true)
          .frame(width: 92)
          .accessibilityLabel("続柄 \(relationLabel)")
          .opacity(contentOpacity)
      }
    }
    .background(alignment: .top) {
      if isSelf {
        EndpointNodeRings(color: AppTheme.attention)
          .frame(width: 120, height: 120)
          .offset(y: -32)
      } else if isFocused {
        EndpointNodeRings(color: AppTheme.ai)
          .frame(width: 120, height: 120)
          .offset(y: -32)
      }
    }
  }
}

/// 経路の両端を示す、テーマ色を抑えて重ねた同心円と呼吸する後光。
private struct EndpointNodeRings: View {
  let color: Color
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isBreathing = false

  var body: some View {
    ZStack {
      Circle()
        .fill(color.opacity(0.15))
        .frame(width: 132, height: 132)
        .blur(radius: 20)
        .scaleEffect(isBreathing ? 1.08 : 1)

      Circle()
        .stroke(color.opacity(0.24), lineWidth: 0.6)
        .frame(width: 78, height: 78)
      Circle()
        .stroke(color.opacity(0.18), lineWidth: 0.55)
        .frame(width: 98, height: 98)
      Circle()
        .stroke(color.opacity(0.12), lineWidth: 0.5)
        .frame(width: 118, height: 118)
    }
    .onAppear {
      guard !reduceMotion else { return }
      withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
        isBreathing = true
      }
    }
  }
}

/// パン・ズームの外側に固定して表示する、家系色の小さな凡例。
private struct FamilyBranchLegend: View {
  var body: some View {
    HStack(spacing: 6) {
      ForEach(FamilyBranch.allCases, id: \.self) { branch in
        Text(branch.legendLabel)
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(branch.color)
          .padding(.horizontal, 8)
          .padding(.vertical, 5)
          .background(branch.color.opacity(0.12), in: Capsule())
          .overlay(Capsule().stroke(AppTheme.rule, lineWidth: 1))
          .accessibilityIdentifier("connectionMap.legend.\(branch.rawValue)")
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("connectionMap.legend")
    .accessibilityLabel("家系色の凡例。直系、配偶者側、外側の家系")
  }
}
