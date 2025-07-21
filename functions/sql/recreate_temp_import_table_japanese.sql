-- 日本語ヘッダー対応の学校データインポート用テーブルの作成
-- Supabase Dashboard > SQL Editor で実行

-- 既存のテーブルがあれば削除
DROP TABLE IF EXISTS temp_schools_import;

-- CSVの日本語ヘッダーに合わせたテーブル作成
CREATE TABLE temp_schools_import (
    "学校コード" TEXT,
    "学校種" TEXT,
    "都道府県番号" TEXT,
    "設置区分" TEXT,
    "本分校" TEXT,
    "学校名" TEXT,
    "学校所在地" TEXT,
    "郵便番号" TEXT,
    "属性情報設定年月日" TEXT,
    "属性情報廃止年月日" TEXT,
    "旧学校調査番号" TEXT,
    "移行後の学校コード" TEXT
);

-- RLS（Row Level Security）ポリシー設定
ALTER TABLE temp_schools_import ENABLE ROW LEVEL SECURITY;

-- 読み取り・書き込み可能ポリシー（作業用なので制限なし）
CREATE POLICY "temp_schools_import is accessible by everyone" ON temp_schools_import
    FOR ALL USING (true) WITH CHECK (true);

-- インデックス作成（検索用）
CREATE INDEX IF NOT EXISTS idx_temp_schools_name_jp ON temp_schools_import("学校名");

-- コメント追加
COMMENT ON TABLE temp_schools_import IS '学校データインポート用一時テーブル（CSV読み込み後にschoolsテーブルに変換）'; 