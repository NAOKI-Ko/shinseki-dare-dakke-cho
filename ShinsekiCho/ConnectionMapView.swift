import SwiftUI
import SwiftData

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
}

/// 自分から見た経路を、地図上の3つの家系色へ分類する。
enum FamilyBranch: String, CaseIterable, Hashable {
    case indigo
    case forest
    case plum

    static func classify(path: [RelationStep]) -> Self {
        if path.isEmpty || path.allSatisfy({ $0 == .parent })
            || path.allSatisfy({ $0 == .child }) {
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

        var shortest: [PersistentModelIDBox: [RelationStep]] = [rootID: []]
        var queue = [rootID]
        var queueIndex = 0

        while queueIndex < queue.count {
            let current = queue[queueIndex]
            queueIndex += 1
            guard let currentPath = shortest[current] else { continue }

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

                guard shortest[next] == nil else { continue }
                shortest[next] = currentPath + [step]
                queue.append(next)
            }
        }

        for (id, path) in shortest {
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
    var onSelect: (Person) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var store = FamilyGraphStore()
    @State private var expandedIDs: Set<PersistentModelIDBox> = []
    @State private var visibleNodeIDs: Set<PersistentModelIDBox> = []
    @State private var edgeProgress: [UUID: CGFloat] = [:]
    @State private var bouncingNodeID: PersistentModelIDBox?

    @State private var scale: CGFloat = 1.0
    @GestureState private var pinchDelta: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var dragDelta: CGSize = .zero

    private let levelHeight: CGFloat = 120
    private let slotWidth: CGFloat = 108
    private let nodeSize: CGFloat = 68

    var body: some View {
        GeometryReader { geo in
            // 親・本人・子の3世代すべてに、画面端と重ならないタップ余白を確保する。
            let origin = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                AppTheme.paper

                ForEach(store.edges) { edge in
                    if let a = store.nodes[edge.from], let b = store.nodes[edge.to] {
                        GraphEdgeShape(
                            start: pixelPosition(a, origin: origin),
                            end: pixelPosition(b, origin: origin)
                        )
                        .trim(from: 0, to: edgeProgress[edge.id] ?? 0)
                        .stroke(
                            store.branch(for: edge).color,
                            style: StrokeStyle(
                                lineWidth: edge.kind == .spouse ? 2.5 : 1.5,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .zIndex(0)
                        .accessibilityHidden(true)
                    }
                }

                ForEach(Array(store.nodes.values), id: \.id) { node in
                    GraphNodeCard(
                        person: node.person,
                        isSelf: node.person.persistentModelID == selfPerson.persistentModelID,
                        isExpanded: expandedIDs.contains(node.id),
                        relationLabel: RelationLabeler.label(for: node.path),
                        branch: store.branch(for: node.id)
                    )
                    .frame(width: nodeSize, height: nodeSize + 34)
                    .position(pixelPosition(node, origin: origin))
                    .scaleEffect(
                        scale * pinchDelta
                            * (visibleNodeIDs.contains(node.id) ? 1 : 0.3)
                            * (bouncingNodeID == node.id ? 1.08 : 1)
                    )
                    .opacity(visibleNodeIDs.contains(node.id) ? 1 : 0)
                    .zIndex(1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("connectionMap.node.\(node.person.name)")
                    .accessibilityLabel(node.person.name)
                    .accessibilityValue(expandedIDs.contains(node.id) ? "展開済み" : "未展開")
                    .accessibilityAction {
                        expand(node)
                    }
                }
            }
            // 子のノードButtonと同時に認識させ、単純なタップを奪わない。
            .simultaneousGesture(
                MagnificationGesture()
                    .updating($pinchDelta) { value, state, _ in state = value }
                    .onEnded { value in
                        scale = min(max(scale * value, 0.4), 2.5)
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
                        if hypot(value.translation.width, value.translation.height) < 10 {
                            if let node = node(at: value.location, origin: origin) {
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
        }
        .frame(height: 420)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("connectionMap.canvas")
        .overlay(alignment: .bottom) {
            FamilyBranchLegend()
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                scale = 1.0
                offset = .zero
            } label: {
                Image(systemName: "scope")
                    .padding(10)
                    .background(AppTheme.paperRaised, in: Circle())
                    .overlay(Circle().stroke(AppTheme.ruleStrong, lineWidth: 1))
            }
            .accessibilityIdentifier("connectionMap.resetButton")
            .padding(.trailing, 12)
            .padding(.bottom, 38)
        }
        .onAppear {
            prepareInitialGraph()
        }
        // blurを含む後光も最終的なキャンバス境界で合成・切り抜きする。
        // 親のListをスクロールしても、見出しカード側へ描画が漏れない。
        .compositingGroup()
        .clipped()
    }

    private func pixelPosition(_ node: GraphNode, origin: CGPoint) -> CGPoint {
        let effectiveScale = scale * pinchDelta
        return CGPoint(
            x: origin.x
                + CGFloat(node.slot) * slotWidth * effectiveScale
                + offset.width + dragDelta.width,
            y: origin.y
                + CGFloat(node.level) * levelHeight * effectiveScale
                + offset.height + dragDelta.height
        )
    }

    private func expand(_ node: GraphNode) {
        let previousNodeIDs = Set(store.nodes.keys)
        let previousEdgeIDs = Set(store.edges.map(\.id))
        store.expand(node.person)
        let addedNodeIDs = Set(store.nodes.keys).subtracting(previousNodeIDs)
        let addedEdgeIDs = Set(store.edges.map(\.id)).subtracting(previousEdgeIDs)

        withAnimation(.easeInOut(duration: reduceMotion ? 0 : 0.2)) {
            expandedIDs.insert(node.id)
        }
        animateNewContent(nodeIDs: addedNodeIDs, edgeIDs: addedEdgeIDs)
        bounce(node.id)
        onSelect(node.person)
    }

    private func prepareInitialGraph() {
        store.reset(with: selfPerson)
        expandedIDs = []
        visibleNodeIDs = []
        edgeProgress = [:]
        bouncingNodeID = nil

        let selfID = PersistentModelIDBox(selfPerson.persistentModelID)
        visibleNodeIDs.insert(selfID)
        let previousNodeIDs = Set(store.nodes.keys)
        store.expand(selfPerson)
        expandedIDs.insert(selfID)
        let addedNodeIDs = Set(store.nodes.keys).subtracting(previousNodeIDs)
        animateNewContent(
            nodeIDs: addedNodeIDs,
            edgeIDs: Set(store.edges.map(\.id))
        )
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

    private func node(at location: CGPoint, origin: CGPoint) -> GraphNode? {
        let hitRadius = max(44, nodeSize * scale * pinchDelta / 2)
        return store.nodes.values
            .map { node in
                let point = pixelPosition(node, origin: origin)
                return (node, hypot(point.x - location.x, point.y - location.y))
            }
            .filter { $0.1 <= hitRadius }
            .min { $0.1 < $1.1 }?
            .0
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
    var isExpanded: Bool
    var relationLabel: String
    var branch: FamilyBranch

    private var photoImage: UIImage? {
        PersonPhotoSupport.image(from: person.photoData)
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // 半透明の意味色の下を紙色で塞ぎ、接続線を一切透過させない。
                Circle().fill(AppTheme.paperRaised)

                if let uiImage = photoImage {
                    Image(uiImage: uiImage).resizable().scaledToFill()
                } else {
                    Circle().fill(AppTheme.ai.opacity(0.08))
                }

                // 写真の有無に関係なく、家系のまとまりを遠目でも識別できる薄い色面。
                // 自分だけは従来の朱を保ち、家系色へ置き換えない。
                Circle()
                    .fill((isSelf ? AppTheme.attention : branch.color).opacity(0.08))

                if photoImage == nil {
                    Text(PersonPhotoSupport.initial(for: person.name))
                        .font(.minchoTitle(20, relativeTo: .headline))
                        .foregroundStyle(AppTheme.ai)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .overlay(
                Circle().stroke(
                    branch.color,
                    lineWidth: isSelf ? 2.5 : (photoImage == nil ? 1 : 1.5)
                )
            )
            // 未展開のノードには、まだ辿れることを示す小さな＋バッジ
            .overlay(alignment: .bottomTrailing) {
                if !isExpanded {
                    Image(systemName: "plus.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ai)
                        .background(Circle().fill(AppTheme.paper))
                }
            }

            Text(person.name)
                .font(.caption2.weight(isSelf ? .bold : .medium))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)

            if !relationLabel.isEmpty {
                Text("(\(relationLabel))")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(AppTheme.inkSoft)
                    .lineLimit(1)
            }
        }
        .background(alignment: .top) {
            if isSelf {
                SelfNodeRings()
                    .frame(width: 120, height: 120)
                    .offset(y: -32)
            }
        }
        .opacity(isExpanded ? 1 : 0.92)
    }
}

/// 自分の位置を地図の基準点として示す、ごく細い同心円。
private struct SelfNodeRings: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.ai.opacity(0.15))
                .frame(width: 132, height: 132)
                .blur(radius: 20)
                .scaleEffect(isBreathing ? 1.08 : 1)

            Circle()
                .stroke(AppTheme.rule.opacity(0.75), lineWidth: 0.6)
                .frame(width: 78, height: 78)
            Circle()
                .stroke(AppTheme.rule.opacity(0.58), lineWidth: 0.55)
                .frame(width: 98, height: 98)
            Circle()
                .stroke(AppTheme.rule.opacity(0.42), lineWidth: 0.5)
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
