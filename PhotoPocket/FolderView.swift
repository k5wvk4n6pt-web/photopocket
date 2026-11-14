import SwiftUI
import SwiftData
import PhotosUI

/// フォルダの中身（写真のグリッド）と取り込み
struct FolderView: View {
    @Bindable var folder: PhotoFolder
    @Environment(\.modelContext) private var context
    @AppStorage("deletePolicy") private var deletePolicyRaw = DeletePolicy.ask.rawValue
    @AppStorage("reviewAfterImport") private var reviewAfterImport = true
    @State private var reviewFirst: PhotoItem?
    @StateObject private var importer = PhotoImporter()

    @State private var showPicker = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var justImported: [PhotoItem] = []
    @State private var failedCount = 0
    @State private var askLibraryDelete = false

    @State private var selecting = false
    @State private var selected = Set<UUID>()
    @State private var viewerItem: PhotoItem?
    @State private var showMove = false
    @State private var confirmAppDelete = false
    @State private var confirmCleanup = false
    @State private var editFolder: FolderEditTarget?
    @State private var alertMessage: String?
    @State private var busy = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
    private var policy: DeletePolicy { DeletePolicy(rawValue: deletePolicyRaw) ?? .ask }
    private var photos: [PhotoItem] { folder.sortedPhotos }
    private var selectedItems: [PhotoItem] { photos.filter { selected.contains($0.id) } }
    private var stillInLibrary: [PhotoItem] { photos.filter(\.isStillInLibrary) }

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
                Button { showPicker = true } label: {
                    Label("写真・動画を取り込む", systemImage: "plus")
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
            maxSelectionCount: nil,
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
                ProgressOverlay(text: "取り込み中… \(importer.done)/\(importer.total)")
            } else if busy {
                ProgressOverlay(text: "処理中…")
            }
        }
        // 取り込み後：写真アプリから消す？残す？
        .confirmationDialog(
            "\(justImported.count)枚を取り込みました",
            isPresented: $askLibraryDelete,
            titleVisibility: .visible
        ) {
            Button("写真アプリから削除する", role: .destructive) {
                let items = justImported
                Task { await deleteFromLibrary(items); await review() }
            }
            Button("写真アプリに残す") { justImported = []; Task { await review() } }
        } message: {
            Text(importMessage)
        }
        .confirmationDialog(
            "写真アプリに残っている\(stillInLibrary.count)枚を削除しますか？",
            isPresented: $confirmCleanup,
            titleVisibility: .visible
        ) {
            Button("写真アプリから削除する", role: .destructive) {
                let items = stillInLibrary
                Task { await deleteFromLibrary(items) }
            }
        } message: {
            Text("このアプリ内の写真はそのまま残ります。削除した写真は写真アプリの「最近削除した項目」に30日間残ります。")
        }
        .confirmationDialog(
            "\(selected.count)枚をこのアプリから削除しますか？",
            isPresented: $confirmAppDelete,
            titleVisibility: .visible
        ) {
            Button("アプリから削除", role: .destructive) { deleteFromApp(selectedItems) }
        } message: {
            Text(appDeleteMessage)
        }
        .sheet(isPresented: $showMove) {
            MoveSheet(currentFolder: folder) { target in
                for item in selectedItems { item.folder = target }
                try? context.save()
                endSelecting()
            }
        }
        .sheet(item: $editFolder) { FolderEditor(target: $0) }
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
                    Button(role: .destructive) {
                        let items = selectedItems.filter(\.isStillInLibrary)
                        Task { await deleteFromLibrary(items); endSelecting() }
                    } label: {
                        Label("写真アプリから削除（アプリには残す）", systemImage: "iphone.slash")
                    }
                    .disabled(!selectedItems.contains(where: \.isStillInLibrary))
                    Button {
                        let items = selectedItems
                        Task { await exportToLibrary(items); endSelecting() }
                    } label: {
                        Label("写真アプリに書き出す", systemImage: "square.and.arrow.down")
                    }
                    Button(role: .destructive) { confirmAppDelete = true } label: {
                        Label("このアプリから削除", systemImage: "trash")
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
                    Divider()
                    Button(role: .destructive) { confirmCleanup = true } label: {
                        Label("写真アプリに残っている分を削除…", systemImage: "iphone.slash")
                    }
                    .disabled(stillInLibrary.isEmpty)
                    Button {
                        let items = photos
                        Task { await exportToLibrary(items) }
                    } label: {
                        Label("すべて写真アプリに書き出す", systemImage: "square.and.arrow.down")
                    }
                    .disabled(photos.isEmpty)
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
            if !stillInLibrary.isEmpty && !selecting {
                Button { confirmCleanup = true } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "iphone")
                        Text("\(stillInLibrary.count)枚")
                            .font(.caption2.bold())
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("写真アプリにも残っている写真\(stillInLibrary.count)枚。タップで削除")
            }
        }
        .padding(14)
        .card()
    }

    private var emptyView: some View {
        FriendlyEmptyView(
            symbol: "photo.badge.plus",
            title: "まだ写真がありません",
            message: "写真アプリから写真や動画を選んで取り込みましょう。\n取り込んだあと、写真アプリの写真を\n消すか残すか選べます。"
        ) {
            Button { showPicker = true } label: {
                Label("写真・動画を取り込む", systemImage: "plus")
            }
            .buttonStyle(BigButtonStyle())
        }
        .padding(.top, 40)
    }

    private var importMessage: String {
        var text = "写真アプリの元の写真はどうしますか？\n削除しても、このアプリには残ります。削除した写真は写真アプリの「最近削除した項目」に30日間残ります。"
        if failedCount > 0 { text += "\n\n※\(failedCount)枚は取り込めませんでした。" }
        return text
    }

    private var appDeleteMessage: String {
        let gone = selectedItems.filter { !$0.isStillInLibrary }.count
        if gone > 0 {
            return "そのうち\(gone)枚は写真アプリから削除済みです。アプリから消すと元に戻せません（写真アプリの「最近削除した項目」に残っている場合を除く）。"
        }
        return "写真アプリには元の写真が残っています。"
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

    private func runImport(_ items: [PhotosPickerItem]) async {
        let result = await importer.importItems(items, into: folder, context: context)
        pickerItems = []
        failedCount = result.failed
        let deletable = result.importedItems.filter { $0.sourceAssetID != nil }
        justImported = deletable
        reviewFirst = result.importedItems.first

        if deletable.isEmpty {
            if result.failed > 0 { alertMessage = "\(result.failed)枚は取り込めませんでした。" }
            await review()
            return
        }
        switch policy {
        case .ask:
            askLibraryDelete = true
        case .delete:
            await deleteFromLibrary(deletable)
            await review()
        case .keep:
            if result.failed > 0 { alertMessage = "\(result.failed)枚は取り込めませんでした。" }
            await review()
        }
    }

    /// 取り込んだ写真をすぐ開いて、回転や文字の確認ができるようにする
    private func review() async {
        guard reviewAfterImport, let first = reviewFirst, alertMessage == nil else { return }
        reviewFirst = nil
        try? await Task.sleep(nanoseconds: 450_000_000)
        viewerItem = first
    }

    private func deleteFromLibrary(_ items: [PhotoItem]) async {
        let ids = items.compactMap(\.sourceAssetID)
        guard !ids.isEmpty else { return }
        busy = true
        defer { busy = false; justImported = [] }
        do {
            _ = try await PhotoLibrary.deleteFromLibrary(identifiers: ids)
            // 見つからなかった写真は、すでに写真アプリから消えているので「削除済み」扱いにする
            // （isStillInLibrary はこの端末で取り込んだ写真だけが対象）
            for item in items { item.deletedFromLibrary = true }
            try? context.save()
        } catch LibraryError.cancelled {
            // キャンセル時は何もしない
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func exportToLibrary(_ items: [PhotoItem]) async {
        guard !items.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            try await PhotoLibrary.exportToLibrary(items: items)
            alertMessage = "\(items.count)枚を写真アプリに書き出しました。"
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func deleteFromApp(_ items: [PhotoItem]) {
        for item in items {
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
