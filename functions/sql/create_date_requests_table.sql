-- デートリクエストテーブル
CREATE TABLE IF NOT EXISTS date_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    match_id UUID NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
    restaurant_id UUID NOT NULL REFERENCES restaurants(id),
    
    -- リクエスト詳細
    message TEXT, -- リクエストメッセージ
    proposed_date_1 TIMESTAMP WITH TIME ZONE, -- 提案日時1
    proposed_date_2 TIMESTAMP WITH TIME ZONE, -- 提案日時2
    proposed_date_3 TIMESTAMP WITH TIME ZONE, -- 提案日時3
    
    -- ステータス管理
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected', 'cancelled', 'expired')),
    response_message TEXT, -- 返信メッセージ
    accepted_date TIMESTAMP WITH TIME ZONE, -- 確定した日時
    
    -- タイムスタンプ
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP + INTERVAL '7 days'), -- 7日で期限切れ
    
    -- インデックス用
    UNIQUE(requester_id, recipient_id, match_id, restaurant_id, created_at)
);

-- インデックス作成
CREATE INDEX IF NOT EXISTS idx_date_requests_requester ON date_requests(requester_id);
CREATE INDEX IF NOT EXISTS idx_date_requests_recipient ON date_requests(recipient_id);
CREATE INDEX IF NOT EXISTS idx_date_requests_match ON date_requests(match_id);
CREATE INDEX IF NOT EXISTS idx_date_requests_status ON date_requests(status);
CREATE INDEX IF NOT EXISTS idx_date_requests_created_at ON date_requests(created_at);

-- 更新時刻自動更新のトリガー
CREATE OR REPLACE FUNCTION update_date_requests_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_date_requests_updated_at
    BEFORE UPDATE ON date_requests
    FOR EACH ROW
    EXECUTE FUNCTION update_date_requests_updated_at();

-- 期限切れリクエストを自動で期限切れにする関数
CREATE OR REPLACE FUNCTION expire_old_date_requests()
RETURNS INTEGER AS $$
DECLARE
    expired_count INTEGER;
BEGIN
    UPDATE date_requests 
    SET status = 'expired', updated_at = CURRENT_TIMESTAMP
    WHERE status = 'pending' 
    AND expires_at < CURRENT_TIMESTAMP;
    
    GET DIAGNOSTICS expired_count = ROW_COUNT;
    RETURN expired_count;
END;
$$ LANGUAGE plpgsql; 