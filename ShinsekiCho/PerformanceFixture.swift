#if DEBUG
import SwiftData
import UIKit

enum PerformanceFixtureSize: String, CaseIterable {
    case small
    case medium
    case stress

    var personCount: Int {
        switch self {
        case .small: 10
        case .medium: 50
        case .stress: 100
        }
    }

    var photoCount: Int {
        switch self {
        case .small: 4
        case .medium: 20
        case .stress: 50
        }
    }

    var gatheringCount: Int {
        switch self {
        case .small: 3
        case .medium: 10
        case .stress: 20
        }
    }

    static func launchArgument(in arguments: [String]) -> Self? {
        if arguments.contains("-ui-testing-performance-stress") { return .stress }
        if arguments.contains("-ui-testing-performance-medium") { return .medium }
        if arguments.contains("-ui-testing-performance-small") { return .small }
        return nil
    }
}

struct PerformanceFixture {
    let size: PerformanceFixtureSize
    let people: [Person]
    let gatherings: [Gathering]

    var selfPerson: Person { people[0] }
}

enum PerformanceFixtureError: Error {
    case relationshipCreationFailed
}

/// Release Candidateの性能検証専用fixture。生成規則は乱数や現在日時に依存しない。
@MainActor
enum PerformanceFixtureBuilder {
    private static let referenceDate = Date(timeIntervalSince1970: 1_767_225_600)

    @discardableResult
    static func build(
        _ size: PerformanceFixtureSize,
        in context: ModelContext
    ) throws -> PerformanceFixture {
        let photoVariants = makePhotoVariants()
        let people = (0..<size.personCount).map { index in
            let identity = identity(at: index)
            let person = Person(
                name: identity.name,
                kana: identity.kana,
                relationNote: identity.relation,
                isSelf: index == 0,
                photoData: index < size.photoCount
                    ? photoVariants[index % photoVariants.count]
                    : nil,
                phone: index.isMultiple(of: 5) ? String(format: "090-0000-%04d", index) : "",
                email: index.isMultiple(of: 7) ? "relative\(index)@example.com" : "",
                livingArea: index == 9 || index.isMultiple(of: 6) ? "横浜" : area(at: index),
                lastMetDate: Calendar(identifier: .gregorian).date(
                    byAdding: .day,
                    value: -index,
                    to: referenceDate
                ),
                lastMetPlace: index.isMultiple(of: 4) ? "実家" : "親族の集まり",
                birthday: Calendar(identifier: .gregorian).date(
                    byAdding: .year,
                    value: -(20 + index % 70),
                    to: referenceDate
                ),
                favorites: index == 9 || index.isMultiple(of: 11) ? "珈琲と登山" : "和菓子",
                dietaryNotes: index.isMultiple(of: 13) ? "甲殻類アレルギー" : "",
                memo: "性能検証用の会話メモ \(index)"
            )
            person.createdAt = referenceDate.addingTimeInterval(TimeInterval(index))
            return person
        }
        people.forEach(context.insert)
        try context.save()

        try linkCoreFamily(people)
        try linkAdditionalGenerations(people)

        let gatherings = (0..<size.gatheringCount).map { index in
            let gathering = Gathering(
                title: index == 0 ? "祖父の法事" : "親族の集まり \(index + 1)",
                date: Calendar(identifier: .gregorian).date(
                    byAdding: .month,
                    value: -index,
                    to: referenceDate
                )!,
                place: index.isMultiple(of: 2) ? "横浜" : "実家",
                note: "性能検証用の集まり \(index)"
            )
            context.insert(gathering)
            let attendeeCount = min(people.count, 20 + index % 11)
            for offset in 0..<attendeeCount {
                let personIndex = (index * 7 + offset) % people.count
                gathering.attendees.append(people[personIndex])
            }
            return gathering
        }
        try context.save()
        return PerformanceFixture(size: size, people: people, gatherings: gatherings)
    }

    static func deterministicSignature(of fixture: PerformanceFixture) -> [String] {
        fixture.people.map { person in
            let spouse = person.spouse?.name ?? "-"
            let parents = person.parents.map(\.name).sorted().joined(separator: ",")
            let children = person.children.map(\.name).sorted().joined(separator: ",")
            return "\(person.name)|S:\(spouse)|P:\(parents)|C:\(children)"
        }
    }

    private static func linkCoreFamily(_ people: [Person]) throws {
        guard people.count >= 10 else { return }
        guard RelationshipManager.setSpouse(people[2], people[3]),
              RelationshipManager.addChild(people[0], to: people[2], includeSpouse: true),
              RelationshipManager.addChild(people[8], to: people[2], includeSpouse: true),
              RelationshipManager.setSpouse(people[4], people[5]),
              RelationshipManager.addChild(people[1], to: people[4], includeSpouse: true),
              RelationshipManager.addChild(people[9], to: people[4], includeSpouse: true),
              RelationshipManager.setSpouse(people[0], people[1]),
              RelationshipManager.addChild(people[6], to: people[0], includeSpouse: true),
              RelationshipManager.addChild(people[7], to: people[0], includeSpouse: true)
        else { throw PerformanceFixtureError.relationshipCreationFailed }
    }

    private static func linkAdditionalGenerations(_ people: [Person]) throws {
        guard people.count > 10 else { return }
        var nextIndex = 10
        var frontier = [people[6], people[7], people[8], people[9]]
        var frontierIndex = 0

        while nextIndex < people.count {
            let parent = frontier[frontierIndex]
            frontierIndex += 1

            var spouse: Person?
            if nextIndex < people.count {
                spouse = people[nextIndex]
                nextIndex += 1
                guard RelationshipManager.setSpouse(parent, spouse!) else {
                    throw PerformanceFixtureError.relationshipCreationFailed
                }
            }

            for _ in 0..<2 where nextIndex < people.count {
                let child = people[nextIndex]
                nextIndex += 1
                guard RelationshipManager.addChild(child, to: parent, includeSpouse: spouse != nil) else {
                    throw PerformanceFixtureError.relationshipCreationFailed
                }
                frontier.append(child)
            }
        }
    }

    private static func identity(at index: Int) -> (name: String, kana: String, relation: String) {
        let core: [(String, String, String)] = [
            ("山田 太郎", "やまだ たろう", "自分"),
            ("佐藤 美咲", "さとう みさき", "配偶者"),
            ("山田 一郎", "やまだ いちろう", "父"),
            ("山田 花子", "やまだ はなこ", "母"),
            ("佐藤 修一", "さとう しゅういち", "配偶者の父"),
            ("佐藤 恵子", "さとう けいこ", "配偶者の母"),
            ("山田 葵", "やまだ あおい", "子"),
            ("山田 湊", "やまだ みなと", "子"),
            ("山田 次郎", "やまだ じろう", "兄弟姉妹"),
            ("佐藤 健太", "さとう けんた", "配偶者の兄弟姉妹")
        ]
        if index < core.count { return core[index] }
        return (
            String(format: "親戚 %03d", index),
            String(format: "しんせき %03d", index),
            index.isMultiple(of: 3) ? "子孫" : "親戚"
        )
    }

    private static func area(at index: Int) -> String {
        ["東京", "名古屋", "大阪", "札幌", "福岡"][index % 5]
    }

    private static func makePhotoVariants() -> [Data] {
        let colors: [UIColor] = [
            UIColor(red: 0.17, green: 0.27, blue: 0.40, alpha: 1),
            UIColor(red: 0.24, green: 0.42, blue: 0.32, alpha: 1),
            UIColor(red: 0.42, green: 0.24, blue: 0.37, alpha: 1),
            UIColor(red: 0.70, green: 0.23, blue: 0.18, alpha: 1)
        ]
        return colors.compactMap { color in
            UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).pngData { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
            }
        }
    }
}
#endif
