-- matchesテーブルの拡張：match_typeカラム追加
ALTER TABLE matches 
ADD COLUMN IF NOT EXISTS match_type VARCHAR(20) DEFAULT 'user' 
CHECK (match_type IN ('user', 'restaurant'));

-- 制約の追加：レストランマッチの場合はrestaurant_idが必須
-- 既存の制約を削除してから追加（エラーを無視）
ALTER TABLE matches DROP CONSTRAINT IF EXISTS restaurant_match_check;
ALTER TABLE matches 
ADD CONSTRAINT restaurant_match_check 
CHECK (
  (match_type = 'user' AND restaurant_id IS NULL) OR
  (match_type = 'restaurant' AND restaurant_id IS NOT NULL)
);

-- インデックス追加
CREATE INDEX IF NOT EXISTS idx_matches_match_type ON matches(match_type);
CREATE INDEX IF NOT EXISTS idx_matches_restaurant_type ON matches(restaurant_id, match_type);

-- 既存データの更新：restaurant_idがあるものはrestaurantタイプに変更
UPDATE matches 
SET match_type = 'restaurant' 
WHERE restaurant_id IS NOT NULL AND match_type = 'user';

-- 確認用クエリ
SELECT 
    match_type,
    COUNT(*) as count,
    COUNT(restaurant_id) as with_restaurant
FROM matches 
GROUP BY match_type; 