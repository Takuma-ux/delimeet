/// Instagram API設定
class InstagramConfig {
  // 🔧 TODO: Meta App Dashboardから取得した実際の値に置き換えてください
  
  /// Instagram App ID (Meta App Dashboard → Instagram → API Setup から取得)
  static const String instagramAppId = '1151381633491642';
  
  /// Instagram App Secret (Meta App Dashboard → Instagram → API Setup から取得)
  static const String instagramAppSecret = '45af0c25440a5537bbdff02756292553'; // 「表示」ボタンから取得して置き換え
  
  /// Meta App ID (Meta App Dashboard → App Settings → Basic から取得)
  static const String metaAppId = '1561246481501037';
  
  /// Meta App Secret (Meta App Dashboard → App Settings → Basic から取得)
  static const String metaAppSecret = '47581c84d2a050f11c645b04e3899ed9'; // App Settings → Basic から取得して置き換え
  
  /// リダイレクトURL
  /// 本番環境: https://your-domain.com/auth/instagram/callback
  /// 開発環境: https://localhost:3000/auth/instagram/callback
  /// テスト用: https://oauth.pstmn.io/v1/callback
  static const String redirectUri = 'https://oauth.pstmn.io/v1/callback';
  
  /// 要求するスコープ
  static const List<String> scopes = [
    'instagram_business_basic',
    'instagram_business_content_publish',
    'instagram_business_manage_comments',
    'instagram_business_manage_messages',
  ];
  
  /// 開発モードかどうか
  static const bool isDevelopment = true;
  
  /// 設定が完了しているかチェック
  static bool get isConfigured {
    return instagramAppId != 'YOUR_INSTAGRAM_APP_ID' &&
           instagramAppSecret != 'YOUR_INSTAGRAM_APP_SECRET' &&
           metaAppId != 'YOUR_META_APP_ID' &&
           metaAppSecret != 'YOUR_META_APP_SECRET';
  }
  
  /// 設定確認メッセージ
  static String get configurationMessage {
    if (isConfigured) {
      return '✅ Instagram API設定完了';
    } else {
      return '⚠️ Instagram API設定が未完了です。\n'
             'lib/config/instagram_config.dart で設定値を更新してください。';
    }
  }
} 