import SwiftUI
import SwiftData
import UIKit

/// 写真を1枚ずつ大きく表示（左右スワイプ・ピンチで拡大）
struct PhotoViewer: View {
    let folder: PhotoFolder
    @State private var currentID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var showMove = false
    @State private var confirmAppDelete = false
    @State private var confirmLibraryDelete = false
    @State private var editingMemo = false
    @State private var memoText = ""
    @State private var alertMessage: String?
    @State private var shareURL: URL?

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
                    FullImagePage(item: item)
                        .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .task(id: currentID) {
                shareURL = nil
                guard let current else { return }
                let id = current.id, data = current.imageData, ext = current.fileExtension, date = current.displayDate
                shareURL = await Task.detached { PhotoStorage.temporaryFile(id: id, data: data, fileExtension: ext, date: date) }.value
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
                        Button {
                            memoText = current.memo
                            editingMemo = true
                        } label: {
                            Image(systemName: current.memo.isEmpty ? "text.bubble" : "text.bubble.fill")
                        }
                        Spacer()
                        Button { showMove = true } label: { Image(systemName: "folder") }
                        Spacer()
                        Menu {
                            Button {
                                Task { await export(current) }
                            } label: {
                                Label("写真アプリに書き出す", systemImage: "square.and.arrow.down")
                            }
                            if current.isStillInLibrary {
                                Button(role: .destructive) { confirmLibraryDelete = true } label: {
                                    Label("写真アプリから削除（アプリには残す）", systemImage: "iphone.slash")
                                }
                            }
                            Button(role: .destructive) { confirmAppDelete = true } label: {
                                Label("このアプリから削除", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
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
                Text("このアプリ内の写真はそのまま残ります。")
            }
            .confirmationDialog("この写真をアプリから削除しますか？", isPresented: $confirmAppDelete, titleVisibility: .visible) {
                Button("アプリから削除", role: .destructive) {
                    if let current { deleteFromApp(current) }
                }
            } message: {
                Text(current?.isStillInLibrary == true
                     ? "写真アプリには元の写真が残っています。"
                     : "写真アプリから削除済みのため、元に戻せません（写真アプリの「最近削除した項目」に残っている場合を除く）。")
            }
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
        guard let id = item.sourceAssetID else { return }
        do {
            _ = try await PhotoLibrary.deleteFromLibrary(identifiers: [id])
            item.deletedFromLibrary = true
            try? context.save()
        } catch LibraryError.cancelled {
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func export(_ item: PhotoItem) async {
        do {
            guard let data = item.imageData else { return }
            try await PhotoLibrary.exportToLibrary(datas: [data])
            alertMessage = "写真アプリに書き出しました。"
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

struct FullImagePage: View {
    let item: PhotoItem
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
            if let image {
                ZoomableImage(image: image)
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
        .task(id: item.id) {
            let data = item.imageData
            image = await Task.detached { PhotoStorage.displayImage(data: data) }.value
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
