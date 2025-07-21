/// アプリの基本設定
class AppConfig {
  /// アプリ名
  static const String appName = 'Delimeet';
  
  /// バージョン
  static const String version = '1.0.0';
  
  /// 本番環境のドメイン
  static const String productionDomain = 'delimeet.jp';
  
  /// お問い合わせ先メールアドレス
  static const String supportEmail = 'support@delimeet.jp';
  
  /// 開発者連絡先
  static const String developerEmail = 'dev@delimeet.jp';
  
  /// プライバシーポリシーURL
  static const String privacyPolicyUrl = 'https://delimeet.jp/privacy';
  
  /// 利用規約URL
  static const String termsOfServiceUrl = 'https://delimeet.jp/terms';
  
  /// 会社情報
  static const String companyName = 'Delimeet Inc.';
  
  /// アプリの説明
  static const String appDescription = 'グルメを通じて素敵な出会いを見つけよう';
  
  /// SNSリンク
  static const String facebookUrl = 'https://facebook.com/delimeet';
  static const String twitterUrl = 'https://twitter.com/delimeet';
  static const String instagramUrl = 'https://instagram.com/delimeet';
  
  /// アプリストアURL
  static const String appStoreUrl = 'https://apps.apple.com/jp/app/delimeet/id123456789';
  static const String googlePlayUrl = 'https://play.google.com/store/apps/details?id=com.delimeet.app';
  
  /// 開発モードかどうか
  static const bool isDevelopment = false;
  
  /// 設定が完了しているかチェック
  static bool get isConfigured {
    return productionDomain.isNotEmpty &&
           supportEmail.isNotEmpty &&
           supportEmail.contains('@delimeet.jp');
  }
  
  /// 設定確認メッセージ
  static String get configurationMessage {
    if (isConfigured) {
      return '✅ アプリ設定完了';
    } else {
      return '⚠️ アプリ設定が未完了です。\n'
             'lib/config/app_config.dart で設定値を更新してください。';
    }
  }
  
  /// 現在の環境に応じたベースURL
  static String get baseUrl {
    if (isDevelopment) {
      return 'https://dating-food-apps.web.app';
    } else {
      return 'https://$productionDomain';
    }
  }
} 