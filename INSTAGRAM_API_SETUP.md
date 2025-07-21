# Instagram API連携設定ガイド

## 🎯 概要
このガイドでは、Dating Food AppでInstagram API連携を正しく実装するための手順を説明します。

## 📋 前提条件

### 必須要件
- [ ] Meta（Facebook）開発者アカウント
- [ ] ビジネス認証完了
- [ ] Instagramビジネスアカウント
- [ ] SSL対応のWebサイト（リダイレクトURL用）
- [ ] アプリストア公開（本番環境）

## 🏗️ Step 1: Meta開発者アカウント設定

### 1.1 Meta Developer Account登録
1. https://developers.facebook.com/ にアクセス
2. Facebookアカウントでログイン
3. 開発者利用規約に同意
4. 電話番号認証を完了

### 1.2 ビジネス認証
**⚠️ 重要：Instagram APIを使用するには必須**

1. **Meta Business Manager**に移動
2. **ビジネス認証**を開始
3. 必要書類を提出：
   - 法人登記簿謄本
   - 事業証明書
   - 代表者身分証明書

認証完了まで：**数日〜数週間**

## 🔧 Step 2: Instagram APIアプリ作成

### 2.1 新しいアプリ作成
```
1. Meta App Dashboard → "Create App"
2. Use case: "Other"
3. App type: "Business"
4. App details:
   - App name: "Dating Food App"
   - Contact email: your-email@domain.com
```

### 2.2 Instagram製品の追加
```
1. App Dashboard → "Add Product"
2. "Instagram" → "Set up"
3. Configuration: "Instagram API with Instagram Login"
```

### 2.3 権限設定
```
必要な権限:
- instagram_business_basic
- instagram_business_content_publish
- instagram_business_manage_comments
- instagram_business_manage_messages (オプション)
```

## 🔑 Step 3: OAuth設定

### 3.1 リダイレクトURL設定
```
Production:
- https://your-domain.com/auth/instagram/callback

Development:
- https://localhost:3000/auth/instagram/callback
- https://oauth.pstmn.io/v1/callback (Postman用)
```

### 3.2 クライアント情報取得
```
App Settings → Basic:
- App ID: [YOUR_APP_ID]
- App Secret: [YOUR_APP_SECRET]

Instagram → API Setup:
- Instagram App ID: [INSTAGRAM_APP_ID]
- Instagram App Secret: [INSTAGRAM_APP_SECRET]
```

## 📱 Step 4: 実装設計

### 4.1 認証フロー比較

| 認証方法 | 新規登録 | 既存アカウント連携 | 実装方法 |
|---------|---------|------------------|---------|
| Instagram認証 | Instagram IDで新規登録 | 既存アカウントにInstagram連携 | OAuth 2.0 |
| その他の認証 | 通常の新規登録 | アカウント設定でInstagram連携 | 後から連携 |

### 4.2 データベース設計
```sql
-- usersテーブル拡張
ALTER TABLE users ADD COLUMN instagram_user_id VARCHAR(255);
ALTER TABLE users ADD COLUMN instagram_username VARCHAR(255);
ALTER TABLE users ADD COLUMN instagram_access_token TEXT;
ALTER TABLE users ADD COLUMN instagram_token_expires_at TIMESTAMP;
ALTER TABLE users ADD COLUMN instagram_connected_at TIMESTAMP;

-- Instagram認証情報テーブル
CREATE TABLE user_instagram_auth (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    instagram_user_id VARCHAR(255) NOT NULL,
    instagram_username VARCHAR(255),
    access_token TEXT NOT NULL,
    refresh_token TEXT,
    token_expires_at TIMESTAMP,
    scopes TEXT[],
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

## 🔄 Step 5: OAuth実装

### 5.1 認証URL生成
```dart
String generateInstagramAuthUrl() {
  final params = {
    'client_id': instagramAppId,
    'redirect_uri': redirectUri,
    'scope': 'instagram_business_basic,instagram_business_content_publish',
    'response_type': 'code',
    'state': generateSecureState(), // CSRF対策
  };
  
  return 'https://api.instagram.com/oauth/authorize?' + 
         params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
}
```

### 5.2 アクセストークン取得
```dart
Future<Map<String, dynamic>> exchangeCodeForToken(String code) async {
  final response = await http.post(
    Uri.parse('https://api.instagram.com/oauth/access_token'),
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: {
      'client_id': instagramAppId,
      'client_secret': instagramAppSecret,
      'grant_type': 'authorization_code',
      'redirect_uri': redirectUri,
      'code': code,
    },
  );
  
  return json.decode(response.body);
}
```

## 📊 Step 6: アプリレビュー申請

### 6.1 必要資料
1. **アプリのスクリーンショット**
2. **使用方法の動画**
3. **プライバシーポリシー**
4. **利用規約**
5. **ビジネス詳細**

### 6.2 申請内容
```
Use Case: Social Media Management for Dating App
- ユーザーが自分の投稿をInstagramでシェア
- レストラン情報付きの投稿作成
- ユーザー同意に基づく連携

Expected Timeline: 2-4週間
```

## 🛡️ Step 7: セキュリティ考慮事項

### 7.1 トークン管理
- アクセストークンの暗号化保存
- 定期的なトークン更新
- 適切な有効期限管理

### 7.2 スコープ制限
- 必要最小限の権限のみ要求
- ユーザー同意の明確化
- データ使用目的の明示

## 🚀 Step 8: 段階的リリース

### Phase 1: プロトタイプ (現在)
- 簡易共有機能（クリップボード + アプリ起動）
- ユーザーフィードバック収集

### Phase 2: 開発環境
- Meta開発者設定完了
- OAuth実装
- テストユーザーでの動作確認

### Phase 3: 本番環境
- アプリレビュー通過
- 本格的なAPI連携
- 全ユーザーへの提供

## 📝 次のアクション

### 即座に実行すべきこと
1. [ ] Meta開発者アカウント作成
2. [ ] ビジネス認証申請
3. [ ] SSL証明書取得（リダイレクトURL用）
4. [ ] プライバシーポリシー作成

### 開発段階で実行すること
1. [ ] OAuth認証フロー実装
2. [ ] データベース設計更新
3. [ ] セキュリティ監査

### 本番リリース前
1. [ ] アプリレビュー申請
2. [ ] セキュリティテスト
3. [ ] ユーザー同意フロー最終確認

## 🔗 参考リンク

- [Meta for Developers](https://developers.facebook.com/)
- [Instagram Platform Documentation](https://developers.facebook.com/docs/instagram-platform/)
- [Instagram API with Instagram Login](https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/)
- [Business Verification Guide](https://www.facebook.com/business/help/2018562745113803)

## ⚠️ 重要な注意事項

1. **Instagram Basic Display APIは2024年12月4日に廃止**
2. **Instagram Platform API (Business)を使用する必要がある**
3. **個人用アカウントではなく、ビジネスアカウントが必要**
4. **アプリストア公開後でないと本番利用不可** 