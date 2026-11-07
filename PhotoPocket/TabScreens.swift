import SwiftUI
import SwiftData

/// すべての写真（月ごと）
struct AllPhotosView: View {
    @Query private var photos: [PhotoItem]
    @State private var viewerItem: PhotoItem?

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
            } else {
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
        .photoViewerCover($viewerItem)
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
