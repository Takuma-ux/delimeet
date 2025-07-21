-- messagesテーブルの拡張：メッセージタイプとデートリクエストデータ
ALTER TABLE messages 
ADD COLUMN IF NOT EXISTS message_type VARCHAR(20) DEFAULT 'text' 
CHECK (message_type IN ('text', 'date_request', 'date_response', 'system'));

-- デートリクエスト固有のデータを格納するJSONBカラム
ALTER TABLE messages 
ADD COLUMN IF NOT EXISTS date_request_data JSONB;

-- リクエストIDへの参照（date_requestsテーブルとの紐付け）
ALTER TABLE messages 
ADD COLUMN IF NOT EXISTS related_date_request_id UUID 
REFERENCES date_requests(id) ON DELETE SET NULL;

-- インデックス追加
CREATE INDEX IF NOT EXISTS idx_messages_message_type ON messages(message_type);
CREATE INDEX IF NOT EXISTS idx_messages_date_request_data ON messages USING GIN (date_request_data);
CREATE INDEX IF NOT EXISTS idx_messages_related_request ON messages(related_date_request_id);

-- メッセージタイプ別の確認用クエリ
SELECT 
    message_type,
    COUNT(*) as count,
    COUNT(date_request_data) as with_request_data,
    COUNT(related_date_request_id) as with_request_id
FROM messages 
GROUP BY message_type; 