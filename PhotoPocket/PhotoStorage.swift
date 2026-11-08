import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// 画像データの加工（サムネイル作成・表示用の縮小・撮影日の取得）
enum PhotoStorage {
    struct Prepared {
        let thumbData: Data?
        let fileExtension: String
        let takenAt: Date?
    }

    /// 取り込んだ元データからサムネイル等を作る
    static func prepare(data: Data) -> Prepared {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return Prepared(thumbData: nil, fileExtension: "jpg", takenAt: nil)
        }
        let thumb = downsample(source: source, maxPixel: 420)?.jpegData(compressionQuality: 0.75)
        return Prepared(thumbData: thumb, fileExtension: fileExtension(source: source), takenAt: captureDate(source: source))
    }

    static func thumbnail(id: UUID, data: Data?) -> UIImage? {
        let key = id.uuidString
        if let cached = ThumbnailCache.shared.image(key) { return cached }
        guard let data, let image = UIImage(data: data) else { return nil }
        ThumbnailCache.shared.set(image, for: key)
        return image
    }

    /// 表示用に縮小して読み込む（メモリ節約）
    static func displayImage(data: Data?, maxPixel: Int = 2800) -> UIImage? {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return downsample(source: source, maxPixel: maxPixel)
    }

    /// 共有・書き出し用に一時ファイルを作る
    static func temporaryFile(id: UUID, data: Data?, fileExtension: String, date: Date) -> URL? {
        guard let data else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("IMG_\(f.string(from: date)).\(fileExtension)")
        if !FileManager.default.fileExists(atPath: url.path) {
            do { try data.write(to: url, options: .atomic) } catch { return nil }
        }
        return url
    }

    struct Rotated: Sendable {
        let image: Data
        let thumb: Data?
    }

    /// 右に90度回転した画像を作る（JPEGで保存し直す）
    static func rotated(data: Data) -> Rotated? {
        guard let src = displayImage(data: data, maxPixel: 6000) else { return nil }
        let size = CGSize(width: src.size.height, height: src.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: size.width / 2, y: size.height / 2)
            c.rotate(by: .pi / 2)
            src.draw(in: CGRect(x: -src.size.width / 2, y: -src.size.height / 2,
                                width: src.size.width, height: src.size.height))
        }
        guard let jpg = image.jpegData(compressionQuality: 0.92) else { return nil }
        return Rotated(image: jpg, thumb: prepare(data: jpg).thumbData)
    }

    // MARK: - private

    private static func downsample(source: CGImageSource, maxPixel: Int) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    private static func fileExtension(source: CGImageSource) -> String {
        guard let typeID = CGImageSourceGetType(source) as String?,
              let type = UTType(typeID),
              let ext = type.preferredFilenameExtension else { return "jpg" }
        return ext
    }

    private static func captureDate(source: CGImageSource) -> Date? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let raw = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (tiff?[kCGImagePropertyTIFFDateTime] as? String)
        guard let raw else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f.date(from: raw)
    }
}

final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()
    init() { cache.countLimit = 600 }
    func image(_ key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func set(_ image: UIImage, for key: String) { cache.setObject(image, forKey: key as NSString) }
    func remove(_ key: String) { cache.removeObject(forKey: key as NSString) }
}
