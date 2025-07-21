-- messagesテーブルのmessage_type制約に'image'を追加（既存制約を保持）
-- 既存の制約を削除
ALTER TABLE messages DROP CONSTRAINT IF EXISTS messages_message_type_check;

-- 新しい制約を追加（既存の'text', 'date_request', 'date_response', 'system'に'image'を追加）
ALTER TABLE messages 
ADD CONSTRAINT messages_message_type_check 
CHECK (message_type IN ('text', 'date_request', 'date_response', 'system', 'image'));

-- 確認用クエリ：現在のメッセージタイプ分布を確認
SELECT 
    message_type,
    COUNT(*) as count
FROM messages 
GROUP BY message_type
ORDER BY message_type;

-- 制約確認
SELECT 
    conname as constraint_name,
    pg_get_constraintdef(oid) as constraint_definition
FROM pg_constraint 
WHERE conrelid = 'messages'::regclass 
AND contype = 'c' 
AND conname = 'messages_message_type_check'; 