-- 既存テーブルの状況確認
-- Supabase SQL Editor で実行して現在の状態を確認

-- 1. 既存テーブルの確認
SELECT 
    table_name,
    table_type
FROM information_schema.tables 
WHERE table_schema = 'public' 
    AND table_name IN ('schools', 'school_aliases', 'temp_schools_import');

-- 2. schoolsテーブルのデータ確認
SELECT 
    'schools' as table_name,
    COUNT(*) as record_count,
    MIN(created_at) as first_record,
    MAX(created_at) as last_record
FROM schools
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'schools');

-- 3. school_aliasesテーブルのデータ確認  
SELECT 
    'school_aliases' as table_name,
    COUNT(*) as record_count,
    MIN(created_at) as first_record,
    MAX(created_at) as last_record
FROM school_aliases
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'school_aliases');

-- 4. インデックスの確認（重要：japanese設定のインデックスがあるかチェック）
SELECT 
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes 
WHERE tablename IN ('schools', 'school_aliases')
    AND schemaname = 'public'
ORDER BY tablename, indexname;

-- 5. usersテーブルのschool_idカラム確認
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns 
WHERE table_name = 'users' 
    AND column_name = 'school_id';

-- 6. エラーの原因となったインデックスの存在確認
SELECT COUNT(*) as japanese_indexes
FROM pg_indexes 
WHERE indexdef LIKE '%japanese%'
    AND tablename IN ('schools', 'school_aliases'); 