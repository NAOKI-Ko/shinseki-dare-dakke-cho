import SwiftData
import SwiftUI
import ImageIO

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
  enum Kind: Hashable { case parentChild, spouse }

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

/// Personとして保存しない、夫婦関係1組を表すrender専用ID。
struct GraphCoupleID: Hashable {
  let people: Set<PersistentModelIDBox>

  init(_ first: PersistentModelIDBox, _ second: PersistentModelIDBox) {
    people = [first, second]
  }
}

struct GraphCoupleKnot: Identifiable, Hashable {
  let id: GraphCoupleID
  let first: PersistentModelIDBox
  let second: PersistentModelIDBox
  let commonChildren: [PersistentModelIDBox]
}

enum GraphKnotSegmentRole: String, Hashable {
  case spouseArm
  case childStem
}

struct GraphKnotSegmentID: Hashable {
  let couple: GraphCoupleID
  let role: GraphKnotSegmentRole
  let person: PersistentModelIDBox
}

enum GraphRenderEndpoint: Hashable {
  case person(PersistentModelIDBox)
  case knot(GraphCoupleID)
}

struct GraphKnotSegment: Identifiable, Hashable {
  let id: GraphKnotSegmentID
  let from: GraphRenderEndpoint
  let to: GraphRenderEndpoint
  let kind: GraphEdge.Kind
  let sourceEdges: Set<GraphEdgeEndpoints>
  let sourceEdgeIDs: Set<UUID>
  let branchNodeID: PersistentModelIDBox
}

struct GraphCoupleRenderModel: Equatable {
  var knots: [GraphCoupleKnot] = []
  var segments: [GraphKnotSegment] = []
  var suppressedEdgeIDs: Set<UUID> = []
}

struct GraphNodeRenderItem: Identifiable {
  let node: GraphNode
  let branch: FamilyBranch
  let relationLabel: String
  var id: PersistentModelIDBox { node.id }
}

struct GraphEdgeRenderItem: Identifiable {
  let edge: GraphEdge
  let branch: FamilyBranch
  var id: UUID { edge.id }
}

/// cameraに依存しない描画情報。グラフ構造が変わった時だけ再構築する。
struct FamilyGraphRenderSnapshot {
  var nodes: [GraphNodeRenderItem] = []
  var edges: [GraphEdgeRenderItem] = []
  var coupleRenderModel = GraphCoupleRenderModel()
  var nodeBranches: [PersistentModelIDBox: FamilyBranch] = [:]
  var edgeBranches: [UUID: FamilyBranch] = [:]
  var knotsByID: [GraphCoupleID: GraphCoupleKnot] = [:]
}

/// 現在表示中の人物と関係だけから、夫婦の結び目と描画線を生成する。
/// SwiftDataへは保存せず、グラフ展開時だけ再計算する。
enum GraphCoupleRenderBuilder {
  static func build(
    nodes: [PersistentModelIDBox: GraphNode],
    edges: [GraphEdge]
  ) -> GraphCoupleRenderModel {
    var result = GraphCoupleRenderModel()

    for spouseEdge in edges where spouseEdge.kind == .spouse {
      guard
        let firstNode = nodes[spouseEdge.from],
        let secondNode = nodes[spouseEdge.to]
      else { continue }

      let firstChildren = Set(firstNode.person.children.map {
        PersistentModelIDBox($0.persistentModelID)
      })
      let secondChildren = Set(secondNode.person.children.map {
        PersistentModelIDBox($0.persistentModelID)
      })
      let commonChildren = firstChildren.intersection(secondChildren)
        .filter { nodes[$0] != nil }
        .sorted {
          let lhs = nodes[$0]
          let rhs = nodes[$1]
          if lhs?.level != rhs?.level { return (lhs?.level ?? 0) < (rhs?.level ?? 0) }
          if lhs?.slot != rhs?.slot { return (lhs?.slot ?? 0) < (rhs?.slot ?? 0) }
          return (lhs?.person.name ?? "") < (rhs?.person.name ?? "")
        }
      guard !commonChildren.isEmpty else { continue }

      let coupleID = GraphCoupleID(spouseEdge.from, spouseEdge.to)
      result.suppressedEdgeIDs.insert(spouseEdge.id)
      let spouseSource = GraphEdgeEndpoints(spouseEdge.from, spouseEdge.to)

      for spouseID in [spouseEdge.from, spouseEdge.to] {
        result.segments.append(
          GraphKnotSegment(
            id: GraphKnotSegmentID(
              couple: coupleID,
              role: .spouseArm,
              person: spouseID
            ),
            from: .person(spouseID),
            to: .knot(coupleID),
            kind: .spouse,
            sourceEdges: [spouseSource],
            sourceEdgeIDs: [spouseEdge.id],
            branchNodeID: spouseID
          )
        )
      }

      for childID in commonChildren {
        let parentEndpoints = [spouseEdge.from, spouseEdge.to].map {
          GraphEdgeEndpoints($0, childID)
        }
        let parentEdges = edges.filter { edge in
          edge.kind == .parentChild && parentEndpoints.contains(edge.endpoints)
        }
        result.suppressedEdgeIDs.formUnion(parentEdges.map(\.id))
        result.segments.append(
          GraphKnotSegment(
            id: GraphKnotSegmentID(
              couple: coupleID,
              role: .childStem,
              person: childID
            ),
            from: .knot(coupleID),
            to: .person(childID),
            kind: .parentChild,
            sourceEdges: Set(parentEndpoints),
            sourceEdgeIDs: Set(parentEdges.map(\.id)),
            branchNodeID: childID
          )
        )
      }

      result.knots.append(
        GraphCoupleKnot(
          id: coupleID,
          first: spouseEdge.from,
          second: spouseEdge.to,
          commonChildren: commonChildren
        )
      )
    }
    return result
  }
}

/// 人物詳細で強調する「自分から表示中人物まで」の線だけを抽出する。
enum GraphPathEmphasis {
  static func orderedEdgeEndpoints(for route: RelationRoute?) -> [GraphEdgeEndpoints] {
    guard let route, route.people.count > 1 else { return [] }
    return zip(route.people, route.people.dropFirst()).map { first, second in
      GraphEdgeEndpoints(
        PersistentModelIDBox(first.persistentModelID),
        PersistentModelIDBox(second.persistentModelID)
      )
    }
  }

  static func edgeEndpoints(for route: RelationRoute?) -> Set<GraphEdgeEndpoints>? {
    let ordered = orderedEdgeEndpoints(for: route)
    return ordered.isEmpty ? nil : Set(ordered)
  }
}

struct GraphGridPosition {
  let level: Int
  let slot: Int
}

struct GraphViewportTransform: Equatable {
  static let interactiveScaleRange: ClosedRange<CGFloat> = 0.4...2.5

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

  /// gesture開始時のcameraを基準に、画面上のanchorを動かさず拡大縮小する。
  func zoomed(
    by magnification: CGFloat,
    anchor: CGPoint,
    around origin: CGPoint,
    scaleRange: ClosedRange<CGFloat> = interactiveScaleRange
  ) -> GraphViewportTransform {
    let proposedScale = scale * magnification
    let nextScale = min(max(proposedScale, scaleRange.lowerBound), scaleRange.upperBound)
    let graphAnchor = removing(from: anchor, around: origin)
    let nextOffset = CGSize(
      width: anchor.x - origin.x - (graphAnchor.x - origin.x) * nextScale,
      height: anchor.y - origin.y - (graphAnchor.y - origin.y) * nextScale
    )
    return GraphViewportTransform(scale: nextScale, offset: nextOffset)
  }

  func panned(by translation: CGSize) -> GraphViewportTransform {
    GraphViewportTransform(
      scale: scale,
      offset: CGSize(
        width: offset.width + translation.width,
        height: offset.height + translation.height
      )
    )
  }
}

/// 1本指のtap候補とpan、2本指のMagnifyを同じcamera計算へ集約する。
enum GraphViewportGesturePolicy {
  static let panThreshold: CGFloat = 10

  static func transform(
    from start: GraphViewportTransform,
    magnification: CGFloat,
    anchor: CGPoint,
    origin: CGPoint,
    translation: CGSize,
    isMagnifying: Bool
  ) -> GraphViewportTransform {
    if isMagnifying {
      return start
        .zoomed(by: magnification, anchor: anchor, around: origin)
        .panned(by: translation)
    }

    guard dragDistance(translation) >= panThreshold else { return start }
    return start.panned(by: translation)
  }

  static func isTapLike(_ translation: CGSize) -> Bool {
    dragDistance(translation) < panThreshold
  }

  private static func dragDistance(_ translation: CGSize) -> CGFloat {
    hypot(translation.width, translation.height)
  }
}

/// 画面外の重いノードViewと完全に画面外の線を生成しないための純粋判定。
enum GraphViewportCulling {
  static let overscan: CGFloat = 160

  static func visibleBounds(
    viewportSize: CGSize,
    overscan: CGFloat = overscan
  ) -> CGRect {
    CGRect(origin: .zero, size: viewportSize).insetBy(dx: -overscan, dy: -overscan)
  }

  static func isNodeVisible(
    center: CGPoint,
    radius: CGFloat,
    viewportSize: CGSize,
    overscan: CGFloat = overscan
  ) -> Bool {
    let nodeBounds = CGRect(
      x: center.x - radius,
      y: center.y - radius,
      width: radius * 2,
      height: radius * 2
    )
    return visibleBounds(viewportSize: viewportSize, overscan: overscan)
      .intersects(nodeBounds)
  }

  static func isEdgeVisible(
    start: CGPoint,
    end: CGPoint,
    viewportSize: CGSize,
    overscan: CGFloat = overscan
  ) -> Bool {
    let edgeBounds = CGRect(
      x: min(start.x, end.x),
      y: min(start.y, end.y),
      width: max(abs(end.x - start.x), 1),
      height: max(abs(end.y - start.y), 1)
    ).insetBy(dx: -2, dy: -2)
    return visibleBounds(viewportSize: viewportSize, overscan: overscan)
      .intersects(edgeBounds)
  }
}

private final class FamilyGraphPhotoCacheKey: NSObject {
  let personID: PersistentModelIDBox

  init(personID: PersistentModelIDBox) {
    self.personID = personID
  }

  override var hash: Int { personID.hashValue }

  override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FamilyGraphPhotoCacheKey else { return false }
    return personID == other.personID
  }
}

private final class FamilyGraphPhotoCacheEntry {
  let photoData: Data
  let image: UIImage?

  init(photoData: Data, image: UIImage?) {
    self.photoData = photoData
    self.image = image
  }
}

/// 家系図用の小さなthumbnail cache。内容が変われば同じPersonでも再decodeする。
final class FamilyGraphPhotoCache {
  typealias Decoder = (_ data: Data, _ maxPixelSize: CGFloat) -> UIImage?

  static let shared = FamilyGraphPhotoCache()

  private let cache = NSCache<FamilyGraphPhotoCacheKey, FamilyGraphPhotoCacheEntry>()
  private let lock = NSLock()
  private let maxPixelSize: CGFloat
  private let decoder: Decoder

  init(
    maxPixelSize: CGFloat = 168,
    totalCostLimit: Int = 24 * 1024 * 1024,
    countLimit: Int = 96,
    decoder: @escaping Decoder = FamilyGraphPhotoCache.decodeThumbnail
  ) {
    self.maxPixelSize = maxPixelSize
    self.decoder = decoder
    cache.totalCostLimit = totalCostLimit
    cache.countLimit = countLimit
  }

  func image(for personID: PersistentModelIDBox, photoData: Data?) -> UIImage? {
    let key = FamilyGraphPhotoCacheKey(personID: personID)
    lock.lock()
    defer { lock.unlock() }

    guard let photoData, !photoData.isEmpty else {
      cache.removeObject(forKey: key)
      return nil
    }
    if let existing = cache.object(forKey: key), existing.photoData == photoData {
      return existing.image
    }

    let image = decoder(photoData, maxPixelSize)
    let entry = FamilyGraphPhotoCacheEntry(photoData: photoData, image: image)
    cache.setObject(entry, forKey: key, cost: cacheCost(image: image, data: photoData))
    return image
  }

  func removeAll() {
    lock.lock()
    cache.removeAllObjects()
    lock.unlock()
  }

  private func cacheCost(image: UIImage?, data: Data) -> Int {
    let decodedBytes: Int
    if let cgImage = image?.cgImage {
      decodedBytes = cgImage.bytesPerRow * cgImage.height
    } else {
      decodedBytes = 0
    }
    return data.count + decodedBytes
  }

  private static func decodeThumbnail(data: Data, maxPixelSize: CGFloat) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
      source,
      0,
      options as CFDictionary
    ) else { return nil }
    return UIImage(cgImage: thumbnail)
  }
}

enum GraphSemanticZoomLevel: String, Equatable {
  case overview
  case normal
  case close
}

struct GraphSemanticVisibility: Equatable {
  let showsName: Bool
  let showsRelation: Bool
  let showsExpansionBadge: Bool
}

/// ズーム倍率ごとの情報量を一箇所で調整する。
/// Phase 2で見た目を詰める場合も、各Viewへ閾値を散らさない。
enum GraphSemanticZoomPolicy {
  static let overviewUpperBound: CGFloat = 0.74
  static let closeLowerBound: CGFloat = 1.35

  static func level(for scale: CGFloat) -> GraphSemanticZoomLevel {
    if scale <= overviewUpperBound { return .overview }
    if scale >= closeLowerBound { return .close }
    return .normal
  }

  static func visibility(
    at level: GraphSemanticZoomLevel,
    isFocused: Bool,
    focusDistance: Int?,
    isExpanded: Bool
  ) -> GraphSemanticVisibility {
    switch level {
    case .overview:
      return GraphSemanticVisibility(
        showsName: isFocused,
        showsRelation: false,
        showsExpansionBadge: false
      )
    case .normal:
      return GraphSemanticVisibility(
        showsName: true,
        showsRelation: isFocused || (focusDistance ?? .max) <= 1,
        showsExpansionBadge: isFocused && !isExpanded
      )
    case .close:
      return GraphSemanticVisibility(
        showsName: true,
        showsRelation: true,
        showsExpansionBadge: !isExpanded
      )
    }
  }
}

enum GraphFocusBand: Equatable {
  case focused
  case direct
  case distanceTwo
  case further
}

struct GraphFocusPresentation: Equatable {
  let band: GraphFocusBand
  let nodeOpacity: Double
  let nodeScale: CGFloat
  let edgeOpacity: Double
  let saturation: Double
  let contrast: Double
}

/// フォーカス人物からの距離を、読みやすさを保つ控えめな奥行きへ変換する。
enum GraphFocusHierarchy {
  static func presentation(for distance: Int?) -> GraphFocusPresentation {
    switch distance {
    case 0:
      GraphFocusPresentation(
        band: .focused,
        nodeOpacity: 1,
        nodeScale: 1.06,
        edgeOpacity: 1,
        saturation: 1,
        contrast: 1.04
      )
    case 1:
      GraphFocusPresentation(
        band: .direct,
        nodeOpacity: 0.96,
        nodeScale: 1,
        edgeOpacity: 0.88,
        saturation: 0.98,
        contrast: 1
      )
    case 2:
      GraphFocusPresentation(
        band: .distanceTwo,
        nodeOpacity: 0.76,
        nodeScale: 0.94,
        edgeOpacity: 0.68,
        saturation: 0.9,
        contrast: 0.97
      )
    default:
      GraphFocusPresentation(
        band: .further,
        nodeOpacity: 0.56,
        nodeScale: 0.9,
        edgeOpacity: 0.48,
        saturation: 0.82,
        contrast: 0.94
      )
    }
  }
}

struct GraphNodeLODPresentation: Equatable {
  let screenDiameter: CGFloat
  let localScale: CGFloat
  let canvasRadius: CGFloat
}

/// 人物の位置間隔はカメラ倍率に従わせつつ、珠と文字の画面上サイズだけを
/// 読める範囲へ制限する。線端も同じcanvasRadiusを使う。
enum GraphNodeLODPolicy {
  static let minimumScreenDiameter: CGFloat = 28
  static let standardDiameter: CGFloat = 56
  static let maximumScreenDiameter: CGFloat = 78

  static func presentation(
    cameraScale: CGFloat,
    focusScale: CGFloat
  ) -> GraphNodeLODPresentation {
    let safeCameraScale = max(abs(cameraScale), 0.0001)
    let proposedDiameter = standardDiameter * safeCameraScale * focusScale
    let screenDiameter = min(
      max(proposedDiameter, minimumScreenDiameter),
      maximumScreenDiameter
    )
    return GraphNodeLODPresentation(
      screenDiameter: screenDiameter,
      localScale: screenDiameter / (standardDiameter * safeCameraScale),
      canvasRadius: screenDiameter / (2 * safeCameraScale)
    )
  }
}

/// 1つの人物珠について、論理座標から画面上の中心・半径・カード配置をまとめて求める。
/// 線端とNode Viewが別々の補正を持たないためのscreen-space契約。
struct GraphNodeScreenGeometry: Equatable {
  let center: CGPoint
  let radius: CGFloat
  let cardPosition: CGPoint
  let visualScale: CGFloat
  let scaleAnchor: UnitPoint

  static func resolve(
    logicalCenter: CGPoint,
    origin: CGPoint,
    viewport: GraphViewportTransform,
    focusScale: CGFloat,
    beadDiameter: CGFloat,
    cardHeight: CGFloat
  ) -> GraphNodeScreenGeometry {
    let lod = GraphNodeLODPolicy.presentation(
      cameraScale: viewport.scale,
      focusScale: focusScale
    )
    let center = viewport.applying(to: logicalCenter, around: origin)
    return GraphNodeScreenGeometry(
      center: center,
      radius: lod.screenDiameter / 2,
      cardPosition: CGPoint(
        x: center.x,
        y: center.y + (cardHeight - beadDiameter) / 2
      ),
      visualScale: lod.screenDiameter / beadDiameter,
      scaleAnchor: UnitPoint(x: 0.5, y: (beadDiameter / 2) / cardHeight)
    )
  }
}

enum GraphLineLODPolicy {
  static func canvasWidth(screenWidth: CGFloat, cameraScale: CGFloat) -> CGFloat {
    screenWidth / max(abs(cameraScale), 0.0001)
  }
}

struct GraphFocusAdornment: Equatable {
  let showsStrongFocus: Bool
  let showsSelfMarker: Bool
}

/// 強い後光は常にフォーカス人物1人だけへ与える。
enum GraphFocusAdornmentPolicy {
  static func adornment(isSelf: Bool, isFocused: Bool) -> GraphFocusAdornment {
    GraphFocusAdornment(
      showsStrongFocus: isFocused,
      showsSelfMarker: isSelf && !isFocused
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
    edgeAnchors(
      from: startCenter,
      to: endCenter,
      startRadius: beadRadius,
      endRadius: beadRadius
    )
  }

  static func edgeAnchors(
    from startCenter: CGPoint,
    to endCenter: CGPoint,
    startRadius: CGFloat,
    endRadius: CGFloat
  ) -> GraphEdgeAnchors {
    let dx = endCenter.x - startCenter.x
    let dy = endCenter.y - startCenter.y
    let distance = hypot(dx, dy)
    guard distance > startRadius + endRadius, distance > 0 else {
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
        x: startCenter.x + unitX * startRadius,
        y: startCenter.y + unitY * startRadius
      ),
      end: CGPoint(
        x: endCenter.x - unitX * endRadius,
        y: endCenter.y - unitY * endRadius
      )
    )
  }

  /// 両端の論理座標を同じviewportで画面座標へ変換してから、
  /// 現在の見た目半径だけscreen-spaceで退避させる。
  static func screenEdgeAnchors(
    from startLogicalCenter: CGPoint,
    to endLogicalCenter: CGPoint,
    origin: CGPoint,
    viewport: GraphViewportTransform,
    startRadius: CGFloat,
    endRadius: CGFloat
  ) -> GraphEdgeAnchors {
    edgeAnchors(
      from: viewport.applying(to: startLogicalCenter, around: origin),
      to: viewport.applying(to: endLogicalCenter, around: origin),
      startRadius: startRadius,
      endRadius: endRadius
    )
  }

  static func coupleKnotCenter(first: CGPoint, second: CGPoint) -> CGPoint {
    CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
  }
}

enum GraphHitTestGeometry {
  static func graphLocation(
    for screenLocation: CGPoint,
    origin: CGPoint,
    viewport: GraphViewportTransform
  ) -> CGPoint {
    viewport.removing(from: screenLocation, around: origin)
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

enum GraphFocusTransition {
  static let duration: TimeInterval = 0.46
  static let illuminationIntervalNanoseconds: UInt64 = 110_000_000

  static func centeredOffset(
    position: GraphGridPosition,
    cameraScale: CGFloat,
    slotWidth: CGFloat,
    levelHeight: CGFloat
  ) -> CGSize {
    CGSize(
      width: -CGFloat(position.slot) * slotWidth * cameraScale,
      height: -CGFloat(position.level) * levelHeight * cameraScale
    )
  }

  /// visual focusだけならcameraを保持し、明示的なfocus時だけ対象を中央へ移す。
  static func viewport(
    from current: GraphViewportTransform,
    centeredOn position: GraphGridPosition,
    slotWidth: CGFloat,
    levelHeight: CGFloat,
    moveCamera: Bool
  ) -> GraphViewportTransform {
    guard moveCamera else { return current }
    return GraphViewportTransform(
      scale: current.scale,
      offset: centeredOffset(
        position: position,
        cameraScale: current.scale,
        slotWidth: slotWidth,
        levelHeight: levelHeight
      )
    )
  }
}

typealias QuickRelationKind = RelationshipKind

extension RelationshipKind {
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
    in context: ModelContext,
    includeSpouseForChild: Bool = false
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
    do {
      try RelationshipManager.link(
        kind,
        person: person,
        relative: newPerson,
        includeSpouseForChild: includeSpouseForChild
      )
      try context.save()
    } catch let error as RelationshipLinkError {
      RelationshipManager.detachAll(newPerson)
      context.delete(newPerson)
      context.rollback()
      throw error
    } catch {
      RelationshipManager.detachAll(newPerson)
      context.delete(newPerson)
      context.rollback()
      throw QuickRelativeRegistrationError.saveFailed
    }
    return newPerson
  }

  static func candidates(
    for kind: QuickRelationKind,
    person: Person,
    from allPersons: [Person]
  ) -> [Person] {
    allPersons.filter {
      RelationshipManager.canLink(kind, person: person, relative: $0)
    }
  }

  static func linkExisting(
    _ relative: Person,
    kind: QuickRelationKind,
    for person: Person,
    in context: ModelContext,
    includeSpouseForChild: Bool = false
  ) throws {
    do {
      try RelationshipTransaction.perform(in: context) {
        try RelationshipManager.link(
          kind,
          person: person,
          relative: relative,
          includeSpouseForChild: includeSpouseForChild
        )
      }
    } catch let error as RelationshipLinkError {
      throw error
    } catch {
      throw QuickRelativeRegistrationError.saveFailed
    }
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
  case knots = 0.5
  case nodes = 1
}

private extension View {
  @ViewBuilder
  func graphDecorativeLayerAccessibility(
    identifier: String,
    value: String
  ) -> some View {
    #if DEBUG
      self
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(value)
    #else
      self.accessibilityHidden(true)
    #endif
  }

  @ViewBuilder
  func graphNodeLayerAccessibility() -> some View {
    #if DEBUG
      self
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("connectionMap.nodeLayer")
        .accessibilityValue("最前面")
    #else
      self.accessibilityElement(children: .contain)
    #endif
  }
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
  private(set) var renderSnapshot = FamilyGraphRenderSnapshot()
  var coupleRenderModel: GraphCoupleRenderModel { renderSnapshot.coupleRenderModel }
  private var rootID: PersistentModelIDBox?

  /// 自分を起点にグラフを初期化する
  func reset(with selfPerson: Person) {
    nodes = [:]
    edges = []
    renderSnapshot = FamilyGraphRenderSnapshot()
    rootID = PersistentModelIDBox(selfPerson.persistentModelID)
    place(selfPerson, level: 0, preferredSlot: 0, path: [])
    refreshRenderSnapshot()
  }

  /// 指定した人物の直接のつながり(親・子・配偶者)を展開する。
  /// 既にキャンバスにいる人物には新しいノードを作らず、エッジだけ追加する。
  func expand(_ person: Person) {
    guard let center = nodes[PersistentModelIDBox(person.persistentModelID)] else { return }

    for (index, parent) in person.parents.enumerated() {
      _ = placeIfNeeded(
        parent,
        level: center.level - 1,
        preferredSlot: center.slot + symmetricOffset(at: index),
        path: center.path + [.parent]
      )
      addEdgeIfNeeded(from: parent, to: person, kind: .parentChild)
    }

    var familyCenterSlot = center.slot
    if let spouse = person.spouse {
      let spouseNode = placeIfNeeded(
        spouse,
        level: center.level,
        preferredSlot: center.slot + spouseDirection(from: center.slot),
        path: center.path + [.spouse]
      )
      addEdgeIfNeeded(from: person, to: spouse, kind: .spouse)
      familyCenterSlot = Int(round(Double(center.slot + spouseNode.slot) / 2))
    }

    for (index, child) in person.children.enumerated() {
      _ = placeIfNeeded(
        child,
        level: center.level + 1,
        preferredSlot: familyCenterSlot + symmetricOffset(at: index),
        path: center.path + [.child]
      )
      addEdgeIfNeeded(from: person, to: child, kind: .parentChild)
    }
    // 兄弟姉妹は「共通の親」を介して自動的に見えるようになるため、
    // ここでは明示的なノード追加はしない(親を展開すれば子として現れる)。
    refreshShortestPaths()
    refreshRenderSnapshot()
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
    preferredSlot: Int,
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
    return place(
      person,
      level: level,
      preferredSlot: preferredSlot,
      path: path
    )
  }

  @discardableResult
  private func place(
    _ person: Person,
    level: Int,
    preferredSlot: Int,
    path: [RelationStep]
  ) -> GraphNode {
    let slot = nearestAvailableSlot(level: level, preferred: preferredSlot)
    let node = GraphNode(person: person, level: level, slot: slot, path: path)
    nodes[PersistentModelIDBox(person.persistentModelID)] = node
    return node
  }

  private func nearestAvailableSlot(level: Int, preferred: Int) -> Int {
    let occupied = Set(nodes.values.filter { $0.level == level }.map(\.slot))
    if !occupied.contains(preferred) { return preferred }
    for distance in 1...100 {
      let candidates = preferred >= 0
        ? [preferred + distance, preferred - distance]
        : [preferred - distance, preferred + distance]
      if let candidate = candidates.first(where: { !occupied.contains($0) }) {
        return candidate
      }
    }
    return preferred
  }

  private func spouseDirection(from slot: Int) -> Int {
    slot < 0 ? -1 : 1
  }

  /// 0, -1, +1, -2, +2... の順で、同世代を中心から横へ広げる。
  private func symmetricOffset(at index: Int) -> Int {
    guard index > 0 else { return 0 }
    let distance = (index + 1) / 2
    return index.isMultiple(of: 2) ? distance : -distance
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
    renderSnapshot.nodeBranches[nodeID]
      ?? FamilyBranch.classify(path: nodes[nodeID]?.path ?? [])
  }

  /// 線は原則として自分から遠い側のノードの家系色を引き継ぐ。
  /// 距離が同じ場合は、直系から分岐する側の色を優先する。
  func branch(for edge: GraphEdge) -> FamilyBranch {
    if let cached = renderSnapshot.edgeBranches[edge.id] { return cached }
    return classifyBranch(for: edge, nodeBranches: renderSnapshot.nodeBranches)
  }

  private func classifyBranch(
    for edge: GraphEdge,
    nodeBranches: [PersistentModelIDBox: FamilyBranch]
  ) -> FamilyBranch {
    guard let fromNode = nodes[edge.from], let toNode = nodes[edge.to] else {
      return .indigo
    }
    let fromBranch = nodeBranches[edge.from] ?? FamilyBranch.classify(path: fromNode.path)
    let toBranch = nodeBranches[edge.to] ?? FamilyBranch.classify(path: toNode.path)
    if fromNode.path.count != toNode.path.count {
      return fromNode.path.count > toNode.path.count ? fromBranch : toBranch
    }
    if fromBranch == .plum || toBranch == .plum { return .plum }
    if fromBranch == .forest || toBranch == .forest { return .forest }
    return .indigo
  }

  private func refreshRenderSnapshot() {
    let coupleModel = GraphCoupleRenderBuilder.build(nodes: nodes, edges: edges)
    let nodeBranches = Dictionary(
      uniqueKeysWithValues: nodes.map { id, node in
        (id, FamilyBranch.classify(path: node.path))
      }
    )
    let nodeItems = nodes.values
      .sorted {
        if $0.level != $1.level { return $0.level < $1.level }
        if $0.slot != $1.slot { return $0.slot < $1.slot }
        return $0.person.name < $1.person.name
      }
      .map { node in
        GraphNodeRenderItem(
          node: node,
          branch: nodeBranches[node.id] ?? .indigo,
          relationLabel: RelationLabeler.label(for: node.path)
        )
      }
    let edgeBranches = Dictionary(
      uniqueKeysWithValues: edges.map { edge in
        (edge.id, classifyBranch(for: edge, nodeBranches: nodeBranches))
      }
    )
    let edgeItems = edges
      .filter { !coupleModel.suppressedEdgeIDs.contains($0.id) }
      .map { edge in
        GraphEdgeRenderItem(
          edge: edge,
          branch: edgeBranches[edge.id] ?? .indigo
        )
      }
    renderSnapshot = FamilyGraphRenderSnapshot(
      nodes: nodeItems,
      edges: edgeItems,
      coupleRenderModel: coupleModel,
      nodeBranches: nodeBranches,
      edgeBranches: edgeBranches,
      knotsByID: Dictionary(uniqueKeysWithValues: coupleModel.knots.map { ($0.id, $0) })
    )
  }

  /// 現在キャンバスに存在するエッジだけを使い、指定人物からの最短距離を返す。
  /// Focus hierarchyの見た目は、この純粋なグラフ距離だけを参照する。
  func distances(from sourceID: PersistentModelIDBox) -> [PersistentModelIDBox: Int] {
    guard nodes[sourceID] != nil else { return [:] }
    var result: [PersistentModelIDBox: Int] = [sourceID: 0]
    var queue = [sourceID]
    var index = 0

    while index < queue.count {
      let current = queue[index]
      index += 1
      let nextDistance = (result[current] ?? 0) + 1
      for edge in edges {
        let neighbor: PersistentModelIDBox
        if edge.from == current {
          neighbor = edge.to
        } else if edge.to == current {
          neighbor = edge.from
        } else {
          continue
        }
        guard result[neighbor] == nil else { continue }
        result[neighbor] = nextDistance
        queue.append(neighbor)
      }
    }
    return result
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
  @State private var illuminatedPathEdges: Set<GraphEdgeEndpoints> = []
  @State private var pathIlluminationToken = UUID()
  @State private var focusedNodeID: PersistentModelIDBox?
  @State private var focusDistances: [PersistentModelIDBox: Int] = [:]
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

  @State private var viewportTransform = GraphViewportTransform(scale: 1, offset: .zero)
  @State private var gestureStartTransform: GraphViewportTransform?

  private let levelHeight: CGFloat = 120
  private let slotWidth: CGFloat = 108
  private let nodeCardWidth: CGFloat = 92
  private let beadDiameter: CGFloat = 56
  private let nodeCardHeight: CGFloat = 102

  var body: some View {
    GeometryReader { geo in
      // 親・本人・子の3世代すべてに、画面端と重ならないタップ余白を確保する。
      let origin = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
      let effectiveScale = viewportTransform.scale
      let semanticZoomLevel = GraphSemanticZoomPolicy.level(for: effectiveScale)
      let renderSnapshot = store.renderSnapshot

      ZStack {
        AppTheme.paper

        ZStack {
          // 線とノードは同じ論理座標とviewport transformから画面座標を派生させる。
          // 線だけ／ノードだけに独自のscale・offsetを重ねない。
          ZStack {
            ForEach(renderSnapshot.edges) { item in
              let edge = item.edge
              if let a = store.nodes[edge.from], let b = store.nodes[edge.to] {
                let anchors = edgeAnchors(
                  from: a,
                  to: b,
                  origin: origin,
                  transform: viewportTransform
                )
                if GraphViewportCulling.isEdgeVisible(
                  start: anchors.start,
                  end: anchors.end,
                  viewportSize: geo.size
                ) {
                  let isEmphasized = emphasizedPathEdges?.contains(edge.endpoints) ?? true
                  let isIlluminated = illuminatedPathEdges.contains(edge.endpoints)
                  let normalWidth: CGFloat = edge.kind == .spouse ? 2.5 : 1.5
                  let focusOpacity = edgeFocusOpacity(for: edge)
                  GraphEdgeShape(start: anchors.start, end: anchors.end)
                    .trim(from: 0, to: edgeProgress[edge.id] ?? 0)
                    .stroke(
                      item.branch.color.opacity(
                        min(
                          isIlluminated ? 1 : focusOpacity * (isEmphasized ? 1 : 0.35),
                          1
                        )
                      ),
                      style: StrokeStyle(
                        lineWidth: (isEmphasized ? normalWidth : normalWidth * 0.5)
                          + (isIlluminated ? 0.7 : 0),
                        lineCap: .round,
                        lineJoin: .round
                      )
                    )
                    .animation(
                      reduceMotion ? nil : .easeInOut(duration: 0.12),
                      value: isIlluminated
                    )
                    .accessibilityHidden(true)
                }
              }
            }

            ForEach(renderSnapshot.coupleRenderModel.segments) { segment in
              if let anchors = knotSegmentAnchors(
                segment,
                origin: origin,
                transform: viewportTransform,
                cameraScale: effectiveScale
              ) {
                if GraphViewportCulling.isEdgeVisible(
                  start: anchors.start,
                  end: anchors.end,
                  viewportSize: geo.size
                ) {
                  let isEmphasized = segmentIsEmphasized(segment)
                  let isIlluminated = segmentIsIlluminated(segment)
                  let normalWidth: CGFloat = segment.kind == .spouse ? 2.5 : 1.5
                  GraphEdgeShape(start: anchors.start, end: anchors.end)
                    .trim(from: 0, to: knotSegmentProgress(segment))
                    .stroke(
                      (renderSnapshot.nodeBranches[segment.branchNodeID] ?? .indigo).color
                        .opacity(
                          min(
                            isIlluminated
                              ? 1
                              : knotSegmentFocusOpacity(segment)
                                * (isEmphasized ? 1 : 0.35),
                            1
                          )
                        ),
                      style: StrokeStyle(
                        lineWidth: (isEmphasized ? normalWidth : normalWidth * 0.5)
                          + (isIlluminated ? 0.7 : 0),
                        lineCap: .round,
                        lineJoin: .round
                      )
                    )
                    .animation(
                      reduceMotion ? nil : .easeInOut(duration: 0.12),
                      value: isIlluminated
                    )
                    .accessibilityHidden(true)
                }
              }
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .zIndex(GraphRenderLayer.edges.rawValue)
          .graphDecorativeLayerAccessibility(
            identifier: "connectionMap.edgeLayer",
            value: "最背面"
          )

          ZStack {
            ForEach(renderSnapshot.coupleRenderModel.knots) { knot in
              let knotCenter = viewportTransform.applying(
                to: knotPosition(knot, origin: origin),
                around: origin
              )
              if GraphViewportCulling.isNodeVisible(
                center: knotCenter,
                radius: CoupleKnotView.diameter,
                viewportSize: geo.size
              ) {
                CoupleKnotView(
                  color: (renderSnapshot.nodeBranches[knot.second] ?? .indigo).color,
                  isFocused: focusedNodeID.map { knot.id.people.contains($0) } ?? false
                )
                .position(knotCenter)
                .accessibilityHidden(true)
              }
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .zIndex(GraphRenderLayer.knots.rawValue)

          // ノードは描画順でもzIndexでも接続線より前面に固定する。
          ZStack {
            ForEach(renderSnapshot.nodes) { item in
              let node = item.node
              let isFocused = node.id == focusedNodeID
              let distance = focusDistances[node.id]
              let focusPresentation = GraphFocusHierarchy.presentation(for: distance)
              let nodeGeometry = nodeScreenGeometry(
                node,
                origin: origin,
                transform: viewportTransform,
                focusScale: focusPresentation.nodeScale
              )
              let beadCenter = nodeGeometry.center
              let semanticVisibility = GraphSemanticZoomPolicy.visibility(
                at: semanticZoomLevel,
                isFocused: isFocused,
                focusDistance: distance,
                isExpanded: expandedIDs.contains(node.id)
              )
              if GraphViewportCulling.isNodeVisible(
                center: beadCenter,
                radius: 96,
                viewportSize: geo.size
              ) {
                let photoImage = FamilyGraphPhotoCache.shared.image(
                  for: node.id,
                  photoData: node.person.photoData
                )
                GraphNodeCard(
                  person: node.person,
                  photoImage: photoImage,
                  isSelf: node.person.persistentModelID == selfPerson.persistentModelID,
                  isFocused: isFocused,
                  isExpanded: expandedIDs.contains(node.id),
                  relationLabel: item.relationLabel,
                  branch: item.branch,
                  semanticVisibility: semanticVisibility,
                  focusPresentation: focusPresentation
                )
                .frame(width: nodeCardWidth, height: nodeCardHeight, alignment: .top)
                // 必ずlocal scaleを先に適用し、その後screen-spaceの中心へ配置する。
                // position後のscaleEffectは絶対座標まで再変換し、倍率に応じたズレを生む。
                .scaleEffect(
                  (visibleNodeIDs.contains(node.id) ? 1 : 0.3)
                    * nodeGeometry.visualScale
                    * (bouncingNodeID == node.id ? 1.08 : 1),
                  anchor: nodeGeometry.scaleAnchor
                )
                .opacity(visibleNodeIDs.contains(node.id) ? 1 : 0)
                .position(nodeGeometry.cardPosition)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("connectionMap.node.\(node.person.name)")
                .accessibilityLabel(
                  nodeAccessibilityLabel(
                    person: node.person,
                    relationLabel: item.relationLabel
                  )
                )
                .accessibilityValue(
                  nodeAccessibilityValue(
                    node: node,
                    zoomLevel: semanticZoomLevel,
                    focusPresentation: focusPresentation,
                    geometry: nodeGeometry
                  )
                )
                .accessibilityAction {
                  expand(node)
                }
                .accessibilityAction(named: Text("詳細を見る")) {
                  onShowDetail(node.person)
                }
                .accessibilityAction(named: Text("家族の追加メニューを開く")) {
                  presentNodeActions(for: node.person)
                }
                .simultaneousGesture(
                  LongPressGesture(minimumDuration: 0.55, maximumDistance: 12)
                    .onEnded { _ in
                      presentNodeActions(for: node.person)
                    }
                  )
              }
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .zIndex(GraphRenderLayer.nodes.rawValue)
          .graphNodeLayerAccessibility()

          #if DEBUG
          if ProcessInfo.processInfo.arguments.contains("-ui-testing-family-graph-expand-all") {
            Color.clear
              .contentShape(Rectangle())
              .accessibilityElement(children: .ignore)
              .accessibilityIdentifier("connectionMap.testGestureSurface")
              .accessibilityLabel("つながりマップ操作面")
              .zIndex(GraphRenderLayer.nodes.rawValue + 1)
          }
          #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      // ピンチとパンを同じ開始cameraから合成し、途中の状態を二重加算しない。
      .simultaneousGesture(viewportGesture(origin: origin))
      .clipped()
      // パン・ズームするグラフの外側に固定し、四辺で紙色へ自然に溶かす。
      .overlay {
        CanvasEdgeFade()
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
      .onAppear {
        prepareInitialGraph(viewport: geo.size)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-family-graph-expand-all") {
          expandAllForUITesting()
        }
        #endif
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
      .frame(minWidth: 44, minHeight: 44)
      .contentShape(Rectangle())
      .accessibilityLabel("つながりマップをリセット")
      .accessibilityHint("拡大率と表示位置を最初の状態へ戻します")
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
    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    .onDisappear {
      cancelIntroAnimation()
      pathIlluminationToken = UUID()
    }
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
      QuickRelativeAddSheet(person: request.person, kind: request.kind) { _ in
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
    gestureStartTransform = nil
    viewportTransform = GraphViewportTransform(scale: 1, offset: .zero)
  }

  private func viewportGesture(origin: CGPoint) -> some Gesture {
    MagnifyGesture(minimumScaleDelta: 0.005)
      .simultaneously(with: DragGesture(minimumDistance: 0))
      .onChanged { value in
        cancelIntroAnimation()
        if gestureStartTransform == nil {
          gestureStartTransform = viewportTransform
        }
        guard let start = gestureStartTransform else { return }
        let magnification = value.first?.magnification ?? 1
        let anchor = value.first?.startLocation ?? origin
        let translation = value.second?.translation ?? .zero
        viewportTransform = GraphViewportGesturePolicy.transform(
          from: start,
          magnification: magnification,
          anchor: anchor,
          origin: origin,
          translation: translation,
          isMagnifying: value.first != nil
        )
      }
      .onEnded { value in
        let start = gestureStartTransform ?? viewportTransform
        let magnification = value.first?.magnification ?? 1
        let anchor = value.first?.startLocation ?? origin
        let translation = value.second?.translation ?? .zero

        if suppressTapAfterLongPress {
          viewportTransform = start
          gestureStartTransform = nil
          suppressTapAfterLongPress = false
          return
        }

        let finalTransform = GraphViewportGesturePolicy.transform(
          from: start,
          magnification: magnification,
          anchor: anchor,
          origin: origin,
          translation: translation,
          isMagnifying: value.first != nil
        )
        viewportTransform = finalTransform
        gestureStartTransform = nil

        guard value.first == nil, let drag = value.second else { return }
        if GraphViewportGesturePolicy.isTapLike(drag.translation),
           let tappedNode = node(
             at: drag.location,
             origin: origin,
             transform: finalTransform
           ) {
          expand(tappedNode)
        }
      }
  }

  private var canvasAccessibilityValue: String {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("-ui-testing-family-graph-ux") {
        return "\(introPhase)|scale:\(String(format: "%.2f", viewportTransform.scale))|offset:\(String(format: "%.1f", viewportTransform.offset.width)),\(String(format: "%.1f", viewportTransform.offset.height))|nodes:\(store.nodes.count)"
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

  private func nodeScreenGeometry(
    _ node: GraphNode,
    origin: CGPoint,
    transform: GraphViewportTransform,
    focusScale: CGFloat? = nil
  ) -> GraphNodeScreenGeometry {
    GraphNodeScreenGeometry.resolve(
      logicalCenter: graphPosition(node, origin: origin),
      origin: origin,
      viewport: transform,
      focusScale: focusScale
        ?? GraphFocusHierarchy.presentation(for: focusDistances[node.id]).nodeScale,
      beadDiameter: beadDiameter,
      cardHeight: nodeCardHeight
    )
  }

  private func edgeAnchors(
    from first: GraphNode,
    to second: GraphNode,
    origin: CGPoint,
    transform: GraphViewportTransform
  ) -> GraphEdgeAnchors {
    let firstGeometry = nodeScreenGeometry(first, origin: origin, transform: transform)
    let secondGeometry = nodeScreenGeometry(second, origin: origin, transform: transform)
    return GraphCanvasGeometry.screenEdgeAnchors(
      from: graphPosition(first, origin: origin),
      to: graphPosition(second, origin: origin),
      origin: origin,
      viewport: transform,
      startRadius: firstGeometry.radius,
      endRadius: secondGeometry.radius
    )
  }

  #if DEBUG
  /// UI検証専用。selfから到達できる全人物を展開し、50/100人fixtureでも
  /// 製品と同じ描画経路を使ったzoom/pan証拠を安定して取得する。
  private func expandAllForUITesting() {
    var processed: Set<PersistentModelIDBox> = []

    while let node = store.nodes.values.first(where: { !processed.contains($0.id) }) {
      processed.insert(node.id)
      expandedIDs.insert(node.id)
      store.expand(node.person)
    }

    visibleNodeIDs.formUnion(store.nodes.keys)
    for edge in store.edges {
      edgeProgress[edge.id] = 1
    }
    updateFocus(to: displayedPerson)
  }
  #endif

  private func edgeFocusOpacity(for edge: GraphEdge) -> Double {
    let closestDistance = [focusDistances[edge.from], focusDistances[edge.to]]
      .compactMap { $0 }
      .min()
    return GraphFocusHierarchy.presentation(for: closestDistance).edgeOpacity
  }

  private func knotPosition(_ knot: GraphCoupleKnot, origin: CGPoint) -> CGPoint {
    guard let first = store.nodes[knot.first], let second = store.nodes[knot.second] else {
      return origin
    }
    let a = graphPosition(first, origin: origin)
    let b = graphPosition(second, origin: origin)
    return GraphCanvasGeometry.coupleKnotCenter(first: a, second: b)
  }

  private func renderPosition(
    _ endpoint: GraphRenderEndpoint,
    origin: CGPoint
  ) -> CGPoint? {
    switch endpoint {
    case .person(let id):
      guard let node = store.nodes[id] else { return nil }
      return graphPosition(node, origin: origin)
    case .knot(let id):
      guard let knot = store.renderSnapshot.knotsByID[id] else {
        return nil
      }
      return knotPosition(knot, origin: origin)
    }
  }

  private func knotSegmentAnchors(
    _ segment: GraphKnotSegment,
    origin: CGPoint,
    transform: GraphViewportTransform,
    cameraScale: CGFloat
  ) -> GraphEdgeAnchors? {
    guard
      let start = renderPosition(segment.from, origin: origin),
      let end = renderPosition(segment.to, origin: origin)
    else { return nil }
    let startRadius = endpointScreenRadius(segment.from, cameraScale: cameraScale)
    let endRadius = endpointScreenRadius(segment.to, cameraScale: cameraScale)
    return GraphCanvasGeometry.screenEdgeAnchors(
      from: start,
      to: end,
      origin: origin,
      viewport: transform,
      startRadius: startRadius,
      endRadius: endRadius
    )
  }

  private func endpointScreenRadius(
    _ endpoint: GraphRenderEndpoint,
    cameraScale: CGFloat
  ) -> CGFloat {
    switch endpoint {
    case .person(let id):
      return GraphNodeLODPolicy.presentation(
        cameraScale: cameraScale,
        focusScale: GraphFocusHierarchy.presentation(for: focusDistances[id]).nodeScale
      ).screenDiameter / 2
    case .knot:
      return CoupleKnotView.diameter / 2
    }
  }

  private func knotSegmentProgress(_ segment: GraphKnotSegment) -> CGFloat {
    guard !segment.sourceEdgeIDs.isEmpty else { return 1 }
    return segment.sourceEdgeIDs.map { edgeProgress[$0] ?? 0 }.max() ?? 0
  }

  private func segmentIsEmphasized(_ segment: GraphKnotSegment) -> Bool {
    guard let emphasizedPathEdges else { return true }
    return !segment.sourceEdges.isDisjoint(with: emphasizedPathEdges)
  }

  private func segmentIsIlluminated(_ segment: GraphKnotSegment) -> Bool {
    !segment.sourceEdges.isDisjoint(with: illuminatedPathEdges)
  }

  private func knotSegmentFocusOpacity(_ segment: GraphKnotSegment) -> Double {
    let personIDs: [PersistentModelIDBox] = [segment.from, segment.to].flatMap {
      switch $0 {
      case .person(let id): [id]
      case .knot(let couple): Array(couple.people)
      }
    }
    let closestDistance = personIDs.compactMap { focusDistances[$0] }.min()
    return GraphFocusHierarchy.presentation(for: closestDistance).edgeOpacity
  }

  private func updateFocus(
    to person: Person,
    moveCamera: Bool = false,
    animateTransition: Bool = false
  ) {
    let id = PersistentModelIDBox(person.persistentModelID)
    let route = RelationLabeler.shortestRoute(from: selfPerson, to: person)
    let distances = store.distances(from: id)
    let emphasized = GraphPathEmphasis.edgeEndpoints(for: route)
    let orderedPath = GraphPathEmphasis.orderedEdgeEndpoints(for: route)
    let nextViewport: GraphViewportTransform
    if let node = store.nodes[id] {
      nextViewport = GraphFocusTransition.viewport(
        from: viewportTransform,
        centeredOn: GraphGridPosition(level: node.level, slot: node.slot),
        slotWidth: slotWidth,
        levelHeight: levelHeight,
        moveCamera: moveCamera
      )
    } else {
      nextViewport = viewportTransform
    }

    guard animateTransition, focusedNodeID != id else {
      focusedNodeID = id
      focusDistances = distances
      emphasizedPathEdges = emphasized
      illuminatedPathEdges = []
      viewportTransform = nextViewport
      return
    }

    pathIlluminationToken = UUID()
    illuminatedPathEdges = []
    withAnimation(.easeInOut(duration: reduceMotion ? 0 : GraphFocusTransition.duration)) {
      focusedNodeID = id
      focusDistances = distances
      emphasizedPathEdges = emphasized
      viewportTransform = nextViewport
    }
    illuminatePath(orderedPath)
  }

  private func illuminatePath(_ orderedPath: [GraphEdgeEndpoints]) {
    // 直接の1本ではなく、複数の人物を辿る時だけ静かな順次点灯を行う。
    guard orderedPath.count >= 2 else { return }
    if reduceMotion {
      illuminatedPathEdges = Set(orderedPath)
      return
    }

    let token = UUID()
    pathIlluminationToken = token
    Task { @MainActor in
      for edge in orderedPath {
        try? await Task.sleep(
          nanoseconds: GraphFocusTransition.illuminationIntervalNanoseconds
        )
        guard pathIlluminationToken == token else { return }
        withAnimation(.easeInOut(duration: 0.12)) {
          _ = illuminatedPathEdges.insert(edge)
        }
      }
    }
  }

  private func nodeAccessibilityValue(
    node: GraphNode,
    zoomLevel: GraphSemanticZoomLevel,
    focusPresentation: GraphFocusPresentation,
    geometry: GraphNodeScreenGeometry
  ) -> String {
    let expansion = expandedIDs.contains(node.id) ? "展開済み" : "未展開"
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("-ui-testing-family-graph-ux") {
        return "\(expansion)|zoom:\(zoomLevel.rawValue)|focus:\(focusPresentation.band)|center:\(String(format: "%.1f", geometry.center.x)),\(String(format: "%.1f", geometry.center.y))|radius:\(String(format: "%.1f", geometry.radius))"
      }
    #endif
    return expansion
  }

  private func nodeAccessibilityLabel(
    person: Person,
    relationLabel: String
  ) -> String {
    var parts = [person.name]
    let note = person.relationNote.trimmingCharacters(in: .whitespacesAndNewlines)
    if !note.isEmpty {
      parts.append("続柄、\(note)")
    } else if !relationLabel.isEmpty {
      parts.append("自分から見た続柄、\(relationLabel)")
    }
    if person.persistentModelID == selfPerson.persistentModelID {
      parts.append("自分")
    }
    return parts.joined(separator: "、")
  }

  private func expand(_ node: GraphNode) {
    cancelIntroAnimation()
    let previousNodeIDs = Set(store.nodes.keys)
    let previousEdgeIDs = Set(store.edges.map(\.id))
    store.expand(node.person)
    let addedNodeIDs = Set(store.nodes.keys).subtracting(previousNodeIDs)
    let addedEdgeIDs = Set(store.edges.map(\.id)).subtracting(previousEdgeIDs)
    updateFocus(to: node.person, moveCamera: false, animateTransition: true)

    _ = withAnimation(.easeInOut(duration: reduceMotion ? 0 : 0.2)) {
      expandedIDs.insert(node.id)
    }
    animateNewContent(nodeIDs: addedNodeIDs, edgeIDs: addedEdgeIDs)
    bounce(node.id)
    onSelect(node.person)
  }

  private func presentNodeActions(for person: Person) {
    suppressTapAfterLongPress = true
    updateFocus(to: person)
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
    illuminatedPathEdges = []
    pathIlluminationToken = UUID()
    focusedNodeID = nil
    focusDistances = [:]
    bouncingNodeID = nil

    let selfID = PersistentModelIDBox(selfPerson.persistentModelID)
    visibleNodeIDs.insert(selfID)
    let previousNodeIDs = Set(store.nodes.keys)
    expandedIDs.formUnion(store.expandShortestPath(to: displayedPerson))
    let addedNodeIDs = Set(store.nodes.keys).subtracting(previousNodeIDs)
    updateFocus(to: displayedPerson)

    if playsIntroAnimation && !reduceMotion {
      let overview = GraphIntroLayout.overview(
        positions: store.nodes.values.map {
          GraphGridPosition(level: $0.level, slot: $0.slot)
        },
        viewport: viewport,
        slotWidth: slotWidth,
        levelHeight: levelHeight
      )
      viewportTransform = overview
      introPhase = "全体表示"
      animateIntroToFocusedPerson(token: animationToken)
    } else {
      let displayedID = PersistentModelIDBox(displayedPerson.persistentModelID)
      let target = store.nodes[displayedID] ?? store.nodes[selfID]
      if let target {
        viewportTransform = GraphIntroLayout.focus(
          position: GraphGridPosition(level: target.level, slot: target.slot),
          slotWidth: slotWidth,
          levelHeight: levelHeight
        )
      } else {
        viewportTransform = GraphViewportTransform(scale: 1, offset: .zero)
      }
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
        viewportTransform = focused
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
    let graphLocation = GraphHitTestGeometry.graphLocation(
      for: location,
      origin: origin,
      viewport: transform
    )
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

private enum RelativeTargetMode: String, CaseIterable {
  case existing
  case new

  var title: String {
    switch self {
    case .existing: "登録済みから選ぶ"
    case .new: "新しい人物"
    }
  }
}

private struct QuickRelativeAddSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query(sort: [SortDescriptor(\Person.kana), SortDescriptor(\Person.name)])
  private var allPersons: [Person]

  let person: Person
  let kind: QuickRelationKind
  let onLinked: (Person) -> Void

  @State private var mode: RelativeTargetMode = .existing
  @State private var name = ""
  @State private var searchText = ""
  @State private var selectedCandidate: Person?
  @State private var includeSpouseForChild = false
  @State private var errorMessage: String?
  @State private var sharedChildPrompt: SharedChildPrompt?
  @State private var dismissAfterSharedChildPrompt = false
  @FocusState private var focusedField: FocusedField?

  private enum FocusedField {
    case name
    case search
  }

  private var candidates: [Person] {
    let available = QuickRelativeRegistration.candidates(
      for: kind,
      person: person,
      from: allPersons
    )
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return available }
    return available.filter {
      $0.name.localizedStandardContains(query)
        || $0.kana.localizedStandardContains(query)
    }
  }

  private var canSave: Bool {
    switch mode {
    case .existing:
      selectedCandidate != nil
    case .new:
      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        Text("\(person.name)の\(kind.menuTitle.replacingOccurrences(of: "を追加", with: ""))")
          .font(.subheadline)
          .foregroundStyle(AppTheme.inkSoft)

        Picker("追加方法", selection: $mode) {
          ForEach(RelativeTargetMode.allCases, id: \.rawValue) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("quickRelative.mode")

        Group {
          switch mode {
          case .existing:
            existingPersonPicker
          case .new:
            newPersonForm
          }
        }

        if kind == .child, let spouse = person.spouse {
          VStack(alignment: .leading, spacing: 4) {
            Toggle("配偶者との共同の子にする", isOn: $includeSpouseForChild)
              .tint(AppTheme.ai)
              .accessibilityIdentifier("quickRelative.sharedChild")
            Text("オンにした場合だけ、\(spouse.name)との親子関係も追加します。")
              .font(.caption)
              .foregroundStyle(AppTheme.inkSoft)
          }
          .padding(12)
          .background(AppTheme.paperRaised, in: RoundedRectangle(cornerRadius: 12))
        }

        if let errorMessage {
          Text(errorMessage)
            .font(.footnote)
            .foregroundStyle(AppTheme.attention)
        }

        Button(action: save) {
          Text(mode == .existing ? "この人物と関係を作る" : "新しい人物を保存")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.ai)
        .disabled(!canSave)
        .accessibilityIdentifier("quickRelative.save")
      }
      .padding(20)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background(AppTheme.paper)
      .navigationTitle(kind.menuTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
      }
      .onAppear {
        if QuickRelativeRegistration.candidates(
          for: kind,
          person: person,
          from: allPersons
        ).isEmpty {
          mode = .new
          focusedField = .name
        } else {
          focusedField = .search
        }
      }
      .onChange(of: mode) { _, newMode in
        errorMessage = nil
        focusedField = newMode == .new ? .name : .search
      }
      .sheet(
        item: $sharedChildPrompt,
        onDismiss: {
          if dismissAfterSharedChildPrompt { dismiss() }
        }
      ) { prompt in
        SharedChildrenLinkSheet(prompt: prompt) { selectedChildren in
          do {
            try RelationshipTransaction.perform(in: modelContext) {
              RelationshipManager.linkSharedChildren(
                selectedChildren,
                of: prompt.person,
                with: prompt.spouse
              )
            }
            errorMessage = nil
          } catch {
            dismissAfterSharedChildPrompt = false
            errorMessage = error.localizedDescription
          }
        }
      }
    }
    .presentationDetents([.height(520), .large])
    .presentationBackground(AppTheme.paper)
  }

  private var existingPersonPicker: some View {
    VStack(spacing: 10) {
      TextField("名前で検索", text: $searchText)
        .textFieldStyle(.roundedBorder)
        .focused($focusedField, equals: .search)
        .accessibilityIdentifier("quickRelative.search")

      ScrollView {
        LazyVStack(spacing: 6) {
          if candidates.isEmpty {
            Text("関係を追加できる登録済み人物はいません。")
              .font(.footnote)
              .foregroundStyle(AppTheme.inkSoft)
              .padding(.vertical, 24)
          } else {
            ForEach(candidates) { candidate in
              Button {
                selectedCandidate = candidate
              } label: {
                HStack {
                  Text(candidate.name)
                    .foregroundStyle(AppTheme.ink)
                  Spacer()
                  if selectedCandidate?.persistentModelID == candidate.persistentModelID {
                    Image(systemName: "checkmark.circle.fill")
                      .foregroundStyle(AppTheme.ai)
                  }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 42)
                .background(
                  AppTheme.paperRaised,
                  in: RoundedRectangle(cornerRadius: 10)
                )
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("quickRelative.candidate.\(candidate.name)")
            }
          }
        }
      }
      .frame(maxHeight: 180)
    }
  }

  private var newPersonForm: some View {
    TextField("名前", text: $name)
      .textInputAutocapitalization(.never)
      .textFieldStyle(.roundedBorder)
      .focused($focusedField, equals: .name)
      .submitLabel(.done)
      .onSubmit(save)
      .accessibilityIdentifier("quickRelative.name")
  }

  private func save() {
    do {
      let relative: Person
      switch mode {
      case .existing:
        guard let selectedCandidate else {
          throw QuickRelativeRegistrationError.saveFailed
        }
        try QuickRelativeRegistration.linkExisting(
          selectedCandidate,
          kind: kind,
          for: person,
          in: modelContext,
          includeSpouseForChild: includeSpouseForChild
        )
        relative = selectedCandidate
      case .new:
        relative = try QuickRelativeRegistration.create(
          named: name,
          kind: kind,
          for: person,
          in: modelContext,
          includeSpouseForChild: includeSpouseForChild
        )
      }

      onLinked(relative)
      errorMessage = nil
      if kind == .spouse {
        let children = RelationshipManager.sharedChildCandidates(
          of: person,
          with: relative
        )
        if !children.isEmpty {
          dismissAfterSharedChildPrompt = true
          sharedChildPrompt = SharedChildPrompt(
            person: person,
            spouse: relative,
            candidates: children
          )
          return
        }
      }
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
  let photoImage: UIImage?
  var isSelf: Bool
  var isFocused: Bool
  var isExpanded: Bool
  var relationLabel: String
  var branch: FamilyBranch
  var semanticVisibility: GraphSemanticVisibility
  var focusPresentation: GraphFocusPresentation

  private var contentOpacity: Double {
    (isExpanded ? 1 : GraphNodeSurfaceContract.inactiveContentOpacity)
      * focusPresentation.nodeOpacity
  }

  private var focusAdornment: GraphFocusAdornment {
    GraphFocusAdornmentPolicy.adornment(isSelf: isSelf, isFocused: isFocused)
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
          isFocused ? (isSelf ? AppTheme.attention : AppTheme.ai) : branch.color,
          lineWidth: isFocused ? 2.5 : (photoImage == nil ? 1 : 1.5)
        )
        .opacity(contentOpacity)
      )
      .shadow(
        color: isFocused
          ? (isSelf ? AppTheme.attention : AppTheme.ai).opacity(0.22)
          : .clear,
        radius: isFocused ? 7 : 0,
        y: isFocused ? 2 : 0
      )
      // 未展開のノードには、まだ辿れることを示す小さな＋バッジ
      .overlay(alignment: .bottomTrailing) {
        if semanticVisibility.showsExpansionBadge {
          Image(systemName: "plus.circle.fill")
            .font(.caption)
            .foregroundStyle(AppTheme.ai)
            .background(Circle().fill(AppTheme.paper))
            .opacity(contentOpacity)
        }
      }

      if semanticVisibility.showsName {
        Text(person.name)
          .font(.caption2.weight(isSelf ? .bold : .medium))
          .foregroundStyle(AppTheme.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
          .allowsTightening(true)
          .frame(width: 92)
          .opacity(contentOpacity)
      }

      if semanticVisibility.showsRelation, !relationLabel.isEmpty {
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
    .saturation(focusPresentation.saturation)
    .contrast(focusPresentation.contrast)
    .background(alignment: .top) {
      if focusAdornment.showsStrongFocus {
        EndpointNodeRings(color: isSelf ? AppTheme.attention : AppTheme.ai)
          .frame(width: 120, height: 120)
          .offset(y: -32)
      } else if focusAdornment.showsSelfMarker {
        SelfNodeMarker()
          .frame(width: 72, height: 72)
          .offset(y: -8)
      }
    }
  }
}

/// 非フォーカス時の「自分」は小さな二重リングだけで識別する。
private struct SelfNodeMarker: View {
  var body: some View {
    ZStack(alignment: .top) {
      Circle()
        .stroke(AppTheme.attention.opacity(0.28), lineWidth: 0.7)
        .frame(width: 64, height: 64)
      Circle()
        .stroke(AppTheme.attention.opacity(0.16), lineWidth: 0.6)
        .frame(width: 70, height: 70)
      Circle()
        .fill(AppTheme.attention.opacity(0.58))
        .frame(width: 4, height: 4)
        .offset(y: -1)
    }
    .accessibilityHidden(true)
  }
}

/// 人物ではなく、夫婦の糸を束ねるrender専用の小さな結び目。
private struct CoupleKnotView: View {
  static let diameter: CGFloat = 9
  let color: Color
  let isFocused: Bool

  var body: some View {
    Circle()
      .fill(AppTheme.paperRaised)
      .frame(width: Self.diameter, height: Self.diameter)
      .overlay {
        Circle()
          .stroke(color.opacity(isFocused ? 0.95 : 0.72), lineWidth: 1.2)
      }
      .shadow(color: color.opacity(isFocused ? 0.18 : 0), radius: 3)
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
    .accessibilityHidden(true)
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
