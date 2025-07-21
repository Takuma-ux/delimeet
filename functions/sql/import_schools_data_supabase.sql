-- Supabase用 学校データインポートSQL
-- 注意: このスクリプトはSupabaseのSQL Editorで実行してください

-- 一時テーブル作成（トランザクション内で実行）
BEGIN;

CREATE TEMP TABLE temp_schools_import (
    school_code TEXT,
    school_type_raw TEXT,
    prefecture_code_raw TEXT,
    establishment_type_raw TEXT,
    campus_type_raw TEXT,
    school_name TEXT,
    address TEXT,
    postal_code TEXT,
    attr_date TEXT,
    delete_date TEXT,
    old_number TEXT,
    migrated_code TEXT
);

-- CSVデータをSupabaseにインポートする際の手順：
-- 1. Supabase Dashboard > SQL Editor を開く
-- 2. 下記のSQLを実行してテーブルを作成
-- 3. Dashboard > Table Editor > temp_schools_import テーブルを選択
-- 4. "Import data via CSV" ボタンをクリック
-- 5. school.csv ファイルをアップロード

-- または、下記のINSERT文を使用してデータを挿入（例）
-- INSERT INTO temp_schools_import VALUES 
-- ('F101110100010','F1(大学)','01(北海道)','1(国)','1(本)','北海道大学','北海道札幌市北区北８条西５丁目','0600808','2021-01-20','','0100',''),
-- ... 他のデータ

-- 学校マスターテーブルにデータを挿入
INSERT INTO schools (
    school_code,
    school_name,
    school_type,
    prefecture_code,
    prefecture_name,
    establishment_type,
    campus_type,
    postal_code,
    address,
    is_active
)
SELECT 
    school_code,
    school_name,
    CASE 
        WHEN school_type_raw LIKE 'F1(%' THEN 'university'
        WHEN school_type_raw LIKE 'F2(%' THEN 'junior_college'
        WHEN school_type_raw LIKE 'F3(%' THEN 'technical_college'
        ELSE 'university'
    END as school_type,
    REGEXP_REPLACE(prefecture_code_raw, '[^0-9]', '', 'g') as prefecture_code,
    CASE REGEXP_REPLACE(prefecture_code_raw, '[^0-9]', '', 'g')
        WHEN '01' THEN '北海道'
        WHEN '02' THEN '青森県'
        WHEN '03' THEN '岩手県'
        WHEN '04' THEN '宮城県'
        WHEN '05' THEN '秋田県'
        WHEN '06' THEN '山形県'
        WHEN '07' THEN '福島県'
        WHEN '08' THEN '茨城県'
        WHEN '09' THEN '栃木県'
        WHEN '10' THEN '群馬県'
        WHEN '11' THEN '埼玉県'
        WHEN '12' THEN '千葉県'
        WHEN '13' THEN '東京都'
        WHEN '14' THEN '神奈川県'
        WHEN '15' THEN '新潟県'
        WHEN '16' THEN '富山県'
        WHEN '17' THEN '石川県'
        WHEN '18' THEN '福井県'
        WHEN '19' THEN '山梨県'
        WHEN '20' THEN '長野県'
        WHEN '21' THEN '岐阜県'
        WHEN '22' THEN '静岡県'
        WHEN '23' THEN '愛知県'
        WHEN '24' THEN '三重県'
        WHEN '25' THEN '滋賀県'
        WHEN '26' THEN '京都府'
        WHEN '27' THEN '大阪府'
        WHEN '28' THEN '兵庫県'
        WHEN '29' THEN '奈良県'
        WHEN '30' THEN '和歌山県'
        WHEN '31' THEN '鳥取県'
        WHEN '32' THEN '島根県'
        WHEN '33' THEN '岡山県'
        WHEN '34' THEN '広島県'
        WHEN '35' THEN '山口県'
        WHEN '36' THEN '徳島県'
        WHEN '37' THEN '香川県'
        WHEN '38' THEN '愛媛県'
        WHEN '39' THEN '高知県'
        WHEN '40' THEN '福岡県'
        WHEN '41' THEN '佐賀県'
        WHEN '42' THEN '長崎県'
        WHEN '43' THEN '熊本県'
        WHEN '44' THEN '大分県'
        WHEN '45' THEN '宮崎県'
        WHEN '46' THEN '鹿児島県'
        WHEN '47' THEN '沖縄県'
        ELSE '不明'
    END as prefecture_name,
    CASE REGEXP_REPLACE(establishment_type_raw, '[^0-9]', '', 'g')
        WHEN '1' THEN 'national'
        WHEN '2' THEN 'public'
        WHEN '3' THEN 'private'
        ELSE 'private'
    END as establishment_type,
    CASE REGEXP_REPLACE(campus_type_raw, '[^0-9]', '', 'g')
        WHEN '1' THEN 'main'
        WHEN '2' THEN 'branch'
        ELSE 'main'
    END as campus_type,
    postal_code,
    address,
    (delete_date IS NULL OR delete_date = '') as is_active
FROM temp_schools_import
WHERE school_name IS NOT NULL AND school_name != ''
ON CONFLICT (school_code) DO NOTHING;  -- 重複データは無視

COMMIT;

-- 主要大学の略称を追加
-- この部分は学校データインポート後に実行
INSERT INTO school_aliases (school_id, alias_name, alias_type) 
SELECT s.id, alias_info.alias_name, alias_info.alias_type
FROM schools s
CROSS JOIN (
    VALUES 
    ('東京大学', '東大', 'abbreviation'),
    ('京都大学', '京大', 'abbreviation'),
    ('大阪大学', '阪大', 'abbreviation'),
    ('東北大学', '東北大', 'abbreviation'),
    ('名古屋大学', '名大', 'abbreviation'),
    ('九州大学', '九大', 'abbreviation'),
    ('北海道大学', '北大', 'abbreviation'),
    ('一橋大学', '一橋', 'abbreviation'),
    ('東京工業大学', '東工大', 'abbreviation'),
    ('早稲田大学', '早稲田', 'abbreviation'),
    ('早稲田大学', '早大', 'abbreviation'),
    ('慶應義塾大学', '慶應', 'abbreviation'),
    ('慶應義塾大学', '慶応', 'abbreviation'),
    ('慶應義塾大学', '慶大', 'abbreviation'),
    ('上智大学', '上智', 'abbreviation'),
    ('明治大学', '明治', 'abbreviation'),
    ('立教大学', '立教', 'abbreviation'),
    ('中央大学', '中央', 'abbreviation'),
    ('法政大学', '法政', 'abbreviation'),
    ('青山学院大学', '青学', 'abbreviation'),
    ('学習院大学', '学習院', 'abbreviation'),
    ('関西大学', '関大', 'abbreviation'),
    ('関西学院大学', '関学', 'abbreviation'),
    ('同志社大学', '同志社', 'abbreviation'),
    ('立命館大学', '立命館', 'abbreviation'),
    ('東京理科大学', '理科大', 'abbreviation'),
    ('日本大学', '日大', 'abbreviation'),
    ('東海大学', '東海大', 'abbreviation')
) AS alias_info(school_name, alias_name, alias_type)
WHERE s.school_name = alias_info.school_name
ON CONFLICT (school_id, alias_name) DO NOTHING;  -- 重複は無視

-- 統計情報の更新
ANALYZE schools;
ANALYZE school_aliases; 