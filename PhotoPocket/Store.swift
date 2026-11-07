import Foundation
import StoreKit

/// 買い切り課金（iCloud同期のアンロック）
@MainActor
final class Store: ObservableObject {
    /// ↓ App Store Connect で作る「非消耗型」App内課金の製品ID
    static let iCloudProductID = "com.example.photopocket.icloud"

    /// 起動時にすぐ判定できるよう、購入済みかどうかを端末にも覚えておく
    static let unlockedKey = "iCloudUnlocked"
    static var isUnlockedCached: Bool { UserDefaults.standard.bool(forKey: unlockedKey) }

    @Published private(set) var product: Product?
    @Published private(set) var isUnlocked: Bool = Store.isUnlockedCached
    @Published var isPurchasing = false
    @Published var message: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshEntitlement()
                }
            }
        }
        Task {
            await loadProduct()
            await refreshEntitlement()
        }
    }

    deinit { updatesTask?.cancel() }

    var priceText: String { product?.displayPrice ?? "—" }

    func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.iCloudProductID]).first
        } catch {
            product = nil
        }
    }

    /// 購入済みかどうかを App Store の記録で確認する
    func refreshEntitlement() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.iCloudProductID, t.revocationDate == nil {
                unlocked = true
            }
        }
        setUnlocked(unlocked)
    }

    func purchase() async {
        if product == nil { await loadProduct() }
        guard let product else {
            message = "App Storeに接続できませんでした。通信環境を確認して、もう一度お試しください。"
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let t) = verification {
                    await t.finish()
                    setUnlocked(true)
                    message = "ありがとうございます！iCloud同期が使えるようになりました。"
                } else {
                    message = "購入を確認できませんでした。"
                }
            case .pending:
                message = "購入の承認待ちです。承認されると自動で使えるようになります。"
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = "購入できませんでした：\(error.localizedDescription)"
        }
    }

    /// 機種変更時などの「購入を復元」
    func restore() async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
        } catch {
            // キャンセル等。下で現在の状態を確認する
        }
        await refreshEntitlement()
        message = isUnlocked ? "購入を復元しました。" : "復元できる購入が見つかりませんでした。"
    }

    private func setUnlocked(_ value: Bool) {
        isUnlocked = value
        UserDefaults.standard.set(value, forKey: Self.unlockedKey)
    }
}
