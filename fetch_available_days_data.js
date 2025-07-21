// Node.js環境でSupabaseからデータを取得してJSONファイルに保存
// npm install @supabase/supabase-js

const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');

// Supabaseの設定（環境変数から取得）
const supabaseUrl = process.env.SUPABASE_URL || 'YOUR_SUPABASE_URL';
const supabaseKey = process.env.SUPABASE_ANON_KEY || 'YOUR_SUPABASE_ANON_KEY';

const supabase = createClient(supabaseUrl, supabaseKey);

async function fetchAvailableDaysData() {
  try {
    console.log('データ取得開始...');
    
    // available_daysデータを取得
    const { data, error } = await supabase
      .from('restaurants')
      .select('id, name, category, available_days')
      .not('available_days', 'is', null)
      .limit(1000);

    if (error) {
      console.error('エラー:', error);
      return;
    }

    // データを分析
    const analysis = {
      total_count: data.length,
      categories: {},
      open_patterns: {},
      close_patterns: {},
      memo_patterns: {},
      samples: data.slice(0, 50) // 最初の50件をサンプルとして保存
    };

    // カテゴリ別集計
    data.forEach(restaurant => {
      const category = restaurant.category || 'unknown';
      if (!analysis.categories[category]) {
        analysis.categories[category] = 0;
      }
      analysis.categories[category]++;

      // openパターンの集計
      if (restaurant.available_days?.open) {
        const openPattern = restaurant.available_days.open;
        if (!analysis.open_patterns[openPattern]) {
          analysis.open_patterns[openPattern] = 0;
        }
        analysis.open_patterns[openPattern]++;
      }

      // closeパターンの集計
      if (restaurant.available_days?.close) {
        const closePattern = restaurant.available_days.close;
        if (!analysis.close_patterns[closePattern]) {
          analysis.close_patterns[closePattern] = 0;
        }
        analysis.close_patterns[closePattern]++;
      }

      // memoパターンの集計
      if (restaurant.available_days?.memo) {
        const memoPattern = restaurant.available_days.memo;
        if (!analysis.memo_patterns[memoPattern]) {
          analysis.memo_patterns[memoPattern] = 0;
        }
        analysis.memo_patterns[memoPattern]++;
      }
    });

    // 結果をJSONファイルに保存
    const fileName = `available_days_analysis_${new Date().toISOString().split('T')[0]}.json`;
    fs.writeFileSync(fileName, JSON.stringify(analysis, null, 2));
    
    console.log(`データ分析完了: ${fileName} に保存しました`);
    console.log(`総レストラン数: ${analysis.total_count}`);
    console.log(`カテゴリ数: ${Object.keys(analysis.categories).length}`);
    console.log(`開店時間パターン数: ${Object.keys(analysis.open_patterns).length}`);
    
  } catch (error) {
    console.error('取得エラー:', error);
  }
}

// 実行
fetchAvailableDaysData(); 