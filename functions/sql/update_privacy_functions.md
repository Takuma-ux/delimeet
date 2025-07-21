# プライバシー機能の更新 - school_id対応

## 🔄 更新が必要な理由

現在の身内バレ防止機能は`school_name`の文字列比較を使用していますが、以下の問題があります：

- **表記揺れ**: 「東京大学」vs「東大」が別扱い
- **入力ミス**: ユーザーの手入力による誤字脱字
- **不正確な比較**: 部分一致や略称での誤判定

## 🎯 新しい設計

学校マスターテーブル（`schools`）の`school_id`を使用した正確な比較に変更：

```sql
-- 旧方式（問題あり）
WHERE user1.school_name = user2.school_name

-- 新方式（正確）  
WHERE user1.school_id = user2.school_id AND user1.school_id IS NOT NULL
```

## 📝 更新が必要なファイル

### 1. user_search_page.dart
```dart
// 変更前
if (_mySchoolName == user['school_name']) {
  return false; // 除外
}

// 変更後  
if (_mySchoolId == user['school_id'] && user['school_id'] != null) {
  return false; // 除外
}
```

### 2. search_page.dart
```dart
// 変更前
if (user['hide_from_same_school'] == true && 
    _mySchoolName != null && 
    user['school_name'] != null &&
    _mySchoolName == user['school_name']) {

// 変更後
if (user['hide_from_same_school'] == true && 
    _mySchoolId != null && 
    user['school_id'] != null &&
    _mySchoolId == user['school_id']) {
```

### 3. Cloud Functions (index.ts)
推薦アルゴリズムでも`school_id`ベースの比較に更新：

```typescript
// getUserProfile関数でschool_idを返す
SELECT 
  id, name, bio, age, gender, prefecture, occupation, 
  weekend_off, favorite_categories, image_url, 
  birth_date, id_verified, created_at, updated_at, 
  deactivated_at, account_status, tags, mbti, 
  preferred_age_range, payment_preference, preferred_gender,
  school_id  -- school_nameの代わりにschool_idを返す
FROM users 
WHERE firebase_uid = $1 LIMIT 1
```

## 🔧 実装手順

### Step 1: プロフィール取得の更新
```dart
// 自分の学校情報取得時
final userResult = await _supabase
    .from('users')
    .select('id, school_id')  // school_nameの代わり
    .eq('firebase_uid', user.uid)
    .single();

_mySchoolId = userResult['school_id'];  // UUIDで保存
```

### Step 2: ユーザー検索クエリの更新
```dart
// 検索結果に学校IDも含める
.select('id, name, image_url, age, occupation, gender, 
         favorite_categories, weekend_off, id_verified, 
         mbti, tags, school_id, hide_from_same_school, 
         visible_only_if_liked')
```

### Step 3: フィルタリングロジックの更新
```dart
// 身内バレ防止
if (user['hide_from_same_school'] == true && 
    _mySchoolId != null && 
    user['school_id'] != null &&
    _mySchoolId == user['school_id']) {
  return false;
}
```

## 🧪 テスト方法

### 1. 同じ学校のユーザー作成
```sql
-- テスト用: 東京大学の学校IDを取得
SELECT id FROM schools WHERE school_name = '東京大学';

-- ユーザー1とユーザー2に同じschool_idを設定
UPDATE users SET school_id = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' 
WHERE firebase_uid IN ('user1_uid', 'user2_uid');
```

### 2. プライバシー設定のテスト
```sql
-- ユーザー1の身内バレ防止をON
UPDATE users SET hide_from_same_school = true 
WHERE firebase_uid = 'user1_uid';
```

### 3. 検索結果の確認
- ユーザー2でユーザー検索
- ユーザー1が検索結果に表示されないことを確認

## 📈 期待される改善効果

1. **正確性向上**: 100%正確な学校判定
2. **メンテナンス性**: 学校名変更への自動対応
3. **パフォーマンス**: UUID比較による高速化
4. **拡張性**: 学校統合・分離への対応

## ⚠️ 注意事項

### 既存データの移行
```sql
-- 既存のschool_nameからschool_idへの変換
UPDATE users 
SET school_id = s.id
FROM schools s
WHERE users.school_name = s.school_name
  AND users.school_id IS NULL;
```

### 互換性の維持
- 移行期間中は`school_name`と`school_id`両方を保持
- 段階的にschool_id方式に移行
- 古いクライアントでも動作するよう配慮 