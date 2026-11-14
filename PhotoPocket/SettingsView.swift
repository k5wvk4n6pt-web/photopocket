import SwiftUI
import SwiftData
import CloudKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearanceRaw = AppearanceMode.light.rawValue
    @AppStorage("reviewAfterImport") private var reviewAfterImport = true
    @Query private var photos: [PhotoItem]
    @Query private var folders: [PhotoFolder]
    @State private var iCloudText = "確認中…"
    @State private var iCloudOK = false
    @State private var showUnlock = false
    @EnvironmentObject private var store: Store
    @ObservedObject private var videoSync = VideoSync.shared
    @ObservedObject private var appLock = AppLock.shared
    @State private var lockMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if store.isUnlocked {
                        Label("フル版を使っています", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Theme.accent)
                        HStack {
                            Image(systemName: iCloudOK ? "checkmark.icloud.fill" : "exclamationmark.icloud")
                                .foregroundStyle(iCloudOK ? Color.green : Color.orange)
                            Text(iCloudText)
                        }
                    } else {
                        LabeledContent("フォルダ", value: "\(folders.count) / \(FreeLimit.folders)つ")
                        LabeledContent("フォルダの写真", value: "\(photos.count) / \(FreeLimit.photos)枚")
                        Button { showUnlock = true } label: {
                            HStack {
                                Label("フル版にする（買い切り）", systemImage: "sparkles")
                                Spacer()
                                Text(store.priceText).foregroundStyle(.secondary)
                            }
                        }
                        Button("購入を復元") { Task { await store.restore() } }
                    }
                } header: {
                    Text(store.isUnlocked ? "フル版" : "無料版")
                } footer: {
                    Text(store.isUnlocked
                         ? "フォルダ分けとメモは、あなたのiCloudに自動で保存されます。同じApple IDのiPhone・iPadで同じ内容が見られ、アプリを入れ直しても戻ります。"
                         : "無料版では、フォルダ\(FreeLimit.folders)つ・写真\(FreeLimit.photos)枚まで仕分けできます。フル版では、枚数・フォルダが無制限になり、iCloud同期・Face IDロック・文字の読み取りとAIのまとめが使えます。")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { appLock.isEnabled && store.isUnlocked },
                        set: { on in
                            // Face IDロックはフル版の機能
                            guard store.isUnlocked else { showUnlock = true; return }
                            Task { lockMessage = await appLock.setEnabled(on) }
                        }
                    )) {
                        Label("\(appLock.methodName)でロック", systemImage: appLock.methodSymbol)
                    }
                    .disabled(appLock.isAuthenticating)
                } header: {
                    Text("アプリのロック")
                } footer: {
                    Text(store.isUnlocked
                         ? "オンにすると、アプリを開くたびに\(appLock.methodName)が必要になります。うまくいかないときはiPhoneのパスコードで開けます。"
                         : "フル版で使えます。")
                }

                Section("画面のモード") {
                    Picker("画面のモード", selection: $appearanceRaw) {
                        ForEach(AppearanceMode.allCases) { m in
                            Text(m.label).tag(m.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("フォルダに入れたあと写真を確認する", isOn: $reviewAfterImport)
                } header: {
                    Text("フォルダに入れる")
                } footer: {
                    Text("写真の本体は写真アプリに残したまま、フォルダに並べます。アプリを削除しても写真は消えません。\n写真アプリから削除するときは、iPhoneの確認画面が出ます。削除した写真は写真アプリの「最近削除した項目」に30日間残ります。")
                }

                if videoSync.waitingUploads > 0 {
                    Section {
                        LabeledContent("今の回線", value: videoSync.onWiFi ? "Wi-Fi" : "Wi-Fi以外（アップロードは待機）")
                        LabeledContent("Wi-Fi待ちの動画",
                                       value: videoSync.isUploading ? "\(videoSync.waitingUploads)本（送信中）" : "\(videoSync.waitingUploads)本")
                    } header: {
                        Text("以前のバージョンの動画")
                    }
                }

                Section("保存状況") {
                    LabeledContent("写真の枚数", value: "\(photos.filter { !$0.isVideo }.count)枚")
                    LabeledContent("動画の本数", value: "\(photos.filter(\.isVideo).count)本")
                }

                Section {
                    Button("写真のアクセス設定を開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } footer: {
                    Text("写真へのアクセスは「フルアクセス」がおすすめです。一部の写真だけを許可していると、フォルダの写真が表示できないことがあります。")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
            .task(id: store.isUnlocked) { if store.isUnlocked { await checkICloud() } }
            .sheet(isPresented: $showUnlock) { UnlockView().environmentObject(store) }
            .alert("アプリのロック", isPresented: Binding(get: { lockMessage != nil }, set: { if !$0 { lockMessage = nil } })) {
                Button("OK") { lockMessage = nil }
            } message: {
                Text(lockMessage ?? "")
            }
            .alert("お知らせ", isPresented: Binding(get: { store.message != nil && !showUnlock }, set: { if !$0 { store.message = nil } })) {
                Button("OK") { store.message = nil }
            } message: {
                Text(store.message ?? "")
            }
        }
    }

    private func checkICloud() async {
        do {
            let status = try await CKContainer.default().accountStatus()
            switch status {
            case .available:
                iCloudOK = true
                iCloudText = "iCloudに同期しています"
            case .noAccount:
                iCloudText = "iCloudにサインインしていません。「設定」アプリでサインインすると同期されます（それまではこのiPhoneにだけ保存）"
            case .restricted:
                iCloudText = "iCloudが制限されています（このiPhoneにだけ保存）"
            case .temporarilyUnavailable:
                iCloudText = "iCloudに一時的に接続できません。あとで自動で同期されます"
            default:
                iCloudText = "iCloudの状態を確認できません"
            }
        } catch {
            iCloudText = "iCloudの状態を確認できません"
        }
    }
}
