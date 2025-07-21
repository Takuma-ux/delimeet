# 開発ルール (rules.md)

## 重要なルール

### 1. 修正作業の分離
- **マッチ画面（`match_detail_page.dart`）の修正中は、グループ画面（`group_chat_page.dart`）の修正を禁止する**
- 一つの画面の修正作業が完了してから次の画面の修正に移る
- 複数画面を同時に修正すると、問題の根本原因の特定が困難になるため

### 2. データベース整合性
- message_typeの変更は全体の整合性を保つため、段階的に実施する
- 新しいmessage_type値を追加する場合は、データベースの制約も同時に更新する

### 3. デバッグ時の優先順位
1. Firebase Functionsのログ確認
2. データベース制約エラーの解決
3. アプリ側のロジック修正
4. UI状態の確認

### 4. Firebase Functions デプロイルール

#### 4.1 基本原則
- **関数デプロイ時は修正した関数だけをデプロイする**
- 全関数をデプロイすると時間とリソースの無駄になる
- デプロイ前に関数名を正確に確認する

#### 4.2 デプロイコマンド例

**単一関数のデプロイ**
```bash
# ユーザー検索関数のデプロイ（今回修正）
firebase deploy --only functions:searchUsers

# レストラン検索関数のデプロイ
firebase deploy --only functions:searchRestaurants

# 退会機能のデプロイ
firebase deploy --only functions:deactivateUserAccount,functions:reactivateUserAccount

# その他の主要関数
firebase deploy --only functions:getUserProfile
firebase deploy --only functions:updateUserProfile
firebase deploy --only functions:addUserLike
firebase deploy --only functions:addRestaurantLike
firebase deploy --only functions:respondToMatchRestaurantVoting
```

**複数関数の同時デプロイ**
```bash
# ユーザー関連の関数をまとめてデプロイ
firebase deploy --only functions:searchUsers,functions:getUserProfile,functions:updateUserProfile

# レストラン関連の関数をまとめてデプロイ
firebase deploy --only functions:searchRestaurants,functions:addRestaurantLike,functions:getRestaurantRecommendations

# 退会機能関連の関数をまとめてデプロイ
firebase deploy --only functions:deactivateUserAccount,functions:reactivateUserAccount
```

#### 4.3 デプロイ前の確認手順
1. **関数名の確認**: `functions/src/index.ts`で`export const 関数名`を確認
2. **ビルドテスト**: `npm run build`でTypeScriptエラーがないことを確認
3. **ローカルテスト** (任意): `npm run serve`でローカル環境でのテスト
4. **デプロイ実行**: 上記コマンドでデプロイ

#### 4.4 デプロイ後の確認
- Firebase Consoleの関数ログで正常にデプロイされたことを確認
- アプリ側で該当機能をテストして動作確認

### 5. エラー対応手順
- データベース制約エラーが発生した場合は、まずSupabaseで制約を修正してから、コード修正を行う
- 文字数制限エラーの場合は、データベース側のVARCHAR制限を適切な値に変更する

### 6. 退会機能のデータベース制約設定 ⚠️ **重要** ⚠️

#### 6.1 matchesテーブルの制約
- **一貫性のため、blockedステータスも含めた制約を使用する**
- 既存のブロック機能と退会機能の両方が動作するよう設定

**推奨する制約設定（Supabase SQL）:**
```sql
-- 制約を削除
ALTER TABLE matches DROP CONSTRAINT IF EXISTS matches_status_check;

-- blockedも含めた新しい制約を追加
ALTER TABLE matches ADD CONSTRAINT matches_status_check 
CHECK (status IN ('active', 'deactivated', 'ended', 'blocked'));

-- 確認
SELECT DISTINCT status, COUNT(*) as count
FROM matches 
GROUP BY status
ORDER BY status;
```

#### 6.2 date_requestsテーブルの制約
```sql
-- date_requestsテーブルの制約も確認・修正
ALTER TABLE date_requests DROP CONSTRAINT IF EXISTS date_requests_status_check;
ALTER TABLE date_requests ADD CONSTRAINT date_requests_status_check 
CHECK (status IN ('pending', 'voted', 'accepted', 'rejected', 'cancelled', 'completed'));

-- 既存のdate_requestsデータのstatusを確認・修正
UPDATE date_requests 
SET status = 'pending' 
WHERE status IS NULL OR status NOT IN ('pending', 'voted', 'accepted', 'rejected', 'cancelled', 'completed');
```

#### 6.3 制約設定の理由
- `blocked`: 既存のブロック機能で使用
- `deactivated`: 退会機能で使用
- `active`: 通常のマッチ状態
- `ended`: マッチ終了状態

### 7. messagesテーブルのmessage_type制約 ⚠️ **重要** ⚠️

#### 7.1 許可されるメッセージタイプ
`messages`テーブルの`message_type`カラムには以下の値が許可されています：

- `text` - 通常のテキストメッセージ
- `date_request` - デートリクエストメッセージ
- `date_response` - デートリクエストへの返信メッセージ
- `date_decision` - デート決定メッセージ
- `restaurant_decision` - レストラン決定メッセージ
- `restaurant_voting` - レストラン投票メッセージ
- `restaurant_voting_response` - レストラン投票への返信メッセージ
- `system` - システムメッセージ
- `image` - 画像メッセージ

#### 7.2 制約定義
```sql
CHECK (message_type IN ('text', 'date_request', 'date_response', 'system', 'image', 'date_decision', 'restaurant_decision', 'restaurant_voting', 'restaurant_voting_response'))
```

#### 7.3 現在のデータ分布
```json
[
  { "message_type": "date_decision", "count": 1 },
  { "message_type": "date_request", "count": 72 },
  { "message_type": "date_response", "count": 36 },
  { "message_type": "restaurant_decision", "count": 5 },
  { "message_type": "restaurant_voting", "count": 25 },
  { "message_type": "restaurant_voting_response", "count": 6 },
  { "message_type": "text", "count": 14 }
]
```

**重要**: 新しいメッセージタイプを追加する場合は、必ずこの制約も更新する必要があります。

### 8. Firestore設定ファイル編集時の注意事項 ⚠️ **超重要** ⚠️

#### 8.1 既存インデックスの保護
- **`firestore.indexes.json`編集前に必ず現在のインデックスを確認する**
- コマンド: `firebase firestore:indexes`
- 既存のインデックスは絶対に削除しないこと（アプリ機能が停止する可能性）

#### 8.2 インデックスデプロイ時の対応
- デプロイ時に「既存インデックスを削除しますか？」と聞かれた場合は**必ず「No」を選択**
- 既存インデックスが必要なクエリ：
  - `messages` コレクション（メッセージ・投票機能）
  - `group_join_requests` コレクション（参加申請管理）
  - `likes` コレクション（いいね機能）
  - `matches` コレクション（マッチング機能）

#### 8.3 設定ファイル編集手順
1. **事前確認**: `firebase firestore:indexes` で現在のインデックス一覧を取得
2. **バックアップ**: 既存の `firestore.indexes.json` をコピーして保存
3. **新規追加**: 既存インデックスを保持したまま新しいインデックスを追加
4. **テストデプロイ**: `firebase deploy --only firestore:indexes`
5. **確認**: 警告が出ないことを確認してからアプリテスト

#### 8.4 重要ファイルの役割
- `firestore.indexes.json`: クエリの高速化設定（削除すると検索が遅くなる）
- `firestore.rules`: セキュリティルール（削除するとアクセス拒否）
- `firebase.json`: プロジェクト設定（削除するとデプロイ不可）

#### 8.5 緊急時の復旧方法
- インデックスを誤って削除した場合：
  1. Firebaseコンソールでインデックスの作成状況を確認
  2. `firebase firestore:indexes` で正しいインデックス定義を取得
  3. `firestore.indexes.json` に正しい定義を追加
  4. 再デプロイを実行

## 現在の作業状況
- ユーザー検索機能の修正・デプロイ完了 ✅
- `searchUsers`関数のデバッグ機能が本番環境に反映済み
- ESLintエラー修正（`npm run lint -- --fix`使用）
- 退会機能の実装・デプロイ完了 ✅
- 画像アップロード機能の実装完了 ✅
  - `profile_edit_page.dart` - プロフィール画像編集
  - `create_group_page.dart` - グループ画像作成
  - `group_chat_page.dart` - グループチャット画像送信
  - `match_detail_page.dart` - マッチ詳細画像送信

## 最近の修正履歴
- レストラン検索の都道府県自動設定機能追加
- 戻るボタンの実装（ユーザー検索・レストラン検索画面）
- Web版画像表示の修正（プロフィール・グループ画像）
- ユーザー検索機能のデバッグ強化
- 退会機能の実装（iOS/Web対応、エラーハンドリング改善）
- 画像アップロード機能のWeb/モバイル両対応実装
- messagesテーブルのmessage_type制約更新（imageタイプ追加）

# Web版修正ルール

## 基本原則
- Web版のバグ修正やエラー対応を行う際は、必ずiOSアプリに影響を与えないよう、`kIsWeb`による条件分岐を使用すること
- Platform固有のAPIやモバイル限定の機能はWeb版では無効化または代替処理を実装する
- Firebase MessagingやGoogle Maps APIなどのWeb版特有の設定も適切に対応する

## 具体的な対応パターン
1. **Platform API使用時**: `if (!kIsWeb)` で囲む
2. **モバイル固有機能**: Web版では代替UI表示
3. **パッケージ初期化**: Web対応を確認してから実行
4. **エラーハンドリング**: Web固有エラーの適切な処理

## 禁止事項
- 既存のiOS/Android向けコードの削除や変更
- 条件分岐なしでのWeb専用機能の追加
- 共通コードでのkIsWebを使わないプラットフォーム判定

## Web版地図機能の実装

### 実装概要
- **ファイル**: `lib/screens/web_map_search_page.dart`
- **実装方式**: Google Maps JavaScript API（新しいimportLibrary方式対応）
- **特徴**: iframeを使用しない直接的な地図表示、マーカークリックイベント対応

### Google Maps JavaScript API設定
- **APIキー**: Web版専用キー（index.htmlに設定済み）
- **許可ドメイン**: delimeet.jp/*, *.delimeet.jp/*, localhost:*/*
- **ライブラリ**: maps, places（新しいローダー方式で読み込み）

### 技術的実装内容

#### 1. APIローダー対応
```dart
// 新旧両方のAPIローダーに対応
if (googleMaps['importLibrary'] != null) {
  // 新しいimportLibrary方式
  final mapsLibrary = await _importLibrary('maps');
  _createMapWithLibrary(mapElement, mapsLibrary);
} else {
  // 従来の直接アクセス方式
  _createMapDirectly(mapElement, googleMaps);
}
```

#### 2. ポーリング方式での読み込み待機
- Google Maps APIの読み込み完了を定期的にチェック
- 最大5秒間待機後、タイムアウト処理
- フォールバック機能で確実な地図表示

#### 3. タップイベント対応
- `js.allowInterop()` を使用してDartコールバックを設定
- レストランマーカークリックでダイアログ表示
-募集作成機能への連携

### Web版地図機能の制約事項
- **位置情報取得**: 制限時間10秒、失敗時は東京駅をデフォルト位置として使用
- **マーカー数制限**: パフォーマンス最適化のため最大50件
- **レストラン検索範囲**: 現在地周辺約5km（±0.045度）

### デバッグ・ログ出力
```javascript
// ブラウザコンソールで確認可能なログ
[WebMapSearch] Google Maps API チェック: 1/50
[WebMapSearch] 新しいAPIローダーを検出
[WebMapSearch] Maps ライブラリ読み込み完了
[WebMapSearch] 地図作成完了: center=(35.6809, 139.7673)
[WebMapSearch] レストランマーカー追加完了: 50件
```

## ビルド・デプロイ手順

### 最適化ビルドスクリプト
```bash
# Web版最適化ビルド
./web/web_build_optimized.sh

# Firebase Hostingデプロイ
firebase deploy --only hosting
```

### ビルド最適化内容
1. **Tree-shaking icons**: アイコンフォントサイズ99.3%削減
2. **Gzip圧縮**: JavaScriptバンドル約70%削減
3. **CanvasKit renderer**: Web版パフォーマンス向上
4. **Release mode optimization**: 実行速度最適化

### バンドルサイズ分析
- **メインバンドル**: 4.1MB → 1.1MB（gzip後）
- **総サイズ**: 42MB（画像・フォント含む）

## 画像アップロード処理
- Web版では`kIsWeb`による条件分岐を使用
- Web版では`putData()`、モバイル版では`putFile()`を使用
- Web版ではHEIC→JPEG変換をスキップ
- Web版では`XFile`、モバイル版では`File`を使用

## 認証状態管理
- Web版での認証状態維持を優先
- セッション切れ時の自動再ログイン機能を実装
- `authStateChanges()`で監視し、適切なタイミングで再認証

## エラー対応
- Web版での認証エラー時は再ログインを促す
- 認証トークンの有効性を定期的にチェック
- Web/モバイル両対応の実装を確認
- Storageルールの設定を確認
- ファイル形式変換の処理を確認 