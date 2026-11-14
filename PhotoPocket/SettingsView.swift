import SwiftUI
import SwiftData
import CloudKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("deletePolicy") private var deletePolicyRaw = DeletePolicy.ask.rawValue
    @AppStorage("appearance") private var appearanceRaw = AppearanceMode.light.rawValue
    @AppStorage("reviewAfterImport") private var reviewAfterImport = true
    @Query private var photos: [PhotoItem]
    @State private var iCloudText = "確認中…"
    @State private var iCloudOK = false
    @State private var showUnlock = false
    @EnvironmentObject private var store: Store
    @ObservedObject private var videoSync = VideoSync.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if store.isUnlocked {
                        HStack {
                            Image(systemName: iCloudOK ? "checkmark.icloud.fill" : "exclamationmark.icloud")
                                .foregroundStyle(iCloudOK ? Color.green : Color.orange)
                            Text(iCloudText)
                        }
                    } else {
                        HStack {
                            Image(systemName: "iphone").foregroundStyle(.secondary)
                            Text("このiPhoneの中だけに保存しています")
                        }
                        Button { showUnlock = true } label: {
                            HStack {
                                Label("iCloud同期を使う（買い切り）", systemImage: "icloud.fill")
                                Spacer()
                                Text(store.priceText).foregroundStyle(.secondary)
                            }
                        }
                        Button("購入を復元") { Task { await store.restore() } }
                    }
                } header: {
                    Text("iCloud")
                } footer: {
                    Text(store.isUnlocked
                         ? "写真と分類・フォルダは、あなたのiCloudに自動で保存されます。同じApple IDのiPhone・iPadで同じ内容が見られ、アプリを入れ直しても戻ります。iCloudの空き容量を使います。"
                         : "無料版では、写真はこのiPhoneの中に保存されます（iPhone全体のiCloudバックアップには含まれます）。アプリを削除すると写真も消えるので、削除前に「写真アプリに書き出す」を使ってください。")
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
                    Picker("取り込み後の写真アプリの写真", selection: $deletePolicyRaw) {
                        ForEach(DeletePolicy.allCases) { p in
                            Text(p.label).tag(p.rawValue)
                        }
                    }
                    Toggle("取り込んだあと写真を確認する", isOn: $reviewAfterImport)
                } header: {
                    Text("取り込み")
                } footer: {
                    Text("「いつも削除する」にしても、削除の前にiPhoneの確認画面が出ます。削除した写真は写真アプリの「最近削除した項目」に30日間残ります。\n写真アプリから削除するには、写真への「フルアクセス」の許可が必要です。\niCloud同期中は、取り込んだ直後はiCloudへの保存が終わっていないことがあります。電波の良い場所で少し待ってから削除すると安心です。")
                }

                if store.isUnlocked {
                    Section {
                        LabeledContent("今の回線", value: videoSync.onWiFi ? "Wi-Fi" : "Wi-Fi以外（アップロードは待機）")
                        LabeledContent("Wi-Fi待ちの動画",
                                       value: videoSync.isUploading ? "\(videoSync.waitingUploads)本（送信中）" : "\(videoSync.waitingUploads)本")
                    } header: {
                        Text("動画のiCloud保存")
                    } footer: {
                        Text("動画は容量が大きいので、Wi-Fiにつながっているときだけ、アプリを開いている間にiCloudへ送ります。送り終わるまでは、写真アプリの元の動画は消さないでおくと安心です。ほかのiPhone・iPadで見るときも、Wi-Fiで届きます。")
                    }
                }

                Section("保存状況") {
                    LabeledContent("写真の枚数", value: "\(photos.filter { !$0.isVideo }.count)枚")
                    LabeledContent("動画の本数", value: "\(photos.filter(\.isVideo).count)本")
                    LabeledContent("このiPhoneの写真アプリにも残っている", value: "\(photos.filter(\.isStillInLibrary).count)枚")
                    LabeledContent("写真・動画の容量", value: ByteCountFormatter.string(fromByteCount: Int64(photos.reduce(0) { $0 + $1.byteSize }), countStyle: .file))
                }

                Section {
                    Button("写真のアクセス設定を開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
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
