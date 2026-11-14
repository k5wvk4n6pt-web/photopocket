import SwiftUI
import SwiftData
import PhotosUI

/// フォルダの中身（写真のグリッド）と、写真アプリからの登録
/// 写真の本体は写真アプリに置いたまま。フォルダには「どの写真か」だけを入れる
struct FolderView: View {
    @Bindable var folder: PhotoFolder
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var store: Store
    @AppStorage("reviewAfterImport") private var reviewAfterImport = true
    @State private var reviewFirst: PhotoItem?
    @StateObject private var importer = PhotoImporter()

    @State private var showPicker = false
    @State private var pickerItems: [PhotosPickerItem] = []

    @State private var selecting = false
    @State private var selected = Set<UUID>()
    @State private var viewerItem: PhotoItem?
    @State private var showMove = false
    @State private var confirmRemove = false
    @State private var confirmLibraryDelete = false
    @State private var editFolder: FolderEditTarget?
    @State private var alertMessage: String?
    @State private var busy = false
    @State private var showUnlock = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
    private var photos: [PhotoItem] { folder.sortedPhotos }
    private var selectedItems: [PhotoItem] { photos.filter { selected.contains($0.id) } }

    var body: some View {
        ScrollView {
            if photos.isEmpty {
                emptyView
            } else {
                VStack(spacing: 14) {
                    folderHeader
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(photos) { item in
                            ThumbnailCell(item: item, selecting: selecting, isSelected: selected.contains(item.id))
                                .contentShape(Rectangle())
                                .onTapGesture { tap(item) }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 100)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            if !selecting && !photos.isEmpty {
                Button { openPicker() } label: {
                    Label("写真・動画を入れる", systemImage: "plus")
                }
                .buttonStyle(BigButtonStyle())
                .padding(.bottom, 10)
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .photosPicker(
            isPresented: $showPicker,
            selection: $pickerItems,
            maxSelectionCount: store.isUnlocked ? nil : max(1, FreeLimit.remainingPhotos(store: store, context: context)),
            selectionBehavior: .ordered,
            matching: .any(of: [.images, .videos]),
            preferredItemEncoding: .current,
            photoLibrary: .shared()
        )
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await runImport(newItems) }
        }
        .overlay {
            if importer.isImporting {
                ProgressOverlay(text: "フォルダに入れています… \(importer.done)/\(importer.total)")
            } else if busy {
                ProgressOverlay(text: "処理中…")
            }
        }
        .confirmationDialog(
            "\(selected.count)枚をこのフォルダから外しますか？",
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button("フォルダから外す", role: .destructive) { removeFromFolder(selectedItems) }
        } message: {
            Text("写真アプリの写真はそのまま残ります。")
        }
        .confirmationDialog(
            "\(selected.count)枚を写真アプリから削除しますか？",
            isPresented: $confirmLibraryDelete,
            titleVisibility: .visible
        ) {
            Button("写真アプリから削除", role: .destructive) {
                let items = selectedItems
                Task { await deleteFromLibrary(items) }
            }
        } message: {
            Text("このあとiPhoneの確認画面が出ます。削除した写真は写真アプリの「最近削除した項目」に30日間残ります。")
        }
        .sheet(isPresented: $showMove) {
            MoveSheet(currentFolder: folder) { target in
                for item in selectedItems { item.folder = target }
                try? context.save()
                endSelecting()
            }
        }
        .sheet(item: $editFolder) { FolderEditor(target: $0) }
        .sheet(isPresented: $showUnlock) { UnlockView().environmentObject(store) }
        .fullScreenCover(item: $viewerItem) { item in
            PhotoViewer(folder: folder, startID: item.id)
        }
        .alert("お知らせ", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if selecting {
            ToolbarItem(placement: .topBarLeading) {
                Button(selected.count == photos.count ? "選択解除" : "すべて選択") {
                    if selected.count == photos.count { selected = [] } else { selected = Set(photos.map(\.id)) }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("完了") { endSelecting() }.bold()
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button { showMove = true } label: { Label("移動", systemImage: "folder") }
                    .disabled(selected.isEmpty)
                Spacer()
                Text("\(selected.count)枚選択").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button { confirmRemove = true } label: {
                        Label("フォルダから外す（写真アプリには残す）", systemImage: "folder.badge.minus")
                    }
                    Button(role: .destructive) { confirmLibraryDelete = true } label: {
                        Label("写真アプリから削除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selected.isEmpty)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { selecting = true } label: { Label("写真を選択", systemImage: "checkmark.circle") }
                        .disabled(photos.isEmpty)
                    Button { editFolder = .edit(folder) } label: { Label("フォルダを編集", systemImage: "pencil") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var folderHeader: some View {
        HStack(spacing: 14) {
            IconBadge(symbol: "folder.fill", color: folder.color, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(folder.name).font(.headline)
                Text(folder.category.map { "\($0.name) ・ \(photos.count)枚" } ?? "\(photos.count)枚")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .card()
    }

    private var emptyView: some View {
        FriendlyEmptyView(
            symbol: "photo.badge.plus",
            title: "まだ写真がありません",
            message: "写真アプリから写真や動画を選んで、このフォルダに入れましょう。\n写真は写真アプリに残ったままなので安心です。"
        ) {
            Button { openPicker() } label: {
                Label("写真・動画を入れる", systemImage: "plus")
            }
            .buttonStyle(BigButtonStyle())
        }
        .padding(.top, 40)
    }

    // MARK: - Actions

    private func tap(_ item: PhotoItem) {
        if selecting {
            if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
        } else {
            viewerItem = item
        }
    }

    private func endSelecting() {
        selecting = false
        selected = []
    }

    /// 無料版の上限に達していたら、有料版の案内を出す
    private func openPicker() {
        if FreeLimit.remainingPhotos(store: store, context: context) <= 0 {
            showUnlock = true
        } else {
            showPicker = true
        }
    }

    private func runImport(_ items: [PhotosPickerItem]) async {
        let limit = FreeLimit.remainingPhotos(store: store, context: context)
        let result = await importer.importItems(items, into: folder, context: context, limit: limit)
        pickerItems = []
        reviewFirst = result.importedItems.first

        if result.overLimit > 0 {
            showUnlock = true
            return
        }
        if result.failed > 0 {
            alertMessage = "\(result.failed)枚は入れられませんでした。写真へのアクセスを「フルアクセス」にすると入れられます。"
        }
        await review()
    }

    /// 入れた写真をすぐ開いて、文字やメモの確認ができるようにする
    private func review() async {
        guard reviewAfterImport, let first = reviewFirst, alertMessage == nil else { return }
        reviewFirst = nil
        try? await Task.sleep(nanoseconds: 450_000_000)
        viewerItem = first
    }

    private func deleteFromLibrary(_ items: [PhotoItem]) async {
        guard !items.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await PhotoAssets.deleteFromLibrary(items, context: context)
            endSelecting()
        } catch LibraryError.cancelled {
            // キャンセル時は何もしない
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func removeFromFolder(_ items: [PhotoItem]) {
        for item in items where !item.isLegacyCopy {
            ThumbnailCache.shared.remove(item.id.uuidString)
            context.delete(item)
        }
        try? context.save()
        endSelecting()
    }
}

struct ThumbnailCell: View {
    let item: PhotoItem
    let selecting: Bool
    let isSelected: Bool
    @State private var image: UIImage?

    var body: some View {
        Theme.accent.opacity(0.08)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if item.isStillInLibrary {
                    Image(systemName: "iphone")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(4)
                }
            }
            .overlay(alignment: .topLeading) {
                if item.isVideo && !selecting {
                    VideoBadge(text: item.durationText).padding(5)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !item.memo.isEmpty {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(5)
                }
            }
            .overlay {
                if selecting && isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.3))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.accent, lineWidth: 3))
                }
            }
            .overlay(alignment: .topTrailing) {
                if selecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isSelected ? Theme.accent : Color.black.opacity(0.2))
                        .shadow(radius: 2)
                        .padding(6)
                }
            }
            .task(id: "\(item.id.uuidString)-\(item.byteSize)") {
                let id = item.id
                let data = item.thumbData
                image = await Task.detached { PhotoStorage.thumbnail(id: id, data: data) }.value
            }
    }
}

struct ProgressOverlay: View {
    let text: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text(text).font(.subheadline)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        }
    }
}
