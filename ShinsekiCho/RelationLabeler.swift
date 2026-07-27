import Foundation

/// 自分を起点に、グラフ上で1本の関係を辿った向き。
enum RelationStep: Hashable {
    case parent
    case child
    case spouse
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
}
