import XCTest
@testable import ShinsekiCho

private final class MemoryFirstLaunchDateStore: FirstLaunchDateStoring {
    var dates: [String: Date] = [:]

    func date(forKey key: String) throws -> Date? {
        dates[key]
    }

    func set(_ date: Date, forKey key: String) throws {
        dates[key] = date
    }

    func removeValue(forKey key: String) throws {
        dates[key] = nil
    }
}

@MainActor
final class TrialManagerTests: XCTestCase {
    func testLessThanSevenDaysIsTrial() {
        let firstLaunch = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(
            TrialAccessPolicy.status(
                firstLaunchDate: firstLaunch,
                now: firstLaunch.addingTimeInterval(6 * 24 * 60 * 60),
                hasPurchasedEntitlement: false
            ),
            .trial(remainingDays: 1)
        )
    }

    func testSevenDaysOrMoreIsExpired() {
        let firstLaunch = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(
            TrialAccessPolicy.status(
                firstLaunchDate: firstLaunch,
                now: firstLaunch.addingTimeInterval(7 * 24 * 60 * 60),
                hasPurchasedEntitlement: false
            ),
            .expired
        )
    }

    func testPurchasedEntitlementAlwaysWinsOverElapsedDays() {
        let firstLaunch = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(
            TrialAccessPolicy.status(
                firstLaunchDate: firstLaunch,
                now: firstLaunch.addingTimeInterval(365 * 24 * 60 * 60),
                hasPurchasedEntitlement: true
            ),
            .purchased
        )
    }

    func testManagerRecordsFirstLaunchAndRefreshesInjectedEntitlement() async {
        let suiteName = "TrialManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = MemoryFirstLaunchDateStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let manager = TrialManager(
            defaults: defaults,
            firstLaunchDateStore: store,
            now: { now },
            entitlementChecker: { true }
        )
        XCTAssertEqual(
            store.dates[TrialManager.firstLaunchDateKey],
            now
        )
        XCTAssertNil(defaults.object(forKey: TrialManager.firstLaunchDateKey))
        await manager.refreshEntitlement()
        XCTAssertEqual(manager.status, .purchased)
    }

    func testLegacyUserDefaultsDateMigratesToKeychainAndIsRemoved() {
        let suiteName = "TrialManagerMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = MemoryFirstLaunchDateStore()
        let firstLaunch = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(firstLaunch, forKey: TrialManager.firstLaunchDateKey)

        let manager = TrialManager(
            defaults: defaults,
            firstLaunchDateStore: store,
            now: { firstLaunch.addingTimeInterval(3 * 24 * 60 * 60) },
            entitlementChecker: { false }
        )

        XCTAssertEqual(store.dates[TrialManager.firstLaunchDateKey], firstLaunch)
        XCTAssertNil(defaults.object(forKey: TrialManager.firstLaunchDateKey))
        XCTAssertEqual(manager.status, .trial(remainingDays: 4))
    }

    func testExistingKeychainDateWinsAndRemovesStaleUserDefaultsDate() {
        let suiteName = "TrialManagerKeychainPriorityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = MemoryFirstLaunchDateStore()
        let keychainDate = Date(timeIntervalSince1970: 1_700_000_000)
        let staleDefaultsDate = keychainDate.addingTimeInterval(5 * 24 * 60 * 60)
        store.dates[TrialManager.firstLaunchDateKey] = keychainDate
        defaults.set(staleDefaultsDate, forKey: TrialManager.firstLaunchDateKey)

        let manager = TrialManager(
            defaults: defaults,
            firstLaunchDateStore: store,
            now: { keychainDate.addingTimeInterval(8 * 24 * 60 * 60) },
            entitlementChecker: { false }
        )

        XCTAssertEqual(manager.status, .expired)
        XCTAssertEqual(store.dates[TrialManager.firstLaunchDateKey], keychainDate)
        XCTAssertNil(defaults.object(forKey: TrialManager.firstLaunchDateKey))
    }

    func testKeychainStoreWritesReadsAndDeletesDate() throws {
        let key = "firstLaunchDate.\(UUID().uuidString)"
        let store = KeychainStore(service: "TrialManagerTests.\(UUID().uuidString)")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        defer { try? store.removeValue(forKey: key) }

        XCTAssertNil(try store.date(forKey: key))
        try store.set(date, forKey: key)
        XCTAssertEqual(try store.date(forKey: key), date)
        try store.removeValue(forKey: key)
        XCTAssertNil(try store.date(forKey: key))
    }

    func testPurchaseUnlocksAndFreshManagerCanRestoreEntitlement() async throws {
        let suiteName = "TrialManagerStoreKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let dateStore = MemoryFirstLaunchDateStore()
        dateStore.dates[TrialManager.firstLaunchDateKey] = Date()
            .addingTimeInterval(-8 * 24 * 60 * 60)

        final class StoreState {
            var hasEntitlement = false
            var didSync = false
        }
        let store = StoreState()

        let manager = TrialManager(
            defaults: defaults,
            firstLaunchDateStore: dateStore,
            entitlementChecker: { store.hasEntitlement },
            productLoader: { nil },
            purchasePerformer: { _ in
                store.hasEntitlement = true
                return .success
            },
            restorePerformer: { store.didSync = true }
        )
        await manager.prepare()
        XCTAssertEqual(manager.status, .expired)

        await manager.purchase()
        XCTAssertEqual(manager.status, .purchased, manager.message ?? "")

        // 新しいManagerを別端末相当のローカル状態に見立て、Apple側の
        // currentEntitlementsが購入済みを返したときの復元を確認する。
        let restoredManager = TrialManager(
            defaults: defaults,
            firstLaunchDateStore: dateStore,
            entitlementChecker: { store.hasEntitlement },
            productLoader: { nil },
            restorePerformer: { store.didSync = true }
        )
        await restoredManager.restorePurchases()
        XCTAssertTrue(store.didSync)
        XCTAssertEqual(restoredManager.status, .purchased, restoredManager.message ?? "")
    }
}
