import SwiftUI
import UIKit
import Photos

/// 写真アプリの写真を一覧で表示し、指でなぞってまとめて選べるグリッド
/// ・タップ：選ぶ／外す
/// ・横になぞる：なぞった範囲をまとめて選ぶ（そのまま上下に動かすと範囲が広がる。端に近づくと自動スクロール）
/// ・長押し：大きく表示
struct LibraryGrid: UIViewRepresentable {
    let assets: [PHAsset]
    @Binding var selected: Set<String>
    var onPreview: (PHAsset) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 2
        layout.minimumLineSpacing = 2
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.alwaysBounceVertical = true
        cv.contentInset = UIEdgeInsets(top: 2, left: 0, bottom: 8, right: 0)
        cv.register(LibraryGridCell.self, forCellWithReuseIdentifier: "cell")
        cv.dataSource = context.coordinator
        cv.delegate = context.coordinator
        cv.prefetchDataSource = context.coordinator

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        cv.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        cv.addGestureRecognizer(tap)

        let long = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        long.minimumPressDuration = 0.45
        cv.addGestureRecognizer(long)

        context.coordinator.collectionView = cv
        return cv
    }

    func updateUIView(_ cv: UICollectionView, context: Context) {
        let c = context.coordinator
        c.parent = self
        let ids = assets.map(\.localIdentifier)
        if ids != c.ids {
            c.ids = ids
            c.assets = assets
            cv.reloadData()
        } else {
            c.refreshVisibleSelection()
        }
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout,
                             UICollectionViewDataSourcePrefetching, UIGestureRecognizerDelegate {
        var parent: LibraryGrid
        var assets: [PHAsset] = []
        var ids: [String] = []
        weak var collectionView: UICollectionView?
        let manager = PHCachingImageManager()

        // なぞって選ぶ
        private var panStart: Int?
        private var panSelecting = true
        private var panBase: Set<String> = []
        private var lastPoint: CGPoint = .zero
        private var autoScroll: CADisplayLink?
        private var autoScrollSpeed: CGFloat = 0
        private var ignoreTap = false

        init(_ parent: LibraryGrid) { self.parent = parent }

        private var thumbSize: CGSize {
            let scale = UIScreen.main.scale
            return CGSize(width: 200 * scale / 2, height: 200 * scale / 2)
        }

        // MARK: データ

        func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int { assets.count }

        func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! LibraryGridCell
            let asset = assets[indexPath.item]
            cell.assetID = asset.localIdentifier
            cell.imageView.image = nil
            cell.setVideo(asset.mediaType == .video ? SwipeSortView.durationText(asset.duration) : nil)
            cell.setSelected(parent.selected.contains(asset.localIdentifier))
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            manager.requestImage(for: asset, targetSize: thumbSize, contentMode: .aspectFill, options: options) { image, _ in
                if cell.assetID == asset.localIdentifier { cell.imageView.image = image }
            }
            return cell
        }

        func collectionView(_ cv: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            let list = indexPaths.compactMap { $0.item < assets.count ? assets[$0.item] : nil }
            manager.startCachingImages(for: list, targetSize: thumbSize, contentMode: .aspectFill, options: nil)
        }

        func collectionView(_ cv: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
            let columns: CGFloat = 4
            let w = floor((cv.bounds.width - 2 * (columns - 1)) / columns)
            return CGSize(width: w, height: w)
        }

        func refreshVisibleSelection() {
            guard let cv = collectionView else { return }
            for case let cell as LibraryGridCell in cv.visibleCells {
                if let id = cell.assetID { cell.setSelected(parent.selected.contains(id)) }
            }
        }

        private func index(at point: CGPoint) -> Int? {
            guard let cv = collectionView else { return nil }
            if let ip = cv.indexPathForItem(at: point) { return ip.item }
            // すき間に指があるときは、いちばん近いセル
            let near = cv.indexPathsForVisibleItems.min { a, b in
                guard let fa = cv.layoutAttributesForItem(at: a)?.center,
                      let fb = cv.layoutAttributesForItem(at: b)?.center else { return false }
                return hypot(fa.x - point.x, fa.y - point.y) < hypot(fb.x - point.x, fb.y - point.y)
            }
            return near?.item
        }

        // MARK: タップ・長押し

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            if ignoreTap { ignoreTap = false; return }
            guard let cv = collectionView, let ip = cv.indexPathForItem(at: g.location(in: cv)) else { return }
            let id = assets[ip.item].localIdentifier
            var s = parent.selected
            if s.contains(id) { s.remove(id) } else { s.insert(id) }
            parent.selected = s
            UISelectionFeedbackGenerator().selectionChanged()
        }

        @objc func handleLongPress(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let cv = collectionView,
                  let ip = cv.indexPathForItem(at: g.location(in: cv)) else { return }
            ignoreTap = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.ignoreTap = false }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            parent.onPreview(assets[ip.item])
        }

        // MARK: なぞって選ぶ

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer, let cv = collectionView else { return true }
            // 横向きに動かし始めたときだけ選択。縦はふつうのスクロール
            let v = pan.velocity(in: cv)
            return abs(v.x) > abs(v.y)
        }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard let cv = collectionView else { return }
            let point = g.location(in: cv)
            switch g.state {
            case .began:
                guard let start = index(at: point) else { return }
                panStart = start
                panBase = parent.selected
                panSelecting = !panBase.contains(assets[start].localIdentifier)
                cv.isScrollEnabled = false
                applyRange(to: start)
                UISelectionFeedbackGenerator().selectionChanged()
            case .changed:
                lastPoint = point
                if let i = index(at: point) { applyRange(to: i) }
                updateAutoScroll(g.location(in: cv.superview ?? cv))
            default:
                panStart = nil
                cv.isScrollEnabled = true
                stopAutoScroll()
            }
        }

        private func applyRange(to end: Int) {
            guard let start = panStart else { return }
            var s = panBase
            for i in min(start, end)...max(start, end) where i < assets.count {
                let id = assets[i].localIdentifier
                if panSelecting { s.insert(id) } else { s.remove(id) }
            }
            if s != parent.selected {
                parent.selected = s
                refreshVisibleSelection()
            }
        }

        private func updateAutoScroll(_ pointInSuper: CGPoint) {
            guard let cv = collectionView else { return }
            let frame = cv.frame
            let edge: CGFloat = 70
            if pointInSuper.y < frame.minY + edge {
                autoScrollSpeed = -max(4, (frame.minY + edge - pointInSuper.y) / 3)
            } else if pointInSuper.y > frame.maxY - edge {
                autoScrollSpeed = max(4, (pointInSuper.y - (frame.maxY - edge)) / 3)
            } else {
                autoScrollSpeed = 0
            }
            if autoScrollSpeed != 0 && autoScroll == nil {
                let link = CADisplayLink(target: self, selector: #selector(stepAutoScroll))
                link.add(to: .main, forMode: .common)
                autoScroll = link
            } else if autoScrollSpeed == 0 {
                stopAutoScroll()
            }
        }

        @objc private func stepAutoScroll() {
            guard let cv = collectionView, panStart != nil else { stopAutoScroll(); return }
            let minY = -cv.adjustedContentInset.top
            let maxY = max(minY, cv.contentSize.height - cv.bounds.height + cv.adjustedContentInset.bottom)
            let newY = min(maxY, max(minY, cv.contentOffset.y + autoScrollSpeed))
            let dy = newY - cv.contentOffset.y
            guard dy != 0 else { return }
            cv.contentOffset.y = newY
            lastPoint.y += dy
            if let i = index(at: lastPoint) { applyRange(to: i) }
        }

        private func stopAutoScroll() {
            autoScroll?.invalidate()
            autoScroll = nil
            autoScrollSpeed = 0
        }
    }
}

final class LibraryGridCell: UICollectionViewCell {
    var assetID: String?
    let imageView = UIImageView()
    private let shade = UIView()
    private let check = UIImageView()
    private let videoLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = UIColor.systemPink.withAlphaComponent(0.08)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        for v in [imageView, shade, check, videoLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(v)
        }
        shade.backgroundColor = UIColor.white.withAlphaComponent(0.35)
        shade.layer.borderColor = UIColor(red: 0.95, green: 0.40, blue: 0.54, alpha: 1).cgColor
        shade.layer.borderWidth = 3
        check.image = UIImage(systemName: "checkmark.circle.fill")
        check.tintColor = UIColor(red: 0.95, green: 0.40, blue: 0.54, alpha: 1)
        check.backgroundColor = .white
        check.layer.cornerRadius = 11
        check.clipsToBounds = true
        videoLabel.font = .systemFont(ofSize: 11, weight: .bold)
        videoLabel.textColor = .white
        videoLabel.shadowColor = UIColor.black.withAlphaComponent(0.6)
        videoLabel.shadowOffset = CGSize(width: 0, height: 1)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            shade.topAnchor.constraint(equalTo: contentView.topAnchor),
            shade.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            shade.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            shade.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            check.widthAnchor.constraint(equalToConstant: 22),
            check.heightAnchor.constraint(equalToConstant: 22),
            check.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            check.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            videoLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            videoLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),
        ])
        setSelected(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setSelected(_ on: Bool) {
        shade.isHidden = !on
        check.isHidden = !on
    }

    func setVideo(_ text: String?) {
        videoLabel.isHidden = text == nil
        videoLabel.text = text.map { "▶︎ \($0)" }
    }
}
