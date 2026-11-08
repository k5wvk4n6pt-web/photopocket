import SwiftUI
import SwiftData

/// すべての写真（月ごと）
struct AllPhotosView: View {
    @Environment(\.modelContext) private var context
    @Query private var photos: [PhotoItem]
    @State private var viewerItem: PhotoItem?
    @State private var query = ""
    @State private var ocrProgress: (done: Int, total: Int)?

    private var unreadCount: Int { photos.filter { !$0.textRecognized }.count }

    private var searchResults: [PhotoItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return photos
            .filter { ($0.recognizedText + "\n" + $0.memo).localizedCaseInsensitiveContains(q) }
            .sorted { $0.displayDate > $1.displayDate }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    struct MonthGroup: Identifiable {
        let title: String
        var items: [PhotoItem]
        var id: String { title }
    }

    private var groups: [MonthGroup] {
        let sorted = photos.sorted { $0.displayDate > $1.displayDate }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月"
        var result: [MonthGroup] = []
        for item in sorted {
            let key = f.string(from: item.displayDate)
            if result.last?.title == key {
                result[result.count - 1].items.append(item)
            } else {
                result.append(MonthGroup(title: key, items: [item]))
            }
        }
        return result
    }

    var body: some View {
        ScrollView {
            if photos.isEmpty {
                FriendlyEmptyView(symbol: "photo.on.rectangle", title: "写真はまだありません",
                                  message: "ホームから分類とフォルダを開いて、写真を取り込みましょう。") { EmptyView() }
            } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Text("「\(query)」が見つかった写真：\(searchResults.count)枚")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(searchResults) { item in
                        Button { viewerItem = item } label: {
                            HStack(spacing: 12) {
                                ThumbnailCell(item: item, selecting: false, isSelected: false)
                                    .frame(width: 64, height: 64)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.folder?.name ?? "")
                                        .font(.subheadline.weight(.heavy))
                                    Text(snippet(of: item))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .card(corner: 16)
                        }
                        .buttonStyle(.plain)
                    }
                    if searchResults.isEmpty {
                        Text("見つかりませんでした。文字を読み取っていない写真は検索に出ません。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
            } else {
                if unreadCount > 0 {
                    Button { Task { await readAll() } } label: {
                        Label("まだ文字を読み取っていない写真 \(unreadCount)枚をまとめて読み取る", systemImage: "text.viewfinder")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.brown.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(ocrProgress != nil)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                }
                LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
                    ForEach(groups) { group in
                        Section {
                            LazyVGrid(columns: columns, spacing: 6) {
                                ForEach(group.items) { item in
                                    ThumbnailCell(item: item, selecting: false, isSelected: false)
                                        .onTapGesture { viewerItem = item }
                                }
                            }
                        } header: {
                            Text(group.title)
                                .font(.subheadline.weight(.heavy))
                                .padding(.vertical, 6)
                                .padding(.horizontal, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.background)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("すべての写真")
        .searchable(text: $query, prompt: "写真の中の文字・メモで探す")
        .overlay {
            if let p = ocrProgress {
                ProgressOverlay(text: "文字を読み取っています… \(p.done)/\(p.total)")
            }
        }
        .photoViewerCover($viewerItem)
    }

    private func snippet(of item: PhotoItem) -> String {
        let q = query.trimmingCharacters(in: .whitespaces)
        for source in [item.recognizedText, item.memo] {
            if let r = source.range(of: q, options: .caseInsensitive) {
                let start = source.index(r.lowerBound, offsetBy: -12, limitedBy: source.startIndex) ?? source.startIndex
                let end = source.index(r.upperBound, offsetBy: 24, limitedBy: source.endIndex) ?? source.endIndex
                return (start > source.startIndex ? "…" : "") + source[start..<end].replacingOccurrences(of: "\n", with: " ") + "…"
            }
        }
        return ""
    }

    private func readAll() async {
        let list = photos.filter { !$0.textRecognized }
        ocrProgress = (0, list.count)
        for (i, item) in list.enumerated() {
            await TextRecognizer.run(on: item, context: context)
            ocrProgress = (i + 1, list.count)
        }
        ocrProgress = nil
    }
}

/// フォルダの一覧（分類ごと）
struct AllFoldersView: View {
    @Query(sort: [SortDescriptor(\PhotoCategory.sortOrder), SortDescriptor(\PhotoCategory.createdAt)])
    private var categories: [PhotoCategory]
    @Query(sort: [SortDescriptor(\PhotoFolder.sortOrder), SortDescriptor(\PhotoFolder.createdAt)])
    private var folders: [PhotoFolder]
    @State private var editingFolder: FolderEditTarget?

    var body: some View {
        List {
            if categories.isEmpty && folders.isEmpty {
                Text("まだフォルダがありません。ホームから作りましょう。")
                    .foregroundStyle(.secondary)
            }
            ForEach(categories) { c in
                Section {
                    if c.folderArray.isEmpty {
                        Button { editingFolder = .new(c) } label: {
                            Label("フォルダを追加", systemImage: "plus").foregroundStyle(Theme.accent)
                        }
                    }
                    ForEach(c.sortedFolders) { row($0) }
                } header: {
                    Label(c.name, systemImage: c.symbol)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(c.color)
                }
            }
            let none = folders.filter { $0.category == nil }
            if !none.isEmpty {
                Section("未分類") {
                    ForEach(none) { row($0) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("フォルダ")
        .sheet(item: $editingFolder) { FolderEditor(target: $0) }
    }

    private func row(_ folder: PhotoFolder) -> some View {
        NavigationLink(value: Route.folder(folder)) {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(folder.color)
                Text(folder.name)
                Spacer()
                Text("\(folder.photoArray.count)枚")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}

/// 最近取り込んだ写真
struct RecentPhotosView: View {
    @Query(sort: \PhotoItem.importedAt, order: .reverse) private var photos: [PhotoItem]
    @State private var viewerItem: PhotoItem?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        ScrollView {
            if photos.isEmpty {
                FriendlyEmptyView(symbol: "clock", title: "まだありません",
                                  message: "取り込んだ写真が、新しい順にここに並びます。") { EmptyView() }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("最近取り込んだ写真（新しい順）")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(photos.prefix(60)) { item in
                            ThumbnailCell(item: item, selecting: false, isSelected: false)
                                .onTapGesture { viewerItem = item }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("最近の写真")
        .photoViewerCover($viewerItem)
    }
}

extension View {
    /// 写真をタップしたら、その写真のフォルダの中で大きく表示する
    func photoViewerCover(_ item: Binding<PhotoItem?>) -> some View {
        fullScreenCover(item: item) { photo in
            if let folder = photo.folder {
                PhotoViewer(folder: folder, startID: photo.id)
            }
        }
    }
}
