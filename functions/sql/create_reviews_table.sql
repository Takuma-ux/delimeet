-- レビューテーブル
CREATE TABLE IF NOT EXISTS restaurant_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    
    -- レビュー内容
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5), -- 1-5の評価
    comment TEXT, -- レビューコメント
    visit_date DATE, -- 訪問日
    
    -- デートリクエスト関連（得点計算用）
    date_request_id UUID REFERENCES date_requests(id) ON DELETE SET NULL,
    is_group_date BOOLEAN DEFAULT FALSE, -- 団体デートかどうか
    is_organizer BOOLEAN DEFAULT FALSE, -- 主催者かどうか（団体デートの場合）
    
    -- いいね機能
    helpful_count INTEGER DEFAULT 0, -- 参考になった数
    
    -- タイムスタンプ
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    -- 同じユーザーが同じレストランに複数レビューを書けないように制約
    UNIQUE(user_id, restaurant_id)
);

-- レビューのいいねテーブル
CREATE TABLE IF NOT EXISTS review_likes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    review_id UUID NOT NULL REFERENCES restaurant_reviews(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- タイムスタンプ
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    -- 同じユーザーが同じレビューに複数いいねできないように制約
    UNIQUE(review_id, user_id)
);

-- 地元案内人バッジテーブル
CREATE TABLE IF NOT EXISTS local_guide_badges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- バッジ情報
    badge_level VARCHAR(20) NOT NULL CHECK (badge_level IN ('bronze', 'silver', 'gold', 'platinum')),
    total_score INTEGER NOT NULL DEFAULT 0,
    
    -- 得点詳細
    review_points INTEGER DEFAULT 0, -- レビュー投稿による得点
    helpful_points INTEGER DEFAULT 0, -- レビューの参考になったによる得点
    favorite_restaurant_points INTEGER DEFAULT 0, -- お気に入りレストラン設定による得点
    
    -- タイムスタンプ
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    -- ユーザーごとに1つのバッジレコード
    UNIQUE(user_id)
);

-- インデックス作成
CREATE INDEX IF NOT EXISTS idx_restaurant_reviews_user ON restaurant_reviews(user_id);
CREATE INDEX IF NOT EXISTS idx_restaurant_reviews_restaurant ON restaurant_reviews(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_restaurant_reviews_rating ON restaurant_reviews(rating);
CREATE INDEX IF NOT EXISTS idx_restaurant_reviews_created_at ON restaurant_reviews(created_at);

CREATE INDEX IF NOT EXISTS idx_review_likes_review ON review_likes(review_id);
CREATE INDEX IF NOT EXISTS idx_review_likes_user ON review_likes(user_id);

CREATE INDEX IF NOT EXISTS idx_local_guide_badges_user ON local_guide_badges(user_id);
CREATE INDEX IF NOT EXISTS idx_local_guide_badges_level ON local_guide_badges(badge_level);

-- 更新時刻自動更新のトリガー
CREATE OR REPLACE FUNCTION update_reviews_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_restaurant_reviews_updated_at
    BEFORE UPDATE ON restaurant_reviews
    FOR EACH ROW
    EXECUTE FUNCTION update_reviews_updated_at();

CREATE TRIGGER trigger_update_local_guide_badges_updated_at
    BEFORE UPDATE ON local_guide_badges
    FOR EACH ROW
    EXECUTE FUNCTION update_reviews_updated_at();

-- レビューのいいね数を自動更新する関数
CREATE OR REPLACE FUNCTION update_review_helpful_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE restaurant_reviews 
        SET helpful_count = helpful_count + 1
        WHERE id = NEW.review_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE restaurant_reviews 
        SET helpful_count = helpful_count - 1
        WHERE id = OLD.review_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_review_helpful_count
    AFTER INSERT OR DELETE ON review_likes
    FOR EACH ROW
    EXECUTE FUNCTION update_review_helpful_count();

-- 地元案内人バッジのレベルを自動更新する関数
CREATE OR REPLACE FUNCTION update_badge_level()
RETURNS TRIGGER AS $$
BEGIN
    -- 総得点に基づいてバッジレベルを決定
    IF NEW.total_score >= 200 THEN
        NEW.badge_level = 'platinum';
    ELSIF NEW.total_score >= 100 THEN
        NEW.badge_level = 'gold';
    ELSIF NEW.total_score >= 50 THEN
        NEW.badge_level = 'silver';
    ELSE
        NEW.badge_level = 'bronze';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_badge_level
    BEFORE INSERT OR UPDATE ON local_guide_badges
    FOR EACH ROW
    EXECUTE FUNCTION update_badge_level(); 