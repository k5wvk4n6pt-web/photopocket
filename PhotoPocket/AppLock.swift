import SwiftUI
import LocalAuthentication

/// アプリを開くときの顔認証ロック
/// 顔認証（Face ID / Touch ID）がうまくいかないときは、iPhoneのパスコードで開ける
@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()

    private static let enabledKey = "appLockEnabled"

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }
    /// いまロック中か（ロックがオンのときだけ意味を持つ）
    @Published private(set) var isLocked: Bool
    @Published private(set) var isAuthenticating = false
    /// 裏に回ってロックしたので、次に開いたとき認証を出す
    private var pendingPrompt = false

    private init() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        isEnabled = enabled
        isLocked = enabled   // ロックがオンなら、起動時は必ずロック
    }

    /// 端末で使える認証の名前（画面の表示用）
    var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "パスコード"
        }
    }

    var methodSymbol: String {
        switch methodName {
        case "Face ID": return "faceid"
        case "Touch ID": return "touchid"
        case "Optic ID": return "opticid"
        default: return "lock.fill"
        }
    }

    /// iPhoneにパスコードが設定されていて、ロックが使えるか
    var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// アプリが裏に回ったらロックし直す
    func lockIfNeeded() {
        guard isEnabled else { return }
        isLocked = true
        pendingPrompt = true
    }

    /// 戻ってきたときに認証を出すべきか（1回だけ true を返す）
    func consumePendingPrompt() -> Bool {
        defer { pendingPrompt = false }
        return pendingPrompt && isEnabled && isLocked
    }

    /// 認証してロックを解除する。成功したら true
    @discardableResult
    func unlock(reason: String = "フォトポケットを開きます") async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        context.localizedCancelTitle = "キャンセル"
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if ok { isLocked = false }
            return ok
        } catch {
            return false
        }
    }

    /// 設定のスイッチから呼ぶ：オンにするときは、一度認証できることを確かめる
    func setEnabled(_ on: Bool) async -> String? {
        if on {
            guard isAvailable else {
                return "iPhoneにパスコードが設定されていないため、ロックを使えません。「設定」アプリの「Face IDとパスコード」でパスコードを設定してください。"
            }
            let ok = await unlock(reason: "アプリのロックをオンにします")
            guard ok else { return nil }   // キャンセル時はオフのまま
            isEnabled = true
            isLocked = false
        } else {
            // オフにするときも本人確認（他の人に勝手に外されないように）
            let ok = await unlock(reason: "アプリのロックをオフにします")
            guard ok else { return nil }
            isEnabled = false
            isLocked = false
        }
        return nil
    }
}

/// ロック中に表示する画面
struct LockScreenView: View {
    @ObservedObject var lock: AppLock

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.12)).frame(width: 150, height: 150)
                    Circle().fill(Theme.accent.opacity(0.18)).frame(width: 104, height: 104)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                VStack(spacing: 6) {
                    Text("フォトポケット").font(.title2.bold())
                    Text("ロックされています").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label("\(lock.methodName)で開く", systemImage: lock.methodSymbol)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BigButtonStyle())
                .disabled(lock.isAuthenticating)
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
    }
}

/// ロックがオンのとき、アプリ一覧（アプリの切り替え画面）で中身が見えないように隠す画面
struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("フォトポケット").font(.title3.bold())
            }
        }
    }
}
