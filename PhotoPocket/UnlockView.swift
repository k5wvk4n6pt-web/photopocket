import SwiftUI
import StoreKit

/// フル版（年額プラン・買い切り）の案内・購入画面
struct UnlockView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showManage = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    ZStack {
                        Circle().fill(Theme.accent.opacity(0.12)).frame(width: 150, height: 150)
                        Circle().fill(Theme.accent.opacity(0.18)).frame(width: 104, height: 104)
                        Image(systemName: store.isUnlocked ? "checkmark.seal.fill" : "sparkles")
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.top, 20)

                    VStack(spacing: 8) {
                        Text(store.isUnlocked ? "フル版を使っています" : "フル版で、もっと自由に")
                            .font(.title2.bold())
                        Text(store.isUnlocked
                             ? statusText
                             : "無料版はフォルダ\(FreeLimit.folders)つ・写真\(FreeLimit.photos)枚までです。\n年額プランか買い切りで、すべての機能が使えます。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)

                    VStack(alignment: .leading, spacing: 16) {
                        benefit("infinity", "フォルダも写真も無制限",
                                "好きなだけフォルダを作って、何枚でも仕分けできます")
                        benefit("iphone.and.arrow.forward", "機種変更しても安心",
                                "新しいiPhoneやアプリの入れ直しでも、フォルダ分けとメモが戻ります")
                        benefit("faceid", "Face IDでロック",
                                "アプリを開くときにFace IDが必要に。アプリ一覧でも中身が見えません")
                        benefit("text.viewfinder", "文字の読み取り・AIのまとめ",
                                "写真の中の文字を読み取って検索できます。書類はAIが短くまとめます")
                    }
                    .padding(18)
                    .card()
                    .padding(.horizontal, 18)

                    if !store.isUnlocked {
                        VStack(spacing: 12) {
                            planButton(
                                title: "年額プラン",
                                price: "\(store.yearlyPriceText) / 年",
                                note: "1年ごとに自動更新・いつでも解約できます",
                                highlighted: true
                            ) { await store.purchaseYearly() }

                            planButton(
                                title: "買い切り",
                                price: store.lifetimePriceText,
                                note: "1回の購入でずっと使えます",
                                highlighted: false
                            ) { await store.purchaseLifetime() }

                            Button("購入を復元") {
                                Task { await store.restore() }
                            }
                            .font(.callout.bold())
                            .disabled(store.isPurchasing)
                            .padding(.top, 4)

                            Text("年額プランは、期間が終わる24時間前までに解約しない限り、同じ料金で自動更新されます。お支払いはApple IDに請求されます。解約はiPhoneの「設定」→ 自分の名前 →「サブスクリプション」からいつでもできます。\n写真の本体はいつも写真アプリに残るので、解約してもアプリを消しても、写真が消えることはありません。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)

                            legalLinks
                        }
                        .padding(.horizontal, 24)
                    } else if store.isSubscribed {
                        VStack(spacing: 12) {
                            Button("サブスクリプションを管理") { showManage = true }
                                .font(.callout.bold())
                            if let lifetime = store.lifetime {
                                Button {
                                    Task { await store.purchaseLifetime() }
                                } label: {
                                    Text("買い切り（\(lifetime.displayPrice)）に切り替える")
                                        .font(.callout)
                                }
                                .disabled(store.isPurchasing)
                                Text("買い切りを購入したら、年額プランは「サブスクリプションを管理」から解約してください（自動では止まりません）。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            legalLinks
                        }
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 30)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.isUnlocked ? "閉じる" : "あとで") { dismiss() }
                }
            }
            .manageSubscriptionsSheet(isPresented: $showManage)
            .alert("お知らせ", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
                Button("OK") { store.message = nil }
            } message: {
                Text(store.message ?? "")
            }
        }
    }

    private var statusText: String {
        if store.hasLifetime { return "ご購入ありがとうございます。買い切りで、すべての機能がずっと使えます。" }
        if store.isSubscribed {
            if let date = store.renewalDate {
                let f = DateFormatter()
                f.locale = Locale(identifier: "ja_JP")
                f.dateFormat = "yyyy年M月d日"
                return "年額プランを使っています。次の更新日は\(f.string(from: date))です。"
            }
            return "年額プランを使っています。"
        }
        return "すべての機能が使えます。"
    }

    private var legalLinks: some View {
        HStack(spacing: 16) {
            Button("利用規約") { openURL(Store.termsURL) }
            Button("プライバシーポリシー") { openURL(Store.privacyURL) }
        }
        .font(.caption.bold())
    }

    private func planButton(title: String, price: String, note: String, highlighted: Bool,
                            action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(note).font(.caption).opacity(0.85)
                }
                Spacer(minLength: 8)
                if store.isPurchasing {
                    ProgressView().tint(highlighted ? .white : Theme.accent)
                } else {
                    Text(price).font(.headline)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .foregroundStyle(highlighted ? Color.white : Theme.accent)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(highlighted ? Theme.accent : Theme.accent.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .disabled(store.isPurchasing)
    }

    private func benefit(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(symbol: symbol, color: Theme.accent, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
