import Foundation

enum PersonSearchMatchReason: Hashable {
    case name
    case kana
    case relationNote(String)
    case structuredRelationship(String)
    case relationshipPath(String)
    case spouseSide
    case directLine
    case livingArea(String)
    case lastMetPlace(String)
    case gatheringTitle(String)
    case gatheringPlace(String)
    case favorites
    case dietaryNotes
    case memo

    var displayText: String {
        switch self {
        case .name:
            "名前に一致"
        case .kana:
            "ふりがなに一致"
        case .relationNote(let value):
            "続柄：\(value)"
        case .structuredRelationship(let value), .relationshipPath(let value):
            "つながり：\(value)"
        case .spouseSide:
            "配偶者側"
        case .directLine:
            "直系"
        case .livingArea(let value):
            "居住地：\(value)"
        case .lastMetPlace(let value):
            "最後に会った場所：\(value)"
        case .gatheringTitle(let value):
            "集まり：\(value)"
        case .gatheringPlace(let value):
            "集まりの場所：\(value)"
        case .favorites:
            "好きなもの・苦手なものに一致"
        case .dietaryNotes:
            "食事の配慮に一致"
        case .memo:
            "会話メモに一致"
        }
    }
}

struct PersonSearchResult {
    let person: Person
    let score: Int
    let matchReasons: [PersonSearchMatchReason]

    var primaryMatchReason: PersonSearchMatchReason? { matchReasons.first }
}

enum PersonSearchNormalizer {
    static func normalize(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "ja_JP")
        )
        let hiragana = folded.applyingTransform(.hiraganaToKatakana, reverse: true) ?? folded
        return hiragana
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func compact(_ value: String) -> String {
        normalize(value).replacingOccurrences(of: " ", with: "")
    }

    static func tokens(in query: String) -> [String] {
        normalize(query).split(separator: " ").map(String.init)
    }
}

/// 保存済み情報だけから検索文書を作る、読み取り専用の検索エンジン。
/// relationship routeは1人物につき1回だけ計算し、全tokenで同じ文書を再利用する。
enum PersonSearchEngine {
    private struct SearchField {
        let value: String
        let normalized: String
        let compact: String
        let weight: Int
        let reason: PersonSearchMatchReason
        let supportsCompactMatch: Bool
        let receivesIdentityBonus: Bool

        init(
            value: String,
            weight: Int,
            reason: PersonSearchMatchReason,
            supportsCompactMatch: Bool = false,
            receivesIdentityBonus: Bool = false
        ) {
            self.value = value
            self.normalized = PersonSearchNormalizer.normalize(value)
            self.compact = PersonSearchNormalizer.compact(value)
            self.weight = weight
            self.reason = reason
            self.supportsCompactMatch = supportsCompactMatch
            self.receivesIdentityBonus = receivesIdentityBonus
        }
    }

    private struct SearchDocument {
        let person: Person
        let fields: [SearchField]
    }

    private struct FieldMatch {
        let score: Int
        let reason: PersonSearchMatchReason
    }

    static func search(
        persons: [Person],
        selfPerson: Person?,
        query: String
    ) -> [PersonSearchResult] {
        let normalizedQuery = PersonSearchNormalizer.normalize(query)
        let tokens = PersonSearchNormalizer.tokens(in: query)
        guard !normalizedQuery.isEmpty, !tokens.isEmpty else {
            return persons.map { PersonSearchResult(person: $0, score: 0, matchReasons: []) }
        }

        return persons.compactMap { person in
            evaluate(
                document: makeDocument(person: person, selfPerson: selfPerson),
                normalizedQuery: normalizedQuery,
                tokens: tokens
            )
        }.sorted(by: resultPrecedes)
    }

    private static func makeDocument(person: Person, selfPerson: Person?) -> SearchDocument {
        var fields = [
            SearchField(
                value: person.name,
                weight: 500,
                reason: .name,
                supportsCompactMatch: true,
                receivesIdentityBonus: true
            ),
            SearchField(
                value: person.kana,
                weight: 450,
                reason: .kana,
                supportsCompactMatch: true,
                receivesIdentityBonus: true
            ),
            SearchField(
                value: person.relationNote,
                weight: 400,
                reason: .relationNote(person.relationNote)
            ),
            SearchField(
                value: person.livingArea,
                weight: 300,
                reason: .livingArea(person.livingArea)
            ),
            SearchField(
                value: person.lastMetPlace,
                weight: 280,
                reason: .lastMetPlace(person.lastMetPlace)
            ),
            SearchField(value: person.favorites, weight: 120, reason: .favorites),
            SearchField(value: person.dietaryNotes, weight: 110, reason: .dietaryNotes),
            SearchField(value: person.memo, weight: 100, reason: .memo)
        ]

        let sortedGatherings = person.gatherings.sorted {
            let titleOrder = PersonSearchNormalizer.normalize($0.title)
                .localizedStandardCompare(PersonSearchNormalizer.normalize($1.title))
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            let placeOrder = PersonSearchNormalizer.normalize($0.place)
                .localizedStandardCompare(PersonSearchNormalizer.normalize($1.place))
            if placeOrder != .orderedSame { return placeOrder == .orderedAscending }
            return $0.date < $1.date
        }
        for gathering in sortedGatherings {
            fields.append(
                SearchField(
                    value: gathering.title,
                    weight: 240,
                    reason: .gatheringTitle(gathering.title)
                )
            )
            fields.append(
                SearchField(
                    value: gathering.place,
                    weight: 220,
                    reason: .gatheringPlace(gathering.place)
                )
            )
        }

        if let selfPerson,
           let route = RelationLabeler.shortestRoute(from: selfPerson, to: person) {
            let structuredLabel = RelationLabeler.label(for: route.steps)
            if !structuredLabel.isEmpty {
                fields.append(
                    SearchField(
                        value: structuredLabel,
                        weight: 360,
                        reason: .structuredRelationship(structuredLabel)
                    )
                )
            }

            if route.people.count > 2 {
                for intermediate in route.people.dropFirst().dropLast() {
                    fields.append(
                        SearchField(
                            value: intermediate.name,
                            weight: 340,
                            reason: .relationshipPath(intermediate.name),
                            supportsCompactMatch: true
                        )
                    )
                    let note = intermediate.relationNote
                    fields.append(
                        SearchField(
                            value: note,
                            weight: 350,
                            reason: .relationshipPath(note)
                        )
                    )
                }
            }

            if route.steps.contains(.spouse) {
                fields.append(
                    SearchField(value: "配偶者側", weight: 370, reason: .spouseSide)
                )
            }
            if !route.steps.isEmpty,
               route.steps.allSatisfy({ $0 == .parent })
                || route.steps.allSatisfy({ $0 == .child }) {
                fields.append(
                    SearchField(value: "直系", weight: 365, reason: .directLine)
                )
            }
        }

        return SearchDocument(
            person: person,
            fields: fields.filter { !$0.normalized.isEmpty }
        )
    }

    private static func evaluate(
        document: SearchDocument,
        normalizedQuery: String,
        tokens: [String]
    ) -> PersonSearchResult? {
        var totalScore = 0
        var reasons: [PersonSearchMatchReason] = []

        for token in tokens {
            guard let best = document.fields.compactMap({ match(token: token, field: $0) })
                .max(by: { $0.score < $1.score }) else {
                return nil
            }
            totalScore += best.score
            if !reasons.contains(best.reason) { reasons.append(best.reason) }
        }

        // token化で失われる「氏名全体の完全一致・prefix」をrankingへ戻す。
        let queryCompact = normalizedQuery.replacingOccurrences(of: " ", with: "")
        let identityBonuses = document.fields.compactMap { field -> Int? in
            guard field.receivesIdentityBonus else { return nil }
            return identityBonus(
                query: normalizedQuery,
                compactQuery: queryCompact,
                field: field
            )
        }
        if let bestIdentityBonus = identityBonuses.max() {
            totalScore += bestIdentityBonus
        }

        return PersonSearchResult(
            person: document.person,
            score: totalScore,
            matchReasons: reasons
        )
    }

    private static func match(token: String, field: SearchField) -> FieldMatch? {
        let normalizedStrength = matchStrength(needle: token, haystack: field.normalized)
        let compactStrength: Int?
        if field.supportsCompactMatch {
            compactStrength = matchStrength(
                needle: token.replacingOccurrences(of: " ", with: ""),
                haystack: field.compact
            )
        } else {
            compactStrength = nil
        }
        guard let strength = [normalizedStrength, compactStrength].compactMap({ $0 }).max() else {
            return nil
        }
        return FieldMatch(score: field.weight + strength, reason: field.reason)
    }

    private static func matchStrength(needle: String, haystack: String) -> Int? {
        guard !needle.isEmpty, !haystack.isEmpty else { return nil }
        if haystack == needle { return 30 }
        if haystack.hasPrefix(needle) { return 20 }
        if haystack.contains(needle) { return 10 }
        return nil
    }

    private static func identityBonus(
        query: String,
        compactQuery: String,
        field: SearchField
    ) -> Int? {
        let normal = matchStrength(needle: query, haystack: field.normalized)
        let compact = matchStrength(needle: compactQuery, haystack: field.compact)
        guard let strength = [normal, compact].compactMap({ $0 }).max() else { return nil }
        switch strength {
        case 30: return 300
        case 20: return 200
        default: return 100
        }
    }

    private static func resultPrecedes(_ lhs: PersonSearchResult, _ rhs: PersonSearchResult) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        let kanaOrder = PersonSearchNormalizer.normalize(lhs.person.kana)
            .localizedStandardCompare(PersonSearchNormalizer.normalize(rhs.person.kana))
        if kanaOrder != .orderedSame { return kanaOrder == .orderedAscending }
        let nameOrder = PersonSearchNormalizer.normalize(lhs.person.name)
            .localizedStandardCompare(PersonSearchNormalizer.normalize(rhs.person.name))
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        if lhs.person.createdAt != rhs.person.createdAt {
            return lhs.person.createdAt < rhs.person.createdAt
        }
        return String(describing: lhs.person.persistentModelID)
            < String(describing: rhs.person.persistentModelID)
    }
}
