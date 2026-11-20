import Foundation
import SwiftData

/// アプリを入れ直したときなどに、同期前に作った分類・フォルダと
/// 同期で戻ってきた分類・フォルダが二重になったら、1つにまとめる
enum Dedupe {
    @MainActor
    static func run(in context: ModelContext) {
        guard let categories = try? context.fetch(FetchDescriptor<PhotoCategory>()) else { return }
        var changed = false

        // 同じ名前・同じアイコンの分類は、古い方にまとめる
        let groups = Dictionary(grouping: categories) { "\($0.name)\u{1F}\($0.symbol)" }
        for (_, group) in groups where group.count > 1 {
            let sorted = group.sorted { $0.createdAt < $1.createdAt }
            let keep = sorted[0]
            for dup in sorted.dropFirst() {
                for folder in dup.folderArray { folder.category = keep }
                context.delete(dup)
                changed = true
            }
        }

        // 同じ分類の中で同じ名前のフォルダは、古い方にまとめる
        guard let folders = try? context.fetch(FetchDescriptor<PhotoFolder>()) else { return }
        let folderGroups = Dictionary(grouping: folders.filter { $0.category != nil && !$0.isDeleted }) {
            "\($0.category!.id.uuidString)\u{1F}\($0.name)"
        }
        for (_, group) in folderGroups where group.count > 1 {
            let sorted = group.sorted { $0.createdAt < $1.createdAt }
            let keep = sorted[0]
            var existing = Set(keep.photoArray.compactMap(\.sourceAssetID))
            for dup in sorted.dropFirst() {
                for item in dup.photoArray {
                    // 同じ写真がすでに入っていれば、二重にしない
                    if let id = item.sourceAssetID, existing.contains(id) {
                        context.delete(item)
                    } else {
                        item.folder = keep
                        if let id = item.sourceAssetID { existing.insert(id) }
                    }
                }
                context.delete(dup)
                changed = true
            }
        }

        if changed { try? context.save() }
    }
}
