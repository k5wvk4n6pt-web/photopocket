import Foundation
import Photos
import PhotosUI
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum LibraryError: LocalizedError {
    case noFullAccess
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noFullAccess:
            return "写真アプリから削除するには、写真へのフルアクセスが必要です。「設定」アプリ →「フォトポケット」→「写真」で「フルアクセス」を選んでください。"
        case .cancelled:
            return "削除をキャンセルしました。写真アプリの写真はそのまま残っています。"
        }
    }
}

/// iPhoneの写真アプリ（写真ライブラリ）とのやりとり
enum PhotoLibrary {
    /// 削除に必要なフルアクセスを確認・要求
    static func ensureFullAccess() async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized else { throw LibraryError.noFullAccess }
    }

    /// 写真アプリから削除する。iPhoneが確認画面を出し、削除した写真は「最近削除した項目」に30日間残る。
    /// - Returns: 実際に削除したローカルID
    static func deleteFromLibrary(identifiers: [String]) async throws -> Set<String> {
        guard !identifiers.isEmpty else { return [] }
        try await ensureFullAccess()
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        guard assets.count > 0 else { return [] }
        var found = Set<String>()
        assets.enumerateObjects { asset, _, _ in found.insert(asset.localIdentifier) }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
        } catch {
            let ns = error as NSError
            if ns.domain == PHPhotosErrorDomain && ns.code == PHPhotosError.Code.userCancelled.rawValue {
                throw LibraryError.cancelled
            }
            // 確認画面で「許可しない」を押した場合もここに来る
            if ns.code == 3072 { throw LibraryError.cancelled }
            throw error
        }
        return found
    }

    /// まだ写真アプリに存在するIDだけを返す
    static func existingIdentifiers(_ identifiers: [String]) async throws -> Set<String> {
        try await ensureFullAccess()
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var found = Set<String>()
        assets.enumerateObjects { asset, _, _ in found.insert(asset.localIdentifier) }
        return found
    }

    /// アプリ内の写真を写真アプリに書き出す（追加のみの権限でOK）
    static func exportToLibrary(items: [PhotoItem]) async throws {
        var photos: [Data] = []
        var videos: [URL] = []
        var missing = 0
        for item in items {
            if item.isVideo {
                if let url = VideoFiles.localURL(for: item) { videos.append(url) } else { missing += 1 }
            } else if let data = item.imageData {
                photos.append(data)
            }
        }
        try await exportToLibrary(datas: photos, videoURLs: videos)
        if missing > 0 {
            throw NSError(domain: "PhotoPocket", code: 2, userInfo: [NSLocalizedDescriptionKey:
                "\(missing)本の動画は、まだこのiPhoneに届いていないため書き出せませんでした。ほかは書き出しました。"])
        }
    }

    static func exportToLibrary(datas: [Data], videoURLs: [URL] = []) async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "PhotoPocket", code: 1, userInfo: [NSLocalizedDescriptionKey: "写真への追加が許可されていません。「設定」アプリで許可してください。"])
        }
        try await PHPhotoLibrary.shared().performChanges {
            for data in datas {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
            for url in videoURLs {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: .video, fileURL: url, options: options)
            }
        }
    }
}

/// 写真アプリの写真をフォルダに登録する処理（写真はコピーしない）
@MainActor
final class PhotoImporter: ObservableObject {
    @Published var isImporting = false
    @Published var done = 0
    @Published var total = 0

    struct Result {
        var importedItems: [PhotoItem] = []
        var failed = 0
        /// 無料版の上限で入れられなかった枚数
        var overLimit = 0
    }

    /// - Parameter limit: 入れられる最大枚数（無料版の上限）
    func importItems(_ pickerItems: [PhotosPickerItem], into folder: PhotoFolder, context: ModelContext,
                     limit: Int = .max) async -> Result {
        var result = Result()
        let ids = pickerItems.compactMap(\.itemIdentifier)
        result.failed = pickerItems.count - ids.count
        let allowed = Array(ids.prefix(limit))
        result.overLimit = ids.count - allowed.count
        guard !allowed.isEmpty else { return result }

        isImporting = true
        done = 0
        total = allowed.count
        defer { isImporting = false }

        guard await PhotoAssets.ensureReadAccess() else {
            result.failed += allowed.count
            return result
        }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: allowed, options: nil)
        var byID: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }

        for id in allowed {
            if let asset = byID[id], let item = await PhotoAssets.makeItem(from: asset, folder: folder, context: context) {
                result.importedItems.append(item)
            } else {
                result.failed += 1
            }
            done += 1
        }
        try? context.save()
        return result
    }
}
