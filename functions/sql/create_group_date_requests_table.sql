-- グループデートリクエストテーブル
CREATE TABLE IF NOT EXISTS group_date_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
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
    UNIQUE(requester_id, group_id, restaurant_id, created_at)
);

-- グループデートリクエスト回答テーブル
CREATE TABLE IF NOT EXISTS group_date_responses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id UUID NOT NULL REFERENCES group_date_requests(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- 回答詳細
    response VARCHAR(10) NOT NULL CHECK (response IN ('accept', 'reject')),
    response_message TEXT, -- 回答メッセージ
    selected_date TIMESTAMP WITH TIME ZONE, -- 選択した日時（承認時のみ）
    
    -- タイムスタンプ
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    -- 同じユーザーが同じリクエストに複数回答できないように制約
    UNIQUE(request_id, user_id)
);

-- インデックス作成
CREATE INDEX IF NOT EXISTS idx_group_date_requests_requester ON group_date_requests(requester_id);
CREATE INDEX IF NOT EXISTS idx_group_date_requests_group ON group_date_requests(group_id);
CREATE INDEX IF NOT EXISTS idx_group_date_requests_restaurant ON group_date_requests(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_group_date_requests_status ON group_date_requests(status);
CREATE INDEX IF NOT EXISTS idx_group_date_requests_created_at ON group_date_requests(created_at);

CREATE INDEX IF NOT EXISTS idx_group_date_responses_request ON group_date_responses(request_id);
CREATE INDEX IF NOT EXISTS idx_group_date_responses_user ON group_date_responses(user_id);
CREATE INDEX IF NOT EXISTS idx_group_date_responses_response ON group_date_responses(response);
CREATE INDEX IF NOT EXISTS idx_group_date_responses_created_at ON group_date_responses(created_at);

-- 更新時刻自動更新のトリガー
CREATE OR REPLACE FUNCTION update_group_date_requests_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_group_date_requests_updated_at
    BEFORE UPDATE ON group_date_requests
    FOR EACH ROW
    EXECUTE FUNCTION update_group_date_requests_updated_at(); 