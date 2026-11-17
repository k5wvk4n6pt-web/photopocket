import SwiftUI
import CloudKit
import CoreData

/// iCloud同期がうまく動いているかを確かめるための情報（テスト版の設定画面にだけ出す）
@MainActor
final class SyncDiagnostics: ObservableObject {
    static let shared = SyncDiagnostics()

    struct Event: Identifiable {
        let id = UUID()
        let kind: String
        let time: Date
        let ok: Bool
        let error: String?
    }

    @Published var account = "確認中…"
    @Published var containerMode = "-"
    @Published var containerError: String?
    @Published var events: [Event] = []

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event, event.endDate != nil else { return }
            let kind: String
            switch event.type {
            case .setup: kind = "準備"
            case .import: kind = "受信"
            case .export: kind = "送信"
            @unknown default: kind = "その他"
            }
            let e = Event(kind: kind, time: event.endDate ?? Date(), ok: event.succeeded,
                          error: event.error.map { SyncDiagnostics.describe($0) })
            Task { @MainActor in
                SyncDiagnostics.shared.events.insert(e, at: 0)
                if SyncDiagnostics.shared.events.count > 8 { SyncDiagnostics.shared.events.removeLast() }
            }
        }
    }

    /// 「一部が失敗」のときは、中の個別のエラーも見えるようにする
    nonisolated static func describe(_ error: Error) -> String {
        guard let ck = error as? CKError else { return "\(error)" }
        var text = "CKError \(ck.code.rawValue)"
        if let partial = ck.partialErrorsByItemID {
            let samples = Set(partial.values.map { e -> String in
                let c = e as? CKError
                let server = (e as NSError).userInfo["ServerErrorDescription"] as? String
                return "[\(c?.code.rawValue ?? -1)] \(server ?? e.localizedDescription)"
            })
            text += "（\(partial.count)件）\n" + samples.prefix(3).joined(separator: "\n")
        }
        return text
    }

    func refresh() async {
        do {
            let status = try await CKContainer(identifier: "iCloud.com.k5wvk4n6pt.photopocket").accountStatus()
            switch status {
            case .available: account = "サインイン済み（使える）"
            case .noAccount: account = "iCloudにサインインしていない"
            case .restricted: account = "制限されている"
            case .couldNotDetermine: account = "確認できない"
            case .temporarilyUnavailable: account = "一時的に使えない"
            @unknown default: account = "不明"
            }
        } catch {
            account = "エラー: \(error.localizedDescription)"
        }
    }
}

struct SyncDiagnosticsSection: View {
    @ObservedObject private var diag = SyncDiagnostics.shared

    var body: some View {
        Section {
            LabeledContent("iCloudアカウント", value: diag.account)
            LabeledContent("保存先", value: diag.containerMode)
            if let err = diag.containerError {
                Text("開始エラー: \(err)").font(.caption).foregroundStyle(.red)
            }
            if diag.events.isEmpty {
                Text("同期の記録はまだありません").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(diag.events) { e in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(e.ok ? "✅" : "❌") \(e.kind)  \(e.time.formatted(date: .omitted, time: .standard))")
                        .font(.caption.bold())
                    if let err = e.error {
                        Text(err).font(.caption2).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
            }
        } header: {
            Text("同期の状態（テスト版のみ）")
        }
        .task { await diag.refresh() }
    }
}
