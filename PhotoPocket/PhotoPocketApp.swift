import SwiftUI
import SwiftData

@main
struct PhotoPocketApp: App {
    @StateObject private var store = Store()
    @StateObject private var appLock = AppLock.shared
    @State private var container: ModelContainer = PhotoPocketApp.makeContainer(iCloud: Store.isUnlockedCached)
    @State private var containerIsCloud: Bool = Store.isUnlockedCached
    @AppStorage("appearance") private var appearanceRaw = AppearanceMode.light.rawValue
    @Environment(\.scenePhase) private var scenePhase
    private let syncTimer = Timer.publish(every: 90, on: .main, in: .common).autoconnect()

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(containerIsCloud)   // 保存先を切り替えたら画面を作り直す
                // アプリのロック（フル版の機能）とアプリ一覧での目隠しは、別の窓（ウインドウ）で一番上に出す
                // （写真を大きく見る画面などの全画面表示よりも上に出すため）
                .onChange(of: lockOverlayKey) { _, _ in updateLockOverlay() }
                .tint(Theme.accent)
                .fontDesign(.rounded)
                .preferredColorScheme((AppearanceMode(rawValue: appearanceRaw) ?? .light).colorScheme)
                .environmentObject(store)
                .onChange(of: store.isUnlocked) { _, unlocked in
                    // 購入（または返金）に合わせて、iCloud同期のオン・オフを切り替える
                    guard unlocked != containerIsCloud else { return }
                    container = PhotoPocketApp.makeContainer(iCloud: unlocked)
                    containerIsCloud = unlocked
                    VideoSync.shared.configure(container: container, cloud: unlocked)
                }
                .task {
                    updateLockOverlay()
                    VideoSync.shared.configure(container: container, cloud: containerIsCloud)
                    // 起動したときにロック中なら、すぐ認証を出す
                    if store.isUnlocked && appLock.isEnabled && appLock.isLocked { await appLock.unlock() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { VideoSync.shared.kick() }
                    if phase == .background { appLock.lockIfNeeded() }
                    // 裏から戻ってきたときにロック中なら、すぐ認証を出す
                    // （認証画面を閉じただけのときは出さない＝キャンセルしても繰り返さない）
                    if phase == .active && appLock.consumePendingPrompt() && store.isUnlocked {
                        Task { await appLock.unlock() }
                    }
                }
                .onReceive(syncTimer) { _ in
                    if scenePhase == .active { VideoSync.shared.kick() }
                }
        }
        .modelContainer(container)
    }

    /// ロック画面・目隠しを出すかどうかが変わったら更新するための目印
    private var lockOverlayKey: String {
        "\(store.isUnlocked)-\(appLock.isEnabled)-\(appLock.isLocked)-\(appLock.isAuthenticating)-\(scenePhase)-\(appearanceRaw)"
    }

    private func updateLockOverlay() {
        let active = store.isUnlocked && appLock.isEnabled
        LockOverlayWindow.shared.update(
            showLock: active && appLock.isLocked,
            // ロックがオンのときは、アプリ一覧（切り替え画面）でも中身を隠す（Face IDの確認中は隠さない）
            showCover: active && scenePhase != .active && !appLock.isAuthenticating,
            lock: appLock,
            appearance: AppearanceMode(rawValue: appearanceRaw) ?? .light
        )
    }

    /// 無料版：端末内のみ／購入後：iCloud（CloudKit）と同期
    /// どちらも同じ保存ファイルを使うので、購入前に整理した写真もそのままiCloudへ送られる
    static func makeContainer(iCloud: Bool) -> ModelContainer {
        let schema = Schema([PhotoCategory.self, PhotoFolder.self, PhotoItem.self])
        if iCloud {
            do {
                let config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
                return try ModelContainer(for: schema, configurations: config)
            } catch {
                print("iCloud同期を開始できませんでした: \(error)")
            }
        }
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        return try! ModelContainer(for: schema, configurations: config)
    }
}
