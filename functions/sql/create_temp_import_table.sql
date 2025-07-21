-- 学校データインポート用テーブルの作成（通常テーブル版）
-- Supabase Dashboard > SQL Editor で実行

-- 既存のテーブルがあれば削除
DROP TABLE IF EXISTS temp_schools_import;

-- インポート用テーブルを通常のテーブルとして作成
CREATE TABLE temp_schools_import (
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

-- RLS（Row Level Security）ポリシー設定
ALTER TABLE temp_schools_import ENABLE ROW LEVEL SECURITY;

-- 読み取り・書き込み可能ポリシー（作業用なので制限なし）
CREATE POLICY "temp_schools_import is accessible by everyone" ON temp_schools_import
    FOR ALL USING (true) WITH CHECK (true);

-- インデックス作成（検索用）
CREATE INDEX IF NOT EXISTS idx_temp_schools_name ON temp_schools_import(school_name);

-- コメント追加
COMMENT ON TABLE temp_schools_import IS '学校データインポート用一時テーブル（CSV読み込み後にschoolsテーブルに変換）'; 