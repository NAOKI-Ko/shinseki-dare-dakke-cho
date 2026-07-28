import Foundation
import SwiftData

/// 自分を起点に、グラフ上で1本の関係を辿った向き。
enum RelationStep: Hashable {
    case parent
    case child
    case spouse
}

/// 自分から表示対象までの最短経路。peopleは起点と終点を含む。
struct RelationRoute {
    let people: [Person]
    let steps: [RelationStep]
}

/// 表示中グラフと全人物グラフで共用する幅優先探索の結果。
struct RelationTraversalResult<Node: Hashable> {
    let paths: [Node: [RelationStep]]
    let previous: [Node: Node]
}

/// 最短経路を、性別情報に依存しない短い続柄へ変換する。
enum RelationLabeler {
    static func label(for path: [RelationStep]) -> String {
        if path.isEmpty { return "自分" }
        if path == [.parent] { return "親" }
        if path == [.spouse] { return "配偶者" }
        if path == [.child] { return "子" }
        if path == [.parent, .parent] { return "祖父母" }
        if path == [.child, .child] { return "孫" }
        if path == [.parent, .child] { return "兄弟姉妹" }
        if path == [.parent, .parent, .child] { return "おじ・おば" }
        if path == [.parent, .child, .child] { return "甥・姪" }
        return ""
    }

    /// 起点から各ノードへの最短経路を幅優先探索で求める。
    /// 同じ長さの経路が複数ある場合は、neighborsが先に返した経路を保つ。
    static func breadthFirstPaths<Node: Hashable>(
        from root: Node,
        neighbors: (Node) -> [(node: Node, step: RelationStep)]
    ) -> RelationTraversalResult<Node> {
        var paths: [Node: [RelationStep]] = [root: []]
        var previous: [Node: Node] = [:]
        var queue = [root]
        var queueIndex = 0

        while queueIndex < queue.count {
            let current = queue[queueIndex]
            queueIndex += 1
            guard let currentPath = paths[current] else { continue }

            for neighbor in neighbors(current) where paths[neighbor.node] == nil {
                paths[neighbor.node] = currentPath + [neighbor.step]
                previous[neighbor.node] = current
                queue.append(neighbor.node)
            }
        }

        return RelationTraversalResult(paths: paths, previous: previous)
    }

    /// Personモデルに保存された親・子・配偶者を辿り、2人を結ぶ最短経路を返す。
    static func shortestRoute(from root: Person, to target: Person) -> RelationRoute? {
        let rootID = PersistentModelIDBox(root.persistentModelID)
        let targetID = PersistentModelIDBox(target.persistentModelID)
        var peopleByID: [PersistentModelIDBox: Person] = [rootID: root]

        let traversal = breadthFirstPaths(from: rootID) { currentID in
            guard let current = peopleByID[currentID] else { return [] }

            var result: [(node: PersistentModelIDBox, step: RelationStep)] = []
            for parent in current.parents {
                let id = PersistentModelIDBox(parent.persistentModelID)
                peopleByID[id] = parent
                result.append((id, .parent))
            }
            for child in current.children {
                let id = PersistentModelIDBox(child.persistentModelID)
                peopleByID[id] = child
                result.append((id, .child))
            }
            if let spouse = current.spouse {
                let id = PersistentModelIDBox(spouse.persistentModelID)
                peopleByID[id] = spouse
                result.append((id, .spouse))
            }
            return result
        }

        guard let steps = traversal.paths[targetID] else { return nil }
        var reversedIDs = [targetID]
        var cursor = targetID
        while cursor != rootID {
            guard let predecessor = traversal.previous[cursor] else { return nil }
            reversedIDs.append(predecessor)
            cursor = predecessor
        }

        let people = reversedIDs.reversed().compactMap { peopleByID[$0] }
        guard people.count == reversedIDs.count else { return nil }
        return RelationRoute(people: people, steps: steps)
    }
}
