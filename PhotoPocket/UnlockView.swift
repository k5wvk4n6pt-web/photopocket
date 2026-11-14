import SwiftUI

/// フル版（買い切り）の案内・購入画面
struct UnlockView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

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
                             ? "ご購入ありがとうございます。すべての機能が使えます。"
                             : "無料版はフォルダ\(FreeLimit.folders)つ・写真\(FreeLimit.photos)枚までです。\n1回の購入で、ずっと使えます。月額ではありません。")
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
                            Button {
                                Task { await store.purchase() }
                            } label: {
                                HStack(spacing: 8) {
                                    if store.isPurchasing { ProgressView().tint(.white) }
                                    Text("\(store.priceText)で購入する（買い切り）")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(BigButtonStyle())
                            .disabled(store.isPurchasing)

                            Button("購入を復元") {
                                Task { await store.restore() }
                            }
                            .font(.callout.bold())
                            .disabled(store.isPurchasing)

                            Text("写真の本体はいつも写真アプリに残るので、無料版でもフル版でも、アプリを消して写真が消えることはありません。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
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
            .alert("お知らせ", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
                Button("OK") { store.message = nil }
            } message: {
                Text(store.message ?? "")
            }
        }
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
