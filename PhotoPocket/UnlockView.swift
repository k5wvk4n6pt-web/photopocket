import SwiftUI

/// iCloud同期（買い切り）の案内・購入画面
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
                        Image(systemName: store.isUnlocked ? "checkmark.icloud.fill" : "icloud.fill")
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.top, 20)

                    VStack(spacing: 8) {
                        Text(store.isUnlocked ? "iCloud同期を使っています" : "iCloudで写真をまもる")
                            .font(.title2.bold())
                        Text(store.isUnlocked
                             ? "ご購入ありがとうございます。写真と分類・フォルダは自動でiCloudに保存されています。"
                             : "1回の購入で、ずっと使えます。\n月額ではありません。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)

                    VStack(alignment: .leading, spacing: 16) {
                        benefit("arrow.triangle.2.circlepath.icloud", "自動でiCloudに保存",
                                "取り込んだ写真・フォルダ・メモがiCloudに保存されます")
                        benefit("iphone.and.arrow.forward", "機種変更・入れ直しも安心",
                                "同じApple IDなら、新しいiPhoneでもそのまま戻ります")
                        benefit("ipad.and.iphone", "iPhoneとiPadで同じ内容",
                                "同じApple IDの端末どうしで自動で同期します")
                        benefit("trash.slash", "写真アプリから消しても安心",
                                "写真アプリを整理しても、写真はiCloudに残ります")
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

                            Text("iCloudの保存容量は、お使いのiCloudの空き容量を使います。無料版のまま使う場合、写真はこのiPhoneの中にだけ保存されます。")
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
