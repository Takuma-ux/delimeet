# Memory - 重要な技術情報

## データベース構造

### データベース管理
- **プラットフォーム**: Supabase (PostgreSQL ベース)
- **管理方法**: Supabase ダッシュボードまたはpsql経由でアクセス可能

### usersテーブル
- **id**: UUID形式のユニークID（例: `189b2cc1-56cd-4353-b4a9-b9236a3d7b4a`）
- **firebase_uid**: Firebase Authentication UID（例: `DTq7aQ8J50cKGMV2GDmXqf62pqm1`, `line_U0a6dfdd286f0a455a811da92c402a7a5`）

### date_requestsテーブル
- **重要なステータス**: `pending`, `voted`, `decided`, `no_match`, `rejected`, `cancelled`, `expired`
- **decided_date**: 決定された日程（TIMESTAMP）
- **selected_dates**: 受信者が選択した日程（JSON形式）

### 重要な実装メモ

#### Firebase UIDとデータベースUUID ID の使い分け
1. **Firebase認証**: `firebase_uid`カラムに保存
2. **アプリ内部処理**: `id`カラム（UUID）を使用
3. **メッセージ送信者**: `sender_id`としてUUID IDまたはFirebase UIDが混在する場合がある

#### データ整合性の注意点
- メッセージの投票状況チェック時は、Firebase UIDとUUID IDの変換が必要
- 同じユーザーでも、認証方法（メール、LINE等）によってFirebase UIDの形式が異なる
- **重要**: フロントエンド表示とデータベース実データに不整合が発生する可能性があり、常にデータベースの実データを信頼すること

#### 日程決定処理の課題
- フロントエンド側で`status=decided`と表示されていても、実際のデータベースでは`status=no_match`の場合がある
- 店舗投票開始前には必ずデータベース上の実際のステータスを確認する必要がある

## 必須ルール

1. **日本語で必ず返信すること**
2. **memory/memory.mdファイルの内容を常に参照し、守ること**
3. **Firebase UIDとデータベースUUID IDの変換処理を正しく実装すること**
4. **Supabaseデータベースの実データを常に信頼し、フロントエンド表示と相違がある場合はデータベースを基準とすること** 