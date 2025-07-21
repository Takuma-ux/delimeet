-- 既存の学校関連テーブルを削除して再作成
-- 注意: 既存データは失われます

-- 1. 既存テーブルを削除（外部キー制約があるため順序重要）
DROP TABLE IF EXISTS school_aliases CASCADE;
DROP TABLE IF EXISTS schools CASCADE;

-- 2. usersテーブルのschool_idカラムも削除（外部キー制約のため）
ALTER TABLE users DROP COLUMN IF EXISTS school_id;

-- 3. 関連するポリシーやインデックスも削除
DROP POLICY IF EXISTS "Schools are viewable by everyone" ON schools;
DROP POLICY IF EXISTS "School aliases are viewable by everyone" ON school_aliases;

-- 4. 削除完了確認
SELECT 'Tables dropped successfully. Ready for recreation.' as status;

-- 5. この後、create_schools_master_supabase_fixed.sql を実行してください 