# フォトポケット（仮）

iPhoneの写真を「分類 → フォルダ」で整理するアプリ（SwiftUI / iOS 17以上）。

## できること
- 分類（例：子ども・家族・書類）を作り、その中にフォルダ（例：運動会・作品）を作る
- フォルダの「取り込む」ボタンから写真アプリの写真を複数選んで取り込む（HEICのまま画質を落とさず保存）
- 取り込んだあと「写真アプリから削除する／残す」を選べる
  - 設定で「毎回たずねる／いつも残す／いつも削除する」を切り替えられる
  - 削除するときは必ずiPhoneの確認画面が出る。削除した写真は「最近削除した項目」に30日残る
  - 残した写真には📱マークが付き、あとから1枚ずつ・まとめて削除もできる
- 写真の拡大表示（左右スワイプ・ピンチ・ダブルタップ）、メモ、別フォルダへの移動、共有
- 写真アプリへの書き戻し（アプリを消す前のバックアップ用）
- 分類を削除しても中のフォルダは「未分類」に移るだけで消えない
- **iCloud同期（有料・買い切り）**：写真・分類・フォルダ・メモが自分のiCloudに保存される。無料版は端末内のみ保存。購入すると、それまでに整理した写真もそのままiCloudへ送られる。同じApple IDのiPhone/iPadで共有でき、アプリを入れ直しても戻る（iCloudの容量を使用）

## ファイル構成
```
project.yml                 XcodeGenの設定（バンドルIDはここで変更）
PhotoPocket/
  PhotoPocketApp.swift      起動
  Models.swift              分類・フォルダ・写真のデータ（SwiftData）
  PhotoStorage.swift        サムネイル作成・表示用の縮小・撮影日
  PhotoLibrary.swift        写真アプリからの取り込み・削除・書き出し
  RootView.swift            ホーム（分類とフォルダの一覧）
  FolderView.swift          フォルダの中身・取り込み・選択操作
  PhotoViewer.swift         写真の拡大表示
  Editors.swift             分類／フォルダの作成・編集、移動先の選択
  SettingsView.swift        設定
  Assets.xcassets           アプリアイコン
.github/workflows/ios.yml   GitHub Actionsでビルド・TestFlight送信
ExportOptions.plist         App Store Connect送信用の設定
```

## Macなしでビルドする手順（GitHub Actions）
1. **App Store Connect** でバンドルIDを登録してアプリを作成し、`project.yml` の `PRODUCT_BUNDLE_IDENTIFIER` を同じ値に書き換える
   - `ICLOUD_CONTAINER` も `iCloud.` ＋ バンドルID に書き換える
   - Apple Developer サイト →「Certificates, Identifiers & Profiles」→「Identifiers」
     - 右上のプルダウンを「iCloud Containers」にして ＋ → 上と同じコンテナIDを登録
     - App IDs に戻ってこのアプリのIDを開き、「iCloud」にチェック →「Edit」で上のコンテナを選んで保存
     - 同じ画面で「Push Notifications」にもチェック（iCloudの変更通知に使う）
2. App Store Connect →「ユーザとアクセス」→「統合」→「App Store Connect API」で **管理（Admin）権限のキー** を作成し、.p8ファイルをダウンロード
3. GitHubに新しいリポジトリを作ってこのフォルダの中身をアップロード
4. リポジトリの Settings → Secrets and variables → Actions に次を登録
   | 名前 | 値 |
   |---|---|
   | `ASC_KEY_ID` | APIキーのキーID |
   | `ASC_ISSUER_ID` | 発行者ID（Issuer ID） |
   | `ASC_KEY_P8` | .p8ファイルの中身をまるごと貼り付け |
   | `TEAM_ID` | Apple DeveloperのチームID（10桁） |
5. Actions タブ →「iOS Build」→「Run workflow」で実行すると、署名してTestFlightに送信される
   - mainにpushするたびに、署名なしのビルド確認だけが自動で走る
6. 数分〜数十分後、iPhoneのTestFlightアプリからインストールして試す

## 買い切り課金（iCloud同期）の設定
1. App Store Connect → このアプリ →「App内課金」→ ＋ →種類は **非消耗型**
   - 製品ID：`com.example.photopocket.icloud`（`Store.swift` の `iCloudProductID` と同じにする。バンドルIDを変えたらこちらも合わせる）
   - 価格・表示名（例：iCloud同期）・説明・審査用スクリーンショット（購入画面のスクショでOK）を入力
2. 最初の審査では、アプリ本体と一緒にこのApp内課金も提出する（バージョンの画面の「App内課金」欄で選ぶ）
3. 「契約/税金/口座情報」で有料アプリ契約が有効になっていること
4. TestFlight版では購入してもお金はかからない（テスト購入になる）

## iCloud（CloudKit）の初回設定 ※最初の1回だけ
iCloudには「開発用（Development）」と「本番用（Production）」の2つの保存場所があり、
本番用にはデータの形（スキーマ）を先に登録しておく必要があります。Macなしでは次の手順で行います。

1. Actions →「Run workflow」で **cloudkit_env を Development** にして実行
2. TestFlightで入れたアプリで、設定 →「iCloud同期を使う」でテスト購入し、分類とフォルダを作り、写真を1枚取り込み、メモも1つ書く（データの形がiCloudに登録される）
3. ブラウザで https://icloud.developer.apple.com を開き、CloudKit Console →
   このアプリのコンテナ →「Schema」→ **Deploy Schema Changes…** → Deploy（本番へ反映）
4. もう一度 Actions →「Run workflow」を **cloudkit_env を Production** で実行。以後はこのビルドを使う・審査に出す
   （Development版で作ったテストデータは本番には引き継がれません）

あとでデータの項目を増やしたときも、同じ手順（Developmentで動かす → Deploy → Production）が必要です。

## App Store審査で聞かれやすい点
- 写真アクセスの用途説明文は `project.yml` の `NSPhotoLibraryUsageDescription` / `NSPhotoLibraryAddUsageDescription`
- データは本人のiCloud（プライベートデータベース）にのみ保存され、開発者は見られない → App Privacyは「データの収集なし」で申告可能
