-- Supabase用学校マスターテーブルの作成（修正版）
-- UUID拡張を有効化（既に有効の場合は無視される）
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 学校マスターテーブル
CREATE TABLE IF NOT EXISTS schools (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    school_code TEXT UNIQUE NOT NULL,           -- 文科省学校コード
    school_name TEXT NOT NULL,                  -- 正式学校名
    school_type TEXT NOT NULL CHECK (school_type IN ('university', 'graduate_school', 'junior_college', 'technical_college')),
    prefecture_code TEXT NOT NULL,              -- 都道府県コード
    prefecture_name TEXT NOT NULL,              -- 都道府県名
    establishment_type TEXT NOT NULL CHECK (establishment_type IN ('national', 'public', 'private')), -- 設置区分
    campus_type TEXT NOT NULL CHECK (campus_type IN ('main', 'branch')), -- 本分校
    postal_code TEXT,                           -- 郵便番号
    address TEXT,                               -- 住所
    is_active BOOLEAN DEFAULT true,             -- 現在も存在するか
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 学校別名・略称テーブル（検索用）
CREATE TABLE IF NOT EXISTS school_aliases (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    school_id UUID REFERENCES schools(id) ON DELETE CASCADE,
    alias_name TEXT NOT NULL,                   -- 別名・略称
    alias_type TEXT NOT NULL CHECK (alias_type IN ('abbreviation', 'common_name', 'old_name')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- RLS（Row Level Security）ポリシー設定
ALTER TABLE schools ENABLE ROW LEVEL SECURITY;
ALTER TABLE school_aliases ENABLE ROW LEVEL SECURITY;

-- 読み取り専用ポリシー（全ユーザーが読み取り可能）
CREATE POLICY "Schools are viewable by everyone" ON schools
    FOR SELECT USING (true);

CREATE POLICY "School aliases are viewable by everyone" ON school_aliases
    FOR SELECT USING (true);

-- インデックス作成（修正版 - Supabase対応）
-- 全文検索インデックス（simple設定を使用）
CREATE INDEX IF NOT EXISTS idx_schools_name_fulltext ON schools USING gin(to_tsvector('simple', school_name));
CREATE INDEX IF NOT EXISTS idx_school_aliases_name_fulltext ON school_aliases USING gin(to_tsvector('simple', alias_name));

-- 通常のB-treeインデックス（部分一致検索用）
CREATE INDEX IF NOT EXISTS idx_schools_name ON schools(school_name);
CREATE INDEX IF NOT EXISTS idx_schools_name_lower ON schools(lower(school_name));
CREATE INDEX IF NOT EXISTS idx_school_aliases_name ON school_aliases(alias_name);
CREATE INDEX IF NOT EXISTS idx_school_aliases_name_lower ON school_aliases(lower(alias_name));

-- その他のインデックス
CREATE INDEX IF NOT EXISTS idx_schools_type ON schools(school_type);
CREATE INDEX IF NOT EXISTS idx_schools_prefecture ON schools(prefecture_code, prefecture_name);
CREATE INDEX IF NOT EXISTS idx_schools_code ON schools(school_code);
CREATE INDEX IF NOT EXISTS idx_school_aliases_school_id ON school_aliases(school_id);

-- usersテーブルにschool_idカラムを追加（まだ存在しない場合）
ALTER TABLE users ADD COLUMN IF NOT EXISTS school_id UUID REFERENCES schools(id);

-- 新しいインデックス
CREATE INDEX IF NOT EXISTS idx_users_school_id ON users(school_id) WHERE school_id IS NOT NULL;

-- コメント追加
COMMENT ON TABLE schools IS '学校マスターデータ（文部科学省データベース準拠）';
COMMENT ON COLUMN schools.school_code IS '文部科学省学校コード';
COMMENT ON COLUMN schools.school_type IS '学校種別: university(大学), graduate_school(大学院), junior_college(短期大学), technical_college(高等専門学校)';
COMMENT ON COLUMN schools.establishment_type IS '設置区分: national(国立), public(公立), private(私立)';
COMMENT ON COLUMN schools.campus_type IS '本分校区分: main(本校), branch(分校)';

COMMENT ON TABLE school_aliases IS '学校別名・略称テーブル（検索用）';
COMMENT ON COLUMN school_aliases.alias_type IS '別名種別: abbreviation(略称), common_name(通称), old_name(旧名)';

COMMENT ON COLUMN users.school_id IS '所属学校ID（schoolsテーブルへの外部キー）'; 