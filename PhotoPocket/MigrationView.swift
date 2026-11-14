import SwiftUI
import SwiftData

/// 以前のバージョンで取り込んだ写真を、写真アプリに戻して新しい形式に切り替える画面
struct MigrationView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var count = 0
    @State private var working = false
    @State private var done = 0
    @State private var total = 0
    @State private var resultText: String?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    ZStack {
                        Circle().fill(Theme.accent.opacity(0.12)).frame(width: 140, height: 140)
                        Image(systemName: resultText == nil ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 54, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.top, 20)

                    if let resultText {
                        Text("切り替えが終わりました").font(.title2.bold())
                        Text(resultText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button { dismiss() } label: {
                            Text("OK").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BigButtonStyle())
                    } else {
                        Text("写真を写真アプリに戻します").font(.title2.bold())
                        Text("フォトポケットは、写真を写真アプリに置いたままフォルダ分けする形に変わりました。アプリを削除しても写真が消えないので安心です。\n\n以前のバージョンで取り込んだ写真が\(count)枚あります。写真アプリから消していた写真は写真アプリに戻し、フォルダ分けとメモはそのまま残します。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)

                        if let errorText {
                            Text(errorText)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.red)
                        }

                        Button {
                            Task { await run() }
                        } label: {
                            HStack(spacing: 8) {
                                if working { ProgressView().tint(.white) }
                                Text(working ? "戻しています… \(done)/\(total)" : "写真アプリに戻す")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BigButtonStyle())
                        .disabled(working)

                        Text("写真へのアクセスで「フルアクセス」を選んでください。終わるまでアプリを閉じないでください。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                if resultText == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("あとで") { dismiss() }.disabled(working)
                    }
                }
            }
            .interactiveDismissDisabled(working)
            .task { count = PhotoAssets.legacyItems(in: context).count }
        }
    }

    private func run() async {
        working = true
        errorText = nil
        defer { working = false }
        do {
            let r = try await PhotoAssets.migrate(context: context) { d, t in
                done = d
                total = t
            }
            var lines: [String] = []
            if r.restored > 0 { lines.append("\(r.restored)枚を写真アプリに戻しました。") }
            if r.converted > 0 { lines.append("\(r.converted)枚は写真アプリに残っていたので、そのまま使います。") }
            if r.skipped > 0 {
                lines.append("\(r.skipped)枚は、このiPhoneに本体が無いため戻せませんでした（以前のアプリのまま見られます）。")
            }
            UserDefaults.standard.set(r.skipped, forKey: "migrationSkippedCount")
            resultText = lines.isEmpty ? "戻す写真はありませんでした。" : lines.joined(separator: "\n")
        } catch {
            errorText = error.localizedDescription
        }
    }
}
