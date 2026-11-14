import SwiftUI
import SwiftData
import UIKit

/// 写真を1枚ずつ大きく表示（左右スワイプ・ピンチで拡大）
struct PhotoViewer: View {
    let folder: PhotoFolder
    @State private var currentID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var store: Store
    @State private var showUnlock = false

    @State private var showMove = false
    @State private var confirmAppDelete = false
    @State private var confirmLibraryDelete = false
    @State private var editingMemo = false
    @State private var memoText = ""
    @State private var alertMessage: String?
    @State private var shareURL: URL?
    @State private var showText = false

    init(folder: PhotoFolder, startID: UUID) {
        self.folder = folder
        _currentID = State(initialValue: startID)
    }

    private var photos: [PhotoItem] { folder.sortedPhotos }
    private var current: PhotoItem? { photos.first { $0.id == currentID } }

    var body: some View {
        NavigationStack {
            TabView(selection: $currentID) {
                ForEach(photos) { item in
                    Group {
                        if item.isVideo {
                            VideoPage(item: item, isCurrent: item.id == currentID)
                        } else {
                            FullImagePage(item: item)
                        }
                    }
                    .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .task(id: currentID) {
                shareURL = nil
                guard let current else { return }
                shareURL = await PhotoAssets.shareFile(for: current)
            }
            .background(Color.black)
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar, .bottomBar)
            .toolbarColorScheme(.dark, for: .navigationBar, .bottomBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let current, current.isStillInLibrary {
                        Image(systemName: "iphone")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("写真アプリにも残っています")
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    if let current {
                        if let shareURL {
                            ShareLink(item: shareURL) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        } else {
                            Image(systemName: "square.and.arrow.up").foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !current.isVideo {
                            Button {
                                // 文字の読み取り・要約は有料版の機能
                                if store.isUnlocked { showText = true } else { showUnlock = true }
                            } label: {
                                Image(systemName: "text.viewfinder")
                            }
                            .accessibilityLabel("写真の文字を読み取る")
                            Spacer()
                        }
                        Button {
                            memoText = current.memo
                            editingMemo = true
                        } label: {
                            Image(systemName: current.memo.isEmpty ? "text.bubble" : "text.bubble.fill")
                        }
                        Spacer()
                        if !current.isVideo && current.isLegacyCopy {
                            Button { rotate(current) } label: { Image(systemName: "rotate.right") }
                                .accessibilityLabel("右に回転")
                            Spacer()
                        }
                        Button { showMove = true } label: { Image(systemName: "folder") }
                        Spacer()
                        Menu {
                            if current.isLegacyCopy {
                                Button {
                                    Task { await export(current) }
                                } label: {
                                    Label("写真アプリに書き出す", systemImage: "square.and.arrow.down")
                                }
                            } else {
                                Button { confirmAppDelete = true } label: {
                                    Label("フォルダから外す（写真アプリには残す）", systemImage: "folder.badge.minus")
                                }
                            }
                            Button(role: .destructive) { confirmLibraryDelete = true } label: {
                                Label("写真アプリから削除", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .sheet(isPresented: $showText) {
                if let current { RecognizedTextSheet(item: current) }
            }
            .alert("メモ", isPresented: $editingMemo) {
                TextField("メモを入力", text: $memoText)
                Button("保存") {
                    current?.memo = memoText
                    try? context.save()
                }
                Button("キャンセル", role: .cancel) {}
            }
            .confirmationDialog("この写真を写真アプリから削除しますか？", isPresented: $confirmLibraryDelete, titleVisibility: .visible) {
                Button("写真アプリから削除", role: .destructive) {
                    if let current { Task { await deleteFromLibrary(current) } }
                }
            } message: {
                Text("このあとiPhoneの確認画面が出ます。削除した写真は写真アプリの「最近削除した項目」に30日間残ります。")
            }
            .confirmationDialog("この写真をフォルダから外しますか？", isPresented: $confirmAppDelete, titleVisibility: .visible) {
                Button("フォルダから外す", role: .destructive) {
                    if let current { deleteFromApp(current) }
                }
            } message: {
                Text("写真アプリの写真はそのまま残ります。")
            }
            .sheet(isPresented: $showUnlock) { UnlockView().environmentObject(store) }
            .sheet(isPresented: $showMove) {
                MoveSheet(currentFolder: folder) { target in
                    guard let current else { return }
                    let next = neighborID(of: current.id)
                    current.folder = target
                    try? context.save()
                    if let next { currentID = next } else { dismiss() }
                }
            }
            .alert("お知らせ", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
                Button("OK") { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private var titleText: String {
        guard let current else { return "" }
        let index = (photos.firstIndex { $0.id == current.id } ?? 0) + 1
        return "\(current.displayDate.formatted(date: .abbreviated, time: .shortened))  \(index)/\(photos.count)"
    }

    /// 写真を右に90度回転して保存する
    private func rotate(_ item: PhotoItem) {
        guard let data = item.imageData else { return }
        Task {
            let result = await Task.detached { PhotoStorage.rotated(data: data) }.value
            guard let result else { return }
            item.imageData = result.image
            item.thumbData = result.thumb
            item.fileExtension = "jpg"
            item.byteSize = result.image.count
            ThumbnailCache.shared.remove(item.id.uuidString)
            try? context.save()
        }
    }

    private func neighborID(of id: UUID) -> UUID? {
        guard let i = photos.firstIndex(where: { $0.id == id }) else { return nil }
        if i + 1 < photos.count { return photos[i + 1].id }
        if i - 1 >= 0 { return photos[i - 1].id }
        return nil
    }

    private func deleteFromApp(_ item: PhotoItem) {
        let next = neighborID(of: item.id)
        ThumbnailCache.shared.remove(item.id.uuidString)
        context.delete(item)
        try? context.save()
        if let next { currentID = next } else { dismiss() }
    }

    private func deleteFromLibrary(_ item: PhotoItem) async {
        let next = neighborID(of: item.id)
        let wasLegacy = item.isLegacyCopy
        do {
            _ = try await PhotoAssets.deleteFromLibrary([item], context: context)
            // 写真アプリから消した写真はフォルダからも外れるので、次の写真へ
            if !wasLegacy {
                if let next { currentID = next } else { dismiss() }
            }
        } catch LibraryError.cancelled {
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func export(_ item: PhotoItem) async {
        do {
            try await PhotoLibrary.exportToLibrary(items: [item])
            alertMessage = "写真アプリに書き出しました。"
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

struct FullImagePage: View {
    let item: PhotoItem
    @State private var image: UIImage?
    @State private var missing = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
            if let image {
                ZoomableImage(image: image)
            } else if missing {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text("写真アプリでこの写真が見つかりません。\n写真アプリで削除されたか、写真へのアクセスが\n許可されていない可能性があります。")
                        .multilineTextAlignment(.center)
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding()
            } else {
                ProgressView().tint(.white)
            }
            if !item.memo.isEmpty {
                Text(item.memo)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.bottom, 16)
                    .padding(.horizontal)
            }
        }
        .task(id: "\(item.id.uuidString)-\(item.byteSize)") {
            image = await PhotoAssets.displayImage(for: item)
            if image == nil { missing = true }
        }
    }
}

/// ピンチ・ダブルタップで拡大できる画像
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .black
        scrollView.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
        ])
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView, let imageView else { return }
            if scrollView.zoomScale > 1.01 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scrollView.bounds.width / 2.5, height: scrollView.bounds.height / 2.5)
                let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}
