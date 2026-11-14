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
        case batch([Action])
    }

    @Published var status: PHAuthorizationStatus = .notDetermined
    @Published var started = false
    @Published var currentAsset: PHAsset?
    @Published var currentImage: UIImage?
    @Published var pendingDelete: [String] = []
    @Published var remaining = 0
    @Published var notice: String?
    /// 一覧モード用：まだ仕分けていない写真・動画
    @Published var gridAssets: [PHAsset] = []
    @Published var progressText: String?

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
    /// "added"＝写真アプリに保存した順（新しい順）、"taken"＝撮影日の新しい順
    private(set) var order = "added"

    private func asset(at i: Int) -> PHAsset? {
        guard let fetch, i >= 0, i < fetch.count else { return nil }
        return order == "added" ? fetch.object(at: fetch.count - 1 - i) : fetch.object(at: i)
    }

    private func makeFetch() {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d || mediaType == %d",
                                        PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        if order == "taken" {
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        }
        // 並べ替えを指定しないと、写真アプリに保存した順（古い順）で返る
        fetch = PHAsset.fetchAssets(with: options)
    }

    /// 並び順を変えて、最初から表示し直す（仕分け済みは出てこない）
    func changeOrder(_ newOrder: String) {
        guard newOrder != order, fetch != nil else { order = newOrder; return }
        order = newOrder
        history.removeAll()
        makeFetch()
        moveToNext(from: 0)
    }

    func start(excluding imported: Set<String>, order: String) async {
        self.order = order
        var s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if s == .notDetermined {
            s = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        status = s
        guard s == .authorized || s == .limited else { started = true; return }
        handled.formUnion(imported)
        makeFetch()
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

    /// 写真アプリの写真・動画をフォルダに登録する（コピーはしない）
    private func importAsset(_ asset: PHAsset, to folder: PhotoFolder, context: ModelContext) async -> PhotoItem? {
        let item = await PhotoAssets.makeItem(from: asset, folder: folder, context: context)
        try? context.save()
        return item
    }

    /// 右スワイプ：フォルダに取り込む
    func move(to folder: PhotoFolder, context: ModelContext, alsoDelete: Bool) async -> Bool {
        guard let asset = currentAsset else { return false }
        let idx = index
        guard let item = await importAsset(asset, to: folder, context: context) else {
            flash("読み込めませんでした（iCloudから取得できない可能性があります）")
            return false
        }
        finishMove(asset: asset, idx: idx, item: item, folder: folder, alsoDelete: alsoDelete)
        return true
    }

    // MARK: - 一覧モードでまとめて仕分け

    /// まとめて削除予定に入れる
    func markDelete(_ assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        var actions: [Action] = []
        for a in assets where !isDone(a) {
            pendingDelete.append(a.localIdentifier)
            actions.append(.delete(a.localIdentifier, index))
        }
        history.append(.batch(actions))
        flash("\(actions.count)枚を削除予定に入れました")
        moveToNext(from: index)
    }

    /// まとめて写真アプリに残す
    func skip(_ assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        var actions: [Action] = []
        for a in assets where !isDone(a) {
            handled.insert(a.localIdentifier)
            actions.append(.skip(a.localIdentifier, index))
        }
        saveHandled()
        history.append(.batch(actions))
        flash("\(actions.count)枚を写真アプリに残しました")
        moveToNext(from: index)
    }

    /// まとめてフォルダに取り込む
    func move(_ assets: [PHAsset], to folder: PhotoFolder, context: ModelContext, alsoDelete: Bool) async -> Int {
        var actions: [Action] = []
        var failed = 0
        for (n, a) in assets.enumerated() where !isDone(a) {
            progressText = "フォルダに入れています… \(n + 1)/\(assets.count)"
            guard let item = await importAsset(a, to: folder, context: context) else { failed += 1; continue }
            handled.insert(a.localIdentifier)
            if alsoDelete { pendingDelete.append(a.localIdentifier) }
            actions.append(.move(a.localIdentifier, index, item, alsoDelete))
        }
        progressText = nil
        saveHandled()
        if !actions.isEmpty { history.append(.batch(actions)) }
        flash(failed > 0 ? "「\(folder.name)」に\(actions.count)枚入れました（\(failed)枚は読み込めませんでした）"
                         : "「\(folder.name)」に\(actions.count)枚入れました")
        moveToNext(from: index)
        return actions.count
    }

    private func finishMove(asset: PHAsset, idx: Int, item: PhotoItem, folder: PhotoFolder, alsoDelete: Bool) {
        handled.insert(asset.localIdentifier)
        saveHandled()
        if alsoDelete { pendingDelete.append(asset.localIdentifier) }
        history.append(.move(asset.localIdentifier, idx, item, alsoDelete))
        flash("「\(folder.name)」に入れました")
        moveToNext(from: idx + 1)
    }

    /// ひとつ前の操作を取り消す
    func undo(context: ModelContext) {
        guard let last = history.popLast() else { return }
        let i = revert(last, context: context)
        saveHandled()
        try? context.save()
        moveToNext(from: min(i, index))
        flash("元に戻しました")
    }

    private func revert(_ action: Action, context: ModelContext) -> Int {
        switch action {
        case .delete(let id, let i):
            pendingDelete.removeAll { $0 == id }
            return i
        case .skip(let id, let i):
            handled.remove(id)
            return i
        case .move(let id, let i, let item, let deleted):
            ThumbnailCache.shared.remove(item.id.uuidString)
            context.delete(item)
            handled.remove(id)
            if deleted { pendingDelete.removeAll { $0 == id } }
            return i
        case .batch(let actions):
            return actions.reversed().map { revert($0, context: context) }.min() ?? index
        }
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
            for p in photos where p.sourceAssetID.map({ deleted.contains($0) }) == true
                && p.importDeviceID == DeviceID.current {
                if p.isLegacyCopy {
                    p.deletedFromLibrary = true
                } else {
                    // 写真アプリから消えた写真は、フォルダからも外す
                    ThumbnailCache.shared.remove(p.id.uuidString)
                    context.delete(p)
                }
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
        refreshGrid()
    }

    // MARK: - 内部

    private func isDone(_ asset: PHAsset) -> Bool {
        handled.contains(asset.localIdentifier) || pendingDelete.contains(asset.localIdentifier)
    }

    private func moveToNext(from start: Int) {
        guard let fetch else { return }
        var i = max(0, start)
        while i < fetch.count, let a = asset(at: i), isDone(a) { i += 1 }
        index = i
        currentAsset = asset(at: i)
        remaining = max(0, fetch.count - i)
        refreshGrid()
        loadImage()
    }

    private func refreshGrid() {
        guard let fetch else { gridAssets = []; return }
        var list: [PHAsset] = []
        list.reserveCapacity(fetch.count)
        for i in 0..<fetch.count {
            if let a = asset(at: i), !isDone(a) { list.append(a) }
        }
        gridAssets = list
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
            let nexts = (index + 1..<upper).compactMap { self.asset(at: $0) }
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
    @EnvironmentObject private var store: Store
    @State private var showUnlock = false
    @AppStorage("recentSortFolders") private var recentRaw = ""
    @AppStorage("sortOrder") private var sortOrder = "added"
    @State private var previewAsset: PHAsset?
    @AppStorage("sortGridMode") private var gridMode = false
    @State private var gridSelection: Set<String> = []

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
                Picker("仕分けかた", selection: $gridMode) {
                    Text("1枚ずつ").tag(false)
                    Text("一覧でまとめて").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.top, 4)
                statusBar
                if gridMode && sorter.currentAsset != nil {
                    gridArea
                } else {
                    cardArea
                }
                if gridMode && sorter.currentAsset != nil {
                    gridActions
                } else if sorter.currentAsset != nil {
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
                        Picker("並び順", selection: $sortOrder) {
                            Text("保存した順（写真アプリと同じ）").tag("added")
                            Text("撮影日順").tag("taken")
                        }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .overlay {
                if busy { ProgressOverlay(text: sorter.progressText ?? "フォルダに入れています…") }
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
            .sheet(isPresented: $showUnlock) { UnlockView().environmentObject(store) }
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
                await sorter.start(excluding: Set(photos.compactMap(\.sourceAssetID)), order: sortOrder)
            }
            .onChange(of: sortOrder) { _, newValue in sorter.changeOrder(newValue) }
            .fullScreenCover(item: $previewAsset) { asset in
                LibraryPreview(asset: asset)
            }
        }
    }

    // MARK: - 部品

    private var statusBar: some View {
        HStack {
            if sorter.currentAsset != nil {
                Text(gridMode ? "未仕分け \(sorter.gridAssets.count)枚" : "あと約\(sorter.remaining)枚")
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
                            .overlay {
                                if asset.mediaType == .video {
                                    VStack(spacing: 8) {
                                        Image(systemName: "play.circle.fill")
                                            .font(.system(size: 64))
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.45))
                                        Text(Self.durationText(asset.duration))
                                            .font(.headline.weight(.heavy))
                                            .monospacedDigit()
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 4)
                                            .background(.black.opacity(0.55), in: Capsule())
                                    }
                                    .shadow(radius: 4)
                                }
                            }
                    } else {
                        ProgressView()
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { previewAsset = asset }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 6) {
                    if let date = asset.creationDate {
                        Text(date.formatted(date: .long, time: .shortened))
                    }
                    Text(asset.mediaType == .video ? "・タップで再生" : "・タップで拡大")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
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
        .accessibilityLabel("写真または動画。タップで拡大・再生。左にスワイプで削除、右にスワイプでフォルダへ、上にスワイプで残す")
    }

    static func durationText(_ seconds: Double) -> String {
        let t = Int(seconds.rounded())
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
                         : String(format: "%d:%02d", t / 60, t % 60)
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

    // MARK: - 一覧モード

    private var selectedAssets: [PHAsset] {
        sorter.gridAssets.filter { gridSelection.contains($0.localIdentifier) }
    }

    private var gridArea: some View {
        LibraryGrid(assets: sorter.gridAssets, selected: $gridSelection) { asset in
            previewAsset = asset
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxHeight: .infinity)
    }

    private var gridActions: some View {
        VStack(spacing: 10) {
            HStack {
                Text(gridSelection.isEmpty ? "タップか、横になぞって選択・長押しで拡大" : "\(gridSelection.count)枚を選択中")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !gridSelection.isEmpty {
                    Button("選択解除") { gridSelection = [] }
                        .font(.caption.weight(.bold))
                }
            }
            if !recentFolders.isEmpty { recentRow.disabled(gridSelection.isEmpty).opacity(gridSelection.isEmpty ? 0.45 : 1) }
            HStack(spacing: 14) {
                circleButton("arrow.uturn.backward", label: "戻す", color: .gray, size: 46) {
                    sorter.undo(context: context)
                }
                .disabled(!sorter.canUndo)
                .opacity(sorter.canUndo ? 1 : 0.4)
                Group {
                    circleButton("xmark", label: "削除", color: .red, size: 56) {
                        sorter.markDelete(selectedAssets)
                        gridSelection = []
                    }
                    circleButton("arrow.up", label: "残す", color: .blue, size: 50) {
                        sorter.skip(selectedAssets)
                        gridSelection = []
                    }
                    circleButton("folder.fill", label: "フォルダへ", color: .green, size: 56) { swipeRight() }
                }
                .disabled(gridSelection.isEmpty)
                .opacity(gridSelection.isEmpty ? 0.4 : 1)
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
        // 無料版の上限（フォルダの写真は合計30枚まで）
        let remaining = FreeLimit.remainingPhotos(store: store, context: context)
        if remaining <= 0 {
            showUnlock = true
            return
        }
        busy = true
        let ok: Bool
        var hitLimit = false
        if gridMode {
            var list = selectedAssets
            guard !list.isEmpty else { busy = false; return }
            if list.count > remaining {
                list = Array(list.prefix(remaining))
                hitLimit = true
            }
            ok = await sorter.move(list, to: folder, context: context, alsoDelete: false) > 0
            gridSelection = []
        } else {
            ok = await sorter.move(to: folder, context: context, alsoDelete: false)
        }
        busy = false
        if ok {
            var ids = recentRaw.split(separator: ",").map(String.init).filter { $0 != folder.id.uuidString }
            ids.insert(folder.id.uuidString, at: 0)
            recentRaw = ids.prefix(6).joined(separator: ",")
        }
        if hitLimit { showUnlock = true }
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


extension PHAsset: @retroactive Identifiable {
    public var id: String { localIdentifier }
}

/// 仕分け中の写真を大きく表示（ピンチで拡大）／動画を再生
struct LibraryPreview: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            Group {
                if asset.mediaType == .video {
                    LibraryVideoPlayer(asset: asset)
                } else if let image {
                    ZoomableImage(image: image).ignoresSafeArea(edges: .bottom)
                } else {
                    ZStack { Color.black; ProgressView().tint(.white) }
                }
            }
            .background(Color.black.ignoresSafeArea())
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("閉じる") { dismiss() } }
            }
        }
        .task {
            guard asset.mediaType != .video else { return }
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            let size = CGSize(width: 3000, height: 3000)
            image = await withCheckedContinuation { continuation in
                PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { img, _ in
                    continuation.resume(returning: img)
                }
            }
        }
    }
}
