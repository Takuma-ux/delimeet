# Supabaseへの学校データインポート手順

## 📋 概要
全国の大学・短期大学・高等専門学校データ（school.csv）をSupabaseデータベースにインポートする手順です。

## 🚀 実行手順

### Step 1: 学校マスターテーブルの作成

1. **Supabase Dashboard**にアクセス
2. **SQL Editor**を開く  
3. `create_schools_master_supabase.sql`の内容をコピー&ペースト
4. **Run**ボタンをクリックして実行

```sql
-- 実行されるテーブル:
-- - schools（学校マスター）
-- - school_aliases（学校別名・略称）
-- - usersテーブルにschool_idカラム追加
```

### Step 2: CSVデータのインポート

#### 方法A: SupabaseダッシュボードのGUI使用（推奨）

1. **Table Editor**を開く
2. 左サイドバーから**temp_schools_import**テーブルを選択
3. **"Insert"** > **"Import data via CSV"**をクリック
4. `school.csv`ファイルをアップロード
5. カラムマッピングを確認：
   ```
   school_code         → school_code
   学校種              → school_type_raw  
   都道府県番号        → prefecture_code_raw
   設置区分            → establishment_type_raw
   本分校              → campus_type_raw
   学校名              → school_name
   学校所在地          → address
   郵便番号            → postal_code
   属性情報設定年月日   → attr_date
   属性情報廃止年月日   → delete_date
   旧学校調査番号      → old_number
   移行後の学校コード   → migrated_code
   ```
6. **Import**ボタンをクリック

#### 方法B: SQL Editorでの直接実行

1. **SQL Editor**を開く
2. 以下のクエリを実行して一時テーブルを作成：

```sql
CREATE TEMP TABLE temp_schools_import (
    school_code TEXT,
    school_type_raw TEXT,
    prefecture_code_raw TEXT,
    establishment_type_raw TEXT,
    campus_type_raw TEXT,
    school_name TEXT,
    address TEXT,
    postal_code TEXT,
    attr_date TEXT,
    delete_date TEXT,
    old_number TEXT,
    migrated_code TEXT
);
```

3. CSV内容を手動でINSERT文に変換（大量データの場合は非推奨）

### Step 3: 学校データの変換・挿入

1. **SQL Editor**で`import_schools_data_supabase.sql`を実行
2. データ変換処理が実行されます：
   - 学校種別の正規化（F1→university等）
   - 都道府県コードから都道府県名への変換
   - 設置区分の正規化（1→national等）
   - 本分校区分の正規化

### Step 4: 主要大学略称の追加

自動で以下の略称が追加されます：
- 東京大学 → 東大
- 早稲田大学 → 早稲田、早大  
- 慶應義塾大学 → 慶應、慶応、慶大
- など25校以上

## 🔍 データ確認

インポート完了後、以下のクエリで確認：

```sql
-- 登録学校数確認
SELECT COUNT(*) FROM schools;

-- 都道府県別学校数
SELECT prefecture_name, COUNT(*) as school_count 
FROM schools 
GROUP BY prefecture_name 
ORDER BY school_count DESC;

-- 学校種別確認  
SELECT school_type, COUNT(*) as count
FROM schools
GROUP BY school_type;

-- 略称データ確認
SELECT s.school_name, sa.alias_name, sa.alias_type
FROM schools s
JOIN school_aliases sa ON s.id = sa.school_id
WHERE s.school_name LIKE '%東京大学%';
```

## 🛠️ トラブルシューティング

### エラー: "UUID extension not available"
```sql
-- UUID拡張を手動で有効化
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

### エラー: "RLS policy denies access"
```sql
-- RLSポリシーを確認・修正
ALTER TABLE schools ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Schools are viewable by everyone" ON schools FOR SELECT USING (true);
```

### インポートデータの重複エラー
- `ON CONFLICT (school_code) DO NOTHING` により重複は自動で無視されます

## 📊 期待される結果

- **schools テーブル**: 約1,200件の学校データ
- **school_aliases テーブル**: 約50件の略称データ  
- **users テーブル**: school_idカラム追加

## 🔄 データ更新

年1回、文部科学省の最新データで更新：

1. 新しいschool.csvをダウンロード
2. Step 2〜3を再実行
3. 新規学校のみ追加（既存データは保持）

## ⚡ パフォーマンス最適化

- 全文検索インデックス（GIN）により高速検索
- 都道府県・学校種別インデックスでフィルタリング高速化  
- RLSポリシーで必要最小限のアクセス制御 