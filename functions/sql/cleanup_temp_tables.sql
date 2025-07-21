-- インポート完了後の一時テーブル削除
-- 注意: インポートが完了し、データが正常に schools テーブルに移行されたことを確認してから実行

-- インポート前後のデータ確認
SELECT 'temp_schools_import' as table_name, COUNT(*) as record_count FROM temp_schools_import
UNION ALL
SELECT 'schools' as table_name, COUNT(*) as record_count FROM schools
UNION ALL
SELECT 'school_aliases' as table_name, COUNT(*) as record_count FROM school_aliases;

-- 確認後、問題なければ一時テーブルを削除
-- DROP TABLE IF EXISTS temp_schools_import;

-- 削除実行後は以下のコメントアウトを外してください
-- SELECT 'Cleanup completed. temp_schools_import table has been dropped.' as status; 