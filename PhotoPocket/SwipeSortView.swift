import SwiftUI
import SwiftData
import Photos
import UIKit

/// iPhoneの写真アプリの写真を1枚ずつ表示して、スワイプで仕分ける
@MainActor
final class SwipeSorter: ObservableObject {
    enum Action {
        case delete(String, Int)
        case skip(String, Int)
        case move(String, Int, PhotoItem, Bool)
    }

    @Published var status: PHAuthorizationStatus = .notDetermined
    @Published var started = false
    @Published var currentAsset: PHAsset?
    @Published var currentImage: UIImage?
    @Published var pendingDelete: [String] = []
    @Published var remaining = 0
    @Published var notice: String?

    private var fetch: PHFetchResult<PHAsset>?
    private var index = 0
    private var handled: Set<String>
    private var history: [Action] = []
    private let manager = PHCachingImageManager()
    private static let handledKey = "sortHandledAssetIDs"
    private let previewSize = CGSize(width: 1400, height: 1400)

    init() {
        handled = Set(UserDefaults.standard.stringArray(forKey: Self.handledKey) ?? [])
    }

    var canUndo: Bool { !history.isEmpty }

    /// 写真へのアクセスを確認して、仕分けを始める
    func start(excluding imported: Set<String>) async {
        var s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if s == .notDetermined {
            s = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        status = s
        guard s == .authorized || s == .limited else { started = true; return }
        handled.formUnion(imported)
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetch = PHAsset.fetchAssets(with: .image, options: options)
        moveToNext(from: 0)
        started = true
    }

    // MARK: - 仕分けの操作

    /// 左スワイプ：削除予定に入れる（まとめて削除するときにiPhoneの確認が出る）
    func markDelete() {
        guard let asset = currentAsset else { return }
        pendingDelete.append(asset.localIdentifier)
        history.append(.delete(asset.localIdentifier, index))
        flash("削除予定に入れました")
        moveToNext(from: index + 1)
    }

    /// 上スワイプ：写真アプリに残す（次からは出てこない）
    func skip() {
        guard let asset = currentAsset else { return }
        handled.insert(asset.localIdentifier)
        saveHandled()
        history.append(.skip(asset.localIdentifier, index))
        flash("写真アプリに残しました")
        moveToNext(from: index + 1)
    }

    /// 右スワイプ：フォルダに取り込む
    func move(to folder: PhotoFolder, context: ModelContext, alsoDelete: Bool) async -> Bool {
        guard let asset = currentAsset else { return false }
        let idx = index
        guard let data = await Self.loadData(asset) else {
            flash("写真を読み込めませんでした（iCloudから取得できない可能性があります）")
            return false
        }
        let prepared = await Task.detached { PhotoStorage.prepare(data: data) }.value
        let item = PhotoItem(
            imageData: data,
            thumbData: prepared.thumbData,
            fileExtension: prepared.fileExtension,
            takenAt: prepared.takenAt ?? asset.creationDate,
            sourceAssetID: asset.localIdentifier,
            folder: folder
        )
        context.insert(item)
        try? context.save()
        handled.insert(asset.localIdentifier)
        saveHandled()
        if alsoDelete { pendingDelete.append(asset.localIdentifier) }
        history.append(.move(asset.localIdentifier, idx, item, alsoDelete))
        flash("「\(folder.name)」に入れました")
        moveToNext(from: idx + 1)
        return true
    }

    /// ひとつ前の操作を取り消す
    func undo(context: ModelContext) {
        guard let last = history.popLast() else { return }
        switch last {
        case .delete(let id, let i):
            pendingDelete.removeAll { $0 == id }
            moveToNext(from: i)
        case .skip(let id, let i):
            handled.remove(id)
            saveHandled()
            moveToNext(from: i)
        case .move(let id, let i, let item, let deleted):
            ThumbnailCache.shared.remove(item.id.uuidString)
            context.delete(item)
            try? context.save()
            handled.remove(id)
            saveHandled()
            if deleted { pendingDelete.removeAll { $0 == id } }
            moveToNext(from: i)
        }
        flash("元に戻しました")
    }

    /// 削除予定の写真を、写真アプリからまとめて削除する
    func commitDeletes(photos: [PhotoItem], context: ModelContext) async -> String? {
        let ids = pendingDelete
        guard !ids.isEmpty else { return nil }
        do {
            let deleted = try await PhotoLibrary.deleteFromLibrary(identifiers: ids)
            handled.formUnion(ids)
            saveHandled()
            pendingDelete = []
            history.removeAll()
            for p in photos where p.sourceAssetID.map({ ids.contains($0) }) == true {
                p.deletedFromLibrary = true
            }
            try? context.save()
            return "\(deleted.count)枚を写真アプリから削除しました。「最近削除した項目」に30日間残ります。"
        } catch LibraryError.cancelled {
            return "削除をキャンセルしました。削除予定はそのまま残っています。"
        } catch {
            return error.localizedDescription
        }
    }

    /// 削除予定を取り消す（写真はそのまま。次回また出てくる）
    func clearPending() {
        pendingDelete = []
        history.removeAll { if case .delete = $0 { return true } else { return false } }
    }

    // MARK: - 内部

    private func isDone(_ asset: PHAsset) -> Bool {
        handled.contains(asset.localIdentifier) || pendingDelete.contains(asset.localIdentifier)
    }

    private func moveToNext(from start: Int) {
        guard let fetch else { return }
        var i = max(0, start)
        while i < fetch.count, isDone(fetch.object(at: i)) { i += 1 }
        index = i
        currentAsset = i < fetch.count ? fetch.object(at: i) : nil
        remaining = max(0, fetch.count - i)
        loadImage()
    }

    private func loadImage() {
        currentImage = nil
        guard let asset = currentAsset, let fetch else { return }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        let id = asset.localIdentifier
        manager.requestImage(for: asset, targetSize: previewSize, contentMode: .aspectFit, options: options) { [weak self] image, _ in
            Task { @MainActor in
                guard let self, let image, self.currentAsset?.localIdentifier == id else { return }
                self.currentImage = image
            }
        }
        // 次の数枚を先に読み込んでおく
        let upper = min(index + 4, fetch.count)
        if index + 1 < upper {
            let nexts = (index + 1..<upper).map { fetch.object(at: $0) }
            manager.startCachingImages(for: nexts, targetSize: previewSize, contentMode: .aspectFit, options: options)
        }
    }

    private func saveHandled() {
        UserDefaults.standard.set(Array(handled), forKey: Self.handledKey)
    }

    private func flash(_ text: String) {
        notice = text
        let current = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if self.notice == current { self.notice = nil }
        }
    }

    static func loadData(_ asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.version = .current
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

/// スワイプで仕分ける画面
struct SwipeSortView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @StateObject private var sorter = SwipeSorter()
    @Query private var photos: [PhotoItem]
    @Query(sort: [SortDescriptor(\PhotoFolder.sortOrder), SortDescriptor(\PhotoFolder.createdAt)])
    private var folders: [PhotoFolder]
    @AppStorage("sortMoveDeletes") private var moveDeletes = true
    @AppStorage("recentSortFolders") private var recentRaw = ""

    @State private var drag: CGSize = .zero
    @State private var showFolders = false
    @State private var busy = false
    @State private var message: String?
    @State private var confirmExit = false
    @State private var confirmCommit = false

    private let threshold: CGFloat = 110

    private var recentFolders: [PhotoFolder] {
        recentRaw.split(separator: ",").compactMap { s in folders.first { $0.id.uuidString == s } }
            .prefix(4).map { $0 }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                statusBar
                cardArea
                if sorter.currentAsset != nil {
                    Text("← 左で削除　　右でフォルダへ →　　↑ 上で残す")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    if !recentFolders.isEmpty { recentRow }
                    actionButtons
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("写真を仕分ける")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        if sorter.pendingDelete.isEmpty { dismiss() } else { confirmExit = true }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("フォルダに入れた写真も写真アプリから削除", isOn: $moveDeletes)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .overlay {
                if busy { ProgressOverlay(text: "取り込んでいます…") }
            }
            .overlay(alignment: .top) {
                if let notice = sorter.notice {
                    Text(notice)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.75), in: Capsule())
                        .padding(.top, 54)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: sorter.notice)
            .sheet(isPresented: $showFolders) {
                FolderChooser { folder in
                    Task { await doMove(folder) }
                }
            }
            .confirmationDialog("削除予定の\(sorter.pendingDelete.count)枚を写真アプリから削除しますか？",
                                isPresented: $confirmCommit, titleVisibility: .visible) {
                Button("削除する", role: .destructive) { Task { await commit(thenClose: false) } }
            } message: {
                Text("このあとiPhoneの確認画面が出ます。削除した写真は「最近削除した項目」に30日間残ります。")
            }
            .confirmationDialog("削除予定の\(sorter.pendingDelete.count)枚があります",
                                isPresented: $confirmExit, titleVisibility: .visible) {
                Button("写真アプリから削除して閉じる", role: .destructive) { Task { await commit(thenClose: true) } }
                Button("削除せずに閉じる") { sorter.clearPending(); dismiss() }
            } message: {
                Text("削除せずに閉じると、その写真は次の仕分けでまた表示されます。")
            }
            .alert("お知らせ", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: {
                Text(message ?? "")
            }
            .task {
                guard !sorter.started else { return }
                await sorter.start(excluding: Set(photos.compactMap(\.sourceAssetID)))
            }
        }
    }

    // MARK: - 部品

    private var statusBar: some View {
        HStack {
            if sorter.currentAsset != nil {
                Text("あと約\(sorter.remaining)枚")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !sorter.pendingDelete.isEmpty {
                Button { confirmCommit = true } label: {
                    Label("削除予定 \(sorter.pendingDelete.count)枚 ・ 削除する", systemImage: "trash")
                        .font(.footnote.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.red.opacity(0.85), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 34)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var cardArea: some View {
        if !sorter.started {
            Spacer()
            ProgressView("写真を読み込んでいます…")
            Spacer()
        } else if sorter.status != .authorized && sorter.status != .limited {
            Spacer()
            FriendlyEmptyView(symbol: "photo.badge.exclamationmark", title: "写真へのアクセスが必要です",
                              message: "「設定」アプリ →「フォトポケット」→「写真」で「フルアクセス」を選んでください。") {
                Button("設定を開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(BigButtonStyle())
            }
            Spacer()
        } else if let asset = sorter.currentAsset {
            card(asset)
        } else {
            Spacer()
            FriendlyEmptyView(symbol: "checkmark.seal.fill", title: "仕分けが終わりました",
                              message: sorter.pendingDelete.isEmpty
                                ? "仕分けていない写真はもうありません。新しく撮った写真は、次に開いたときに出てきます。"
                                : "上の「削除する」を押すと、削除予定の写真を写真アプリからまとめて削除します。") {
                Button("閉じる") {
                    if sorter.pendingDelete.isEmpty { dismiss() } else { confirmExit = true }
                }
                .buttonStyle(BigButtonStyle())
            }
            Spacer()
        }
    }

    private func card(_ asset: PHAsset) -> some View {
        let leftAmount = min(1, max(0, -drag.width / threshold))
        let rightAmount = min(1, max(0, drag.width / threshold))
        let upAmount = min(1, max(0, -drag.height / threshold)) * (abs(drag.width) < threshold ? 1 : 0)
        return ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Theme.card)
                .shadow(color: .black.opacity(0.1), radius: 14, x: 0, y: 6)
            VStack(spacing: 8) {
                ZStack {
                    if let image = sorter.currentImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let date = asset.creationDate {
                    Text(date.formatted(date: .long, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)

            stamp("削除", color: .red, angle: 12)
                .opacity(leftAmount)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(26)
            stamp("フォルダへ", color: .green, angle: -12)
                .opacity(rightAmount)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(26)
            stamp("残す", color: .blue, angle: 0)
                .opacity(upAmount)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(40)
        }
        .offset(drag)
        .rotationEffect(.degrees(Double(drag.width / 22)))
        .gesture(
            DragGesture()
                .onChanged { drag = $0.translation }
                .onEnded { value in
                    let t = value.translation
                    if t.width < -threshold {
                        swipeLeft()
                    } else if t.width > threshold {
                        swipeRight()
                    } else if t.height < -threshold {
                        swipeUp()
                    } else {
                        withAnimation(.spring(duration: 0.3)) { drag = .zero }
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("写真。左にスワイプで削除、右にスワイプでフォルダへ、上にスワイプで残す")
    }

    private func stamp(_ text: String, color: Color, angle: Double) -> some View {
        Text(text)
            .font(.title2.weight(.heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 4))
            .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
            .rotationEffect(.degrees(angle))
    }

    private var recentRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(recentFolders) { folder in
                    Button { Task { await doMove(folder) } } label: {
                        Label(folder.name, systemImage: "folder.fill")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(folder.color.opacity(0.18), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 14) {
            circleButton("arrow.uturn.backward", label: "戻す", color: .gray, size: 50) {
                sorter.undo(context: context)
            }
            .disabled(!sorter.canUndo)
            .opacity(sorter.canUndo ? 1 : 0.4)
            circleButton("xmark", label: "削除", color: .red, size: 64) { swipeLeft() }
            circleButton("arrow.up", label: "残す", color: .blue, size: 54) { swipeUp() }
            circleButton("folder.fill", label: "フォルダへ", color: .green, size: 64) { swipeRight() }
        }
        .padding(.top, 2)
    }

    private func circleButton(_ symbol: String, label: String, color: Color, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Circle()
                    .fill(Theme.card)
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
                    .overlay(Image(systemName: symbol).font(.system(size: size * 0.38, weight: .bold)).foregroundStyle(color))
                Text(label).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - 動き

    private func swipeLeft() {
        withAnimation(.easeIn(duration: 0.2)) { drag = CGSize(width: -700, height: 40) }
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            sorter.markDelete()
            drag = .zero
        }
    }

    private func swipeUp() {
        withAnimation(.easeIn(duration: 0.2)) { drag = CGSize(width: 0, height: -900) }
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            sorter.skip()
            drag = .zero
        }
    }

    private func swipeRight() {
        withAnimation(.spring(duration: 0.3)) { drag = .zero }
        if folders.isEmpty {
            message = "先にホームで分類とフォルダを作ってください。"
        } else {
            showFolders = true
        }
    }

    private func doMove(_ folder: PhotoFolder) async {
        busy = true
        let ok = await sorter.move(to: folder, context: context, alsoDelete: moveDeletes)
        busy = false
        if ok {
            var ids = recentRaw.split(separator: ",").map(String.init).filter { $0 != folder.id.uuidString }
            ids.insert(folder.id.uuidString, at: 0)
            recentRaw = ids.prefix(6).joined(separator: ",")
        }
    }

    private func commit(thenClose: Bool) async {
        let result = await sorter.commitDeletes(photos: photos, context: context)
        if thenClose && sorter.pendingDelete.isEmpty {
            dismiss()
        } else {
            message = result
        }
    }
}

/// 仕分け先のフォルダを選ぶ
struct FolderChooser: View {
    let onSelect: (PhotoFolder) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\PhotoCategory.sortOrder), SortDescriptor(\PhotoCategory.createdAt)])
    private var categories: [PhotoCategory]
    @Query(sort: [SortDescriptor(\PhotoFolder.sortOrder), SortDescriptor(\PhotoFolder.createdAt)])
    private var folders: [PhotoFolder]

    var body: some View {
        NavigationStack {
            List {
                ForEach(categories) { c in
                    if !c.folderArray.isEmpty {
                        Section {
                            ForEach(c.sortedFolders) { row($0) }
                        } header: {
                            Label(c.name, systemImage: c.symbol).foregroundStyle(c.color)
                        }
                    }
                }
                let none = folders.filter { $0.category == nil }
                if !none.isEmpty {
                    Section("未分類") { ForEach(none) { row($0) } }
                }
            }
            .navigationTitle("どのフォルダに入れますか？")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ folder: PhotoFolder) -> some View {
        Button {
            dismiss()
            onSelect(folder)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill").foregroundStyle(folder.color)
                Text(folder.name).foregroundStyle(.primary)
                Spacer()
                Text("\(folder.photoArray.count)枚").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
