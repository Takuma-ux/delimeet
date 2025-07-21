-- 退会機能に必要なカラムを追加するスクリプト
-- 実行前にバックアップを取ることを推奨

-- usersテーブルに退会関連のカラムを追加
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS deactivated_at TIMESTAMP WITH TIME ZONE;

-- account_statusカラムが存在しない場合は追加
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'users' AND column_name = 'account_status'
    ) THEN
        ALTER TABLE users ADD COLUMN account_status VARCHAR(20) DEFAULT 'active' CHECK (account_status IN ('active', 'warned', 'suspended', 'banned', 'deactivated'));
    END IF;
END $$;

-- matchesテーブルの既存データを確認・修正
DO $$
DECLARE
    invalid_status_count INTEGER;
BEGIN
    -- 現在のmatchesテーブルのstatusカラムの値を確認
    SELECT COUNT(*) INTO invalid_status_count
    FROM matches 
    WHERE status IS NOT NULL 
    AND status NOT IN ('active', 'deactivated', 'ended');
    
    -- 無効なステータスがある場合はログ出力
    IF invalid_status_count > 0 THEN
        RAISE NOTICE 'Found % rows with invalid status in matches table', invalid_status_count;
        
        -- 無効なステータスを'active'に変更
        UPDATE matches 
        SET status = 'active' 
        WHERE status IS NOT NULL 
        AND status NOT IN ('active', 'deactivated', 'ended');
        
        RAISE NOTICE 'Updated % rows to have status = active', invalid_status_count;
    END IF;
END $$;

-- matchesテーブルにdeactivatedステータスを追加
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'matches' AND column_name = 'status'
    ) THEN
        ALTER TABLE matches ADD COLUMN status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'deactivated', 'ended'));
    ELSE
        -- 既存のstatusカラムの制約を更新
        ALTER TABLE matches DROP CONSTRAINT IF EXISTS matches_status_check;
        ALTER TABLE matches ADD CONSTRAINT matches_status_check 
        CHECK (status IN ('active', 'deactivated', 'ended'));
    END IF;
END $$;

-- インデックスを作成
CREATE INDEX IF NOT EXISTS idx_users_account_status ON users(account_status);
CREATE INDEX IF NOT EXISTS idx_users_deactivated_at ON users(deactivated_at);
CREATE INDEX IF NOT EXISTS idx_matches_status ON matches(status);

-- 既存のアクティブユーザーのaccount_statusを確認・更新
UPDATE users 
SET account_status = 'active' 
WHERE account_status IS NULL;

-- コメントを追加
COMMENT ON COLUMN users.account_status IS 'アカウントステータス: active, warned, suspended, banned, deactivated';
COMMENT ON COLUMN users.deactivated_at IS '退会日時';
COMMENT ON COLUMN matches.status IS 'マッチステータス: active, deactivated, ended'; 