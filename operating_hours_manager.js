/**
 * 営業時間データ管理ユーティリティ
 * レストランの営業時間データを効率的に処理・管理するためのクラス
 */

class OperatingHoursManager {
  constructor() {
    this.dayNames = ['日', '月', '火', '水', '木', '金', '土'];
    this.dayNamesEn = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  }

  /**
   * 営業時間データを正規化（重複除去・最適化）
   * @param {Object} operatingData - レストランの営業時間データ
   * @returns {Object} - 正規化された営業時間データ
   */
  normalizeOperatingHours(operatingData) {
    if (!operatingData.operating_hours || !Array.isArray(operatingData.operating_hours)) {
      return operatingData;
    }

    const normalized = [];
    const processedCombinations = new Set();

    operatingData.operating_hours.forEach(schedule => {
      const key = `${schedule.days.sort().join(',')}_${schedule.open_time}_${schedule.close_time}`;
      
      if (!processedCombinations.has(key)) {
        processedCombinations.add(key);
        normalized.push({
          ...schedule,
          days: [...schedule.days].sort() // 曜日を昇順にソート
        });
      }
    });

    return {
      ...operatingData,
      operating_hours: normalized
    };
  }

  /**
   * 指定日時にレストランが営業中かチェック
   * @param {Object} operatingData - レストランの営業時間データ
   * @param {Date} targetDate - チェック対象の日時
   * @returns {boolean} - 営業中の場合true
   */
  isOpenAt(operatingData, targetDate) {
    if (!operatingData.operating_hours) return false;

    const dayOfWeek = targetDate.getDay();
    const timeString = targetDate.toTimeString().slice(0, 5); // "HH:MM"形式

    // 定休日チェック
    if (operatingData.closed_days && operatingData.closed_days.includes(dayOfWeek)) {
      return false;
    }

    // 営業時間チェック
    for (const schedule of operatingData.operating_hours) {
      if (schedule.days.includes(dayOfWeek)) {
        if (this.isTimeInRange(timeString, schedule.open_time, schedule.close_time)) {
          return true;
        }
      }
    }

    return false;
  }

  /**
   * 指定した日にレストランが営業しているかチェック
   * @param {Object} operatingData - レストランの営業時間データ
   * @param {Date} targetDate - チェック対象の日付
   * @returns {boolean} - 営業日の場合true
   */
  isOpenOnDate(operatingData, targetDate) {
    if (!operatingData.operating_hours) return false;

    const dayOfWeek = targetDate.getDay();

    // 定休日チェック
    if (operatingData.closed_days && operatingData.closed_days.includes(dayOfWeek)) {
      return false;
    }

    // その日に営業時間が設定されているかチェック
    return operatingData.operating_hours.some(schedule => 
      schedule.days.includes(dayOfWeek)
    );
  }

  /**
   * 時刻が営業時間範囲内かチェック
   * @param {string} time - チェック対象時刻 "HH:MM"
   * @param {string} openTime - 開店時刻 "HH:MM"
   * @param {string} closeTime - 閉店時刻 "HH:MM"
   * @returns {boolean}
   */
  isTimeInRange(time, openTime, closeTime) {
    const timeMinutes = this.timeToMinutes(time);
    const openMinutes = this.timeToMinutes(openTime);
    let closeMinutes = this.timeToMinutes(closeTime);

    // 翌日営業の場合（例：23:00～02:00）
    if (closeMinutes <= openMinutes) {
      closeMinutes += 24 * 60; // 翌日に調整
      
      // 時刻が翌日の場合も考慮
      if (timeMinutes < openMinutes) {
        return timeMinutes + 24 * 60 <= closeMinutes;
      }
    }

    return timeMinutes >= openMinutes && timeMinutes <= closeMinutes;
  }

  /**
   * 時刻文字列を分に変換
   * @param {string} time - "HH:MM"形式の時刻
   * @returns {number} - 分単位の時刻
   */
  timeToMinutes(time) {
    const [hours, minutes] = time.split(':').map(Number);
    return hours * 60 + minutes;
  }

  /**
   * 営業時間の人間向け表示文字列を生成
   * @param {Object} operatingData - レストランの営業時間データ
   * @returns {string} - 表示用文字列
   */
  formatForDisplay(operatingData) {
    if (!operatingData.operating_hours || operatingData.operating_hours.length === 0) {
      return '営業時間情報なし';
    }

    const schedules = this.normalizeOperatingHours(operatingData).operating_hours;
    const grouped = this.groupSchedulesByTime(schedules);

    return grouped.map(group => {
      const dayStr = this.formatDays(group.days);
      return `${dayStr}: ${group.open_time}～${group.close_time}`;
    }).join('\n');
  }

  /**
   * 営業時間を時間帯でグループ化
   * @param {Array} schedules - 営業スケジュール配列
   * @returns {Array} - グループ化された営業時間
   */
  groupSchedulesByTime(schedules) {
    const grouped = new Map();

    schedules.forEach(schedule => {
      const timeKey = `${schedule.open_time}_${schedule.close_time}`;
      
      if (grouped.has(timeKey)) {
        const existing = grouped.get(timeKey);
        existing.days = [...new Set([...existing.days, ...schedule.days])].sort();
      } else {
        grouped.set(timeKey, {
          days: [...schedule.days],
          open_time: schedule.open_time,
          close_time: schedule.close_time
        });
      }
    });

    return Array.from(grouped.values());
  }

  /**
   * 曜日配列を読みやすい文字列に変換
   * @param {Array} days - 曜日番号の配列 [0,1,2,3,4,5,6]
   * @returns {string} - 曜日の表示文字列
   */
  formatDays(days) {
    if (!days || days.length === 0) return '';
    
    const sortedDays = [...days].sort();
    
    // 全曜日の場合
    if (sortedDays.length === 7) return '毎日';
    
    // 連続する曜日をまとめる
    const ranges = [];
    let start = sortedDays[0];
    let end = start;
    
    for (let i = 1; i <= sortedDays.length; i++) {
      if (i < sortedDays.length && sortedDays[i] === end + 1) {
        end = sortedDays[i];
      } else {
        if (start === end) {
          ranges.push(this.dayNames[start]);
        } else if (end === start + 1) {
          ranges.push(`${this.dayNames[start]}・${this.dayNames[end]}`);
        } else {
          ranges.push(`${this.dayNames[start]}～${this.dayNames[end]}`);
        }
        
        if (i < sortedDays.length) {
          start = sortedDays[i];
          end = start;
        }
      }
    }
    
    return ranges.join('、');
  }

  /**
   * デート可能な時間帯をチェック
   * @param {Array} restaurants - レストラン配列
   * @param {Date} dateTime - デート予定日時
   * @returns {Array} - 営業中のレストラン配列
   */
  filterOpenRestaurants(restaurants, dateTime) {
    return restaurants.filter(restaurant => {
      if (!restaurant.operating_hours) return false;
      return this.isOpenAt(restaurant.operating_hours, dateTime);
    });
  }

  /**
   * レストランの今日の営業時間を取得
   * @param {Object} operatingData - レストランの営業時間データ
   * @param {Date} date - 対象日（デフォルト：今日）
   * @returns {Array} - その日の営業時間配列
   */
  getTodaysHours(operatingData, date = new Date()) {
    if (!operatingData.operating_hours) return [];

    const dayOfWeek = date.getDay();
    
    return operatingData.operating_hours
      .filter(schedule => schedule.days.includes(dayOfWeek))
      .map(schedule => ({
        open_time: schedule.open_time,
        close_time: schedule.close_time,
        period_type: schedule.period_type || 'default'
      }));
  }

  /**
   * データの検証
   * @param {Object} operatingData - 営業時間データ
   * @returns {Object} - 検証結果
   */
  validateData(operatingData) {
    const errors = [];
    const warnings = [];

    if (!operatingData) {
      errors.push('営業時間データがありません');
      return { valid: false, errors, warnings };
    }

    if (!operatingData.operating_hours || !Array.isArray(operatingData.operating_hours)) {
      errors.push('operating_hoursが配列ではありません');
      return { valid: false, errors, warnings };
    }

    // 各スケジュールの検証
    operatingData.operating_hours.forEach((schedule, index) => {
      if (!schedule.days || !Array.isArray(schedule.days)) {
        errors.push(`schedule[${index}]: daysが配列ではありません`);
      }

      if (!schedule.open_time || !schedule.close_time) {
        errors.push(`schedule[${index}]: 開店・閉店時刻が設定されていません`);
      }

      // 時刻フォーマットの検証
      const timeRegex = /^([01]?[0-9]|2[0-3]):[0-5][0-9]$/;
      if (schedule.open_time && !timeRegex.test(schedule.open_time)) {
        warnings.push(`schedule[${index}]: 開店時刻のフォーマットが不正です`);
      }
      if (schedule.close_time && !timeRegex.test(schedule.close_time)) {
        warnings.push(`schedule[${index}]: 閉店時刻のフォーマットが不正です`);
      }
    });

    return {
      valid: errors.length === 0,
      errors,
      warnings
    };
  }
}

// 使用例
const manager = new OperatingHoursManager();

// サンプルデータで使用例を示す
const sampleData = {
  "success": true,
  "batch_id": 3,
  "closed_days": [],
  "source_text": "月～金、祝前日: 11:00～14:00 17:00～22:00 土: 17:00～22:00",
  "processed_at": "2025-06-27T17:15:18.485228+00:00",
  "operating_hours": [
    {"days": [1,2,3,4,5], "open_time": "11:00", "close_time": "14:00", "period_type": "default"},
    {"days": [1,2,3,4,5], "open_time": "17:00", "close_time": "22:00", "period_type": "default"},
    {"days": [6], "open_time": "17:00", "close_time": "22:00", "period_type": "default"}
  ]
};

console.log('=== 営業時間管理システム使用例 ===');
console.log('1. データ正規化:');
console.log(JSON.stringify(manager.normalizeOperatingHours(sampleData), null, 2));

console.log('\n2. 表示用フォーマット:');
console.log(manager.formatForDisplay(sampleData));

console.log('\n3. 営業中チェック（金曜12:00）:');
const fridayNoon = new Date('2025-06-27T12:00:00');
console.log(manager.isOpenAt(sampleData, fridayNoon));

console.log('\n4. データ検証:');
console.log(manager.validateData(sampleData));

module.exports = OperatingHoursManager; 