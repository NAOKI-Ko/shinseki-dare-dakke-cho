import XCTest
import SwiftData
@testable import ShinsekiCho

@MainActor
final class OnboardingTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Person.self,
            Gathering.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    func testFirstLaunchWithoutSelfPresentsOnboarding() {
        let progress = OnboardingProgress(
            hasStarted: false,
            hasCompleted: false,
            isReplayRequested: false
        )

        XCTAssertTrue(progress.shouldPresent(hasRegisteredSelf: false))
        XCTAssertFalse(progress.shouldPresent(hasRegisteredSelf: true))
    }

    func testCompletedOnboardingDoesNotPresentAgain() {
        let progress = OnboardingProgress(
            hasStarted: true,
            hasCompleted: true,
            isReplayRequested: false
        )

        XCTAssertFalse(progress.shouldPresent(hasRegisteredSelf: false))
        XCTAssertFalse(progress.shouldPresent(hasRegisteredSelf: true))
    }

    func testSettingsReplayPresentsEvenAfterCompletion() {
        var progress = OnboardingProgress(
            hasStarted: true,
            hasCompleted: true,
            isReplayRequested: false
        )

        progress.requestReplay()

        XCTAssertTrue(progress.shouldPresent(hasRegisteredSelf: true))
    }

    func testSkipCompletesFirstExperienceWithoutReappearing() {
        var progress = OnboardingProgress(
            hasStarted: false,
            hasCompleted: false,
            isReplayRequested: false
        )

        progress.start()
        progress.finishOrSkip()

        XCTAssertTrue(progress.hasCompleted)
        XCTAssertFalse(progress.isReplayRequested)
        XCTAssertFalse(progress.shouldPresent(hasRegisteredSelf: false))
    }

    func testRegistrationCreatesSelfAndSelectedFamilyThroughRelationshipManager() throws {
        let container = try makeContainer()
        let context = container.mainContext
        var draft = OnboardingDraft()
        draft.selfName = "山田 太郎"
        draft.father = OnboardingRelativeDraft(isSelected: true, name: "山田 一郎")
        draft.mother = OnboardingRelativeDraft(isSelected: true, name: "山田 花子")
        draft.spouse = OnboardingRelativeDraft(isSelected: true, name: "佐藤 美咲")
        draft.sibling = OnboardingRelativeDraft(isSelected: true, name: "山田 次郎")
        draft.paternalGrandfather = OnboardingRelativeDraft(
            isSelected: true,
            name: "山田 源治"
        )

        let selfPerson = try OnboardingRegistrationService.register(
            draft: draft,
            existingSelf: nil,
            in: context
        )

        XCTAssertTrue(selfPerson.isSelf)
        XCTAssertEqual(Set(selfPerson.parents.map(\.name)), Set(["山田 一郎", "山田 花子"]))
        XCTAssertEqual(selfPerson.spouse?.name, "佐藤 美咲")
        let sibling = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Person>()).first { $0.name == "山田 次郎" }
        )
        XCTAssertEqual(Set(sibling.parents.map(\.name)), Set(["山田 一郎", "山田 花子"]))
        let father = try XCTUnwrap(selfPerson.parents.first { $0.name == "山田 一郎" })
        XCTAssertEqual(father.parents.map(\.name), ["山田 源治"])
    }
}
