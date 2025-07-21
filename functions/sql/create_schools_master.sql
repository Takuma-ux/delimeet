-- 学校マスターテーブルの作成
CREATE TABLE IF NOT EXISTS schools (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- 学校別名・略称テーブル（検索用）
CREATE TABLE IF NOT EXISTS school_aliases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID REFERENCES schools(id) ON DELETE CASCADE,
    alias_name TEXT NOT NULL,                   -- 別名・略称
    alias_type TEXT NOT NULL CHECK (alias_type IN ('abbreviation', 'common_name', 'old_name')),
    created_at TIMESTAMP DEFAULT NOW()
);

-- インデックス作成
CREATE INDEX IF NOT EXISTS idx_schools_name ON schools USING gin(to_tsvector('japanese', school_name));
CREATE INDEX IF NOT EXISTS idx_schools_type ON schools(school_type);
CREATE INDEX IF NOT EXISTS idx_schools_prefecture ON schools(prefecture_code, prefecture_name);
CREATE INDEX IF NOT EXISTS idx_schools_code ON schools(school_code);
CREATE INDEX IF NOT EXISTS idx_school_aliases_name ON school_aliases USING gin(to_tsvector('japanese', alias_name));
CREATE INDEX IF NOT EXISTS idx_school_aliases_school_id ON school_aliases(school_id);

-- usersテーブルに新しいschool_idカラムを追加
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