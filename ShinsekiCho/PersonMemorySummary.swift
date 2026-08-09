import Foundation

/// 人物詳細の冒頭で使う、保存済み情報だけから作る記憶支援サマリー。
/// 経路や表示文は永続化せず、表示のたびに現在の関係グラフから再計算する。
struct PersonMemorySummary: Equatable {
    struct Relationship: Equatable {
        enum Status: Equatable {
            case connected
            case disconnected
        }

        let status: Status
        let breadcrumbComponents: [String]
        let structuredLabel: String?

        var breadcrumb: String {
            switch status {
            case .connected:
                breadcrumbComponents.joined(separator: " → ")
            case .disconnected:
                "自分とのつながりはまだ登録されていません"
            }
        }
    }

    struct LastMet: Equatable {
        let date: Date
        let place: String?
    }

    struct GatheringRecall: Equatable {
        let title: String
        let date: Date
    }

    let relationship: Relationship
    let lastMet: LastMet?
    let livingArea: String?
    let memo: String?
    let favorites: String?
    let latestGathering: GatheringRecall?
}

enum PersonMemorySummaryBuilder {
    static func make(selfPerson: Person?, target: Person) -> PersonMemorySummary {
        let relationship = makeRelationship(selfPerson: selfPerson, target: target)
        let lastMet = target.lastMetDate.map {
            PersonMemorySummary.LastMet(
                date: $0,
                place: normalized(target.lastMetPlace)
            )
        }
        let latestGathering = target.gatherings.max { lhs, rhs in
            lhs.date < rhs.date
        }.map {
            PersonMemorySummary.GatheringRecall(title: $0.title, date: $0.date)
        }

        return PersonMemorySummary(
            relationship: relationship,
            lastMet: lastMet,
            livingArea: normalized(target.livingArea),
            memo: normalized(target.memo),
            favorites: normalized(target.favorites),
            latestGathering: latestGathering
        )
    }

    private static func makeRelationship(
        selfPerson: Person?,
        target: Person
    ) -> PersonMemorySummary.Relationship {
        guard let selfPerson,
              let route = RelationLabeler.shortestRoute(from: selfPerson, to: target) else {
            return PersonMemorySummary.Relationship(
                status: .disconnected,
                breadcrumbComponents: [],
                structuredLabel: nil
            )
        }

        if selfPerson.persistentModelID == target.persistentModelID {
            return PersonMemorySummary.Relationship(
                status: .connected,
                breadcrumbComponents: ["自分"],
                structuredLabel: nil
            )
        }

        let finalIndex = route.people.index(before: route.people.endIndex)
        let components = route.people.indices.map { index -> String in
            if index == route.people.startIndex { return "自分" }

            let person = route.people[index]
            let note = normalized(person.relationNote)
            if index == finalIndex {
                return note.map { "\($0)（\(person.name)）" } ?? person.name
            }
            return note ?? person.name
        }
        let label = normalized(RelationLabeler.label(for: route.steps))

        return PersonMemorySummary.Relationship(
            status: .connected,
            breadcrumbComponents: components,
            structuredLabel: label
        )
    }

    private static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
