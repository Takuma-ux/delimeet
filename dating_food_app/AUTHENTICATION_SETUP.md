# 認証機能設定ガイド

このドキュメントでは、Dating Food Appで実装された各種認証機能の設定方法について説明します。

## 実装済み認証機能

1. **Google認証** ✅
2. **Apple認証** ✅
3. **SMS認証（電話番号）** ✅
4. **LINE認証** ⚠️ (サーバーサイド実装が必要)
5. **Instagram認証** ⚠️ (開発中)
6. **メール認証** ✅ (既存機能)

## 1. Google認証の設定

### Android向け設定

1. [Google Cloud Console](https://console.cloud.google.com/)にアクセス
2. プロジェクトを選択または作成
3. 「APIとサービス」 > 「認証情報」に移動
4. 「認証情報を作成」 > 「OAuth 2.0 クライアントID」を選択
5. アプリケーションタイプを「Android」に設定
6. パッケージ名を入力: `com.example.dating_food_app`
7. SHA-1証明書フィンガープリントを追加：
   ```bash
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
   ```

### iOS向け設定

1. 同じGoogle Cloud Consoleプロジェクトで
2. 「認証情報を作成」 > 「OAuth 2.0 クライアントID」を選択
3. アプリケーションタイプを「iOS」に設定
4. バンドルIDを入力: `com.example.datingFoodApp`
5. ダウンロードしたplistファイルを `ios/Runner/` に配置

### Webクライアント設定

1. 「Webアプリケーション」タイプのOAuthクライアントIDも作成
2. クライアントIDをFlutterアプリで使用

## 2. Apple認証の設定

### Apple Developer設定

1. [Apple Developer](https://developer.apple.com/)にログイン
2. 「Certificates, Identifiers & Profiles」に移動
3. App IDを作成またはSign In with Appleを有効化
4. Sign In with Apple用のキーを生成

### iOS設定

1. `ios/Runner/Info.plist`に以下を追加：
   ```xml
   <key>CFBundleURLTypes</key>
   <array>
       <dict>
           <key>CFBundleURLName</key>
           <string>com.example.datingFoodApp</string>
           <key>CFBundleURLSchemes</key>
           <array>
               <string>com.example.datingFoodApp</string>
           </array>
       </dict>
   </array>
   ```

2. Signing & Capabilitiesで「Sign In with Apple」を有効化

## 3. SMS認証の設定

### Firebase設定

1. [Firebase Console](https://console.firebase.google.com/)にアクセス
2. プロジェクトの「Authentication」に移動
3. 「Sign-in method」タブで「電話番号」を有効化
4. 必要に応じてテスト電話番号を追加

### Android設定

1. `android/app/build.gradle`でminSdkVersionを21以上に設定
2. SHA-1フィンガープリントをFirebaseプロジェクトに追加

### iOS設定

1. APNs認証キーをFirebaseプロジェクトにアップロード
2. `ios/Runner/Info.plist`でURL Schemeを設定

## 4. LINE認証の設定 ⚠️

### LINE Developers設定

1. [LINE Developers](https://developers.line.biz/)でアカウント作成
2. 新しいチャネルを作成（LINE Login）
3. チャネルIDとチャネルシークレットを取得

### アプリ設定

1. `lib/main.dart`の `YOUR_LINE_CHANNEL_ID` を実際のIDに置換：
   ```dart
   await LineSDK.instance.setup("YOUR_ACTUAL_LINE_CHANNEL_ID");
   ```

### サーバーサイド実装が必要

⚠️ **重要**: LINE認証は現在、以下のサーバーサイド実装が必要です：

1. LINEアクセストークンの検証
2. Firebaseカスタムトークンの生成
3. セキュアなトークン交換エンドポイント

参考実装：
```javascript
// Firebase Cloud Functions例
exports.verifyLineToken = functions.https.onCall(async (data, context) => {
  const lineToken = data.lineToken;
  
  // LINEトークンを検証
  const lineProfile = await verifyLineAccessToken(lineToken);
  
  // Firebaseカスタムトークンを生成
  const customToken = await admin.auth().createCustomToken(lineProfile.userId);
  
  return { customToken };
});
```

## 5. Instagram認証の設定 ⚠️

### Instagram Basic Display API設定

1. [Facebook Developers](https://developers.facebook.com/)でアプリ作成
2. Instagram Basic Display APIを追加
3. クライアントIDとリダイレクトURIを設定

### アプリ設定

1. `lib/services/auth_service.dart`の設定値を更新：
   ```dart
   const clientId = 'YOUR_ACTUAL_INSTAGRAM_CLIENT_ID';
   const redirectUri = 'YOUR_ACTUAL_REDIRECT_URI';
   ```

⚠️ **開発中機能**: 現在は基本的なOAuth URLの構築のみ実装されています。完全な実装には以下が必要です：

1. リダイレクトURLの監視
2. 認証コードの処理
3. アクセストークンの取得
4. Firebaseとの連携

## 6. Firebase設定の確認

### Android

1. `android/app/google-services.json`が配置されていることを確認
2. Firebase CLIでプロジェクトが正しく設定されていることを確認

### iOS

1. `ios/Runner/GoogleService-Info.plist`が配置されていることを確認
2. URL Schemeが正しく設定されていることを確認

## トラブルシューティング

### Google認証エラー

- SHA-1フィンガープリントが正しく設定されているか確認
- パッケージ名/バンドルIDが一致しているか確認
- Google Services設定ファイルが最新か確認

### Apple認証エラー

- Apple Developer AccountでSign In with Appleが有効か確認
- App IDの設定が正しいか確認
- iOS 13以上でのみ利用可能

### SMS認証エラー

- 日本では +81 から始まる正しい電話番号形式を使用
- Firebaseプロジェクトで電話番号認証が有効化されているか確認
- テスト環境では事前に登録したテスト電話番号を使用

### LINE認証エラー

- チャネルIDが正しく設定されているか確認
- サーバーサイドのカスタムトークン生成が実装されているか確認
- LINEアプリがインストールされているか確認

## 開発時の注意事項

1. **テスト環境**: 本番環境の認証キーは使用しない
2. **セキュリティ**: クライアントシークレットはクライアントサイドに保存しない
3. **プライバシー**: ユーザーの同意なくデータを取得しない
4. **リリース前**: 各認証方法の動作確認を行う

## ファイル構成

```
lib/
├── services/
│   └── auth_service.dart          # 認証サービス（Google, Apple, SMS, LINE）
├── screens/auth/
│   ├── login_page.dart           # 更新されたログイン画面
│   ├── phone_auth_page.dart      # SMS認証専用画面
│   └── profile_setup_page.dart   # 更新されたプロフィール設定
└── main.dart                     # LINE SDK初期化追加
```

このガイドに従って設定を行い、必要に応じてサーバーサイドの実装を追加してください。 