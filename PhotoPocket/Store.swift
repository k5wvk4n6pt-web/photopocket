import Foundation
import StoreKit

/// フル版の課金（無制限・iCloud同期・Face IDロック・文字の読み取り）
/// ・年額プラン（自動更新サブスクリプション）
/// ・買い切り（非消耗型）
/// どちらか一方を持っていればフル版になる
@MainActor
final class Store: ObservableObject {
    /// ↓ App Store Connect で作る製品ID
    /// 買い切り（非消耗型）。以前の「iCloud同期」と同じ製品をそのまま使う（購入済みの人もフル版になる）
    static let lifetimeProductID = "com.k5wvk4n6pt.photopocket.icloud"
    /// 年額プラン（自動更新サブスクリプション）
    static let yearlyProductID = "com.k5wvk4n6pt.photopocket.pro.yearly"
    static var allProductIDs: [String] { [yearlyProductID, lifetimeProductID] }

    /// 利用規約（Appleの標準EULA）とプライバシーポリシー
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyURL = URL(string: "https://k5wvk4n6pt-web.github.io/photopocket/privacy.html")!

    /// 起動時にすぐ判定できるよう、フル版かどうかを端末にも覚えておく
    static let unlockedKey = "iCloudUnlocked"
    static var isUnlockedCached: Bool { UserDefaults.standard.bool(forKey: unlockedKey) }

    @Published private(set) var yearly: Product?
    @Published private(set) var lifetime: Product?
    @Published private(set) var isUnlocked: Bool = Store.isUnlockedCached
    /// いま有効なのが年額プランか（買い切りを持っていれば false）
    @Published private(set) var isSubscribed = false
    @Published private(set) var hasLifetime = false
    @Published private(set) var renewalDate: Date?
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
            await loadProducts()
            await refreshEntitlement()
        }
    }

    deinit { updatesTask?.cancel() }

    var yearlyPriceText: String { yearly?.displayPrice ?? "—" }
    var lifetimePriceText: String { lifetime?.displayPrice ?? "—" }

    func loadProducts() async {
        do {
            let products = try await Product.products(for: Self.allProductIDs)
            yearly = products.first { $0.id == Self.yearlyProductID }
            lifetime = products.first { $0.id == Self.lifetimeProductID }
        } catch {
            yearly = nil
            lifetime = nil
        }
    }

    /// フル版かどうかを App Store の記録で確認する
    /// （年額プランは、期限が切れたり解約されて期間が終わったりすると、ここに出てこなくなる）
    func refreshEntitlement() async {
        var lifetimeOwned = false
        var subscribed = false
        var renewal: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil else { continue }
            switch t.productID {
            case Self.lifetimeProductID:
                lifetimeOwned = true
            case Self.yearlyProductID:
                if let exp = t.expirationDate, exp < Date() { continue }
                subscribed = true
                renewal = t.expirationDate
            default:
                break
            }
        }
        hasLifetime = lifetimeOwned
        isSubscribed = subscribed && !lifetimeOwned
        renewalDate = renewal
        setUnlocked(lifetimeOwned || subscribed)
    }

    func purchaseYearly() async { await purchase(yearly, id: Self.yearlyProductID) }
    func purchaseLifetime() async { await purchase(lifetime, id: Self.lifetimeProductID) }

    private func purchase(_ product: Product?, id: String) async {
        var product = product
        if product == nil {
            await loadProducts()
            product = id == Self.yearlyProductID ? yearly : lifetime
        }
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
                    await refreshEntitlement()
                    message = "ありがとうございます！フル版のすべての機能が使えるようになりました。"
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
