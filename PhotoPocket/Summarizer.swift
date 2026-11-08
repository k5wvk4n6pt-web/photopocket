import Foundation
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence（端末内の文章AI）で要約する。対応iPhone・iOS 26以降のみ
enum Summarizer {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static func summarize(_ text: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: """
            あなたは、写真に写った書類・お知らせ・メモの内容を短くまとめるアシスタントです。
            日本語で、「・」で始まる箇条書き3〜5行にまとめてください。
            日付・時間・金額・締め切り・持ち物・連絡先など、大事な情報は必ず残してください。
            書かれていないことは付け足さないでください。
            """)
            let response = try await session.respond(to: "次の文章を要約してください。\n\n" + String(text.prefix(2000)))
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        throw NSError(domain: "PhotoPocket", code: 2, userInfo: [NSLocalizedDescriptionKey: "このiPhoneではAIの要約を使えません。"])
    }
}

/// 文字から大事な情報（日付・金額・電話番号など）を抜き出す
enum KeyInfo {
    struct Group: Identifiable {
        let symbol: String
        let label: String
        let items: [String]
        var id: String { label }
    }

    static func extract(from text: String) -> [Group] {
        func matches(_ pattern: String) -> [String] {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
            let ns = text as NSString
            let found = re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
                ns.substring(with: $0.range).trimmingCharacters(in: .whitespaces)
            }
            var seen = Set<String>()
            return found.filter { !$0.isEmpty && seen.insert($0).inserted }
        }
        func lines(_ pattern: String, limit: Int) -> [String] {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
            var seen = Set<String>()
            return text.components(separatedBy: "\n")
                .filter { re.firstMatch(in: $0, range: NSRange(location: 0, length: ($0 as NSString).length)) != nil }
                .map { String($0.prefix(50)).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && seen.insert($0).inserted }
                .prefix(limit).map { $0 }
        }

        let groups: [Group] = [
            Group(symbol: "exclamationmark.circle", label: "期限・大事な行",
                  items: lines("まで|締切|締め切り|〆切|期限|提出|持ち物|持参", limit: 5)),
            Group(symbol: "calendar", label: "日付",
                  items: matches("(?:令和|平成)?\\d{1,4}年\\s*\\d{1,2}月\\s*\\d{1,2}日(?:\\s*[（(][月火水木金土日](?:曜日?)?[)）])?|\\d{1,2}月\\s*\\d{1,2}日(?:\\s*[（(][月火水木金土日](?:曜日?)?[)）])?|\\b\\d{1,2}/\\d{1,2}(?:\\s*[（(][月火水木金土日][)）])?")),
            Group(symbol: "clock", label: "時間",
                  items: matches("(?:午前|午後)?\\s*\\d{1,2}[:：]\\d{2}(?:\\s*[〜~～-]\\s*\\d{1,2}[:：]\\d{2})?|(?:午前|午後)\\d{1,2}時(?:\\d{1,2}分)?")),
            Group(symbol: "yensign.circle", label: "金額",
                  items: matches("[¥￥]\\s?\\d{1,3}(?:[,，]\\d{3})+|[¥￥]\\s?\\d+|\\d{1,3}(?:[,，]\\d{3})+\\s?円|\\d+\\s?円")),
            Group(symbol: "phone", label: "電話番号",
                  items: matches("0\\d{1,4}[-－‐ー(（]\\d{1,4}[-－‐ー)）]\\d{3,4}|0[5789]0\\d{8}|\\b0\\d{9}\\b")),
            Group(symbol: "mappin.and.ellipse", label: "住所",
                  items: lines("(都|道|府|県).{1,8}(市|区|町|村)|[市区町村].{0,12}\\d+[-－‐丁]", limit: 3)),
            Group(symbol: "link", label: "URL", items: matches("https?://[^\\s　]+|www\\.[^\\s　]+")),
            Group(symbol: "envelope", label: "メール", items: matches("[\\w.+-]+@[\\w-]+\\.[\\w.]+")),
        ]
        return groups.filter { !$0.items.isEmpty }
    }
}

/// 要点の表示（タップでコピー）
struct KeyInfoCard: View {
    let text: String
    @State private var copied: String?

    var body: some View {
        let groups = KeyInfo.extract(from: text)
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("要点", systemImage: "sparkles")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Theme.accent)
                ForEach(groups) { g in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: g.symbol)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(g.label).font(.caption2).foregroundStyle(.secondary)
                            ForEach(g.items, id: \.self) { item in
                                Button {
                                    UIPasteboard.general.string = item
                                    copied = item
                                } label: {
                                    Text(item)
                                        .font(.footnote.weight(.bold))
                                        .multilineTextAlignment(.leading)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Text(copied.map { "コピーしました：\($0.prefix(20))" } ?? "タップでコピーできます")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(corner: 16)
        }
    }
}
