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
                // 下の小花
                HStack {
                    LittleFlower(color: Decor.peach, size: 20)
                    LittleFlower(color: Decor.pink.opacity(0.7), size: 14).offset(y: 8)
                    Spacer()
                    LittleFlower(color: Decor.pink.opacity(0.7), size: 14).offset(y: 8)
                    LittleFlower(color: Decor.peach, size: 20)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 20)
            }
        }
        .background(HomeBackdrop())
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

    /// iPhoneの写真をスワイプで仕分ける入口（スマホのイラスト＋ひょっこりくま）
    private var sorterCard: some View {
        Button { showSorter = true } label: {
            HStack(spacing: 10) {
                SorterPhoneIllustration()
                    .scaleEffect(0.7)
                    .frame(width: 74, height: 86)
                    .padding(.leading, -4)
                VStack(alignment: .leading, spacing: 4) {
                    Text("iPhoneの写真を仕分ける")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("左で削除・右でフォルダへ。スワイプでどんどん整理")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.headline.bold())
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: Decor.sorterGradient.map { $0.opacity(0.95) },
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .overlay(alignment: .bottomTrailing) {
                CornerCloud(color: .white).scaleEffect(1.6).offset(x: 10, y: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Decor.glassStroke, lineWidth: 1.5))
            .shadow(color: Decor.pink.opacity(0.15), radius: 12, x: 0, y: 6)
            .overlay(alignment: .topTrailing) {
                PeekingBear()
                    .scaleEffect(0.52)
                    .frame(width: 58, height: 50)
                    .offset(x: -22, y: -26)
                    .allowsHitTesting(false)
            }
            .colorScheme(.light)
        }
        .buttonStyle(.plain)
        .padding(.top, 20)
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
                            if let art = CategoryArt.asset(for: category.symbol) {
                                Image(art).resizable().scaledToFit().padding(8)
                            } else {
                                Image(systemName: category.symbol)
                                    .font(.system(size: 26, weight: .semibold))
                                    .foregroundStyle(category.color)
                            }
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
        .background(
            LinearGradient(colors: [category.color.opacity(0.16), Theme.background],
                           startPoint: .top, endPoint: .center)
                .background(Theme.background)
                .ignoresSafeArea()
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { editingFolder = .new(category) } label: { Label("フォルダを追加", systemImage: "folder.badge.plus") }
                    Menu {
                        ForEach(category.sortedFolders) { f in
                            Button { editingFolder = .edit(f) } label: { Label(f.name, systemImage: "folder") }
                        }
                    } label: { Label("フォルダを編集", systemImage: "pencil") }
                    .disabled(category.folderArray.isEmpty)
                    Button { showFolderReorder = true } label: { Label("フォルダを並び替え", systemImage: "arrow.up.arrow.down") }
                        .disabled(category.folderArray.count < 2)
                    Menu {
                        ForEach(category.sortedFolders) { f in
                            Button(role: .destructive) { folderToDelete = f } label: { Label(f.name, systemImage: "folder") }
                        }
                    } label: { Label("フォルダを削除", systemImage: "trash") }
                    .disabled(category.folderArray.isEmpty)
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
    @Query private var allFolders: [PhotoFolder]
    @State private var moveSource: PhotoFolder?
    @State private var showDone: String?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "フォルダ「\(folder?.name ?? "")」を削除しますか？",
            isPresented: Binding(get: { folder != nil }, set: { if !$0 { folder = nil } }),
            titleVisibility: .visible
        ) {
            if let f = folder {
                if f.photoArray.isEmpty {
                    Button("フォルダを削除", role: .destructive) { delete(f) }
                } else {
                    if allFolders.contains(where: { $0.id != f.id }) {
                        Button("写真を別のフォルダに移してから削除") { moveSource = f }
                    }
                    Button("フォルダだけ削除", role: .destructive) { delete(f) }
                }
            }
        } message: {
            if let f = folder, !f.photoArray.isEmpty {
                let legacy = f.photoArray.filter { $0.isLegacyCopy && !$0.isStillInLibrary }.count
                Text("中に写真が\(f.photoArray.count)枚あります。写真アプリの写真は消えません。フォルダ分けを残したいときは「別のフォルダに移してから削除」を選んでください。"
                     + (legacy > 0 ? "\n※以前の版で取り込み、写真アプリから消した写真が\(legacy)枚あります。この写真は「フォルダだけ削除」を選ぶと見られなくなります。" : ""))
            } else {
                Text("このフォルダは空です。")
            }
        }
        .sheet(item: $moveSource) { source in
            FolderChooser(excluding: source.id, title: "写真をどのフォルダに移しますか？") { dest in
                let photos = source.photoArray
                for p in photos { p.folder = dest }
                try? context.save()
                let name = source.name
                context.delete(source)
                try? context.save()
                showDone = "\(photos.count)枚を「\(dest.name)」に移して、フォルダ「\(name)」を削除しました。"
            }
        }
        .alert("完了", isPresented: Binding(get: { showDone != nil }, set: { if !$0 { showDone = nil } })) {
            Button("OK") { showDone = nil }
        } message: {
            Text(showDone ?? "")
        }
    }

    private func delete(_ f: PhotoFolder) {
        for photo in f.photoArray { ThumbnailCache.shared.remove(photo.id.uuidString) }
        context.delete(f)
        try? context.save()
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

/// 分類のカード（ホーム）：大きなアイコン・名前・写真3枚・飾り
struct CategoryCard: View {
    let category: PhotoCategory

    var body: some View {
        let photos = category.allPhotos
        let accent = category.color
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent.opacity(0.16))
                    .frame(width: 42, height: 42)
                    .overlay {
                        if let art = CategoryArt.asset(for: category.symbol) {
                            Image(art).resizable().scaledToFit().padding(6)
                        } else {
                            Image(systemName: category.symbol)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(accent)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text("フォルダ\(category.folderArray.count)つ・\(photos.count)枚")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.top, 2)
                .layoutPriority(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            HStack(spacing: 6) {
                if photos.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(accent.opacity(0.10))
                            .aspectRatio(1, contentMode: .fit)
                    }
                } else {
                    ForEach(photos.prefix(3)) { photo in
                        CardThumb(item: photo)
                    }
                    ForEach(0..<max(0, 3 - min(3, photos.count)), id: \.self) { _ in
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 白一色にせず、分類の色をやさしく重ねる（左上は白、右下ほどその色）
        .background(
            ZStack {
                Decor.glass
                LinearGradient(colors: [accent.opacity(0.04), accent.opacity(0.16)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            },
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(alignment: .bottomTrailing) {
            CornerCloud(color: accent)
                .offset(x: 24, y: 24)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            CardAccent(seed: category.name, color: accent)
                .scaleEffect(0.75)
                .offset(x: -24, y: 2)
                .allowsHitTesting(false)
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(accent.opacity(0.45), lineWidth: 1.5))
        .shadow(color: Decor.cardShadow, radius: 10, x: 0, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 24))
    }
}

/// カードの小さな飾り（分類ごとに、キラッ・ハートのどちらかが付く）
struct CardAccent: View {
    let seed: String
    let color: Color
    var body: some View {
        let n = seed.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 997 }
        Group {
            if n % 2 == 0 {
                Twinkle(color: color).rotationEffect(.degrees(40)).scaleEffect(0.8)
            } else {
                TinyHeart(color: color, size: 15, filled: n % 3 != 0)
            }
        }
    }
}

/// 分類カードの写真（正方形・白い縁）
struct CardThumb: View {
    let item: PhotoItem
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Theme.accentSoft
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
            .task(id: item.id) {
                let id = item.id, data = item.thumbData
                image = await Task.detached { PhotoStorage.thumbnail(id: id, data: data) }.value
            }
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
                    // 縦長の写真でも枠からはみ出さないよう、枠の大きさに切り抜く
                    Color.clear.overlay {
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
                .clipped()
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
    @AppStorage("appTheme") private var themeRaw = AppTheme.pink.rawValue
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
                    Picker("色のテーマ", selection: $themeRaw) {
                        ForEach(AppTheme.allCases) { t in
                            Label(t.label, systemImage: t == .pink ? "heart.fill" : "drop.fill").tag(t.rawValue)
                        }
                    }
                } label: {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 40, height: 38)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("画面のモード：\(mode.label)")
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 40, height: 38)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("設定")
            }
            .foregroundStyle(Theme.ink)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(dateText) ・ \(Theme.greeting)")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                Text("フォトポケット")
                    .font(.system(size: 31, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                TitleSwoosh()
                    .frame(width: 205, height: 16)
                    .padding(.top, -4)
            }
            .padding(.trailing, 110)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, -6)
            // カメラと写真は重ねて置くだけ（レイアウトの高さには入れない）
            .overlay(alignment: .topTrailing) {
                CameraIllustration()
                    .scaleEffect(0.7)
                    .frame(width: 112, height: 98)
                    .offset(x: 14, y: -10)
                    .allowsHitTesting(false)
            }

            if showStats {
                HStack(spacing: 10) {
                    StatTile(symbol: "deco_photo_icon", color: Decor.pink,
                             tint: AppTheme.isBlue ? Color(red: 0.88, green: 0.93, blue: 1.0) : Color(red: 1.0, green: 0.90, blue: 0.92),
                             value: "\(photoCount)", label: "写真") { StatPhotosDecor() }
                    StatTile(symbol: "deco_folder", color: Color(red: 0.85, green: 0.54, blue: 0.12),
                             tint: Color(red: 1.0, green: 0.95, blue: 0.84),
                             value: "\(folderCount)", label: "フォルダ") { StatFolderDecor() }
                    Button(action: onICloud) {
                        StatTile(symbol: iCloudOn ? "deco_badge" : "sparkles",
                                 color: Color(red: 0.18, green: 0.50, blue: 0.85),
                                 tint: Color(red: 0.90, green: 0.94, blue: 1.0),
                                 value: iCloudOn ? "フル版" : "無料版", label: "プラン") { StatPlanDecor(unlocked: iCloudOn) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(iCloudOn ? "設定を開きます" : "フル版の案内を開きます")
                }
                .padding(.top, 16)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 0)
        .padding(.bottom, 6)
    }
}

/// 数字のカード（写真・フォルダ・プラン）：淡い色のカード＋右下の飾り
struct StatTile<Decoration: View>: View {
    let symbol: String
    let color: Color
    let tint: Color
    let value: String
    let label: String
    @ViewBuilder var decoration: () -> Decoration

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.16))
                .frame(width: 30, height: 30)
                .overlay {
                    if symbol.hasPrefix("deco_") {
                        Art.image(symbol).resizable().scaledToFit().padding(3)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(color)
                    }
                }
                .padding(.bottom, 6)
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Decor.glass, tint.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(alignment: .bottomTrailing) {
            decoration()
                .scaleEffect(0.6)
                .frame(width: 52, height: 50)
                .offset(x: 2, y: 4)
                .opacity(0.9)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .allowsHitTesting(false)
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Decor.glassStroke, lineWidth: 1.5))
        .shadow(color: Decor.cardShadow, radius: 8, x: 0, y: 4)
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
