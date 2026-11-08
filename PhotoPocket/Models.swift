import Foundation
import SwiftData
import SwiftUI
import UIKit

// iCloud（CloudKit）同期のルール：
// ・すべての項目に初期値を付ける（または Optional）
// ・リレーションは Optional
// ・@Attribute(.unique) は使わない

/// 分類（例：家族、子ども、書類、旅行）
@Model
final class PhotoCategory {
    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "square.grid.2x2"
    var colorName: String = "pink"
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    // 分類を消しても中のフォルダは消さずに「未分類」へ移す
    @Relationship(deleteRule: .nullify, inverse: \PhotoFolder.category)
    var folders: [PhotoFolder]? = []

    init(name: String, symbol: String = "square.grid.2x2", colorName: String = "pink", sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.symbol = symbol
        self.colorName = colorName
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    var folderArray: [PhotoFolder] { folders ?? [] }

    var color: Color { FolderColor.color(named: colorName) }

    /// 分類の中のすべての写真（新しい順）
    var allPhotos: [PhotoItem] {
        folderArray.flatMap(\.photoArray).sorted { $0.displayDate > $1.displayDate }
    }

    var sortedFolders: [PhotoFolder] {
        folderArray.sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
    }
}

/// フォルダ（写真が入る場所）
@Model
final class PhotoFolder {
    var id: UUID = UUID()
    var name: String = ""
    var colorName: String = "orange"
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var category: PhotoCategory?

    @Relationship(deleteRule: .cascade, inverse: \PhotoItem.folder)
    var photos: [PhotoItem]? = []

    init(name: String, category: PhotoCategory?, colorName: String = "orange", sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.category = category
        self.colorName = colorName
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    var color: Color { FolderColor.color(named: colorName) }

    var photoArray: [PhotoItem] { photos ?? [] }

    /// 撮影日の新しい順
    var sortedPhotos: [PhotoItem] {
        photoArray.sorted { $0.displayDate > $1.displayDate }
    }
}

/// 取り込んだ写真1枚（画像そのものもiCloudに同期される）
@Model
final class PhotoItem {
    var id: UUID = UUID()
    /// 元の画像データ（HEIC/JPEGなど）。大きいデータは自動で別ファイル管理・iCloudにはアセットとして保存される
    @Attribute(.externalStorage) var imageData: Data?
    /// 一覧表示用の小さな画像
    @Attribute(.externalStorage) var thumbData: Data?
    var fileExtension: String = "jpg"
    var byteSize: Int = 0
    var takenAt: Date?
    var importedAt: Date = Date()
    var memo: String = ""
    /// 写真から読み取った文字（OCR）
    var recognizedText: String = ""
    /// 文字の読み取りを済ませたか
    var textRecognized: Bool = false
    /// 取り込み元の写真アプリ上のID（端末ごとに違うIDなので、取り込んだ端末でのみ使う）
    var sourceAssetID: String?
    /// 取り込んだ端末の識別子
    var importDeviceID: String?
    /// 写真アプリから削除済みか
    var deletedFromLibrary: Bool = false
    var folder: PhotoFolder?

    init(imageData: Data, thumbData: Data?, fileExtension: String, takenAt: Date?, sourceAssetID: String?, folder: PhotoFolder?) {
        self.id = UUID()
        self.imageData = imageData
        self.thumbData = thumbData
        self.fileExtension = fileExtension
        self.byteSize = imageData.count
        self.takenAt = takenAt
        self.importedAt = Date()
        self.sourceAssetID = sourceAssetID
        self.importDeviceID = DeviceID.current
        self.folder = folder
    }

    var displayDate: Date { takenAt ?? importedAt }

    /// このiPhoneの写真アプリにまだ残っている（はず）
    var isStillInLibrary: Bool {
        sourceAssetID != nil && !deletedFromLibrary && importDeviceID == DeviceID.current
    }
}

enum DeviceID {
    /// このアプリ×この端末で固定のID
    static let current: String = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
}

struct FolderColorOption {
    let name: String
    let label: String
    let color: Color
    init(_ name: String, _ label: String, _ color: Color) {
        self.name = name
        self.label = label
        self.color = color
    }
}

enum FolderColor {
    static let all: [FolderColorOption] = [
        FolderColorOption("orange", "オレンジ", .orange),
        FolderColorOption("pink", "ピンク", .pink),
        FolderColorOption("red", "赤", .red),
        FolderColorOption("yellow", "黄", .yellow),
        FolderColorOption("green", "緑", .green),
        FolderColorOption("mint", "ミント", .mint),
        FolderColorOption("blue", "青", .blue),
        FolderColorOption("indigo", "藍", .indigo),
        FolderColorOption("purple", "紫", .purple),
        FolderColorOption("brown", "茶", .brown),
        FolderColorOption("gray", "グレー", .gray),
    ]

    static func color(named name: String) -> Color {
        all.first { $0.name == name }?.color ?? .orange
    }
}

enum CategorySymbol {
    static let all: [String] = [
        "square.grid.2x2", "person.2.fill", "figure.and.child.holdinghands", "house.fill",
        "doc.text.fill", "airplane", "fork.knife", "pawprint.fill",
        "heart.fill", "star.fill", "camera.fill", "briefcase.fill",
        "graduationcap.fill", "gift.fill", "leaf.fill", "cart.fill",
    ]
}

/// 画面のモード（標準はライト）
enum AppearanceMode: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }
    var label: String {
        switch self {
        case .light: return "ライトモード"
        case .dark: return "ダークモード"
        case .system: return "端末に合わせる"
        }
    }
    var symbol: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .system: return "circle.lefthalf.filled"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

/// 取り込み後に写真アプリの写真をどうするか
enum DeletePolicy: String, CaseIterable, Identifiable {
    case ask, keep, delete
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ask: return "毎回たずねる"
        case .keep: return "いつも残す"
        case .delete: return "いつも削除する"
        }
    }
}
