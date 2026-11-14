import Foundation
import SwiftUI
import SwiftData
import AVFoundation
import AVKit
import CloudKit
import Network
import Photos
import UIKit
import UniformTypeIdentifiers

// MARK: - 端末内の動画ファイル

/// 動画本体は大きいので、SwiftData（iCloud自動同期）には入れず、端末内のファイルとして置く。
/// iCloudへは VideoSync がWi-Fi接続時だけアップロードする。
enum VideoFiles {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Videos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func url(id: UUID, ext: String) -> URL {
        directory.appendingPathComponent("\(id.uuidString).\(ext)")
    }

    static func localURL(for item: PhotoItem) -> URL? {
        let url = url(id: item.id, ext: item.fileExtension)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func hasFile(_ item: PhotoItem) -> Bool { localURL(for: item) != nil }

    /// 一時ファイルを動画の置き場所へ移す
    static func store(_ temp: URL, id: UUID, ext: String) throws {
        let dest = url(id: id, ext: ext)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: temp, to: dest)
        } catch {
            try FileManager.default.copyItem(at: temp, to: dest)
        }
    }

    static func remove(id: UUID) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for f in files where f.deletingPathExtension().lastPathComponent == id.uuidString {
            try? fm.removeItem(at: f)
        }
    }

    struct Prepared {
        let poster: Data
        let thumb: Data?
        let duration: Double
        let takenAt: Date?
        let byteSize: Int
    }

    /// 動画から表示用の1コマ・サムネイル・長さ・撮影日を取り出す
    static func prepare(url: URL) async -> Prepared? {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
        var takenAt: Date?
        if let item = try? await asset.load(.creationDate) {
            takenAt = try? await item.load(.dateValue)
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1600, height: 1600)
        let time = CMTime(seconds: min(0.5, max(0, duration / 2)), preferredTimescale: 600)
        guard let cg = try? await generator.image(at: time).image else { return nil }
        let image = UIImage(cgImage: cg)
        guard let poster = image.jpegData(compressionQuality: 0.8) else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        return Prepared(poster: poster, thumb: PhotoStorage.prepare(data: poster).thumbData,
                        duration: duration, takenAt: takenAt, byteSize: size)
    }

    /// 動画ファイルから PhotoItem を作って保存する（ファイルは置き場所へ移す）
    @MainActor
    static func makeItem(from temp: URL, sourceAssetID: String?, fallbackDate: Date?, folder: PhotoFolder,
                         context: ModelContext) async -> PhotoItem? {
        guard let prepared = await prepare(url: temp) else { return nil }
        let ext = temp.pathExtension.isEmpty ? "mov" : temp.pathExtension.lowercased()
        let item = PhotoItem(videoPoster: prepared.poster, thumbData: prepared.thumb, fileExtension: ext,
                             byteSize: prepared.byteSize, duration: prepared.duration,
                             takenAt: prepared.takenAt ?? fallbackDate, sourceAssetID: sourceAssetID, folder: folder)
        do {
            try store(temp, id: item.id, ext: ext)
        } catch {
            return nil
        }
        context.insert(item)
        try? context.save()
        VideoSync.shared.kick()
        return item
    }

    /// 写真アプリの動画を一時ファイルに書き出す
    static func export(asset: PHAsset) async -> URL? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .fullSizeVideo })
                ?? resources.first(where: { $0.type == .video }) else { return nil }
        let ext = (resource.originalFilename as NSString).pathExtension.lowercased()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("video.\(ext.isEmpty ? "mov" : ext)")
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
                continuation.resume(returning: error == nil ? url : nil)
            }
        }
    }

    /// 共有用：分かりやすい名前のリンクを一時フォルダに作る
    static func shareURL(for item: PhotoItem) -> URL? {
        guard let src = localURL(for: item) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(item.id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("VID_\(f.string(from: item.displayDate)).\(item.fileExtension)")
        if !FileManager.default.fileExists(atPath: url.path) {
            do { try FileManager.default.linkItem(at: src, to: url) } catch {
                do { try FileManager.default.copyItem(at: src, to: url) } catch { return nil }
            }
        }
        return url
    }
}

/// 写真ピッカーから動画をファイルで受け取る
struct PickedVideo: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dest = dir.appendingPathComponent("video.\(ext)")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedVideo(url: dest)
        }
    }
}

// MARK: - 動画のiCloud同期（Wi-Fiのときだけ）

@MainActor
final class VideoSync: ObservableObject {
    static let shared = VideoSync()

    /// Wi-Fi（または有線）で、通信量を気にしなくてよい回線につながっている
    @Published private(set) var onWiFi = false
    @Published private(set) var waitingUploads = 0
    @Published private(set) var isUploading = false
    /// 動画ファイルが届いたら増える（再生画面の更新用）
    @Published private(set) var fileVersion = 0
    @Published private(set) var downloading: Set<UUID> = []

    private var container: ModelContainer?
    private var cloudEnabled = false
    private var running = false
    private var again = false
    private let monitor = NWPathMonitor()
    private let database = CKContainer(identifier: "iCloud.com.k5wvk4n6pt.photopocket").privateCloudDatabase
    private static let recordType = "VideoFile"
    private static let pendingDeleteKey = "videoPendingCloudDeletes"

    private init() {
        monitor.pathUpdateHandler = { path in
            let wifi = path.status == .satisfied && !path.isExpensive && !path.isConstrained
                && (path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet))
            Task { @MainActor in
                let changed = VideoSync.shared.onWiFi != wifi
                VideoSync.shared.onWiFi = wifi
                if changed && wifi { VideoSync.shared.kick() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "photopocket.network"))
    }

    func configure(container: ModelContainer, cloud: Bool) {
        self.container = container
        self.cloudEnabled = cloud
        kick()
    }

    /// 同期を試みる（何度呼んでもよい）
    func kick() {
        if running { again = true; return }
        running = true
        Task {
            repeat {
                again = false
                await runOnce()
            } while again
            running = false
        }
    }

    private var context: ModelContext? { container?.mainContext }

    private func videos() -> [PhotoItem] {
        guard let context else { return [] }
        let descriptor = FetchDescriptor<PhotoItem>(predicate: #Predicate { $0.mediaType == "video" })
        return (try? context.fetch(descriptor)) ?? []
    }

    private func runOnce() async {
        guard let context else { return }
        let items = videos()
        cleanupOrphans(existing: Set(items.map(\.id)))
        let toUpload = items.filter { !$0.videoUploaded && VideoFiles.hasFile($0) }
        waitingUploads = cloudEnabled ? toUpload.count : 0
        guard cloudEnabled else { return }

        await processCloudDeletes()
        guard onWiFi else { return }

        // アップロード（Wi-Fiのみ）
        let background = UIApplication.shared.beginBackgroundTask(withName: "video-upload")
        defer { UIApplication.shared.endBackgroundTask(background) }
        for item in toUpload {
            guard onWiFi, item.modelContext != nil else { break }
            isUploading = true
            let ok = await upload(item)
            isUploading = false
            if ok {
                item.videoUploaded = true
                try? context.save()
                waitingUploads = max(0, waitingUploads - 1)
            } else {
                break
            }
        }

        // ほかの端末で入れた動画のダウンロード（自動はWi-Fiのみ）
        for item in items where item.videoUploaded && !VideoFiles.hasFile(item) && item.modelContext != nil {
            guard onWiFi else { break }
            if !(await download(item, allowCellular: false)) { break }
        }
    }

    private func upload(_ item: PhotoItem) async -> Bool {
        guard let url = VideoFiles.localURL(for: item) else { return false }
        let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: item.id.uuidString))
        record["file"] = CKAsset(fileURL: url)
        record["ext"] = item.fileExtension as CKRecordValue
        let config = CKOperation.Configuration()
        config.allowsCellularAccess = false
        config.qualityOfService = .utility
        do {
            let result = try await database.configuredWith(configuration: config) { db in
                try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys, atomically: true)
            }
            if case .failure(let error) = result.saveResults[record.recordID] {
                print("動画のアップロードに失敗: \(error)")
                return false
            }
            return true
        } catch {
            print("動画のアップロードに失敗: \(error)")
            return false
        }
    }

    /// iCloudから動画を取ってくる。allowCellular=true は「今すぐダウンロード」を押したとき
    @discardableResult
    func download(_ item: PhotoItem, allowCellular: Bool) async -> Bool {
        guard cloudEnabled, !downloading.contains(item.id) else { return false }
        downloading.insert(item.id)
        defer { downloading.remove(item.id) }
        let id = CKRecord.ID(recordName: item.id.uuidString)
        let config = CKOperation.Configuration()
        config.allowsCellularAccess = allowCellular
        config.qualityOfService = allowCellular ? .userInitiated : .utility
        do {
            let results = try await database.configuredWith(configuration: config) { db in
                try await db.records(for: [id], desiredKeys: ["file", "ext"])
            }
            guard case .success(let record) = results[id],
                  let asset = record["file"] as? CKAsset, let file = asset.fileURL else { return false }
            let dest = VideoFiles.url(id: item.id, ext: item.fileExtension)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: file, to: dest)
            fileVersion += 1
            return true
        } catch {
            print("動画のダウンロードに失敗: \(error)")
            return false
        }
    }

    /// アプリから消えた動画のファイルを片付け、iCloud上の動画も消す
    private func cleanupOrphans(existing: Set<UUID>) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: VideoFiles.directory,
                                                      includingPropertiesForKeys: [.creationDateKey]) else { return }
        var pending = Set(UserDefaults.standard.stringArray(forKey: Self.pendingDeleteKey) ?? [])
        for f in files {
            let name = f.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: name), !existing.contains(id) else { continue }
            // 取り込み直後の保存待ちを消さないよう、10分以上たったものだけ
            let created = (try? f.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            guard Date().timeIntervalSince(created) > 600 else { continue }
            try? fm.removeItem(at: f)
            pending.insert(name)
        }
        UserDefaults.standard.set(Array(pending), forKey: Self.pendingDeleteKey)
    }

    private func processCloudDeletes() async {
        let names = UserDefaults.standard.stringArray(forKey: Self.pendingDeleteKey) ?? []
        guard !names.isEmpty else { return }
        let ids = names.map { CKRecord.ID(recordName: $0) }
        do {
            let result = try await database.modifyRecords(saving: [], deleting: ids, savePolicy: .allKeys, atomically: false)
            var done = Set<String>()
            for (id, r) in result.deleteResults {
                switch r {
                case .success: done.insert(id.recordName)
                case .failure(let error):
                    if (error as? CKError)?.code == .unknownItem { done.insert(id.recordName) }
                }
            }
            let rest = names.filter { !done.contains($0) }
            UserDefaults.standard.set(rest, forKey: Self.pendingDeleteKey)
        } catch {
            print("iCloudの動画の削除に失敗: \(error)")
        }
    }
}

// MARK: - 再生

/// アプリに取り込んだ動画の再生ページ
struct VideoPage: View {
    let item: PhotoItem
    let isCurrent: Bool
    @ObservedObject private var sync = VideoSync.shared
    @State private var player: AVPlayer?
    @State private var poster: UIImage?
    @EnvironmentObject private var store: Store

    var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
            } else {
                if let poster {
                    Image(uiImage: poster).resizable().scaledToFit()
                }
                missingNotice
            }
        }
        .task(id: "\(item.id)-\(sync.fileVersion)") {
            if let url = VideoFiles.localURL(for: item) {
                if player == nil { player = AVPlayer(url: url) }
            } else {
                let data = item.imageData
                poster = await Task.detached { PhotoStorage.displayImage(data: data) }.value
            }
        }
        .onChange(of: isCurrent) { _, current in
            if !current { player?.pause() }
        }
        .onDisappear { player?.pause() }
    }

    private var missingNotice: some View {
        VStack(spacing: 12) {
            if sync.downloading.contains(item.id) {
                ProgressView().tint(.white)
                Text("iCloudから動画を取ってきています…")
            } else if store.isUnlocked && item.videoUploaded {
                Image(systemName: "icloud.and.arrow.down").font(.largeTitle)
                Text("この動画はWi-Fiにつながると\niCloudから自動で届きます")
                    .multilineTextAlignment(.center)
                Button {
                    Task { await sync.download(item, allowCellular: true) }
                } label: {
                    Text("今すぐダウンロード（モバイル通信も使う）")
                        .font(.footnote.weight(.bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Theme.accent, in: Capsule())
                }
            } else {
                Image(systemName: "icloud.slash").font(.largeTitle)
                Text("この動画は、取り込んだiPhoneから\nまだiCloudに届いていません。\nそのiPhoneがWi-Fiにつながると届きます。")
                    .multilineTextAlignment(.center)
            }
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(.white)
        .padding(20)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
        .padding()
    }
}

/// 写真アプリの動画を再生する（仕分け中に確認する用）
struct LibraryVideoPlayer: View {
    let asset: PHAsset
    @State private var player: AVPlayer?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player).ignoresSafeArea(edges: .bottom)
            } else if failed {
                Text("動画を読み込めませんでした").foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
            }
        }
        .task {
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .automatic
            let item: AVPlayerItem? = await withCheckedContinuation { continuation in
                PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                    continuation.resume(returning: item)
                }
            }
            if let item {
                let p = AVPlayer(playerItem: item)
                player = p
                p.play()
            } else {
                failed = true
            }
        }
        .onDisappear { player?.pause() }
    }
}

/// 長さ表示のバッジ（▶︎ 0:32）
struct VideoBadge: View {
    let text: String
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "play.fill").font(.system(size: 8, weight: .bold))
            Text(text).font(.system(size: 10, weight: .bold)).monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.black.opacity(0.55), in: Capsule())
    }
}
