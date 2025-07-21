-- messagesテーブルのmessage_type制約を安全に修正するスクリプト
-- 既存データを確認してから制約を更新

-- 1. 現在のmessage_typeの分布を確認
SELECT 
    message_type,
    COUNT(*) as count
FROM messages 
GROUP BY message_type
ORDER BY message_type;

-- 2. 制約に違反するデータがあるかチェック
SELECT 
    message_type,
    COUNT(*) as count
FROM messages 
WHERE message_type NOT IN ('text', 'date_request', 'date_response', 'system', 'image', 'date_decision', 'restaurant_decision', 'restaurant_voting', 'restaurant_voting_response')
GROUP BY message_type;

-- 4. 既存の制約を削除
ALTER TABLE messages DROP CONSTRAINT IF EXISTS messages_message_type_check;

-- 5. 新しい制約を追加（すべての既存タイプを含む）
ALTER TABLE messages 
ADD CONSTRAINT messages_message_type_check 
CHECK (message_type IN ('text', 'date_request', 'date_response', 'system', 'image', 'date_decision', 'restaurant_decision', 'restaurant_voting', 'restaurant_voting_response'));

-- 6. 修正後の確認
SELECT 
    message_type,
    COUNT(*) as count
FROM messages 
GROUP BY message_type
ORDER BY message_type;

-- 7. 制約が正しく適用されているか確認
SELECT 
    conname as constraint_name,
    pg_get_constraintdef(oid) as constraint_definition
FROM pg_constraint 
WHERE conrelid = 'messages'::regclass 
AND contype = 'c' 
AND conname = 'messages_message_type_check'; 