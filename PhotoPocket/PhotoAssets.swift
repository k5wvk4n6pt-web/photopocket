import Foundation
import Photos
import UIKit
import AVFoundation
import SwiftData

/// 写真アプリの写真を「参照」として扱うための道具
///
/// フォトポケットは写真の本体をコピーせず、写真アプリのどの写真かを覚えておくだけにする。
/// こうしておけば、アプリを消しても写真は写真アプリに残る。
/// （古いバージョンで取り込んだ写真は imageData に本体を持っている。これを「旧形式」と呼ぶ）
enum PhotoAssets {
    // MARK: - 写真アプリの写真を探す

    /// 端末をまたいでも同じ写真を指せるID（iCloud写真のID）
    static func cloudID(for localID: String) -> String? {
        let map = PHPhotoLibrary.shared().cloudIdentifierMappings(forLocalIdentifiers: [localID])
        if case .success(let cloud)? = map[localID] { return cloud.stringValue }
        return nil
    }

    /// この端末の写真アプリでのID
    static func localID(for item: PhotoItem) -> String? {
        if item.importDeviceID == DeviceID.current, let id = item.sourceAssetID { return id }
        guard let cloud = item.cloudAssetID else { return item.sourceAssetID }
        let cid = PHCloudIdentifier(stringValue: cloud)
        let map = PHPhotoLibrary.shared().localIdentifierMappings(for: [cid])
        if case .success(let local)? = map[cid] { return local }
        return nil
    }

    static func asset(for item: PhotoItem) -> PHAsset? {
        guard let id = localID(for: item) else { return nil }
        return PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// 写真を見るための許可（読み取り）を確認・要求する
    @discardableResult
    static func ensureReadAccess() async -> Bool {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        return status == .authorized || status == .limited
    }

    // MARK: - フォルダに登録する

    /// 写真アプリの写真・動画を、コピーせずにフォルダへ登録する
    @MainActor
    static func makeItem(from asset: PHAsset, folder: PhotoFolder, context: ModelContext) async -> PhotoItem? {
        guard let thumb = await image(for: asset, maxPixel: 420) else { return nil }
        let item = PhotoItem(
            referenceTo: asset.localIdentifier,
            cloudAssetID: cloudID(for: asset.localIdentifier),
            thumbData: thumb.jpegData(compressionQuality: 0.75),
            takenAt: asset.creationDate,
            isVideo: asset.mediaType == .video,
            duration: asset.duration,
            folder: folder
        )
        context.insert(item)
        return item
    }

    // MARK: - 表示・共有

    /// 写真アプリの写真を指定の大きさで読み込む
    static func image(for asset: PHAsset, maxPixel: CGFloat) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: maxPixel, height: maxPixel),
                contentMode: .aspectFit, options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// 大きく表示する画像（旧形式なら中のデータ、参照なら写真アプリから）
    static func displayImage(for item: PhotoItem, maxPixel: Int = 2800) async -> UIImage? {
        if item.isLegacyCopy, let data = item.imageData {
            return await Task.detached { PhotoStorage.displayImage(data: data, maxPixel: maxPixel) }.value
        }
        guard let asset = asset(for: item) else { return nil }
        return await image(for: asset, maxPixel: CGFloat(maxPixel))
    }

    /// 文字の読み取りなどに使う元の画像データ
    static func imageData(for item: PhotoItem) async -> Data? {
        if item.isLegacyCopy, let data = item.imageData { return data }
        guard let asset = asset(for: item) else { return nil }
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.version = .current
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// 動画を再生するためのデータ
    static func playerItem(for item: PhotoItem) async -> AVPlayerItem? {
        guard let asset = asset(for: item) else { return nil }
        return await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .automatic
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { playerItem, _ in
                continuation.resume(returning: playerItem)
            }
        }
    }

    /// 共有用の一時ファイルを作る
    static func shareFile(for item: PhotoItem) async -> URL? {
        if item.isLegacyCopy {
            if item.isVideo { return VideoFiles.shareURL(for: item) }
            let id = item.id, data = item.imageData, ext = item.fileExtension, date = item.displayDate
            return await Task.detached { PhotoStorage.temporaryFile(id: id, data: data, fileExtension: ext, date: date) }.value
        }
        guard let asset = asset(for: item) else { return nil }
        let resources = PHAssetResource.assetResources(for: asset)
        let preferred: [PHAssetResourceType] = item.isVideo ? [.fullSizeVideo, .video] : [.fullSizePhoto, .photo]
        guard let resource = preferred.lazy.compactMap({ type in resources.first { $0.type == type } }).first
                ?? resources.first else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(item.id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(resource.originalFilename)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        do {
            try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - 写真アプリから削除

    /// 写真アプリから削除し、フォルダからも外す（iPhoneの確認画面が出る）
    @MainActor
    static func deleteFromLibrary(_ items: [PhotoItem], context: ModelContext) async throws -> Int {
        var idsByItem: [(PhotoItem, String)] = []
        var notFound: [PhotoItem] = []
        for item in items {
            if let id = localID(for: item) { idsByItem.append((item, id)) } else { notFound.append(item) }
        }
        let deleted = try await PhotoLibrary.deleteFromLibrary(identifiers: idsByItem.map(\.1))
        for (item, id) in idsByItem where deleted.contains(id) || !item.isLegacyCopy {
            // 旧形式で写真アプリに見つからなかったものは、アプリ内の写真が唯一の本体なので消さない
            ThumbnailCache.shared.remove(item.id.uuidString)
            context.delete(item)
        }
        try? context.save()
        return deleted.count
    }

    // MARK: - 旧形式からの切り替え

    /// 旧形式（アプリ内に本体を持つ）の写真
    static func legacyItems(in context: ModelContext) -> [PhotoItem] {
        let descriptor = FetchDescriptor<PhotoItem>(predicate: #Predicate { $0.byteSize > 0 })
        return (try? context.fetch(descriptor)) ?? []
    }

    struct MigrationResult {
        var converted = 0
        var restored = 0
        var skipped = 0
    }

    /// 旧形式の写真を、写真アプリの写真を指す形に切り替える
    /// ・写真アプリに残っている → そのまま参照に切り替える（アプリ内のコピーは消す）
    /// ・写真アプリから消してある → 写真アプリに戻してから参照に切り替える
    @MainActor
    static func migrate(context: ModelContext, progress: (Int, Int) -> Void) async throws -> MigrationResult {
        try await PhotoLibrary.ensureFullAccess()
        let items = legacyItems(in: context)
        var result = MigrationResult()
        for (n, item) in items.enumerated() {
            progress(n, items.count)
            // 1) 写真アプリにまだ残っているか
            if !item.deletedFromLibrary, item.importDeviceID == DeviceID.current, let id = item.sourceAssetID,
               PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject != nil {
                convert(item, to: id)
                result.converted += 1
                continue
            }
            // 2) 写真アプリに戻す
            guard let newID = try await restoreToLibrary(item) else {
                result.skipped += 1
                continue
            }
            convert(item, to: newID)
            result.restored += 1
            try? context.save()
        }
        try? context.save()
        progress(items.count, items.count)
        return result
    }

    @MainActor
    private static func convert(_ item: PhotoItem, to localID: String) {
        item.sourceAssetID = localID
        item.cloudAssetID = cloudID(for: localID)
        item.importDeviceID = DeviceID.current
        item.deletedFromLibrary = false
        item.imageData = nil
        item.byteSize = 0
        // 動画ファイルは、動画の同期処理が後で片付ける（iCloud上の動画も消える）
    }

    /// アプリ内の写真・動画を写真アプリに保存し、新しいIDを返す
    @MainActor
    private static func restoreToLibrary(_ item: PhotoItem) async throws -> String? {
        var newID: String?
        if item.isVideo {
            guard let url = VideoFiles.localURL(for: item) else { return nil }
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: .video, fileURL: url, options: options)
                request.creationDate = item.takenAt
                newID = request.placeholderForCreatedAsset?.localIdentifier
            }
        } else {
            guard let data = item.imageData else { return nil }
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
                newID = request.placeholderForCreatedAsset?.localIdentifier
            }
        }
        return newID
    }
}

/// 無料版の上限
enum FreeLimit {
    static let folders = 3
    static let photos = 30

    static func photoCount(in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<PhotoItem>())) ?? 0
    }

    static func folderCount(in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<PhotoFolder>())) ?? 0
    }

    /// あと何枚フォルダに入れられるか（有料版なら上限なし）
    @MainActor
    static func remainingPhotos(store: Store, context: ModelContext) -> Int {
        store.isUnlocked ? Int.max : max(0, photos - photoCount(in: context))
    }

    @MainActor
    static func canAddFolder(store: Store, context: ModelContext) -> Bool {
        store.isUnlocked || folderCount(in: context) < folders
    }
}
