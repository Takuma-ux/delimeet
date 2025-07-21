-- グループ機能のテーブル作成スクリプト
-- 実行順序: 1. groups → 2. group_members → 3. group_invitations → 4. group_date_requests → 5. group_date_responses

-- 1. グループテーブル
CREATE TABLE IF NOT EXISTS groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    description TEXT,
    image_url TEXT,
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- 設定
    is_private BOOLEAN DEFAULT false,
    max_members INTEGER DEFAULT 50,
    
    -- メタデータ
    last_message TEXT,
    last_message_at TIMESTAMP WITH TIME ZONE,
    last_message_by UUID REFERENCES users(id),
    
    -- タイムスタンプ
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. グループメンバーテーブル
CREATE TABLE IF NOT EXISTS group_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- メンバー情報
    role VARCHAR(20) DEFAULT 'member' CHECK (role IN ('admin', 'member')),
    is_active BOOLEAN DEFAULT true,
    
    -- タイムスタンプ
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_seen TIMESTAMP WITH TIME ZONE,
    
    -- 同じユーザーが同じグループに複数回参加できないように制約
    UNIQUE(group_id, user_id)
);

-- 3. グループ招待テーブル
CREATE TABLE IF NOT EXISTS group_invitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    inviter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    invitee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- 招待ステータス
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected', 'expired')),
    message TEXT, -- 招待メッセージ
    
    -- タイムスタンプ
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    responded_at TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP + INTERVAL '7 days'),
    
    -- 同じユーザーが同じグループに複数の未処理招待を持てないように制約
    UNIQUE(group_id, invitee_id, status)
);

-- 4. グループデートリクエストテーブル
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

-- 5. グループデートリクエスト回答テーブル
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
-- groupsテーブル
CREATE INDEX IF NOT EXISTS idx_groups_created_by ON groups(created_by);
CREATE INDEX IF NOT EXISTS idx_groups_created_at ON groups(created_at);
CREATE INDEX IF NOT EXISTS idx_groups_is_private ON groups(is_private);

-- group_membersテーブル
CREATE INDEX IF NOT EXISTS idx_group_members_group ON group_members(group_id);
CREATE INDEX IF NOT EXISTS idx_group_members_user ON group_members(user_id);
CREATE INDEX IF NOT EXISTS idx_group_members_role ON group_members(role);
CREATE INDEX IF NOT EXISTS idx_group_members_is_active ON group_members(is_active);
CREATE INDEX IF NOT EXISTS idx_group_members_joined_at ON group_members(joined_at);

-- group_invitationsテーブル
CREATE INDEX IF NOT EXISTS idx_group_invitations_group ON group_invitations(group_id);
CREATE INDEX IF NOT EXISTS idx_group_invitations_inviter ON group_invitations(inviter_id);
CREATE INDEX IF NOT EXISTS idx_group_invitations_invitee ON group_invitations(invitee_id);
CREATE INDEX IF NOT EXISTS idx_group_invitations_status ON group_invitations(status);
CREATE INDEX IF NOT EXISTS idx_group_invitations_created_at ON group_invitations(created_at);

-- group_date_requestsテーブル
CREATE INDEX IF NOT EXISTS idx_group_date_requests_requester ON group_date_requests(requester_id);
CREATE INDEX IF NOT EXISTS idx_group_date_requests_group ON group_date_requests(group_id);
CREATE INDEX IF NOT EXISTS idx_group_date_requests_restaurant ON group_date_requests(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_group_date_requests_status ON group_date_requests(status);
CREATE INDEX IF NOT EXISTS idx_group_date_requests_created_at ON group_date_requests(created_at);

-- group_date_responsesテーブル
CREATE INDEX IF NOT EXISTS idx_group_date_responses_request ON group_date_responses(request_id);
CREATE INDEX IF NOT EXISTS idx_group_date_responses_user ON group_date_responses(user_id);
CREATE INDEX IF NOT EXISTS idx_group_date_responses_response ON group_date_responses(response);
CREATE INDEX IF NOT EXISTS idx_group_date_responses_created_at ON group_date_responses(created_at);

-- 更新時刻自動更新のトリガー
CREATE OR REPLACE FUNCTION update_groups_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_groups_updated_at
    BEFORE UPDATE ON groups
    FOR EACH ROW
    EXECUTE FUNCTION update_groups_updated_at();

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