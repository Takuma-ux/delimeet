-- マッチしたい人の特徴カラムを追加
ALTER TABLE users 
ADD COLUMN preferred_age_range VARCHAR(20),
ADD COLUMN payment_preference VARCHAR(20),
ADD COLUMN preferred_gender VARCHAR(10);

-- カラムにコメントを追加
COMMENT ON COLUMN users.preferred_age_range IS 'マッチしたい相手の年齢層 (例: 18-22, 23-27, 28-32, 33-37, 38-42, 43+)';
COMMENT ON COLUMN users.payment_preference IS '支払い希望 (split: 割り勘希望, pay: 奢りたい, be_paid: 奢られたい)';
COMMENT ON COLUMN users.preferred_gender IS 'マッチしたい相手の性別 (男性, 女性, どちらでも)'; 