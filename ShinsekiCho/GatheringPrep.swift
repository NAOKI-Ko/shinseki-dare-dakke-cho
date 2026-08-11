import SwiftUI
import SwiftData

struct GatheringPrepEntry {
    let person: Person
}

/// 集まりの参加者を読み取り専用で順に確認する、一時的なセッション。
/// indexを含めてSwiftDataへは保存しない。
struct GatheringPrepSession {
    let entries: [GatheringPrepEntry]
    private(set) var currentIndex: Int

    init(entries: [GatheringPrepEntry], currentIndex: Int = 0) {
        self.entries = entries
        if entries.isEmpty {
            self.currentIndex = 0
        } else {
            self.currentIndex = min(max(currentIndex, 0), entries.count - 1)
        }
    }

    var count: Int { entries.count }
    var currentPerson: Person? {
        guard entries.indices.contains(currentIndex) else { return nil }
        return entries[currentIndex].person
    }
    var canGoPrevious: Bool { currentIndex > 0 }
    var canGoNext: Bool { currentIndex + 1 < count }
    var progressText: String { count == 0 ? "0 / 0" : "\(currentIndex + 1) / \(count)" }

    mutating func moveNext() {
        guard canGoNext else { return }
        currentIndex += 1
    }

    mutating func movePrevious() {
        guard canGoPrevious else { return }
        currentIndex -= 1
    }
}

enum GatheringPrepBuilder {
    static func make(attendees: [Person]) -> GatheringPrepSession {
        let targets = attendees
            .filter { !$0.isSelf }
            .sorted(by: precedes)
            .map(GatheringPrepEntry.init(person:))
        return GatheringPrepSession(entries: targets)
    }

    static func make(gathering: Gathering) -> GatheringPrepSession {
        make(attendees: gathering.attendees)
    }

    private static func precedes(_ lhs: Person, _ rhs: Person) -> Bool {
        let leftKana = normalized(lhs.kana)
        let rightKana = normalized(rhs.kana)
        let kanaOrder = leftKana.localizedStandardCompare(rightKana)
        if kanaOrder != .orderedSame { return kanaOrder == .orderedAscending }

        let nameOrder = normalized(lhs.name).localizedStandardCompare(normalized(rhs.name))
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }

        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return String(describing: lhs.persistentModelID)
            < String(describing: rhs.persistentModelID)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct GatheringPrepView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(filter: #Predicate<Person> { $0.isSelf }) private var selfPeople: [Person]

    let gathering: Gathering
    @State private var session: GatheringPrepSession
    @State private var selectedPerson: Person?

    init(gathering: Gathering) {
        self.gathering = gathering
        _session = State(initialValue: GatheringPrepBuilder.make(gathering: gathering))
        _selectedPerson = State(initialValue: nil)
    }

    var body: some View {
        Group {
            if let person = session.currentPerson {
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 4) {
                            Text(gathering.title)
                                .font(.minchoTitle(18, relativeTo: .title3))
                                .foregroundStyle(AppTheme.ink)
                                .accessibilityIdentifier("gatheringPrep.root")
                            Text("\(session.progressText)人")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.ai)
                                .accessibilityIdentifier("gatheringPrep.progress")
                                .accessibilityValue(
                                    "全\(session.count)人中\(session.currentIndex + 1)人目"
                                )
                        }

                        personCard(person)

                        PersonMemorySummaryView(summary: summary(for: person))

                        Button {
                            selectedPerson = person
                        } label: {
                            Label("詳しく見る", systemImage: "person.text.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(AppTheme.ai)
                        .accessibilityIdentifier("gatheringPrep.showDetail")
                    }
                    .padding(16)
                    .padding(.bottom, 76)
                }
                .safeAreaInset(edge: .bottom) {
                    navigationControls
                }
            } else {
                ContentUnavailableView(
                    "予習する出席者がいません",
                    systemImage: "person.2.slash",
                    description: Text("自分以外の出席者を登録すると確認できます。")
                )
            }
        }
        .background(AppTheme.paper)
        .navigationTitle("集まりの前に確認")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedPerson) { person in
            GatheringPrepPersonDetailSheet(person: person)
        }
    }

    private func summary(for person: Person) -> PersonMemorySummary {
        PersonMemorySummaryBuilder.make(
            selfPerson: selfPeople.first,
            target: person,
            excludingGathering: gathering,
            latestGatheringBefore: gathering.date
        )
    }

    private func personCard(_ person: Person) -> some View {
        HairlineCard {
            VStack(spacing: 10) {
                Group {
                    if let image = PersonPhotoSupport.image(from: person.photoData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            Circle().fill(AppTheme.paperRaised)
                            Text(PersonPhotoSupport.initial(for: person.name))
                                .font(.minchoTitle(34, relativeTo: .largeTitle))
                                .foregroundStyle(AppTheme.ai)
                        }
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                .overlay(Circle().stroke(AppTheme.ai.opacity(0.35), lineWidth: 1.5))
                .accessibilityHidden(true)

                Text(person.name)
                    .font(.minchoAmount(21, relativeTo: .title2))
                    .foregroundStyle(AppTheme.ink)
                    .accessibilityIdentifier("gatheringPrep.personName")
                    .accessibilityLabel(person.name)
                    .accessibilityValue(
                        person.relationNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? ""
                            : "続柄、\(person.relationNote)"
                    )
                if !person.relationNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(person.relationNote)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.inkSoft)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
        }
    }

    private var navigationControls: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    previousButton
                    primaryNavigationButton
                }
            } else {
                HStack(spacing: 12) {
                    previousButton
                    primaryNavigationButton
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            if reduceTransparency {
                AppTheme.paperRaised
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
    }

    private var previousButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                session.movePrevious()
            }
        } label: {
            Label("前へ", systemImage: "chevron.left")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .disabled(!session.canGoPrevious)
        .accessibilityIdentifier("gatheringPrep.previous")
    }

    @ViewBuilder
    private var primaryNavigationButton: some View {
        if session.canGoNext {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    session.moveNext()
                }
            } label: {
                Label("次へ", systemImage: "chevron.right")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.ai)
            .accessibilityIdentifier("gatheringPrep.next")
        } else {
            Button {
                dismiss()
            } label: {
                Label("確認を終える", systemImage: "checkmark")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.done)
            .accessibilityIdentifier("gatheringPrep.finish")
        }
    }
}

private struct GatheringPrepPersonDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let person: Person

    var body: some View {
        NavigationStack {
            PersonDetailView(person: person)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { dismiss() }
                    }
                }
        }
    }
}
