-- バッジ写真テーブル
CREATE TABLE IF NOT EXISTS badge_photos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    photo_url TEXT NOT NULL,
    photo_order INTEGER NOT NULL CHECK (photo_order >= 1 AND photo_order <= 9),
    
    -- タイムスタンプ
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    -- ユーザーごとに同じレストランで同じ順序の写真は1つだけ
    UNIQUE(user_id, restaurant_id, photo_order)
);

-- インデックス作成
CREATE INDEX IF NOT EXISTS idx_badge_photos_user ON badge_photos(user_id);
CREATE INDEX IF NOT EXISTS idx_badge_photos_restaurant ON badge_photos(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_badge_photos_order ON badge_photos(photo_order);

-- 更新時刻自動更新のトリガー
CREATE TRIGGER trigger_update_badge_photos_updated_at
    BEFORE UPDATE ON badge_photos
    FOR EACH ROW
    EXECUTE FUNCTION update_reviews_updated_at(); 