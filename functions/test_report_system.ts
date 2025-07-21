import * as admin from "firebase-admin";
import {Pool} from "pg";
import * as dotenv from "dotenv";

// 環境変数を読み込み
dotenv.config();

// Firebase Admin初期化
if (!admin.apps.length) {
  admin.initializeApp();
}

// PostgreSQL接続設定
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === "production" ? {rejectUnauthorized: false} : false,
});

console.log("🔧 データベース接続設定:");
console.log("DATABASE_URL:", process.env.DATABASE_URL ? "設定済み" : "未設定");
console.log("NODE_ENV:", process.env.NODE_ENV || "未設定");

/**
 * テスト用ユーザーの通報数を直接設定
 * @param {string} userId - ユーザーID
 * @param {number} reportCount - 設定する通報数
 */
async function setUserReportCount(userId: string, reportCount: number) {
  try {
    await pool.query(
      "UPDATE users SET report_count = $1 WHERE id = $2",
      [reportCount, userId]
    );
    console.log(`✅ ユーザー ${userId} の通報数を ${reportCount} に設定`);
  } catch (error) {
    console.error("❌ 通報数設定失敗:", error);
  }
}

/**
 * 制限処理をテスト
 * @param {string} userId - ユーザーID
 * @param {number} reportCount - 通報数
 */
async function testRestrictions(userId: string, reportCount: number) {
  console.log(`\n🧪 テスト開始: ユーザー${userId}, 通報数${reportCount}`);

  let newStatus = "active";
  let suspensionUntil: string | null = null;
  let notificationMessage = "";

  if (reportCount >= 15) {
    newStatus = "banned";
    notificationMessage = "アカウントが永久停止されました。";
  } else if (reportCount >= 10) {
    newStatus = "suspended";
    const suspensionDate = new Date();
    suspensionDate.setMonth(suspensionDate.getMonth() + 1);
    suspensionUntil = suspensionDate.toISOString();
    notificationMessage = "アカウントが1ヶ月間停止されました。";
  } else if (reportCount >= 5) {
    newStatus = "suspended";
    const suspensionDate = new Date();
    suspensionDate.setDate(suspensionDate.getDate() + 7);
    suspensionUntil = suspensionDate.toISOString();
    notificationMessage = "アカウントが1週間停止されました。";
  } else if (reportCount >= 3) {
    newStatus = "warned";
    const suspensionDate = new Date();
    suspensionDate.setDate(suspensionDate.getDate() + 1);
    suspensionUntil = suspensionDate.toISOString();
    notificationMessage = "警告: 24時間のマッチング制限が適用されました。";
  }

  if (newStatus !== "active") {
    try {
      // まず基本的な更新を実行
      await pool.query(
        `UPDATE users
         SET account_status = $1,
             suspension_until = $2
         WHERE id = $3`,
        [newStatus, suspensionUntil, userId]
      );

      // 警告の場合のみ、last_warning_atを更新
      if (newStatus === "warned") {
        await pool.query(
          `UPDATE users
           SET last_warning_at = CURRENT_TIMESTAMP
           WHERE id = $1`,
          [userId]
        );
      }

      console.log(`🔒 制限適用: ${newStatus}`);
      console.log(`⏰ 制限期限: ${suspensionUntil}`);
      console.log(`📱 通知メッセージ: ${notificationMessage}`);

      // 結果確認
      const result = await pool.query(
        "SELECT account_status, suspension_until, last_warning_at FROM users WHERE id = $1",
        [userId]
      );

      console.log("📊 データベース確認:", result.rows[0]);
    } catch (error) {
      console.error("❌ 制限適用失敗:", error);
    }
  } else {
    console.log("✅ 制限なし (通報数が3未満)");
  }
}

/**
 * 特定ユーザーの現在の状態を確認
 * @param {string} userId - ユーザーID
 */
async function checkUserStatus(userId: string) {
  try {
    const result = await pool.query(
      `SELECT
         id, name, email, account_status, report_count,
         suspension_until, last_warning_at, created_at
       FROM users
       WHERE id = $1`,
      [userId]
    );

    if (result.rows.length > 0) {
      console.log("👤 ユーザー情報:", result.rows[0]);
    } else {
      console.log("❌ ユーザーが見つかりません");
    }
  } catch (error) {
    console.error("❌ ユーザー状態確認失敗:", error);
  }
}

/**
 * 通報履歴を確認
 * @param {string} userId - ユーザーID
 */
async function checkReportHistory(userId: string) {
  try {
    const result = await pool.query(
      `SELECT
         r.id, r.report_type, r.description, r.status, r.created_at,
         reporter.name as reporter_name
       FROM reports r
       JOIN users reporter ON r.reporter_id = reporter.id
       WHERE r.reported_user_id = $1
       ORDER BY r.created_at DESC`,
      [userId]
    );

    console.log(`📋 通報履歴 (${result.rows.length}件):`);
    result.rows.forEach((report, index) => {
      console.log(`${index + 1}. ${report.report_type} - ${report.description || "説明なし"}`);
      console.log(`   通報者: ${report.reporter_name}, 日時: ${report.created_at}`);
    });
  } catch (error) {
    console.error("❌ 通報履歴確認失敗:", error);
  }
}

/**
 * ユーザーの状態を完全にリセット（テスト後のクリーンアップ用）
 * @param {string} userId - ユーザーID
 */
async function resetUserStatus(userId: string) {
  try {
    await pool.query(
      `UPDATE users 
       SET account_status = 'active',
           report_count = 0,
           suspension_until = NULL,
           last_warning_at = NULL
       WHERE id = $1`,
      [userId]
    );
    
    console.log(`✅ ユーザー ${userId} の状態を完全にリセットしました`);
    
    // リセット後の状態確認
    const result = await pool.query(
      `SELECT account_status, report_count, suspension_until, last_warning_at 
       FROM users WHERE id = $1`,
      [userId]
    );
    
    console.log("📊 リセット後の状態:", result.rows[0]);
  } catch (error) {
    console.error("❌ ユーザー状態リセット失敗:", error);
  }
}

/**
 * テスト用通報データを削除
 * @param {string} userId - ユーザーID
 */
async function deleteTestReports(userId: string) {
  try {
    const result = await pool.query(
      "DELETE FROM reports WHERE reported_user_id = $1",
      [userId]
    );
    
    console.log(`✅ ${result.rowCount}件のテスト通報データを削除しました`);
  } catch (error) {
    console.error("❌ テスト通報データ削除失敗:", error);
  }
}

// メイン実行部分
const mode = process.argv[2];
const userId = process.argv[3];

switch (mode) {
  case "status":
    if (!userId) {
      console.error("使用方法: npm run test-reports status <user-id>");
      process.exit(1);
    }
    checkUserStatus(userId).then(() => process.exit(0));
    break;

  case "reports":
    if (!userId) {
      console.error("使用方法: npm run test-reports reports <user-id>");
      process.exit(1);
    }
    checkReportHistory(userId).then(() => process.exit(0));
    break;

  case "set-count":
    if (!userId || !process.argv[4]) {
      console.error("使用方法: npm run test-reports set-count <user-id> <count>");
      process.exit(1);
    }
    const count = parseInt(process.argv[4], 10);
    setUserReportCount(userId, count).then(() => process.exit(0));
    break;

  case "test-restrictions":
    if (!userId || !process.argv[4]) {
      console.error("使用方法: npm run test-reports test-restrictions <user-id> <count>");
      process.exit(1);
    }
    const testCount = parseInt(process.argv[4], 10);
    testRestrictions(userId, testCount).then(() => process.exit(0));
    break;

  case "reset-status":
    if (!userId) {
      console.error("使用方法: npm run test-reports reset-status <user-id>");
      process.exit(1);
    }
    resetUserStatus(userId).then(() => process.exit(0));
    break;

  case "delete-reports":
    if (!userId) {
      console.error("使用方法: npm run test-reports delete-reports <user-id>");
      process.exit(1);
    }
    deleteTestReports(userId).then(() => process.exit(0));
    break;

  default:
    console.log("使用方法:");
    console.log("  npm run test-reports status <user-id>                    # ユーザー状態確認");
    console.log("  npm run test-reports reports <user-id>                   # 通報履歴確認");
    console.log("  npm run test-reports set-count <user-id> <count>         # 通報数設定");
    console.log("  npm run test-reports test-restrictions <user-id> <count> # 制限テスト");
    console.log("  npm run test-reports reset-status <user-id>                # ユーザー状態リセット");
    console.log("  npm run test-reports delete-reports <user-id>               # テスト通報データ削除");
    process.exit(1);
} 