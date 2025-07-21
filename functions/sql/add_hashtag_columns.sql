-- ハッシュタグ機能に必要なカラムを追加するスクリプト
-- 実行前にバックアップを取ることを推奨

-- usersテーブルにハッシュタグ関連のカラムを追加
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS tags TEXT[] DEFAULT '{}';

ALTER TABLE users 
ADD COLUMN IF NOT EXISTS mbti VARCHAR(4) CHECK (mbti IN (
  'ISTJ', 'ISFJ', 'INFJ', 'INTJ',
  'ISTP', 'ISFP', 'INFP', 'INTP',
  'ESTP', 'ESFP', 'ENFP', 'ENTP',
  'ESTJ', 'ESFJ', 'ENFJ', 'ENTJ'
));

-- インデックスを作成（検索性能向上のため）
CREATE INDEX IF NOT EXISTS idx_users_tags ON users USING GIN(tags);
CREATE INDEX IF NOT EXISTS idx_users_mbti ON users(mbti);

-- 既存データの確認・更新
-- 既存ユーザーのtagsカラムを空配列で初期化
UPDATE users 
SET tags = '{}' 
WHERE tags IS NULL;

-- コメントを追加
COMMENT ON COLUMN users.tags IS 'ユーザーが選択したハッシュタグの配列（レストラン・趣味・性格系）';
COMMENT ON COLUMN users.mbti IS 'MBTI性格タイプ（16タイプから1つ選択）';

-- 確認用クエリ
SELECT 
  COUNT(*) as total_users,
  COUNT(tags) as users_with_tags,
  COUNT(mbti) as users_with_mbti,
  COUNT(CASE WHEN array_length(tags, 1) > 0 THEN 1 END) as users_with_selected_tags
FROM users; 