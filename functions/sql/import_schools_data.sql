-- school.csvデータインポート用の一時テーブル作成
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

-- CSVデータをCOPYコマンドでインポート
-- \copy temp_schools_import FROM 'school.csv' WITH CSV HEADER;

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
    SUBSTRING(prefecture_code_raw FROM '(\d+)') as prefecture_code,
    CASE SUBSTRING(prefecture_code_raw FROM '(\d+)')
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
    CASE SUBSTRING(establishment_type_raw FROM '(\d+)')
        WHEN '1' THEN 'national'
        WHEN '2' THEN 'public'
        WHEN '3' THEN 'private'
        ELSE 'private'
    END as establishment_type,
    CASE SUBSTRING(campus_type_raw FROM '(\d+)')
        WHEN '1' THEN 'main'
        WHEN '2' THEN 'branch'
        ELSE 'main'
    END as campus_type,
    postal_code,
    address,
    (delete_date IS NULL OR delete_date = '') as is_active
FROM temp_schools_import
WHERE school_name IS NOT NULL AND school_name != '';

-- 主要大学の略称を追加
INSERT INTO school_aliases (school_id, alias_name, alias_type) VALUES
-- 国立大学の略称
((SELECT id FROM schools WHERE school_name = '東京大学' LIMIT 1), '東大', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '京都大学' LIMIT 1), '京大', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '大阪大学' LIMIT 1), '阪大', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '東北大学' LIMIT 1), '東北大', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '名古屋大学' LIMIT 1), '名大', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '九州大学' LIMIT 1), '九大', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '北海道大学' LIMIT 1), '北大', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '一橋大学' LIMIT 1), '一橋', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '東京工業大学' LIMIT 1), '東工大', 'abbreviation'),

-- 私立大学の略称
((SELECT id FROM schools WHERE school_name = '早稲田大学' LIMIT 1), '早稲田', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '早稲田大学' LIMIT 1), '早大', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '慶應義塾大学' LIMIT 1), '慶應', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '慶應義塾大学' LIMIT 1), '慶応', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '慶應義塾大学' LIMIT 1), '慶大', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '上智大学' LIMIT 1), '上智', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '明治大学' LIMIT 1), '明治', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '立教大学' LIMIT 1), '立教', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '中央大学' LIMIT 1), '中央', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '法政大学' LIMIT 1), '法政', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '青山学院大学' LIMIT 1), '青学', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '学習院大学' LIMIT 1), '学習院', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '関西大学' LIMIT 1), '関大', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '関西学院大学' LIMIT 1), '関学', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '同志社大学' LIMIT 1), '同志社', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '立命館大学' LIMIT 1), '立命館', 'abbreviation'),

-- その他の略称や通称
((SELECT id FROM schools WHERE school_name = '東京理科大学' LIMIT 1), '理科大', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '日本大学' LIMIT 1), '日大', 'abbreviation'),
((SELECT id FROM schools WHERE school_name = '東海大学' LIMIT 1), '東海大', 'abbreviation')
WHERE NOT EXISTS (
    SELECT 1 FROM school_aliases 
    WHERE school_id = (SELECT id FROM schools WHERE school_name = '東京大学' LIMIT 1)
    AND alias_name = '東大'
);

-- 統計情報の更新
ANALYZE schools;
ANALYZE school_aliases; 