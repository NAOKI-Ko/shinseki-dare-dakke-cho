import StoreKit
import StoreKitTest
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

private struct StoreKitStubError: LocalizedError {
    var errorDescription: String? { "StoreKit接続テストエラー" }
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

    func testMissingProductShowsActionableMessageInsteadOfIgnoringTap() async {
        let dateStore = MemoryFirstLaunchDateStore()
        dateStore.dates[TrialManager.firstLaunchDateKey] = Date()
            .addingTimeInterval(-8 * 24 * 60 * 60)
        let manager = TrialManager(
            firstLaunchDateStore: dateStore,
            entitlementChecker: { false },
            productLoader: { nil }
        )

        await manager.purchase()

        XCTAssertEqual(manager.status, .expired)
        XCTAssertEqual(manager.productAvailability, .unavailable)
        XCTAssertTrue(manager.message?.contains("購入商品を読み込めませんでした") == true)
        XCTAssertFalse(manager.isProcessing)
    }

    func testProductLoadFailureShowsRetryableMessage() async {
        let manager = TrialManager(
            firstLaunchDateStore: MemoryFirstLaunchDateStore(),
            entitlementChecker: { false },
            productLoader: { throw StoreKitStubError() }
        )

        let loaded = await manager.loadProduct(forceReload: true)

        XCTAssertFalse(loaded)
        XCTAssertEqual(manager.productAvailability, .unavailable)
        XCTAssertTrue(manager.message?.contains("再読み込みしてください") == true)
        XCTAssertTrue(manager.message?.contains("StoreKit接続テストエラー") == true)
    }

    func testPendingPurchaseExplainsThatApprovalIsRequired() async {
        let manager = TrialManager(
            firstLaunchDateStore: MemoryFirstLaunchDateStore(),
            entitlementChecker: { false },
            productLoader: { nil },
            purchasePerformer: { _ in .pending }
        )

        await manager.purchase()

        XCTAssertTrue(manager.message?.contains("承認待ち") == true)
        XCTAssertNotEqual(manager.status, .purchased)
    }

    func testCancelledPurchaseAcknowledgesCancellation() async {
        let manager = TrialManager(
            firstLaunchDateStore: MemoryFirstLaunchDateStore(),
            entitlementChecker: { false },
            productLoader: { nil },
            purchasePerformer: { _ in .userCancelled }
        )

        await manager.purchase()

        XCTAssertTrue(manager.message?.contains("キャンセルしました") == true)
        XCTAssertNotEqual(manager.status, .purchased)
    }

    func testPurchaseFailureShowsVisibleError() async {
        let manager = TrialManager(
            firstLaunchDateStore: MemoryFirstLaunchDateStore(),
            entitlementChecker: { false },
            productLoader: { nil },
            purchasePerformer: { _ in throw StoreKitStubError() }
        )

        await manager.purchase()

        XCTAssertTrue(manager.message?.contains("購入を開始できませんでした") == true)
        XCTAssertTrue(manager.message?.contains("StoreKit接続テストエラー") == true)
        XCTAssertFalse(manager.isProcessing)
    }

    func testStoreKitConfigurationLoadsYenProductAndCompletesPurchase() async throws {
        let configurationURL = try XCTUnwrap(
            Bundle(for: TrialManagerTests.self).url(
                forResource: "ShinsekiCho",
                withExtension: "storekit"
            )
        )
        let session = try SKTestSession(contentsOf: configurationURL)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.storefront = "JPN"
        session.locale = Locale(identifier: "ja_JP")
        defer {
            session.clearTransactions()
            session.resetToDefaultState()
        }

        let dateStore = MemoryFirstLaunchDateStore()
        dateStore.dates[TrialManager.firstLaunchDateKey] = Date()
            .addingTimeInterval(-8 * 24 * 60 * 60)
        let manager = TrialManager(
            firstLaunchDateStore: dateStore,
            entitlementChecker: { false }
        )

        let loaded = await manager.loadProduct(forceReload: true)
        guard loaded, let product = manager.product else {
            throw XCTSkip(
                "このxcodebuild環境ではSKTestSessionがStoreKitデーモンへ設定を渡せません。XcodeのRunまたは実機Sandboxで確認します。"
            )
        }

        XCTAssertEqual(product.id, TrialManager.productID)
        XCTAssertEqual(product.price, Decimal(600))
        XCTAssertTrue(product.displayPrice.contains("600"), product.displayPrice)
        XCTAssertTrue(
            product.displayPrice.contains("¥") || product.displayPrice.contains("￥"),
            product.displayPrice
        )

        await manager.purchase()

        XCTAssertEqual(manager.status, .purchased, manager.message ?? "")
        XCTAssertTrue(manager.message?.contains("購入が完了しました") == true)
    }

    func testStoreKitConfigurationMatchesProductIDPriceAndJapaneseStorefront() throws {
        let configurationURL = try XCTUnwrap(
            Bundle(for: TrialManagerTests.self).url(
                forResource: "ShinsekiCho",
                withExtension: "storekit"
            )
        )
        let data = try Data(contentsOf: configurationURL)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let products = try XCTUnwrap(root["products"] as? [[String: Any]])
        let product = try XCTUnwrap(products.first)
        let settings = try XCTUnwrap(root["settings"] as? [String: Any])

        XCTAssertEqual(products.count, 1)
        XCTAssertEqual(product["productID"] as? String, TrialManager.productID)
        XCTAssertEqual(product["displayPrice"] as? String, "600")
        XCTAssertEqual(product["type"] as? String, "NonConsumable")
        XCTAssertEqual(settings["_storefront"] as? String, "JPN")
        XCTAssertEqual(settings["_locale"] as? String, "ja_JP")
    }
}
