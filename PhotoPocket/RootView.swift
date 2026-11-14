import SwiftUI
import SwiftData

enum CategoryEditTarget: Identifiable {
    case new
    case edit(PhotoCategory)
    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let c): return "edit-\(c.id.uuidString)"
        }
    }
}

enum FolderEditTarget: Identifiable {
    case new(PhotoCategory?)
    case edit(PhotoFolder)
    var id: String {
        switch self {
        case .new(let c): return "new-\(c?.id.uuidString ?? "none")"
        case .edit(let f): return "edit-\(f.id.uuidString)"
        }
    }
}

/// 画面の移動先
enum Route: Hashable {
    case category(PhotoCategory)
    case folder(PhotoFolder)
}

extension View {
    /// どのタブからでも「分類」「フォルダ」に進めるようにする
    func photoPocketDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .category(let c): CategoryView(category: c)
            case .folder(let f): FolderView(folder: f)
            }
        }
    }
}

// MARK: - タブ

enum AppTab: String, CaseIterable, Identifiable {
    case home, all, folders, recent
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "ホーム"
        case .all: return "すべての写真"
        case .folders: return "フォルダ"
        case .recent: return "最近の写真"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .all: return "photo.on.rectangle"
        case .folders: return "folder"
        case .recent: return "clock"
        }
    }
}

struct RootView: View {
    @State private var tab: AppTab = .home
    @State private var homePath = NavigationPath()
    @State private var allPath = NavigationPath()
    @State private var foldersPath = NavigationPath()
    @State private var recentPath = NavigationPath()

    private var isAtTop: Bool {
        switch tab {
        case .home: return homePath.isEmpty
        case .all: return allPath.isEmpty
        case .folders: return foldersPath.isEmpty
        case .recent: return recentPath.isEmpty
        }
    }

    var body: some View {
        Group {
            switch tab {
            case .home:
                NavigationStack(path: $homePath) { HomeView().photoPocketDestinations() }
            case .all:
                NavigationStack(path: $allPath) { AllPhotosView().photoPocketDestinations() }
            case .folders:
                NavigationStack(path: $foldersPath) { AllFoldersView().photoPocketDestinations() }
            case .recent:
                NavigationStack(path: $recentPath) { RecentPhotosView().photoPocketDestinations() }
            }
        }
        .foregroundStyle(Theme.ink)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // 分類やフォルダの中に入ったら、タブバーは隠して広く使う
            if isAtTop {
                FloatingTabBar(tab: $tab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isAtTop)
    }
}

/// 画面下の丸いタブバー
struct FloatingTabBar: View {
    @Binding var tab: AppTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { t in
                Button {
                    tab = t
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.symbol)
                            .font(.system(size: 21, weight: .semibold))
                            .frame(height: 24)
                        Text(t.title)
                            .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(tab == t ? Theme.accent : Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(tab == t ? Theme.accentSoft : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == t ? .isSelected : [])
            }
        }
        .padding(7)
        .background(Theme.card, in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 14, x: 0, y: 6)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

// MARK: - ホーム（最初は分類だけを表示）

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var store: Store
    @Query(sort: [SortDescriptor(\PhotoCategory.sortOrder), SortDescriptor(\PhotoCategory.createdAt)])
    private var categories: [PhotoCategory]
    @Query(sort: [SortDescriptor(\PhotoFolder.sortOrder), SortDescriptor(\PhotoFolder.createdAt)])
    private var allFolders: [PhotoFolder]
    @Query private var allPhotos: [PhotoItem]

    @State private var editingCategory: CategoryEditTarget?
    @State private var editingFolder: FolderEditTarget?
    @State private var showSettings = false
    @State private var showUnlock = false
    @State private var categoryToDelete: PhotoCategory?
    @State private var folderToDelete: PhotoFolder?
    @State private var showSorter = false
    @State private var showReorder = false
    @State private var showMigration = false

    private var uncategorized: [PhotoFolder] { allFolders.filter { $0.category == nil } }
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HomeHeader(
                    showStats: !(categories.isEmpty && allFolders.isEmpty),
                    photoCount: allPhotos.count,
                    folderCount: allFolders.count,
                    iCloudOn: store.isUnlocked,
                    onSettings: { showSettings = true },
                    onICloud: { if store.isUnlocked { showSettings = true } else { showUnlock = true } }
                )

                if categories.isEmpty && allFolders.isEmpty {
                    welcomeView
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        sorterCard
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("分類").font(.title3.weight(.heavy))
                            Text("\(categories.count)こ").font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            if !categories.isEmpty {
                                Button { showReorder = true } label: {
                                    Label("編集・並び替え", systemImage: "arrow.up.arrow.down")
                                        .font(.subheadline.weight(.heavy))
                                        .foregroundStyle(Theme.ink)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(Theme.card, in: Capsule())
                                        .overlay(Capsule().stroke(Color.brown.opacity(0.2)))
                                }
                                .buttonStyle(.plain)
                            }
                            Button { editingCategory = .new } label: {
                                Label("追加", systemImage: "plus")
                                    .font(.subheadline.weight(.heavy))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Theme.accent, in: Capsule())
                                    .shadow(color: Theme.accent.opacity(0.3), radius: 6, x: 0, y: 3)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("分類を追加")
                        }
                        .padding(.top, 14)

                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(categories) { category in
                                NavigationLink(value: Route.category(category)) {
                                    CategoryCard(category: category)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { editingFolder = .new(category) } label: { Label("フォルダを追加", systemImage: "folder.badge.plus") }
                                    Button { editingCategory = .edit(category) } label: { Label("分類を編集", systemImage: "pencil") }
                                    Button(role: .destructive) { categoryToDelete = category } label: { Label("分類を削除", systemImage: "trash") }
                                }
                            }
                            Button { editingCategory = .new } label: {
                                AddCard(title: "分類を追加", minHeight: 176)
                            }
                            .buttonStyle(.plain)
                        }

                        if !uncategorized.isEmpty {
                            Text("未分類のフォルダ")
                                .font(.title3.weight(.heavy))
                                .padding(.top, 14)
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(uncategorized) { folder in
                                    NavigationLink(value: Route.folder(folder)) {
                                        FolderCard(folder: folder)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button { editingFolder = .edit(folder) } label: { Label("フォルダを編集", systemImage: "pencil") }
                                        Button(role: .destructive) { folderToDelete = folder } label: { Label("フォルダを削除", systemImage: "trash") }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .padding(.bottom, 30)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editingCategory) { CategoryEditor(target: $0) }
        .sheet(item: $editingFolder) { FolderEditor(target: $0) }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store) }
        .sheet(isPresented: $showUnlock) { UnlockView().environmentObject(store) }
        .deleteCategoryDialog($categoryToDelete)
        .deleteFolderDialog($folderToDelete)
        .fullScreenCover(isPresented: $showSorter) { SwipeSortView() }
        .sheet(isPresented: $showReorder) { CategoryReorderSheet() }
        .sheet(isPresented: $showMigration) { MigrationView() }
        .task {
            // 以前のバージョンで取り込んだ写真（アプリ内にコピーがある）があれば、写真アプリに戻す案内を出す
            // （戻せなかった写真だけが残っている場合は、毎回は出さない）
            let legacy = PhotoAssets.legacyItems(in: context).count
            if legacy > 0 && legacy != UserDefaults.standard.integer(forKey: "migrationSkippedCount") {
                showMigration = true
            }
        }
    }

    /// iPhoneの写真をスワイプで仕分ける入口
    private var sorterCard: some View {
        Button { showSorter = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.green.opacity(0.25))
                        .frame(width: 34, height: 40)
                        .rotationEffect(.degrees(12))
                        .offset(x: 8)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.red.opacity(0.22))
                        .frame(width: 34, height: 40)
                        .rotationEffect(.degrees(-12))
                        .offset(x: -8)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.accent)
                        .frame(width: 34, height: 40)
                        .overlay(Image(systemName: "hand.draw.fill").foregroundStyle(.white))
                }
                .frame(width: 56, height: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text("iPhoneの写真を仕分ける").font(.headline.weight(.heavy))
                    Text("左で削除・右でフォルダへ。スワイプでどんどん整理")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.subheadline.bold())
            }
            .padding(14)
            .card(corner: 20)
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    private var welcomeView: some View {
        FriendlyEmptyView(
            symbol: "photo.on.rectangle.angled",
            title: "ようこそ！",
            message: "写真を「分類」と「フォルダ」に分けて、すっきりしまっておけるアプリです。\nまずは入れ物を作りましょう。"
        ) {
            Button { createStarterSet() } label: {
                Label("おすすめのセットで始める", systemImage: "sparkles")
            }
            .buttonStyle(BigButtonStyle())
            Button("自分で分類を作る") { editingCategory = .new }
                .font(.callout.bold())
                .foregroundStyle(Theme.accent)
                .padding(.top, 4)
        }
        .padding(.top, 10)
    }

    /// はじめての人向けの分類とフォルダのセット
    private func createStarterSet() {
        // 無料版はフォルダ3つまでなので、3つだけのセット
        let freeStarter: [(String, String, String, [(String, String)])] = [
            ("家族", "house.fill", "pink", [("日々のこと", "orange")]),
            ("学校", "graduationcap.fill", "blue", [("おたより・書類", "blue")]),
            ("趣味", "heart.fill", "purple", [("お気に入り", "pink")]),
        ]
        let fullStarter: [(String, String, String, [(String, String)])] = [
            ("家族", "house.fill", "pink", [("日々のこと", "orange"), ("記念日", "pink")]),
            ("学校", "graduationcap.fill", "blue", [("行事", "yellow"), ("おたより・書類", "blue")]),
            ("仕事", "briefcase.fill", "indigo", [("資料", "indigo"), ("メモ", "gray")]),
            ("友達", "person.2.fill", "orange", [("あそび", "purple"), ("ごはん", "red")]),
            ("趣味", "heart.fill", "purple", [("お気に入り", "pink"), ("作品", "green")]),
            ("自然", "leaf.fill", "green", [("風景", "mint"), ("花・植物", "green")]),
        ]
        let starter = store.isUnlocked ? fullStarter : freeStarter
        for (i, entry) in starter.enumerated() {
            let category = PhotoCategory(name: entry.0, symbol: entry.1, colorName: entry.2, sortOrder: i)
            context.insert(category)
            for (j, folder) in entry.3.enumerated() {
                context.insert(PhotoFolder(name: folder.0, category: category, colorName: folder.1, sortOrder: j))
            }
        }
        try? context.save()
    }
}

// MARK: - 分類の中（フォルダ一覧）

struct CategoryView: View {
    let category: PhotoCategory
    @Environment(\.dismiss) private var dismiss
    @State private var editingFolder: FolderEditTarget?
    @State private var editingCategory: CategoryEditTarget?
    @State private var folderToDelete: PhotoFolder?
    @State private var categoryToDelete: PhotoCategory?
    @State private var showFolderReorder = false

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(category.color.opacity(0.16))
                        .frame(width: 56, height: 56)
                        .overlay {
                            Image(systemName: category.symbol)
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(category.color)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.name).font(.title.weight(.heavy))
                        Text("フォルダ\(category.folderArray.count)つ・\(category.allPhotos.count)枚")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(category.sortedFolders) { folder in
                        NavigationLink(value: Route.folder(folder)) {
                            FolderCard(folder: folder)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { editingFolder = .edit(folder) } label: { Label("フォルダを編集", systemImage: "pencil") }
                            Button(role: .destructive) { folderToDelete = folder } label: { Label("フォルダを削除", systemImage: "trash") }
                        }
                    }
                    Button { editingFolder = .new(category) } label: {
                        AddCard(title: "フォルダを追加", minHeight: 186)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { editingFolder = .new(category) } label: { Label("フォルダを追加", systemImage: "folder.badge.plus") }
                    Button { showFolderReorder = true } label: { Label("フォルダの編集・並び替え", systemImage: "arrow.up.arrow.down") }
                        .disabled(category.folderArray.count < 1)
                    Button { editingCategory = .edit(category) } label: { Label("分類を編集", systemImage: "pencil") }
                    Button(role: .destructive) { categoryToDelete = category } label: { Label("分類を削除", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $editingFolder) { FolderEditor(target: $0) }
        .sheet(item: $editingCategory) { CategoryEditor(target: $0) }
        .deleteFolderDialog($folderToDelete)
        .deleteCategoryDialog($categoryToDelete) { dismiss() }
        .sheet(isPresented: $showFolderReorder) { FolderReorderSheet(category: category) }
    }
}

// MARK: - 削除の確認（共通）

private struct DeleteFolderDialog: ViewModifier {
    @Binding var folder: PhotoFolder?
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "フォルダ「\(folder?.name ?? "")」を削除しますか？",
            isPresented: Binding(get: { folder != nil }, set: { if !$0 { folder = nil } }),
            titleVisibility: .visible
        ) {
            Button("フォルダを削除", role: .destructive) {
                if let f = folder {
                    for photo in f.photoArray { ThumbnailCache.shared.remove(photo.id.uuidString) }
                    context.delete(f)
                    try? context.save()
                }
            }
        } message: {
            Text("中の写真\(folder?.photoArray.count ?? 0)枚はフォルダから外れますが、写真アプリの写真はそのまま残ります。")
        }
    }
}

private struct DeleteCategoryDialog: ViewModifier {
    @Binding var category: PhotoCategory?
    var onDeleted: () -> Void
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "分類「\(category?.name ?? "")」を削除しますか？",
            isPresented: Binding(get: { category != nil }, set: { if !$0 { category = nil } }),
            titleVisibility: .visible
        ) {
            Button("分類を削除", role: .destructive) {
                if let c = category {
                    context.delete(c)
                    try? context.save()
                    onDeleted()
                }
            }
        } message: {
            Text("中のフォルダと写真は消えずに「未分類」に移ります。")
        }
    }
}

extension View {
    func deleteFolderDialog(_ folder: Binding<PhotoFolder?>) -> some View {
        modifier(DeleteFolderDialog(folder: folder))
    }
    func deleteCategoryDialog(_ category: Binding<PhotoCategory?>, onDeleted: @escaping () -> Void = {}) -> some View {
        modifier(DeleteCategoryDialog(category: category, onDeleted: onDeleted))
    }
}

// MARK: - カード

/// 分類のカード（ホーム）
struct CategoryCard: View {
    let category: PhotoCategory

    var body: some View {
        let photos = category.allPhotos
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(category.color.opacity(0.16))
                    .frame(width: 58, height: 58)
                    .overlay {
                        Image(systemName: category.symbol)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(category.color)
                    }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.headline.weight(.heavy))
                    .lineLimit(1)
                Text("フォルダ\(category.folderArray.count)つ・\(photos.count)枚")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: -8) {
                if photos.isEmpty {
                    RoundedRectangle(cornerRadius: 8).fill(category.color.opacity(0.14)).frame(width: 28, height: 28)
                } else {
                    ForEach(photos.prefix(4)) { photo in
                        MiniThumb(item: photo)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .contentShape(RoundedRectangle(cornerRadius: Theme.corner))
    }
}

struct MiniThumb: View {
    let item: PhotoItem
    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.accentSoft)
            .frame(width: 28, height: 28)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.card, lineWidth: 2))
            .task(id: item.id) {
                let id = item.id, data = item.thumbData
                image = await Task.detached { PhotoStorage.thumbnail(id: id, data: data) }.value
            }
    }
}

/// フォルダのカード（フォルダの絵の中に最新の写真）
struct FolderCard: View {
    let folder: PhotoFolder
    @State private var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FolderIllustration(color: folder.color, image: image)
                .padding(.horizontal, 4)
                .padding(.top, 4)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(.headline.weight(.heavy))
                        .lineLimit(1)
                    Text(folder.photoArray.isEmpty ? "まだ空っぽ" : "\(folder.photoArray.count)枚")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.subheadline.bold())
            }
            .padding(.horizontal, 6)
        }
        .padding(10)
        .card()
        .contentShape(RoundedRectangle(cornerRadius: Theme.corner))
        .task(id: folder.sortedPhotos.first?.id) {
            guard let first = folder.sortedPhotos.first else { image = nil; return }
            let id = first.id, data = first.thumbData
            image = await Task.detached { PhotoStorage.thumbnail(id: id, data: data) }.value
        }
    }
}

/// フォルダの絵
struct FolderIllustration: View {
    let color: Color
    let image: UIImage?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                // うしろのタブ
                UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12, style: .continuous)
                    .fill(color)
                    .brightness(-0.06)
                    .frame(width: w * 0.44, height: h * 0.26)
                // うしろの面
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(color)
                    .brightness(-0.04)
                    .frame(width: w, height: h * 0.9)
                    .offset(y: h * 0.1)
                // 写真
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white)
                    Group {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            LinearGradient(colors: [Theme.skyTop, Theme.skyBottom], startPoint: .top, endPoint: .bottom)
                                .overlay {
                                    Image(systemName: "photo")
                                        .font(.system(size: 22))
                                        .foregroundStyle(Color.blue.opacity(0.35))
                                }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(5)
                }
                .frame(width: w * 0.56, height: h * 0.64)
                .rotationEffect(.degrees(-6))
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                .offset(x: w * 0.24, y: h * 0.18)
                // 手前の面（写真の下半分が中に入っているように見せる）
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(color.opacity(0.92))
                    .frame(width: w, height: h * 0.38)
                    .offset(y: h * 0.62)
            }
        }
        .aspectRatio(1.45, contentMode: .fit)
    }
}

/// 点線の「追加」カード
struct AddCard: View {
    let title: String
    var minHeight: CGFloat = 160

    var body: some View {
        VStack(spacing: 10) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 46, height: 46)
                .overlay(Image(systemName: "plus").font(.title3.bold()).foregroundStyle(.white))
            Text(title).font(.subheadline.weight(.heavy))
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(Color.brown.opacity(0.45), style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.corner))
    }
}

// MARK: - ホームの上の部分（案D：大きなタイトル＋数字カード）

struct HomeHeader: View {
    var showStats: Bool
    var photoCount: Int
    var folderCount: Int
    var iCloudOn: Bool
    var onSettings: () -> Void
    var onICloud: () -> Void

    @AppStorage("appearance") private var appearanceRaw = AppearanceMode.light.rawValue
    private var mode: AppearanceMode { AppearanceMode(rawValue: appearanceRaw) ?? .light }

    private var dateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Spacer()
                Menu {
                    Picker("画面のモード", selection: $appearanceRaw) {
                        ForEach(AppearanceMode.allCases) { m in
                            Label(m.label, systemImage: m.symbol).tag(m.rawValue)
                        }
                    }
                } label: {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("画面のモード：\(mode.label)")
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("設定")
            }
            .foregroundStyle(Theme.ink)

            Text("\(dateText) ・ \(Theme.greeting)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
            Text("フォトポケット")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .accessibilityAddTraits(.isHeader)

            if showStats {
                HStack(spacing: 10) {
                    StatTile(symbol: "photo", color: Color(red: 0.91, green: 0.34, blue: 0.49),
                             value: "\(photoCount)", label: "写真")
                    StatTile(symbol: "folder", color: Color(red: 0.85, green: 0.54, blue: 0.12),
                             value: "\(folderCount)", label: "フォルダ")
                    Button(action: onICloud) {
                        StatTile(symbol: iCloudOn ? "checkmark.seal" : "sparkles",
                                 color: Color(red: 0.18, green: 0.50, blue: 0.85),
                                 value: iCloudOn ? "フル版" : "無料版", label: "プラン")
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(iCloudOn ? "設定を開きます" : "フル版の案内を開きます")
                }
                .padding(.top, 16)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

/// 数字のカード（写真・フォルダ・プラン）
struct StatTile: View {
    let symbol: String
    let color: Color
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.14))
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(color)
                }
            Text(value)
                .font(.title3.weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 2)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 3)
        .accessibilityElement(children: .combine)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}
