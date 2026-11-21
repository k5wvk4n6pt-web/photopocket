import Foundation
import SwiftData

/// テスト版だけの「録画用の空のデータ」
/// いつものデータとは別のファイルに保存し、iCloudにも送らない。オフに戻すといつものデータに戻る
enum DemoData {
    static let key = "demoEmptyData"

    static var isOn: Bool {
        UnlockView.isTestBuild && UserDefaults.standard.bool(forKey: key)
    }

    static func makeContainer(schema: Schema) -> ModelContainer? {
        let dir = URL.applicationSupportDirectory.appending(path: "Demo", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = ModelConfiguration("demo", schema: schema,
                                        url: dir.appending(path: "demo.store"),
                                        cloudKitDatabase: .none)
        return try? ModelContainer(for: schema, configurations: config)
    }

    /// 録画用のデータを空に戻す（次にオンにしたとき、また何もない状態から始められる）
    static func erase() {
        let dir = URL.applicationSupportDirectory.appending(path: "Demo", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: dir)
    }
}
