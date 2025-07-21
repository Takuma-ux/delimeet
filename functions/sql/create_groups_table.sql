-- グループテーブル
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

-- グループメンバーテーブル
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

-- グループ招待テーブル
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

-- インデックス作成
CREATE INDEX IF NOT EXISTS idx_groups_created_by ON groups(created_by);
CREATE INDEX IF NOT EXISTS idx_groups_created_at ON groups(created_at);
CREATE INDEX IF NOT EXISTS idx_groups_is_private ON groups(is_private);

CREATE INDEX IF NOT EXISTS idx_group_members_group ON group_members(group_id);
CREATE INDEX IF NOT EXISTS idx_group_members_user ON group_members(user_id);
CREATE INDEX IF NOT EXISTS idx_group_members_role ON group_members(role);
CREATE INDEX IF NOT EXISTS idx_group_members_is_active ON group_members(is_active);
CREATE INDEX IF NOT EXISTS idx_group_members_joined_at ON group_members(joined_at);

CREATE INDEX IF NOT EXISTS idx_group_invitations_group ON group_invitations(group_id);
CREATE INDEX IF NOT EXISTS idx_group_invitations_inviter ON group_invitations(inviter_id);
CREATE INDEX IF NOT EXISTS idx_group_invitations_invitee ON group_invitations(invitee_id);
CREATE INDEX IF NOT EXISTS idx_group_invitations_status ON group_invitations(status);
CREATE INDEX IF NOT EXISTS idx_group_invitations_created_at ON group_invitations(created_at);

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