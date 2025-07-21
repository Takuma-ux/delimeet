-- usersテーブルに学校関連とプライバシー機能のカラムを追加

-- 学校関連カラム
ALTER TABLE users ADD COLUMN IF NOT EXISTS school_name text;
ALTER TABLE users ADD COLUMN IF NOT EXISTS school_type text CHECK (school_type IN ('university', 'graduate_school', 'vocational_school', 'college'));
ALTER TABLE users ADD COLUMN IF NOT EXISTS show_school boolean DEFAULT true;

-- プライバシー設定カラム
ALTER TABLE users ADD COLUMN IF NOT EXISTS hide_from_same_school boolean DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS visible_only_if_liked boolean DEFAULT false;

-- インデックスの追加（検索パフォーマンス向上）
CREATE INDEX IF NOT EXISTS idx_users_school_name ON users(school_name) WHERE school_name IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_school_type ON users(school_type) WHERE school_type IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_privacy_settings ON users(hide_from_same_school, visible_only_if_liked);

-- コメント追加
COMMENT ON COLUMN users.school_name IS '学校名（大学・大学院・専門学校・短大など）';
COMMENT ON COLUMN users.school_type IS '学校種別: university(大学), graduate_school(大学院), vocational_school(専門学校), college(短大)';
COMMENT ON COLUMN users.show_school IS '学校名をプロフィールに表示するかどうか';
COMMENT ON COLUMN users.hide_from_same_school IS '同じ学校の人から見えないようにする（身内バレ防止）';
COMMENT ON COLUMN users.visible_only_if_liked IS 'こちらからいいねした人にのみ表示される'; 