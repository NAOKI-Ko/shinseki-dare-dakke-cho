import Foundation
import Observation
import StoreKit
import SwiftUI

enum TrialStatus: Equatable {
    case trial(remainingDays: Int)
    case expired
    case purchased

    var allowsEditing: Bool {
        switch self {
        case .trial, .purchased: true
        case .expired: false
        }
    }

    var settingsText: String {
        switch self {
        case .trial(let remainingDays): "試用期間: あと\(remainingDays)日"
        case .expired: "試用期間は終了しました"
        case .purchased: "購入済み"
        }
    }
}

enum TrialAccessPolicy {
    static let trialLength: TimeInterval = 7 * 24 * 60 * 60

    static func status(
        firstLaunchDate: Date,
        now: Date,
        hasPurchasedEntitlement: Bool
    ) -> TrialStatus {
        if hasPurchasedEntitlement { return .purchased }

        let elapsed = max(0, now.timeIntervalSince(firstLaunchDate))
        guard elapsed < trialLength else { return .expired }
        let remaining = max(1, Int(ceil((trialLength - elapsed) / (24 * 60 * 60))))
        return .trial(remainingDays: remaining)
    }
}

enum TrialPurchaseError: LocalizedError {
    case productUnavailable
    case failedVerification

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            "購入商品を読み込めませんでした。通信状態を確認して、もう一度お試しください。"
        case .failedVerification:
            "購入情報を確認できませんでした。購入は確定していません。"
        }
    }
}

enum TrialPurchaseOutcome {
    case success
    case pending
    case userCancelled
}

@MainActor
@Observable
final class TrialManager {
    nonisolated static let productID = "com.naoki-ko.shinsekicho.fullaccess"
    static let firstLaunchDateKey = "firstLaunchDate"

    private(set) var status: TrialStatus
    private(set) var product: Product?
    private(set) var isProcessing = false
    var message: String?

    var canEdit: Bool { status.allowsEditing }
    var displayPrice: String { product?.displayPrice ?? "600円" }

    private let firstLaunchDate: Date
    private let now: () -> Date
    private let entitlementChecker: () async -> Bool
    private let productLoader: () async throws -> Product?
    private let purchasePerformer: ((Product?) async throws -> TrialPurchaseOutcome)?
    private let restorePerformer: () async throws -> Void
    private var updatesTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        firstLaunchDateStore: any FirstLaunchDateStoring = KeychainStore(),
        now: @escaping () -> Date = Date.init,
        entitlementChecker: (() async -> Bool)? = nil,
        productLoader: @escaping () async throws -> Product? = {
            try await Product.products(for: [TrialManager.productID]).first
        },
        purchasePerformer: ((Product?) async throws -> TrialPurchaseOutcome)? = nil,
        restorePerformer: @escaping () async throws -> Void = {
            try await AppStore.sync()
        }
    ) {
        self.now = now
        self.entitlementChecker = entitlementChecker ?? {
            await Self.hasVerifiedFullAccessEntitlement()
        }
        self.productLoader = productLoader
        self.purchasePerformer = purchasePerformer
        self.restorePerformer = restorePerformer

        let firstLaunchDate = Self.resolveFirstLaunchDate(
            store: firstLaunchDateStore,
            defaults: defaults,
            now: now
        )
        self.firstLaunchDate = firstLaunchDate
        status = TrialAccessPolicy.status(
            firstLaunchDate: firstLaunchDate,
            now: now(),
            hasPurchasedEntitlement: false
        )
    }

    func prepare() async {
        await refreshEntitlement()
        await loadProduct()
        startListeningForTransactions()
    }

    func refreshEntitlement() async {
        let hasPurchasedEntitlement = await entitlementChecker()
        status = TrialAccessPolicy.status(
            firstLaunchDate: firstLaunchDate,
            now: now(),
            hasPurchasedEntitlement: hasPurchasedEntitlement
        )
    }

    func purchase() async {
        guard !isProcessing else { return }
        isProcessing = true
        message = nil
        defer { isProcessing = false }

        do {
            let outcome: TrialPurchaseOutcome
            if let purchasePerformer {
                outcome = try await purchasePerformer(product)
            } else {
                if product == nil { await loadProduct() }
                guard let product else { throw TrialPurchaseError.productUnavailable }
                switch try await product.purchase() {
                case .success(let verificationResult):
                    let transaction = try Self.verified(verificationResult)
                    guard transaction.productID == Self.productID,
                          transaction.revocationDate == nil else {
                        throw TrialPurchaseError.failedVerification
                    }
                    await transaction.finish()
                    outcome = .success
                case .pending:
                    outcome = .pending
                case .userCancelled:
                    outcome = .userCancelled
                @unknown default:
                    outcome = .userCancelled
                }
            }

            switch outcome {
            case .success:
                status = .purchased
                message = "購入が完了しました。すべての機能を利用できます。"
            case .pending:
                message = "購入は承認待ちです。承認後に自動で利用可能になります。"
            case .userCancelled:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func restorePurchases() async {
        guard !isProcessing else { return }
        isProcessing = true
        message = nil
        defer { isProcessing = false }

        do {
            try await restorePerformer()
            await refreshEntitlement()
            message = status == .purchased
                ? "購入を復元しました。"
                : "復元できる購入履歴が見つかりませんでした。"
        } catch {
            message = error.localizedDescription
        }
    }

    private func loadProduct() async {
        do {
            product = try await productLoader()
        } catch {
            message = error.localizedDescription
        }
    }

    private func startListeningForTransactions() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                guard case .verified(let transaction) = result,
                      transaction.productID == Self.productID else { continue }
                await transaction.finish()
                await self.refreshEntitlement()
            }
        }
    }

    private static func resolveFirstLaunchDate(
        store: any FirstLaunchDateStoring,
        defaults: UserDefaults,
        now: () -> Date
    ) -> Date {
        do {
            if let savedDate = try store.date(forKey: firstLaunchDateKey) {
                // Keychainが正なら、移行前のUserDefaults値は不要。
                defaults.removeObject(forKey: firstLaunchDateKey)
                return savedDate
            }

            if let legacyDate = defaults.object(forKey: firstLaunchDateKey) as? Date {
                try store.set(legacyDate, forKey: firstLaunchDateKey)
                defaults.removeObject(forKey: firstLaunchDateKey)
                return legacyDate
            }

            let createdDate = now()
            try store.set(createdDate, forKey: firstLaunchDateKey)
            return createdDate
        } catch {
            // Keychainが一時的に利用できない場合だけ旧方式へ退避し、
            // 次回起動時に同じ移行処理を再試行する。
            let fallbackDate = defaults.object(forKey: firstLaunchDateKey) as? Date ?? now()
            defaults.set(fallbackDate, forKey: firstLaunchDateKey)
            return fallbackDate
        }
    }

    nonisolated private static func verified<T>(
        _ result: VerificationResult<T>
    ) throws -> T {
        switch result {
        case .verified(let value): value
        case .unverified: throw TrialPurchaseError.failedVerification
        }
    }

    nonisolated private static func hasVerifiedFullAccessEntitlement() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == productID,
               transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }
}

struct PurchaseSheet: View {
    @Environment(TrialManager.self) private var trialManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(AppTheme.ai)

                VStack(spacing: 8) {
                    Text("親戚だれだっけ帳を引き続き使う")
                        .font(.minchoAmount(22, relativeTo: .title2))
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.center)
                    Text("試用期間の終了後も、登録済みの記録はいつでも閲覧できます。購入すると、人物・関係・集まりの追加と編集が再び使えるようになります。")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.inkSoft)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task {
                        await trialManager.purchase()
                        if trialManager.status == .purchased { dismiss() }
                    }
                } label: {
                    Text("今すぐ購入（\(trialManager.displayPrice)）して全機能を使う")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.ai)
                .disabled(trialManager.isProcessing)
                .accessibilityIdentifier("purchase.buyButton")

                Button("購入を復元") {
                    Task { await trialManager.restorePurchases() }
                }
                .disabled(trialManager.isProcessing)
                .accessibilityIdentifier("purchase.restoreButton")

                if trialManager.isProcessing {
                    ProgressView("Appleに確認しています…")
                        .tint(AppTheme.ai)
                }

                if let message = trialManager.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(
                            trialManager.status == .purchased ? AppTheme.done : AppTheme.inkSoft
                        )
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("purchase.message")
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .background(AppTheme.paper)
            .navigationTitle("フルアクセス")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("purchase.sheet")
    }
}
