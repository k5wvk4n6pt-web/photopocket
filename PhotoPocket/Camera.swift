import SwiftUI
import SwiftData
import Photos
import UniformTypeIdentifiers

/// フォルダの中から撮影する。撮った写真・動画は写真アプリに保存して、そのフォルダに入れる
struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: (Captured) -> Void
    var onCancel: () -> Void

    enum Captured {
        case photo(UIImage)
        case video(URL)
    }

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = (UIImagePickerController.availableMediaTypes(for: .camera) ?? [UTType.image.identifier])
            .filter { $0 == UTType.image.identifier || $0 == UTType.movie.identifier }
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL {
                parent.onCapture(.video(url))
            } else if let image = info[.originalImage] as? UIImage {
                parent.onCapture(.photo(image))
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}

enum CameraSaver {
    /// 写真アプリに保存して、フォルダに入れる。うまくいかなければ理由の文を返す
    @MainActor
    static func save(_ captured: CameraPicker.Captured, to folder: PhotoFolder, context: ModelContext) async -> String? {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized || status == .limited else {
            return "写真へのアクセスが許可されていないため、保存できませんでした。設定アプリで「写真」へのアクセスを許可してください。"
        }

        final class Box: @unchecked Sendable { var id: String? }
        let box = Box()
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                switch captured {
                case .photo(let image):
                    guard let data = image.jpegData(compressionQuality: 0.92) else { return }
                    request.addResource(with: .photo, data: data, options: nil)
                case .video(let url):
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = false
                    request.addResource(with: .video, fileURL: url, options: options)
                }
                request.creationDate = Date()
                box.id = request.placeholderForCreatedAsset?.localIdentifier
            }
        } catch {
            return "写真アプリに保存できませんでした。"
        }

        guard let localID = box.id,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localID], options: nil).firstObject,
              await PhotoAssets.makeItem(from: asset, folder: folder, context: context) != nil else {
            return "写真アプリには保存しましたが、フォルダに入れられませんでした。"
        }
        try? context.save()
        return nil
    }
}
