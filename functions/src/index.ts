import * as functions from "firebase-functions";
import {onCall, HttpsError, CallableRequest, onRequest} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as dotenv from "dotenv";
import {Pool} from "pg";
import {v4 as uuidv4} from "uuid";
import axios from "axios";
dotenv.config();

// Firebase Admin SDK 初期化
if (!admin.apps.length) {
  admin.initializeApp();
}

// デートリクエスト機能をインポート
export * from "./date_requests";

// グループデートリクエスト機能をインポート
export * from "./group_date_requests";

// レビューシステム機能をインポート
export * from "./reviews";

// バッジ写真機能をインポート
export * from "./badge_photos";

/**
 * グループを作成する関数（Firestore対応）
 */
export const createGroup = onCall(
  async (request: CallableRequest): Promise<{
    success: boolean;
    groupId?: string;
    error?: string;
  }> => {
    console.log("🔍 createGroup関数開始");

    try {
      // Firebase Authenticationからユーザー情報を取得
      if (!request.auth) {
        console.error("❌ 認証エラー: request.authが存在しません");
        throw new HttpsError("unauthenticated", "認証が必要です");
      }

      const firebaseUid = request.auth.uid;
      console.log("🔍 Firebase UID:", firebaseUid);

      // リクエストデータを取得
      const {
        name,
        description,
        groupType = "general",
        restaurantInfo,
        eventDateTime,
        eventEndDateTime,
        minMembers,
        maxMembers = 100,
        isPublic = true,
        category,
        prefecture,
        nearestStation,
        imageUrl,
        tags,
      } = request.data;

      console.log("🔍 グループ作成データ:", {
        name,
        description,
        groupType,
        restaurantInfo,
        eventDateTime,
        minMembers,
        maxMembers,
        isPublic,
        category,
        prefecture,
        nearestStation,
        tags,
      });

      // 入力バリデーション
      if (!name || name.trim().length === 0) {
        throw new HttpsError("invalid-argument", "グループ名は必須です");
      }

      if (name.length > 100) {
        throw new HttpsError("invalid-argument", "グループ名は100文字以内で入力してください");
      }

      if (description && description.length > 500) {
        throw new HttpsError("invalid-argument", "説明は500文字以内で入力してください");
      }

      if (maxMembers && (maxMembers < 2 || maxMembers > 1000)) {
        throw new HttpsError("invalid-argument", "最大参加人数は2-1000人の間で設定してください");
      }

      if (minMembers && maxMembers && minMembers > maxMembers) {
        throw new HttpsError("invalid-argument", "最小参加人数は最大参加人数以下で設定してください");
      }

      // Firestoreにグループを作成
      const groupData = {
        name: name.trim(),
        description: description?.trim() || "",
        imageUrl: imageUrl || null,
        createdBy: firebaseUid,
        members: [firebaseUid],
        admins: [firebaseUid],
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastMessage: null,
        lastMessageAt: null,
        lastMessageBy: null,
        isPrivate: !isPublic,
        maxMembers: maxMembers,
        category: category || null,
        prefecture: prefecture || null,
        nearestStation: nearestStation || null,
        // 新しい募集機能用フィールド
        groupType: groupType,
        restaurantInfo: restaurantInfo || null,
        // 日時のタイムゾーン処理を修正（JST対応）
        eventDateTime: eventDateTime ? (() => {
          // ISO文字列をJSTとして解釈
          console.log("🕐 受信した日時（ISO文字列）:", eventDateTime);
          console.log("🕐 UTC時間:", new Date(eventDateTime).toISOString());
          console.log("🕐 JST時間:", new Date(eventDateTime).toLocaleString("ja-JP", {timeZone: "Asia/Tokyo"}));

          // 元のISO文字列がローカル時間（JST）だった場合、UTCとの差分を調整
          // Flutter側でローカル時間として作成された日時をそのまま保持
          const originalDate = new Date(eventDateTime.replace("Z", ""));
          console.log("🕐 調整後の日時:", originalDate);

          return admin.firestore.Timestamp.fromDate(originalDate);
        })() : null,
        eventEndDateTime: eventEndDateTime ? (() => {
          const originalDate = new Date(eventEndDateTime.replace("Z", ""));
          console.log("🕐 終了時間 - 受信:", eventEndDateTime);
          console.log("🕐 終了時間 - 調整後:", originalDate);
          return admin.firestore.Timestamp.fromDate(originalDate);
        })() : null,
        minMembers: minMembers || null,
        tags: tags || [],
      };

      console.log("🔍 Firestoreデータ:", groupData);

      // Firestoreにドキュメントを作成
      const groupRef = await admin.firestore().collection("groups").add(groupData);
      const groupId = groupRef.id;

      console.log("✅ グループ作成完了:", groupId);
      return {
        success: true,
        groupId,
      };
    } catch (error) {
      console.error("❌ グループ作成エラー:", error);

      const err = error as Error;
      console.error("❌ エラー詳細:", {
        name: err.name,
        message: err.message,
        stack: err.stack,
      });

      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError(
        "internal",
        `グループの作成に失敗しました: ${err.message}`
      );
    }
  }
);

/**
 * ユーザーのお気に入りレストラン一覧を取得
 */
export const getFavoriteRestaurants = onCall(
  async (request: CallableRequest): Promise<{
    restaurants: Array<{
      id: string;
      name: string;
      category?: string;
      prefecture?: string;
      nearest_station?: string;
      price_range?: string;
      image_url?: string;
      price_level?: number;
    }>;
  }> => {
    console.log("🔍 getFavoriteRestaurants関数開始");

    try {
      // Firebase Authenticationからユーザー情報を取得
      if (!request.auth) {
        console.error("❌ 認証エラー: request.authが存在しません");
        throw new HttpsError("unauthenticated", "認証が必要です");
      }

      const firebaseUid = request.auth.uid;
      console.log("🔍 Firebase UID:", firebaseUid);

      // Firebase UIDからユーザーUUIDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      console.log("🔍 ユーザーUUID:", userUuid);

      if (!userUuid) {
        console.error("❌ ユーザーUUID取得失敗");
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }

      // お気に入りレストラン一覧を取得（価格レベルも含む）
      const query = `
        SELECT 
          r.id,
          r.name,
          r.category,
          r.prefecture,
          r.nearest_station,
          r.price_range,
          r.image_url,
          r.price_level,
          r.hotpepper_url,
          r.operating_hours
        FROM restaurants r
        INNER JOIN restaurants_likes rl ON r.id = rl.restaurant_id
        WHERE rl.user_id = $1 
        ORDER BY rl.liked_at DESC
        LIMIT 50
      `;

      console.log("🔍 クエリ実行:", query);
      console.log("🔍 パラメータ:", [userUuid]);

      const result = await pool.query(query, [userUuid]);
      console.log("🔍 クエリ結果:", result.rows.length, "件");

      const restaurants = result.rows.map((row) => ({
        id: row.id,
        name: row.name || "不明なレストラン",
        category: row.category,
        prefecture: row.prefecture,
        nearest_station: row.nearest_station,
        price_range: row.price_range,
        image_url: row.image_url,
        price_level: row.price_level,
        hotpepper_url: row.hotpepper_url,
        operating_hours: row.operating_hours,
      }));

      console.log("✅ getFavoriteRestaurants関数完了:", restaurants.length, "件");
      return {restaurants};
    } catch (error) {
      console.error("❌ お気に入りレストラン取得エラー:", error);

      const err = error as Error;
      console.error("❌ エラー詳細:", {
        name: err.name,
        message: err.message,
        stack: err.stack,
      });

      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError(
        "internal",
        `お気に入りレストランの取得に失敗しました: ${err.message}`
      );
    }
  }
);

/**
 * マッチ通知を両方のユーザーに送信する関数
 * @param {string} user1Id - ユーザー1のID
 * @param {string} user2Id - ユーザー2のID
 * @return {Promise<void>} 処理の完了
 */
async function sendMatchNotifications(
  user1Id: string,
  user2Id: string
): Promise<void> {
  try {
    // 両方のユーザー情報を取得
    const usersQuery = `
      SELECT id, name, firebase_uid, fcm_token FROM users 
      WHERE id IN ($1, $2)
    `;
    const usersResult = await pool.query(usersQuery, [user1Id, user2Id]);

    if (usersResult.rows.length !== 2) {
      console.error("マッチ通知: ユーザー情報の取得に失敗");
      return;
    }

    const user1 = usersResult.rows.find((row) => row.id === user1Id);
    const user2 = usersResult.rows.find((row) => row.id === user2Id);

    if (!user1 || !user2) {
      console.error("マッチ通知: ユーザー情報が不完全");
      return;
    }

    // 両方のユーザーに通知を送信
    const notifications = [
      sendSingleMatchNotification(user1, user2.name),
      sendSingleMatchNotification(user2, user1.name),
    ];

    await Promise.all(notifications);
  } catch (error) {
    console.error("マッチ通知送信エラー:", error);
    throw error;
  }
}

/**
 * 単一ユーザーへのマッチ通知送信
 * @param {any} recipient - 通知受信ユーザー情報
 * @param {string} partnerName - マッチ相手の名前
 * @return {Promise<void>} 処理の完了
 */
async function sendSingleMatchNotification(
  recipient: any,
  partnerName: string
): Promise<void> {
  if (!recipient.fcm_token) {
    console.log(`マッチ通知スキップ: FCMトークンなし (${recipient.name})`);
    return;
  }

  try {
    // 通知設定を確認
    const settingsDoc = await admin.firestore()
      .collection("users")
      .doc(recipient.firebase_uid)
      .collection("settings")
      .doc("notifications")
      .get();

    let shouldSendNotification = true;
    if (settingsDoc.exists) {
      const settings = settingsDoc.data();
      const enablePush = settings?.enablePush !== false;
      const enableMatch = settings?.enableMatch !== false;
      shouldSendNotification = enablePush && enableMatch;
    }

    if (!shouldSendNotification) {
      console.log(`マッチ通知スキップ: 設定により無効 (${recipient.name})`);
      return;
    }

    // プッシュ通知を送信
    const message = {
      token: recipient.fcm_token,
      notification: {
        title: "デリミート",
        body: `${partnerName}さんとマッチしました！`,
      },
      data: {
        type: "match",
        partnerId: recipient.id,
        partnerName: partnerName,
      },
      android: {
        priority: "high" as const,
        notification: {
          channelId: "dating_food_app_channel",
          priority: "high" as const,
        },
      },
      apns: {
        payload: {
          aps: {
            alert: {
              title: "デリミート",
              body: `${partnerName}さんとマッチしました！`,
            },
            badge: 1,
            sound: "default",
          },
        },
      },
    };

    await admin.messaging().send(message);

    // Firestoreに通知履歴を保存
    const notificationData = {
      userId: recipient.firebase_uid,
      type: "match",
      title: "デリミート",
      body: `${partnerName}さんとマッチしました！`,
      senderId: "system",
      senderName: "System",
      data: {
        type: "match",
        partnerId: recipient.id,
        partnerName: partnerName,
      },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      isRead: false,
      isDeleted: false,
    };

    await admin.firestore()
      .collection("notifications")
      .add(notificationData);

    console.log(`マッチ通知送信成功: ${recipient.name} <- ${partnerName}`);
  } catch (error) {
    console.error(`マッチ通知送信失敗: ${recipient.name}`, error);
  }
}

// PostgreSQL 接続プール設定（Supabase or CloudSQL対応）
export const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: {rejectUnauthorized: false}, // Supabaseでは true, CloudSQLでは false または省略
});


interface SearchData {
  keyword?: string;
  prefecture?: string;
  city?: string;
  category?: string | string[];
  priceRange?: string;
  nearestStation?: string;
  limit?: number;
}
interface Restaurant {
  id: string;
  name: string;
  prefecture?: string;
  category?: string;
  priceRange?: string;
  nearestStation?: string;
  imageUrl?: string;
  // 必要に応じて列を追加
}

// レストラン検索（複数条件対応）
export const searchRestaurants = onCall(
  async (
    request: CallableRequest<SearchData & {
      timestamp?: number;
      randomValue?: number;
      cacheBreaker?: string;
      forceRefresh?: boolean;
    }>
  ): Promise<{restaurants: Restaurant[]; totalCount: number}> => {
    const {
      keyword,
      prefecture,
      city,
      category,
      priceRange,
      nearestStation,
      limit = 15, // デフォルト値を削減
      timestamp,
      randomValue,
      cacheBreaker,
      forceRefresh,
    } = request.data;

    // キャッシュ無効化パラメータをログ出力
    console.log("🔍 searchRestaurants呼び出し開始");
    console.log("🔍 キャッシュ無効化パラメータ:", {
      timestamp,
      randomValue,
      cacheBreaker,
      forceRefresh,
      requestTime: new Date().toISOString(),
    });

    console.log("🔍 受信したパラメータ:", {
      keyword,
      prefecture,
      city,
      category,
      priceRange,
      nearestStation,
      limit,
    });

    try {
      // まず実際のデータサンプルを確認（LIMIT 5）
      const sampleQuery = "SELECT * FROM restaurants LIMIT 5";
      const sampleResult = await pool.query(sampleQuery);
      console.log("🔍 データベースサンプル（5件）:");
      sampleResult.rows.forEach((row, index) => {
        console.log(
          `  ${index + 1}. ${row.name} - 都道府県: ${row.prefecture} - ` +
          `カテゴリ: ${row.category} - 価格帯: ${row.price_range} - ` +
          `駅: ${row.nearest_station}`
        );
      });

      // 実際の検索クエリを構築
      let query = "SELECT * FROM restaurants WHERE 1=1";
      const params: string[] = [];
      let paramIndex = 1;

      // キーワード検索（店名）
      if (keyword && keyword.trim() !== "") {
        query += ` AND name ILIKE $${paramIndex}`;
        params.push(`%${keyword}%`);
        console.log(`🔍 キーワード条件追加: name ILIKE '%${keyword}%'`);
        paramIndex++;
      }

      // 都道府県絞り込み
      if (prefecture && prefecture.trim() !== "") {
        query += ` AND prefecture = $${paramIndex}`;
        params.push(prefecture);
        console.log(`🔍 都道府県条件追加: prefecture = '${prefecture}'`);
        paramIndex++;
      }

      // 市町村絞り込み
      if (city && city.trim() !== "") {
        query += ` AND city = $${paramIndex}`;
        params.push(city);
        console.log(`🔍 市町村条件追加: city = '${city}'`);
        paramIndex++;
      }

      // カテゴリ絞り込み（単一文字列または配列に対応）
      if (category) {
        const categories = Array.isArray(category) ? category : [category];
        const validCategories = categories.filter(
          (cat) => cat && cat.trim() !== ""
        );

        if (validCategories.length > 0) {
          const categoryPlaceholders = validCategories.map(
            () => `$${paramIndex++}`
          ).join(", ");
          query += ` AND category IN (${categoryPlaceholders})`;
          params.push(...validCategories);
          console.log(
            `🔍 カテゴリ条件追加: category IN (${validCategories.join(", ")})`
          );
        }
      }

      // 価格帯絞り込み（low_price、high_priceカラムを使用）
      if (priceRange && priceRange.trim() !== "") {
        console.log(`🔍 価格帯条件追加: priceRange = '${priceRange}'`);

        // 価格帯の範囲を解析
        const {minPrice, maxPrice} = parsePriceRange(priceRange);
        console.log(`🔍 解析結果: minPrice=${minPrice}, maxPrice=${maxPrice}`);

        if (minPrice !== null || maxPrice !== null) {
          const priceConditions: string[] = [];

          if (minPrice !== null && maxPrice !== null) {
            // 両方指定：レストランの価格帯と指定範囲が重複するかチェック
            // 条件：レストランの下限価格 <= 検索上限価格 AND レストランの上限価格 >= 検索下限価格
            priceConditions.push(`(
              (low_price IS NULL OR low_price <= $${paramIndex + 1}) 
              AND (high_price IS NULL OR high_price >= $${paramIndex})
            )`);
            params.push(minPrice.toString(), maxPrice.toString());
            console.log(`🔍 価格範囲条件: レストラン価格帯が${minPrice}-${maxPrice}円と重複`);
            paramIndex += 2;
          } else if (minPrice !== null) {
            // 下限のみ：レストランの上限価格が指定下限以上
            priceConditions.push(`(
              high_price IS NULL OR high_price >= $${paramIndex}
            )`);
            params.push(minPrice.toString());
            paramIndex++;
          } else if (maxPrice !== null) {
            // 上限のみ：レストランの下限価格が指定上限以下
            priceConditions.push(`(
              low_price IS NULL OR low_price <= $${paramIndex}
            )`);
            params.push(maxPrice.toString());
            paramIndex++;
          }

          if (priceConditions.length > 0) {
            query += ` AND ${priceConditions.join(" AND ")}`;
            console.log("🔍 価格範囲検索条件追加完了（low_price/high_priceカラム使用）");
          }
        } else {
          console.log("🔍 価格範囲解析失敗、価格フィルタなしで検索継続");
        }
      } else {
        console.log("🔍 価格帯条件なし");
      }

      // 最寄駅絞り込み（駅名の「駅」を除去して検索）
      if (nearestStation && nearestStation.trim() !== "") {
        // 入力から「駅」を除去してデータベースの形式に合わせる
        const stationName = nearestStation.replace(/駅$/, "");

        query += ` AND nearest_station ILIKE $${paramIndex}`;
        params.push(`%${stationName}%`);
        console.log(
          `🔍 駅条件追加: nearest_station ILIKE '%${stationName}%'`
        );
        paramIndex++;
      }

      query += ` ORDER BY name LIMIT ${limit}`;

      console.log("🔍 最終検索クエリ:", query);
      console.log("🔍 検索パラメータ:", params);

      const result = await pool.query(query, params);

      // 全件数を取得（LIMIT なし）
      const countQuery = query.replace(` ORDER BY name LIMIT ${limit}`, "");
      const countResult = await pool.query(
        `SELECT COUNT(*) as total FROM (${countQuery}) as subquery`,
        params
      );
      const totalCount = parseInt(countResult.rows[0]?.total || "0", 10);

      console.log(`🔍 検索結果: ${result.rows.length}件 / 全${totalCount}件`);
      if (result.rows.length > 0) {
        console.log("🔍 検索結果サンプル（最初の3件）:");
        result.rows.slice(0, 3).forEach((row, index) => {
          console.log(
            `  ${index + 1}. ${row.name} - ${row.prefecture} - ` +
            `${row.category} - ${row.price_range} - ` +
            `low:${row.low_price} high:${row.high_price}`
          );
        });
      }

      return {
        restaurants: result.rows,
        totalCount: totalCount,
      };
    } catch (err) {
      console.error("❌ 検索失敗:", err);
      throw new functions.https.HttpsError(
        "internal",
        "検索に失敗しました"
      );
    }
  }
);
// 座標データを持つレストラン検索（地図表示用）
export const searchRestaurantsWithCoordinates = onCall(
  async (request: CallableRequest<{
    limit?: number;
    category?: string | string[];
    priceRange?: string;
    prefecture?: string;
    city?: string;
    minLatitude?: number;
    maxLatitude?: number;
    minLongitude?: number;
    maxLongitude?: number;
  }>): Promise<{
    restaurants: Restaurant[];
    totalCount: number;
    validCoordinatesCount: number;
    coordinateStats: {
      totalRestaurants: number;
      withCoordinates: number;
      validJapanCoordinates: number;
    };
  }> => {
    console.log("🗺️ searchRestaurantsWithCoordinates呼び出し開始");

    const {
      limit = 1000,
      category,
      priceRange,
      prefecture,
      city,
      minLatitude,
      maxLatitude,
      minLongitude,
      maxLongitude,
    } = request.data;

    console.log("🔍 受信したパラメータ:", {
      limit,
      category,
      priceRange,
      prefecture,
      city,
      coordinateBounds: {
        minLatitude,
        maxLatitude,
        minLongitude,
        maxLongitude,
      },
    });

    try {
      // 座標データの有効性をチェック
      const coordinateCheckQuery = `
        SELECT 
          COUNT(*) as total_restaurants,
          COUNT(CASE WHEN location_latitude IS NOT NULL AND location_longitude IS NOT NULL THEN 1 END) as with_coordinates,
          COUNT(CASE WHEN location_latitude IS NOT NULL AND location_longitude IS NOT NULL 
                     AND location_latitude BETWEEN 24 AND 46 
                     AND location_longitude BETWEEN 123 AND 146 THEN 1 END) as valid_japan_coordinates
        FROM restaurants
      `;

      const coordinateCheck = await pool.query(coordinateCheckQuery);
      const coordinateStats = coordinateCheck.rows[0];
      console.log("🔍 座標データ統計:", coordinateStats);

      // 基本クエリ（座標データが有効なレストランのみ）
      let query = `
        SELECT 
          id,
          name,
          category,
          prefecture,
          city,
          nearest_station,
          price_range,
          low_price,
          high_price,
          image_url,
          address,
          hotpepper_url,
          operating_hours,
          location_latitude,
          location_longitude
        FROM restaurants 
        WHERE location_latitude IS NOT NULL 
          AND location_longitude IS NOT NULL
          AND location_latitude BETWEEN 24 AND 46
          AND location_longitude BETWEEN 123 AND 146
      `;

      const params: any[] = [];
      let paramIndex = 1;

      // カテゴリフィルター
      if (category) {
        const categories = Array.isArray(category) ? category : [category];
        const validCategories = categories.filter((cat) => cat && cat.trim() !== "");

        if (validCategories.length > 0) {
          const categoryPlaceholders = validCategories.map(() => `$${paramIndex++}`).join(", ");
          query += ` AND category IN (${categoryPlaceholders})`;
          params.push(...validCategories);
          console.log("🔍 カテゴリフィルター:", validCategories);
        }
      }

      // 都道府県フィルター
      if (prefecture && prefecture.trim() !== "") {
        query += ` AND prefecture = $${paramIndex}`;
        params.push(prefecture);
        paramIndex++;
        console.log("🔍 都道府県フィルター:", prefecture);
      }

      // 市町村フィルター
      if (city && city.trim() !== "") {
        query += ` AND city = $${paramIndex}`;
        params.push(city);
        paramIndex++;
        console.log("🔍 市町村フィルター:", city);
      }

      // 価格帯フィルター
      if (priceRange && priceRange.trim() !== "") {
        const {minPrice, maxPrice} = parsePriceRange(priceRange);
        if (minPrice !== null && maxPrice !== null) {
          query += ` AND ((low_price IS NULL OR low_price <= $${paramIndex + 1}) AND (high_price IS NULL OR high_price >= $${paramIndex}))`;
          params.push(minPrice.toString(), maxPrice.toString());
          paramIndex += 2;
          console.log("🔍 価格帯フィルター:", minPrice, "-", maxPrice);
        }
      }

      // 地理的境界フィルター
      if (minLatitude !== undefined && maxLatitude !== undefined &&
          minLongitude !== undefined && maxLongitude !== undefined) {
        query += ` AND location_latitude BETWEEN $${paramIndex} AND $${paramIndex + 1}`;
        query += ` AND location_longitude BETWEEN $${paramIndex + 2} AND $${paramIndex + 3}`;
        params.push(minLatitude, maxLatitude, minLongitude, maxLongitude);
        paramIndex += 4;
        console.log("🔍 地理的境界フィルター:", {minLatitude, maxLatitude, minLongitude, maxLongitude});
      }

      // ソートと制限
      query += ` ORDER BY name LIMIT $${paramIndex}`;
      params.push(limit);

      console.log("🔍 最終クエリ:", query);
      console.log("🔍 パラメータ:", params);

      const result = await pool.query(query, params);

      // 全件数を取得
      const countQuery = query.replace(` ORDER BY name LIMIT $${paramIndex}`, "");
      const countParams = params.slice(0, -1);
      const countResult = await pool.query(
        `SELECT COUNT(*) as total FROM (${countQuery}) as subquery`,
        countParams
      );

      const totalCount = parseInt(countResult.rows[0]?.total || "0", 10);

      console.log(`🔍 検索結果: ${result.rows.length}件 / 全${totalCount}件（座標付き）`);

      // 座標データの妥当性を追加チェック
      const validCoordinatesCount = result.rows.filter((row) =>
        row.location_latitude && row.location_longitude &&
        row.location_latitude >= 24 && row.location_latitude <= 46 &&
        row.location_longitude >= 123 && row.location_longitude <= 146
      ).length;

      console.log(`🔍 有効な座標データ: ${validCoordinatesCount}件`);

      if (result.rows.length > 0) {
        console.log("🔍 座標データサンプル（最初の3件）:");
        result.rows.slice(0, 3).forEach((row, index) => {
          console.log(`  ${index + 1}. ${row.name} - 座標: (${row.location_latitude}, ${row.location_longitude})`);
        });
      }

      return {
        restaurants: result.rows,
        totalCount: totalCount,
        validCoordinatesCount: validCoordinatesCount,
        coordinateStats: {
          totalRestaurants: parseInt(coordinateStats.total_restaurants),
          withCoordinates: parseInt(coordinateStats.with_coordinates),
          validJapanCoordinates: parseInt(coordinateStats.valid_japan_coordinates),
        },
      };
    } catch (err) {
      console.error("❌ 座標付きレストラン検索失敗:", err);
      throw new functions.https.HttpsError(
        "internal",
        "座標付きレストラン検索に失敗しました"
      );
    }
  }
);

// おすすめユーザー取得
export const getRecommendedUsers = onCall(
  async (request: CallableRequest<{
    timestamp?: number;
    randomValue?: number;
    cacheBreaker?: string;
    forceRefresh?: boolean;
  }>) => {
    try {
      // キャッシュ無効化パラメータをログ出力
      const {
        timestamp,
        randomValue,
        cacheBreaker,
        forceRefresh,
      } = request.data || {};
      console.log("🔍 getRecommendedUsers呼び出し開始");
      console.log("🔍 キャッシュ無効化パラメータ:", {
        timestamp,
        randomValue,
        cacheBreaker,
        forceRefresh,
        requestTime: new Date().toISOString(),
      });

      // クエリを最適化
      let query = "SELECT id, name, age, firebase_uid, image_url FROM users WHERE (deactivated_at IS NULL OR deactivated_at > NOW())";
      const params: string[] = [];
      let paramIndex = 1;

      console.log("🔍 アカウント停止中ユーザー除外条件追加");

      // ログインユーザーがいる場合は除外
      if (request.auth?.uid) {
        query += ` AND firebase_uid != $${paramIndex}`;
        params.push(request.auth.uid);
        paramIndex++;
        console.log("🔍 ログインユーザー除外:", request.auth.uid);

        // ブロック機能：一時的に無効化（型の不一致問題のため）
        // TODO: user_blocksテーブルの型を統一してから再有効化
        console.log("🔍 ブロック機能は一時的に無効化されています");
      }

      query += " LIMIT 10";
      console.log("🔍 実行クエリ:", query);

      const result = await pool.query(query, params);
      console.log("✅ ユーザー取得成功:", result.rows.length, "件");

      return result.rows;
    } catch (err) {
      console.error("❌ ユーザー取得失敗:", err);
      throw new functions.https.HttpsError(
        "internal",
        "ユーザー取得に失敗しました"
      );
    }
  }
);

interface UserSearchData {
  keyword?: string;
  minAge?: number;
  maxAge?: number;
  genders?: string[];
  occupations?: string[];
  weekendOff?: boolean;
  favoriteCategories?: string[];
  idVerified?: boolean;
  tags?: string[];
  limit?: number;
  mbti?: string;
  schools?: string[]; // 学校フィルター追加
}

// グループ検索データのインターフェース
interface GroupSearchData {
  keyword?: string;
  category?: string;
  prefecture?: string;
  nearestStation?: string;
  groupType?: string;
  tags?: string[];
  limit?: number;
}

// グループメンバー検索データのインターフェース
interface GroupMemberSearchData {
  groupId: string;
  keyword?: string;
  tags?: string[];
  limit?: number;
}

// グループ検索（Firestore対応）
export const searchGroups = onCall(
  async (
    request: CallableRequest<GroupSearchData>
  ): Promise<{groups: any[]; totalCount: number}> => {
    const {
      keyword,
      category,
      prefecture,
      nearestStation,
      groupType,
      tags,
      limit = 20,
    } = request.data;

    console.log("🔍 グループ検索パラメータ:", {
      keyword,
      category,
      prefecture,
      nearestStation,
      groupType,
      tags,
      limit,
    });

    try {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "認証が必要です");
      }

      // Firestoreクエリを構築
      let query = admin.firestore().collection("groups").where("isPrivate", "==", false);

      // カテゴリフィルター
      if (category && category.trim() !== "") {
        query = query.where("category", "==", category);
        console.log(`🔍 カテゴリフィルター: ${category}`);
      }

      // 都道府県フィルター
      if (prefecture && prefecture.trim() !== "") {
        query = query.where("prefecture", "==", prefecture);
        console.log(`🔍 都道府県フィルター: ${prefecture}`);
      }

      // 最寄駅フィルター
      if (nearestStation && nearestStation.trim() !== "") {
        query = query.where("nearestStation", "==", nearestStation);
        console.log(`🔍 最寄駅フィルター: ${nearestStation}`);
      }

      // グループタイプフィルター
      if (groupType && groupType.trim() !== "") {
        query = query.where("groupType", "==", groupType);
        console.log(`🔍 グループタイプフィルター: ${groupType}`);
      }

      // 作成日時でソート（最新順）
      query = query.orderBy("createdAt", "desc");

      const snapshot = await query.get();
      let groups = snapshot.docs.map((doc) => {
        const data = doc.data();
        return {
          id: doc.id,
          ...data,
          name: data.name || "",
          description: data.description || "",
          tags: data.tags || [],
          createdAt: data.createdAt?.toDate()?.toISOString(),
          updatedAt: data.updatedAt?.toDate()?.toISOString(),
          eventDateTime: data.eventDateTime?.toDate()?.toISOString(),
          eventEndDateTime: data.eventEndDateTime?.toDate()?.toISOString(),
        };
      });

      // キーワード検索（クライアント側フィルタリング）
      if (keyword && keyword.trim() !== "") {
        const searchKeyword = keyword.toLowerCase();
        groups = groups.filter((group) =>
          group.name.toLowerCase().includes(searchKeyword) ||
          group.description.toLowerCase().includes(searchKeyword)
        );
        console.log(`🔍 キーワード検索: ${keyword}`);
      }

      // ハッシュタグフィルター（クライアント側フィルタリング）
      if (tags && tags.length > 0) {
        groups = groups.filter((group) => {
          const groupTags = group.tags || [];
          return tags.some((tag) => groupTags.includes(tag));
        });
        console.log(`🔍 ハッシュタグフィルター: ${tags.join(", ")}`);
      }

      const totalCount = groups.length;

      // 制限を適用
      groups = groups.slice(0, limit);

      console.log(`🔍 グループ検索結果: ${groups.length}件 / 全${totalCount}件`);

      return {
        groups: groups,
        totalCount: totalCount,
      };
    } catch (err) {
      console.error("❌ グループ検索失敗:", err);
      throw new HttpsError(
        "internal",
        "グループ検索に失敗しました"
      );
    }
  }
);

// グループメンバー検索（Firestore対応）
export const searchGroupMembers = onCall(
  async (
    request: CallableRequest<GroupMemberSearchData>
  ): Promise<{members: any[]; totalCount: number}> => {
    const {
      groupId,
      keyword,
      tags,
      limit = 20,
    } = request.data;

    console.log("🔍 グループメンバー検索パラメータ:", {
      groupId,
      keyword,
      tags,
      limit,
    });

    try {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "認証が必要です");
      }

      if (!groupId) {
        throw new HttpsError("invalid-argument", "グループIDが必要です");
      }

      // グループの存在確認
      const groupDoc = await admin.firestore()
        .collection("groups")
        .doc(groupId)
        .get();

      if (!groupDoc.exists) {
        throw new HttpsError("not-found", "グループが見つかりません");
      }

      const groupData = groupDoc.data();
      const memberFirebaseUids = groupData?.members || [];

      if (memberFirebaseUids.length === 0) {
        return {
          members: [],
          totalCount: 0,
        };
      }

      // PostgreSQLからメンバー情報を取得
      const memberPlaceholders = memberFirebaseUids.map((_: string, index: number) => `$${index + 1}`).join(", ");
      let query = `
        SELECT id, name, age, gender, occupation, weekend_off, 
               favorite_categories, id_verified, firebase_uid, image_url, tags, mbti 
        FROM users 
        WHERE firebase_uid IN (${memberPlaceholders})
        AND (deactivated_at IS NULL OR deactivated_at > NOW())
      `;

      const params: unknown[] = [...memberFirebaseUids];

      // キーワード検索（名前）
      if (keyword && keyword.trim() !== "") {
        query += ` AND name ILIKE $${params.length + 1}`;
        params.push(`%${keyword}%`);
        console.log(`🔍 キーワード条件追加: name ILIKE '%${keyword}%'`);
      }

      // ハッシュタグ検索（配列の重複）
      if (tags && tags.length > 0) {
        query += ` AND tags && $${params.length + 1}::text[]`;
        params.push(tags);
        console.log(`🔍 ハッシュタグ条件追加: ${tags.join(", ")}`);
      }

      query += ` ORDER BY name LIMIT ${limit}`;

      console.log("🔍 最終グループメンバー検索クエリ:", query);
      console.log("🔍 検索パラメータ:", params);

      const result = await pool.query(query, params);

      // 全件数を取得
      const countQuery = query.replace(` ORDER BY name LIMIT ${limit}`, "");
      const countResult = await pool.query(
        `SELECT COUNT(*) as total FROM (${countQuery}) as subquery`,
        params
      );
      const totalCount = parseInt(countResult.rows[0]?.total || "0", 10);

      console.log(`🔍 グループメンバー検索結果: ${result.rows.length}件 / 全${totalCount}件`);

      return {
        members: result.rows,
        totalCount: totalCount,
      };
    } catch (err) {
      console.error("❌ グループメンバー検索失敗:", err);
      throw new HttpsError(
        "internal",
        "グループメンバー検索に失敗しました"
      );
    }
  }
);

// ユーザー検索（詳細条件対応）
export const searchUsers = onCall(
  async (
    request: CallableRequest<UserSearchData>
  ): Promise<{users: Record<string, unknown>[]; totalCount: number}> => {
    const {
      keyword,
      minAge,
      maxAge,
      genders,
      occupations,
      weekendOff,
      favoriteCategories,
      idVerified,
      tags,
      mbti,
      schools,
      limit = 20,
    } = request.data;

    console.log("🔍 ユーザー検索パラメータ:", {
      keyword,
      minAge,
      maxAge,
      genders,
      occupations,
      weekendOff,
      favoriteCategories,
      idVerified,
      tags,
      mbti,
      schools,
      limit,
    });

    try {
      let query = "SELECT id, name, age, gender, occupation, weekend_off, " +
                  "favorite_categories, id_verified, firebase_uid, image_url, tags, mbti, school_id " +
                  "FROM users WHERE 1=1";
      const params: unknown[] = [];
      let paramIndex = 1;

      // アカウント停止中のユーザーを除外
      query += " AND (deactivated_at IS NULL OR deactivated_at > NOW())";
      console.log("🔍 アカウント停止中ユーザー除外条件追加");

      // ログインユーザーを除外
      if (request.auth?.uid) {
        console.log("🔍 ログインユーザー除外処理開始:", request.auth.uid);
        query += ` AND firebase_uid != $${paramIndex}`;
        params.push(request.auth.uid);
        paramIndex++;
        console.log(`🔍 自分自身除外条件追加: firebase_uid != '${request.auth.uid}'`);

        const myUserUuid = await getUserUuidFromFirebaseUid(request.auth.uid);
        console.log("🔍 取得したユーザーUUID:", myUserUuid);
        if (myUserUuid) {
          query += ` AND NOT EXISTS (
            SELECT 1 FROM user_blocks
            WHERE (blocker_id = $${paramIndex}::uuid AND blocked_id = users.id)
               OR (blocker_id = users.id AND blocked_id = $${paramIndex}::uuid)
          )`;
          params.push(myUserUuid);
          paramIndex++;
          console.log(`🔍 ブロック関係除外条件追加: ユーザーUUID = '${myUserUuid}'`);
        } else {
          console.log("⚠️ ユーザーUUIDが取得できませんでした");
        }
      } else {
        console.log("⚠️ 認証情報がありません");
      }

      // キーワード検索（名前）
      if (keyword && keyword.trim() !== "") {
        query += ` AND name ILIKE $${paramIndex}`;
        params.push(`%${keyword}%`);
        console.log(`🔍 キーワード条件追加: name ILIKE '%${keyword}%'`);
        paramIndex++;
      }

      // 年齢範囲検索
      if (minAge !== undefined && minAge !== null) {
        query += ` AND age >= $${paramIndex}`;
        params.push(minAge);
        console.log(`🔍 最小年齢条件追加: age >= ${minAge}`);
        paramIndex++;
      }

      if (maxAge !== undefined && maxAge !== null) {
        query += ` AND age <= $${paramIndex}`;
        params.push(maxAge);
        console.log(`🔍 最大年齢条件追加: age <= ${maxAge}`);
        paramIndex++;
      }

      // 性別検索（複数選択）
      if (genders && genders.length > 0) {
        const genderPlaceholders = genders.map(() =>
          `$${paramIndex++}`).join(", ");
        query += ` AND gender IN (${genderPlaceholders})`;
        params.push(...genders);
        console.log(`🔍 性別条件追加: gender IN (${genders.join(", ")})`);
      }

      // 職業検索（複数選択）
      if (occupations && occupations.length > 0) {
        const occupationPlaceholders = occupations.map(() =>
          `$${paramIndex++}`).join(", ");
        query += ` AND occupation IN (${occupationPlaceholders})`;
        params.push(...occupations);
        console.log(`🔍 職業条件追加: occupation IN (${occupations.join(", ")})`);
      }

      // 土日休み検索
      if (weekendOff !== undefined && weekendOff !== null) {
        query += ` AND weekend_off = $${paramIndex}`;
        params.push(weekendOff);
        console.log(`🔍 土日休み条件追加: weekend_off = ${weekendOff}`);
        paramIndex++;
      }

      // 好きなカテゴリ検索（配列の重複）
      if (favoriteCategories && favoriteCategories.length > 0) {
        const categoryConditions = favoriteCategories.map(() => {
          return `favorite_categories && ARRAY[$${paramIndex++}]`;
        });
        query += ` AND (${categoryConditions.join(" OR ")})`;
        params.push(...favoriteCategories);
        console.log(`🔍 好きなカテゴリ条件追加: ${favoriteCategories.join(", ")}`);
      }

      // 身分証明書済み検索
      if (idVerified !== undefined && idVerified !== null) {
        query += ` AND id_verified = $${paramIndex}`;
        params.push(idVerified);
        console.log(`🔍 身分証明書条件追加: id_verified = ${idVerified}`);
        paramIndex++;
      }

      // MBTI検索
      if (mbti && mbti.trim() !== "") {
        query += ` AND mbti = $${paramIndex}`;
        params.push(mbti);
        paramIndex++;
      }

      // ハッシュタグ検索（配列の重複）
      if (tags && tags.length > 0) {
        query += ` AND tags && $${paramIndex}::text[]`;
        params.push(tags);
        console.log(`🔍 ハッシュタグ条件追加: ${tags.join(", ")}`);
        paramIndex++;
      }

      // 学校フィルター（複数選択）
      if (schools && schools.length > 0) {
        const schoolPlaceholders = schools.map(() =>
          `$${paramIndex++}`).join(", ");
        query += ` AND school_id IN (${schoolPlaceholders})`;
        params.push(...schools);
        console.log(`🔍 学校条件追加: school_id IN (${schools.join(", ")})`);
      }

      query += ` ORDER BY name LIMIT ${limit}`;

      console.log("🔍 最終ユーザー検索クエリ:", query);
      console.log("🔍 検索パラメータ:", params);

      const result = await pool.query(query, params);

      // 全件数を取得
      const countQuery = query.replace(` ORDER BY name LIMIT ${limit}`, "");
      const countResult = await pool.query(
        `SELECT COUNT(*) as total FROM (${countQuery}) as subquery`,
        params
      );
      const totalCount = parseInt(countResult.rows[0]?.total || "0", 10);

      console.log(`🔍 ユーザー検索結果: ${result.rows.length}件 / 全${totalCount}件`);

      // デバッグ用：検索結果の詳細確認
      if (result.rows.length > 0) {
        console.log("🔍 検索結果サンプル（最初の1件）:", {
          id: result.rows[0].id,
          name: result.rows[0].name,
          age: result.rows[0].age,
          gender: result.rows[0].gender,
          firebase_uid: result.rows[0].firebase_uid,
        });

        // 自分が検索結果に含まれていないかチェック
        const currentUserInResults = result.rows.some((user) => user.firebase_uid === request.auth?.uid);
        if (currentUserInResults) {
          console.error("❌ 問題発見: 自分自身が検索結果に含まれています！");
          console.error("🔍 現在のユーザーUID:", request.auth?.uid);
          console.error("🔍 検索結果内のfirebase_uid一覧:", result.rows.map((u) => u.firebase_uid));
        } else {
          console.log("✅ 自分自身は正しく除外されています");
        }
      } else {
        // 検索結果が0件の場合、全件数確認
        try {
          const totalUsersResult = await pool.query(
            "SELECT COUNT(*) as total FROM users WHERE firebase_uid != $1 AND (deactivated_at IS NULL OR deactivated_at > NOW())",
            [request.auth?.uid || ""]
          );
          const totalUsers = parseInt(totalUsersResult.rows[0]?.total || "0", 10);
          console.log(`🔍 データベース内の他のユーザー総数（アカウント停止中除外）: ${totalUsers}件`);

          if (totalUsers === 0) {
            console.log("⚠️ データベースに他のユーザーが存在しません");
          } else {
            console.log("⚠️ 検索条件が厳しすぎる可能性があります");
          }
        } catch (debugError) {
          console.error("🔥 デバッグ用総数取得エラー:", debugError);
        }
      }

      return {
        users: result.rows,
        totalCount: totalCount,
      };
    } catch (err) {
      console.error("❌ ユーザー検索失敗:", err);
      throw new functions.https.HttpsError(
        "internal",
        "ユーザー検索に失敗しました"
      );
    }
  }
);

/**
 * Firebase UIDからユーザーのUUID IDを取得するヘルパー関数
 * @param {string} firebaseUid Firebase Authentication UID
 * @return {Promise<string | null>} ユーザーのUUID ID
 */
async function getUserUuidFromFirebaseUid(
  firebaseUid: string
): Promise<string | null> {
  try {
    const result = await pool.query(
      "SELECT id FROM users WHERE firebase_uid = $1 AND (deactivated_at IS NULL OR deactivated_at > NOW())",
      [firebaseUid]
    );
    return result.rows[0]?.id || null;
  } catch (err) {
    console.error("ユーザーUUID取得エラー:", err);
    return null;
  }
}
// 価格帯文字列を解析して最小値・最大値を取得（プライベート関数）
// eslint-disable-next-line require-jsdoc
function parsePriceRange(priceRangeStr: string): {
  minPrice: number | null;
  maxPrice: number | null;
} {
  try {
    console.log(`🔍 価格帯解析開始: "${priceRangeStr}"`);

    // "500-4500"形式（ハイフン区切り）を解析
    if (priceRangeStr.includes("-")) {
      const parts = priceRangeStr.split("-");
      const minPrice = parts[0] && parts[0].trim() !== "" ?
        parseInt(parts[0], 10) : null;
      const maxPrice = parts[1] && parts[1].trim() !== "" ?
        parseInt(parts[1], 10) : null;

      console.log(
        `🔍 ハイフン区切り解析結果: min=${minPrice}, max=${maxPrice}`
      );

      return {
        minPrice: minPrice !== null && isNaN(minPrice) ? null : minPrice,
        maxPrice: maxPrice !== null && isNaN(maxPrice) ? null : maxPrice,
      };
    }
    // "500～5000円" または "500円～" の形式を解析
    const cleanStr = priceRangeStr.replace(/円/g, "");

    if (cleanStr.includes("～")) {
      const parts = cleanStr.split("～");
      const minPrice = parts[0] ? parseInt(parts[0], 10) : null;
      const maxPrice = parts[1] ? parseInt(parts[1], 10) : null;

      console.log(
        `🔍 波線区切り解析結果: min=${minPrice}, max=${maxPrice}`
      );

      return {
        minPrice: minPrice !== null && isNaN(minPrice) ? null : minPrice,
        maxPrice: maxPrice !== null && isNaN(maxPrice) ? null : maxPrice,
      };
    }

    // 単一の値の場合
    const singlePrice = parseInt(cleanStr, 10);
    if (!isNaN(singlePrice)) {
      console.log(`🔍 単一価格解析結果: ${singlePrice}`);
      return {minPrice: singlePrice, maxPrice: singlePrice};
    }

    console.log("🔍 価格帯解析失敗: 有効な形式が見つからない");
    return {minPrice: null, maxPrice: null};
  } catch (err) {
    console.error("価格帯解析エラー:", err);
    return {minPrice: null, maxPrice: null};
  }
}

// レストランLIKE追加
export const addRestaurantLike = onCall(
  async (request: CallableRequest<{restaurantId: string}>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {restaurantId} = request.data;

    console.log(
      "🔍 レストランLIKE追加:",
      `firebaseUid=${firebaseUid}, restaurantId=${restaurantId}`
    );

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      const result = await pool.query(
        `INSERT INTO restaurants_likes (user_id, restaurant_id) 
         VALUES ($1, $2) 
         ON CONFLICT (user_id, restaurant_id) DO NOTHING 
         RETURNING id`,
        [userUuid, restaurantId]
      );
      console.log("✅ レストランLIKE追加成功:", result.rows);
      return {success: true};
    } catch (err: unknown) {
      const error = err as Error;
      console.error("❌ レストランLIKE追加失敗:", error);
      console.error("詳細情報:", {
        firebaseUid,
        restaurantId,
        errorName: error.name,
        errorMessage: error.message,
      });
      throw new functions.https.HttpsError(
        "internal",
        `LIKEの追加に失敗しました: ${error.message}`
      );
    }
  }
);

// レストランLIKE削除
export const removeRestaurantLike = onCall(
  async (request: CallableRequest<{restaurantId: string}>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {restaurantId} = request.data;

    console.log(
      "🔍 レストランLIKE削除:",
      `firebaseUid=${firebaseUid}, restaurantId=${restaurantId}`
    );

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      const result = await pool.query(
        `DELETE FROM restaurants_likes 
         WHERE user_id = $1 AND restaurant_id = $2 
         RETURNING id`,
        [userUuid, restaurantId]
      );
      console.log("✅ レストランLIKE削除成功:", result.rows);
      return {success: true};
    } catch (err: unknown) {
      const error = err as Error;
      console.error("❌ レストランLIKE削除失敗:", error);
      console.error("詳細情報:", {
        firebaseUid,
        restaurantId,
        errorName: error.name,
        errorMessage: error.message,
      });
      throw new functions.https.HttpsError(
        "internal",
        `LIKEの削除に失敗しました: ${error.message}`
      );
    }
  }
);

// ユーザーLIKE追加（マッチ機能付き）
export const addUserLike = onCall(
  async (request: CallableRequest<{likedUserId: string}>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {likedUserId} = request.data;

    console.log(
      "🔍 ユーザーLIKE追加:",
      `firebaseUid=${firebaseUid}, likedUserId=${likedUserId}`
    );

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      // 自分自身にはいいねできない
      if (userUuid === likedUserId) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "自分自身にはいいねできません"
        );
      }

      // いいねを追加
      const result = await pool.query(
        `INSERT INTO users_likes (user_id, liked_user_id) 
         VALUES ($1, $2) 
         ON CONFLICT (user_id, liked_user_id) DO NOTHING 
         RETURNING id`,
        [userUuid, likedUserId]
      );

      console.log("✅ ユーザーLIKE追加成功:", result.rows);

      // マッチチェック：相手も自分にいいねしているかを確認
      console.log("🔍 マッチチェック開始");
      console.log(`🔍 チェック対象: ${likedUserId} → ${userUuid} のいいね`);
      const matchCheckResult = await pool.query(
        `SELECT id FROM users_likes 
         WHERE user_id = $1 AND liked_user_id = $2`,
        [likedUserId, userUuid]
      );

      console.log(`🔍 マッチチェック結果: ${matchCheckResult.rows.length}件`);
      if (matchCheckResult.rows.length > 0) {
        console.log("🔍 マッチチェック詳細:", matchCheckResult.rows[0]);
      }

      let matchId = null;
      let isNewMatch = false;

      if (matchCheckResult.rows.length > 0) {
        console.log("🎉 相互いいね発見！マッチ作成開始");

        // 既存マッチをチェック
        const existingMatchResult = await pool.query(
          `SELECT id FROM matches 
           WHERE (user1_id = $1 AND user2_id = $2) 
           OR (user1_id = $2 AND user2_id = $1)`,
          [userUuid, likedUserId]
        );

        if (existingMatchResult.rows.length > 0) {
          console.log("⚠️ 既存マッチ発見:", existingMatchResult.rows[0].id);
          matchId = existingMatchResult.rows[0].id;
        } else {
          console.log("🔍 新規マッチ作成: create_match_if_mutual_like関数実行");

          // マッチを作成（create_match_if_mutual_like関数を使用）
          const matchResult = await pool.query(
            "SELECT create_match_if_mutual_like($1, $2) as match_id",
            [userUuid, likedUserId]
          );

          console.log("🔍 create_match_if_mutual_like結果:", matchResult.rows);

          if (matchResult.rows[0]?.match_id) {
            matchId = matchResult.rows[0].match_id;
            isNewMatch = true;
            console.log("✅ マッチ作成成功:", matchId);

            // マッチ成立通知を両方のユーザーに送信
            try {
              await sendMatchNotifications(userUuid, likedUserId);
              console.log("✅ マッチ通知送信完了");
            } catch (notificationError) {
              console.error("⚠️ マッチ通知送信エラー:", notificationError);
              // 通知エラーはメイン機能に影響しない
            }
          } else {
            console.log("❌ マッチ作成失敗: match_idがnull");
          }
        }
      } else {
        console.log("⏳ 相手からのいいね待ち（マッチ未成立）");
      }

      return {
        success: true,
        isMatch: isNewMatch,
        matchId: matchId,
      };
    } catch (err: unknown) {
      const error = err as Error;
      console.error("❌ ユーザーLIKE追加失敗:", error);
      console.error("詳細情報:", {
        firebaseUid,
        likedUserId,
        errorName: error.name,
        errorMessage: error.message,
      });
      throw new functions.https.HttpsError(
        "internal",
        `LIKEの追加に失敗しました: ${error.message}`
      );
    }
  }
);

// ユーザーLIKE削除
export const removeUserLike = onCall(
  async (request: CallableRequest<{likedUserId: string}>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {likedUserId} = request.data;

    console.log(
      "🔍 ユーザーLIKE削除:",
      `firebaseUid=${firebaseUid}, likedUserId=${likedUserId}`
    );

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      const result = await pool.query(
        `DELETE FROM users_likes 
         WHERE user_id = $1 AND liked_user_id = $2 
         RETURNING id`,
        [userUuid, likedUserId]
      );
      console.log("✅ ユーザーLIKE削除成功:", result.rows);
      return {success: true};
    } catch (err: unknown) {
      const error = err as Error;
      console.error("❌ ユーザーLIKE削除失敗:", error);
      console.error("詳細情報:", {
        firebaseUid,
        likedUserId,
        errorName: error.name,
        errorMessage: error.message,
      });
      throw new functions.https.HttpsError(
        "internal",
        `LIKEの削除に失敗しました: ${error.message}`
      );
    }
  }
);

// ユーザーのLIKE状態取得
export const getUserLikes = onCall(
  async (request: CallableRequest<unknown>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      // 送信したいいね（自分が他の人にいいねした）
      const sentLikesResult = await pool.query(`
        SELECT 
          ul.liked_user_id,
          ul.liked_at::text as liked_at,
          u.name,
          u.age,
          u.gender,
          u.image_url,
          u.occupation
        FROM users_likes ul
        JOIN users u ON ul.liked_user_id = u.id AND (u.deactivated_at IS NULL OR u.deactivated_at > NOW())
        WHERE ul.user_id = $1
        ORDER BY ul.liked_at DESC
      `, [userUuid]);

      // 受信したいいね（他の人が自分にいいねした）
      const receivedLikesResult = await pool.query(`
        SELECT 
          ul.user_id as sender_id,
          ul.liked_at::text as liked_at,
          u.name,
          u.age,
          u.gender,
          u.image_url,
          u.occupation
        FROM users_likes ul
        JOIN users u ON ul.user_id = u.id AND (u.deactivated_at IS NULL OR u.deactivated_at > NOW())
        WHERE ul.liked_user_id = $1
        ORDER BY ul.liked_at DESC
      `, [userUuid]);

      // レストランのいいね（従来の機能も維持）
      const restaurantsResult = await pool.query(
        "SELECT restaurant_id FROM restaurants_likes WHERE user_id = $1",
        [userUuid]
      );

      const sentCount = sentLikesResult.rows.length;
      const receivedCount = receivedLikesResult.rows.length;
      console.log(`✅ いいね取得成功: 送信${sentCount}件, 受信${receivedCount}件`);

      return {
        sentLikes: sentLikesResult.rows,
        receivedLikes: receivedLikesResult.rows,
        // 従来の互換性維持
        likedUsers: sentLikesResult.rows.map((row) => row.liked_user_id),
        likedRestaurants: restaurantsResult.rows.map(
          (row) => row.restaurant_id
        ),
      };
    } catch (err) {
      console.error("LIKE状態取得失敗:", err);
      throw new functions.https.HttpsError(
        "internal",
        "LIKE状態の取得に失敗しました"
      );
    }
  }
);

// いいねしたレストラン詳細取得
export const getLikedRestaurants = onCall(
  async (request: CallableRequest<unknown>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      console.log(`🔍 いいねレストラン取得開始: userUuid=${userUuid}`);

      // いいねしたレストランの詳細情報を取得
      const likedRestaurantsResult = await pool.query(`
        SELECT 
          r.id,
          r.name,
          r.category,
          r.prefecture,
          r.nearest_station,
          r.price_range,
          r.low_price,
          r.high_price,
          r.image_url,
          r.address,
          r.hotpepper_url,
          r.operating_hours,
          rl.liked_at::text as liked_at
        FROM restaurants_likes rl
        JOIN restaurants r ON rl.restaurant_id = r.id
        WHERE rl.user_id = $1
        ORDER BY rl.liked_at DESC
      `, [userUuid]);

      console.log(
        `✅ いいねレストラン取得成功: ${likedRestaurantsResult.rows.length}件`
      );

      return {
        restaurants: likedRestaurantsResult.rows,
      };
    } catch (err) {
      console.error("❌ いいねレストラン取得失敗:", err);
      throw new functions.https.HttpsError(
        "internal",
        "いいねレストランの取得に失敗しました"
      );
    }
  }
);

// ユーザープロフィール作成
export const createUserProfile = onCall(async (request) => {
  try {
    console.log("🔥 createUserProfile: 開始");
    console.log("🔥 createUserProfile: request.auth =", !!request.auth);

    // 認証確認
    if (!request.auth) {
      console.log("🔥 createUserProfile: 認証エラー - request.authがnull");
      throw new functions.https.HttpsError(
        "unauthenticated",
        "ユーザーが認証されていません",
      );
    }

    const firebaseUid = request.auth.uid;
    console.log("🔥 createUserProfile: Firebase UID =", firebaseUid);
    console.log("🔥 createUserProfile: Auth Token =", request.auth.token);

    // 認証ユーザー情報のログ出力
    const authUser = request.auth;
    console.log("🔥 createUserProfile: Auth User =", {
      uid: authUser.uid,
      email: authUser.token.email,
      email_verified: authUser.token.email_verified,
      firebase: authUser.token.firebase,
    });

    // プロバイダーデータ確認
    const providerData = authUser.token.firebase?.identities || {};
    console.log("🔥 createUserProfile: Provider Data =", providerData);

    // 一時的にメール認証チェックを無効化（デバッグ用）
    /*
    // パスワードベースの認証（メール）の場合、email_verifiedをチェック
    if (providerData['email'] && !authUser.token.email_verified) {
      console.log("🔥 createUserProfile: メール未認証エラー");
      throw new functions.https.HttpsError(
        "permission-denied",
        "メール認証が完了していません。メールボックスを確認してください。",
      );
    }
    */

    const {
      name,
      bio,
      age,
      birth_date: birthDate,
      gender,
      prefecture,
      occupation,
      weekend_off: weekendOff,
      favorite_categories: favoriteCategories,
      authMethod,
      email,
      phoneNumber,
      image_url: imageUrl,
      preferred_age_range: preferredAgeRange,
      payment_preference: paymentPreference,
      preferred_gender: preferredGender,
      school_id: schoolId,
      show_school: showSchool,
      hide_from_same_school: hideFromSameSchool,
      visible_only_if_liked: visibleOnlyIfLiked,
    } = request.data;

    // パラメータの正規化
    const finalBirthDate = birthDate;
    const finalWeekendOff = weekendOff;
    const finalFavoriteCategories = favoriteCategories;
    const finalImageUrl = imageUrl;
    const finalPreferredAgeRange = preferredAgeRange;
    const finalPaymentPreference = paymentPreference;
    const finalPreferredGender = preferredGender;
    const finalSchoolId = schoolId;
    const finalShowSchool = showSchool !== undefined ? showSchool : true;
    const finalHideFromSameSchool = hideFromSameSchool !== undefined ? hideFromSameSchool : false;
    const finalVisibleOnlyIfLiked = visibleOnlyIfLiked !== undefined ? visibleOnlyIfLiked : false;

    console.log("🔥 createUserProfile: 受信データ =", {
      name,
      bio,
      age,
      birthDate: finalBirthDate,
      gender,
      prefecture,
      occupation,
      weekendOff: finalWeekendOff,
      favoriteCategories: finalFavoriteCategories,
      authMethod,
      email,
      phoneNumber,
      imageUrl: finalImageUrl,
      preferredAgeRange: finalPreferredAgeRange,
      paymentPreference: finalPaymentPreference,
      preferredGender: finalPreferredGender,
      schoolId: finalSchoolId,
      showSchool: finalShowSchool,
      hideFromSameSchool: finalHideFromSameSchool,
      visibleOnlyIfLiked: finalVisibleOnlyIfLiked,
    });

    // 必須フィールドのバリデーション（緩和版）
    if (!name) {
      console.log("🔥 createUserProfile: 名前が必須です");
      throw new functions.https.HttpsError(
        "invalid-argument",
        "名前は必須です",
      );
    }

    // 年齢のデフォルト値設定
    const userAge = age || 20;

    // 生年月日の処理
    let parsedBirthDate = null;
    if (finalBirthDate) {
      try {
        parsedBirthDate = new Date(finalBirthDate);
        console.log("🔥 createUserProfile: 生年月日解析成功 =", parsedBirthDate);
      } catch (error) {
        console.log("🔥 createUserProfile: 生年月日解析失敗 =", finalBirthDate);
      }
    }

    // 既存ユーザーチェック（重複防止）
    console.log("🔥 createUserProfile: 既存ユーザーチェック開始");
    const existingUserResult = await pool.query(
      "SELECT id, firebase_uid FROM users WHERE firebase_uid = $1 LIMIT 1",
      [firebaseUid]
    );

    if (existingUserResult.rows.length > 0) {
      console.log(
        "🔥 createUserProfile: 既存ユーザー検出 =",
        existingUserResult.rows[0]
      );
      throw new functions.https.HttpsError(
        "already-exists",
        "このFirebase UIDのユーザーは既に存在します",
        {existingUserId: existingUserResult.rows[0].id}
      );
    }

    // UUIDの生成
    const userId = uuidv4();
    console.log("🔥 createUserProfile: 生成されたUUID =", userId);

    // データベースに挿入
    console.log("🔥 createUserProfile: データベース挿入開始");
    const result = await pool.query(`
      INSERT INTO users (
        id, 
        firebase_uid, 
        name,
        bio,
        age,
        birth_date,
        gender, 
        prefecture,
        occupation, 
        weekend_off, 
        favorite_categories, 
        id_verified,
        email,
        phone_number,
        provider_id,
        is_profile_complete,
        image_url,
        preferred_age_range,
        payment_preference,
        preferred_gender,
        school_id,
        show_school,
        hide_from_same_school,
        visible_only_if_liked,
        created_at,
        updated_at
      ) VALUES (
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16,
        $17, $18, $19, $20, $21, $22, $23, $24, $25, $26
      )
      RETURNING id
    `, [
      userId,
      firebaseUid,
      name,
      bio || "",
      userAge,
      parsedBirthDate,
      gender || null,
      prefecture || null,
      occupation || null,
      finalWeekendOff || false,
      finalFavoriteCategories || [],
      false, // id_verified - 初期は未認証
      email || null,
      phoneNumber || null,
      authMethod || "anonymous",
      !!(gender && prefecture && occupation), // 基本情報が全て揃っていればtrue
      finalImageUrl || null,
      finalPreferredAgeRange || null,
      finalPaymentPreference || null,
      finalPreferredGender || null,
      finalSchoolId || null,
      finalShowSchool,
      finalHideFromSameSchool,
      finalVisibleOnlyIfLiked,
      new Date(),
      new Date(),
    ]);

    console.log("🔥 createUserProfile: データベース挿入成功 =", result.rows);
    console.log(
      `✅ ユーザー作成成功: ${userId}, Firebase UID: ${firebaseUid}`
    );

    return {
      success: true,
      userId: userId,
      message: "ユーザープロフィールが作成されました",
    };
  } catch (error) {
    console.error("🔥 ユーザー作成エラー:", error);

    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    throw new functions.https.HttpsError(
      "internal",
      "ユーザー作成に失敗しました",
    );
  }
});

// プロフィール取得
export const getUserProfile = onCall(async (request) => {
  try {
    console.log("🔥 getUserProfile: 開始");

    if (!request.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "ユーザーが認証されていません"
      );
    }

    const firebaseUid = request.auth.uid;
    console.log("🔥 getUserProfile: Firebase UID =", firebaseUid);

    const result = await pool.query(
      `SELECT 
        u.id, u.name, u.bio, u.age, u.gender, u.prefecture, u.occupation, 
        u.weekend_off, u.favorite_categories, u.image_url, 
        u.birth_date, u.id_verified, u.created_at, u.updated_at, u.deactivated_at, u.account_status,
        u.tags, u.mbti, u.preferred_age_range, u.payment_preference, u.preferred_gender,
        u.school_id, u.show_school, u.hide_from_same_school, u.visible_only_if_liked,
        s.school_name, s.school_type, s.prefecture_name as school_prefecture
       FROM users u
       LEFT JOIN schools s ON u.school_id = s.id
       WHERE u.firebase_uid = $1 LIMIT 1`,
      [firebaseUid]
    );

    if (result.rows.length === 0) {
      return {
        exists: false,
        message: "ユーザーが見つかりません",
      };
    }

    const user = result.rows[0];
    console.log("🔥 getUserProfile: データベースから取得した生データ =", user);
    console.log("🔥 getUserProfile: birth_date の値 =", user.birth_date);
    console.log("🔥 getUserProfile: birth_date の型 =", typeof user.birth_date);

    // favorite_categories の詳細デバッグ
    console.log("🔥 getUserProfile: favorite_categories の値 =", user.favorite_categories);
    console.log("🔥 getUserProfile: favorite_categories の型 =", typeof user.favorite_categories);
    console.log("🔥 getUserProfile: favorite_categories は配列か? =", Array.isArray(user.favorite_categories));
    if (user.favorite_categories) {
      console.log("🔥 getUserProfile: favorite_categories の内容 =", JSON.stringify(user.favorite_categories));
    }

    console.log("🔥 getUserProfile: ユーザー取得成功");

    return {
      exists: true,
      user: {
        id: user.id,
        name: user.name,
        bio: user.bio,
        age: user.age,
        gender: user.gender,
        prefecture: user.prefecture,
        occupation: user.occupation,
        weekend_off: user.weekend_off,
        favorite_categories: user.favorite_categories,
        image_url: user.image_url,
        birth_date: user.birth_date ? user.birth_date.toISOString() : null,
        id_verified: user.id_verified,
        created_at: user.created_at,
        updated_at: user.updated_at,
        deactivated_at: user.deactivated_at ? user.deactivated_at.toISOString() : null,
        account_status: user.account_status,
        tags: user.tags || [],
        mbti: user.mbti,
        preferred_age_range: user.preferred_age_range,
        payment_preference: user.payment_preference,
        preferred_gender: user.preferred_gender,
        school_id: user.school_id,
        school_name: user.school_name,
        school_type: user.school_type,
        show_school: user.show_school,
        hide_from_same_school: user.hide_from_same_school,
        visible_only_if_liked: user.visible_only_if_liked,
      },
    };
  } catch (error) {
    console.error("🔥 getUserProfile エラー:", error);

    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    throw new functions.https.HttpsError(
      "internal",
      "プロフィール取得に失敗しました"
    );
  }
});

// プロフィール更新
export const updateUserProfile = onCall(async (request) => {
  try {
    console.log("🔥 updateUserProfile: 開始");

    if (!request.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "ユーザーが認証されていません"
      );
    }

    const firebaseUid = request.auth.uid;
    const {
      name,
      bio,
      gender,
      birthDate,
      prefecture,
      occupation,
      weekendOff,
      favoriteCategories,
      imageUrl,
      tags,
      mbti,
      preferredAgeRange,
      paymentPreference,
      preferredGender,
      schoolId,
      showSchool,
      hideFromSameSchool,
      visibleOnlyIfLiked,
    } = request.data;

    // スネークケースパラメータも受け取る（下位互換性のため）
    const requestData = request.data as Record<string, unknown>;
    const birthDateSnake = requestData.birth_date;
    const weekendOffSnake = requestData.weekend_off;
    const favoriteCategoriesSnake = requestData.favorite_categories;
    const imageUrlSnake = requestData.image_url;
    const preferredAgeRangeSnake = requestData.preferred_age_range;
    const paymentPreferenceSnake = requestData.payment_preference;
    const preferredGenderSnake = requestData.preferred_gender;
    const schoolIdSnake = requestData.school_id;
    const showSchoolSnake = requestData.show_school;
    const hideFromSameSchoolSnake = requestData.hide_from_same_school;
    const visibleOnlyIfLikedSnake = requestData.visible_only_if_liked;

    // パラメータの正規化
    const finalBirthDate = birthDateSnake || birthDate;
    const finalWeekendOff = weekendOffSnake !== undefined ? weekendOffSnake : weekendOff;
    const finalFavoriteCategories = favoriteCategoriesSnake || favoriteCategories;
    const finalImageUrl = imageUrlSnake || imageUrl;
    const finalPreferredAgeRange = preferredAgeRangeSnake || preferredAgeRange;
    const finalPaymentPreference = paymentPreferenceSnake || paymentPreference;
    const finalPreferredGender = preferredGenderSnake || preferredGender;
    const finalSchoolId = schoolIdSnake || schoolId;
    const finalShowSchool = showSchoolSnake !== undefined ? showSchoolSnake : (showSchool !== undefined ? showSchool : true);
    const finalHideFromSameSchool = hideFromSameSchoolSnake !== undefined ? hideFromSameSchoolSnake : (hideFromSameSchool !== undefined ? hideFromSameSchool : false);
    const finalVisibleOnlyIfLiked = visibleOnlyIfLikedSnake !== undefined ? visibleOnlyIfLikedSnake : (visibleOnlyIfLiked !== undefined ? visibleOnlyIfLiked : false);

    // ハッシュタグとMBTIの処理
    const finalTags = tags || [];
    const finalMbti = mbti || null;

    console.log("🔥 updateUserProfile: 受信した生データ =", request.data);
    console.log("🔥 updateUserProfile: 更新データ =", {
      name,
      gender,
      birthDate: finalBirthDate,
      prefecture,
      occupation,
      weekendOff: finalWeekendOff,
      favoriteCategories: finalFavoriteCategories,
      imageUrl: finalImageUrl,
      tags: finalTags,
      mbti: finalMbti,
      preferredAgeRange: finalPreferredAgeRange,
      paymentPreference: finalPaymentPreference,
      preferredGender: finalPreferredGender,
    });

    // 年齢計算
    let age = null;
    if (finalBirthDate) {
      console.log("🔥 updateUserProfile: 生年月日処理開始 =", finalBirthDate);
      const birthDateObj = new Date(finalBirthDate);
      console.log("🔥 updateUserProfile: 生年月日オブジェクト =", birthDateObj);

      // 現在の日付（日本時間）
      const now = new Date();
      const currentYear = now.getFullYear();
      const currentMonth = now.getMonth(); // 0-11
      const currentDay = now.getDate();

      // 生年月日
      const birthYear = birthDateObj.getFullYear();
      const birthMonth = birthDateObj.getMonth(); // 0-11
      const birthDay = birthDateObj.getDate();

      // 年齢計算
      age = currentYear - birthYear;

      // 誕生日がまだ来ていない場合は1歳引く
      if (currentMonth < birthMonth ||
          (currentMonth === birthMonth && currentDay < birthDay)) {
        age--;
      }

      console.log("🔥 updateUserProfile: 計算された年齢 =", age);
      console.log(
        "🔥 updateUserProfile: 現在日付 =",
        `${currentYear}/${currentMonth + 1}/${currentDay}`
      );
      console.log(
        "🔥 updateUserProfile: 生年月日 =",
        `${birthYear}/${birthMonth + 1}/${birthDay}`
      );
    } else {
      console.log("🔥 updateUserProfile: 生年月日が空です");
    }

    const result = await pool.query(
      `UPDATE users SET 
        name = COALESCE($2, name),
        bio = COALESCE($3, bio),
        age = COALESCE($4, age),
        gender = COALESCE($5, gender),
        birth_date = COALESCE($6, birth_date),
        prefecture = COALESCE($7, prefecture),
        occupation = COALESCE($8, occupation),
        weekend_off = COALESCE($9, weekend_off),
        favorite_categories = COALESCE($10, favorite_categories),
        image_url = COALESCE($11, image_url),
        tags = COALESCE($12, tags),
        mbti = COALESCE($13, mbti),
        preferred_age_range = COALESCE($14, preferred_age_range),
        payment_preference = COALESCE($15, payment_preference),
        preferred_gender = COALESCE($16, preferred_gender),
        school_id = COALESCE($17, school_id),
        show_school = COALESCE($18, show_school),
        hide_from_same_school = COALESCE($19, hide_from_same_school),
        visible_only_if_liked = COALESCE($20, visible_only_if_liked),
        updated_at = $21
       WHERE firebase_uid = $1
       RETURNING id`,
      [
        firebaseUid,
        name,
        bio,
        age,
        gender,
        finalBirthDate,
        prefecture,
        occupation,
        finalWeekendOff,
        finalFavoriteCategories,
        finalImageUrl,
        finalTags,
        finalMbti,
        finalPreferredAgeRange,
        finalPaymentPreference,
        finalPreferredGender,
        finalSchoolId,
        finalShowSchool,
        finalHideFromSameSchool,
        finalVisibleOnlyIfLiked,
        new Date(),
      ],
    );

    if (result.rows.length === 0) {
      throw new functions.https.HttpsError(
        "not-found",
        "ユーザーが見つかりません"
      );
    }

    console.log("🔥 updateUserProfile: 更新成功");

    return {
      success: true,
      message: "プロフィールを更新しました",
    };
  } catch (error) {
    console.error("🔥 updateUserProfile エラー:", error);

    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    throw new functions.https.HttpsError(
      "internal",
      "プロフィール更新に失敗しました"
    );
  }
});

// 他のユーザーのプロフィール取得
export const getUserProfileById = onCall(async (request) => {
  try {
    console.log("🔥 getUserProfileById: 開始");

    if (!request.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "ユーザーが認証されていません"
      );
    }

    const {userId} = request.data;

    if (!userId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "ユーザーIDが必要です"
      );
    }

    console.log("🔥 getUserProfileById: 取得対象ユーザーID =", userId);

    const result = await pool.query(
      `SELECT 
        u.id, u.name, u.bio, u.age, u.gender, u.prefecture, u.occupation, 
        u.weekend_off, u.favorite_categories, u.image_url, 
        u.birth_date, u.id_verified, u.created_at, u.tags, u.mbti,
        u.preferred_age_range, u.payment_preference, u.preferred_gender,
        u.school_id, u.show_school, u.hide_from_same_school, u.visible_only_if_liked,
        s.school_name, s.school_type, s.prefecture_name as school_prefecture
       FROM users u
       LEFT JOIN schools s ON u.school_id = s.id
       WHERE u.id = $1 LIMIT 1`,
      [userId]
    );

    if (result.rows.length === 0) {
      return {
        exists: false,
        message: "ユーザーが見つかりません",
      };
    }

    const user = result.rows[0];
    console.log("🔥 getUserProfileById: ユーザー取得成功");

    return {
      exists: true,
      user: {
        id: user.id,
        name: user.name,
        age: user.age,
        gender: user.gender,
        prefecture: user.prefecture,
        occupation: user.occupation,
        weekend_off: user.weekend_off,
        favorite_categories: user.favorite_categories,
        image_url: user.image_url,
        birth_date: user.birth_date ? user.birth_date.toISOString() : null,
        id_verified: user.id_verified,
        created_at: user.created_at,
        tags: user.tags || [],
        mbti: user.mbti,
        preferred_age_range: user.preferred_age_range,
        payment_preference: user.payment_preference,
        preferred_gender: user.preferred_gender,
        school_id: user.school_id,
        school_name: user.school_name,
        school_type: user.school_type,
        show_school: user.show_school,
        hide_from_same_school: user.hide_from_same_school,
        visible_only_if_liked: user.visible_only_if_liked,
      },
    };
  } catch (error) {
    console.error("🔥 getUserProfileById エラー:", error);

    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    throw new functions.https.HttpsError(
      "internal",
      "プロフィール取得に失敗しました"
    );
  }
});

// Firebase UIDからユーザー情報を取得
export const getUserByFirebaseUid = onCall(async (request) => {
  try {
    console.log("🔥 getUserByFirebaseUid: 開始");

    if (!request.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "ユーザーが認証されていません"
      );
    }

    const {firebaseUid} = request.data;

    if (!firebaseUid) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Firebase UIDが必要です"
      );
    }

    console.log("🔥 getUserByFirebaseUid: 取得対象Firebase UID =", firebaseUid);

    const result = await pool.query(
      `SELECT 
        id, name, bio, age, gender, prefecture, occupation, 
        weekend_off, favorite_categories, image_url, 
        birth_date, id_verified, created_at, firebase_uid, email,
        preferred_age_range, payment_preference, preferred_gender,
        school_id, show_school, hide_from_same_school, visible_only_if_liked
       FROM users 
       WHERE firebase_uid = $1 
       AND (deactivated_at IS NULL OR deactivated_at > NOW())
       LIMIT 1`,
      [firebaseUid]
    );

    if (result.rows.length === 0) {
      console.log("🔥 getUserByFirebaseUid: ユーザーが見つかりません");
      return {
        exists: false,
        message: "ユーザーが見つかりません",
      };
    }

    const user = result.rows[0];
    console.log("🔥 getUserByFirebaseUid: ユーザー取得成功", user.name);

    return {
      exists: true,
      user: {
        id: user.id,
        name: user.name,
        displayName: user.name, // Firestore形式に合わせる
        age: user.age,
        gender: user.gender,
        prefecture: user.prefecture,
        occupation: user.occupation,
        weekend_off: user.weekend_off,
        favorite_categories: user.favorite_categories,
        image_url: user.image_url,
        imageUrl: user.image_url, // Firestore形式に合わせる
        birth_date: user.birth_date ? user.birth_date.toISOString() : null,
        id_verified: user.id_verified,
        created_at: user.created_at,
        firebase_uid: user.firebase_uid,
        email: user.email,
        preferred_age_range: user.preferred_age_range,
        payment_preference: user.payment_preference,
        preferred_gender: user.preferred_gender,
        school_id: user.school_id,
        show_school: user.show_school,
        hide_from_same_school: user.hide_from_same_school,
        visible_only_if_liked: user.visible_only_if_liked,
      },
    };
  } catch (error) {
    console.error("🔥 getUserByFirebaseUid エラー:", error);

    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    throw new functions.https.HttpsError(
      "internal",
      "ユーザー取得に失敗しました"
    );
  }
});

// 退会・復元機能は後半で実装済み

// マッチ一覧取得
export const getUserMatches = onCall(
  async (request: CallableRequest<{limit?: number}>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {limit = 50} = request.data;

    console.log(
      "🔍 マッチ一覧取得:",
      `firebaseUid=${firebaseUid}, limit=${limit}`
    );

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      const result = await pool.query(
        `SELECT 
          m.id,
          m.user1_id,
          m.user2_id,
          m.restaurant_id,
          m.status,
          m.matched_at,
          m.last_message,
          m.last_message_at,
          m.last_message_sender_id,
          CASE 
            WHEN m.user1_id = $1 THEN m.unread_count_user1
            ELSE m.unread_count_user2
          END as unread_count,
          -- 相手ユーザーの情報
          CASE 
            WHEN m.user1_id = $1 THEN u2.name
            ELSE u1.name
          END as partner_name,
          CASE 
            WHEN m.user1_id = $1 THEN u2.image_url
            ELSE u1.image_url
          END as partner_image_url,
          CASE 
            WHEN m.user1_id = $1 THEN u2.id
            ELSE u1.id
          END as partner_id,
          -- レストラン情報
          r.name as restaurant_name,
          r.image_url as restaurant_image_url
         FROM matches m
         LEFT JOIN users u1 ON m.user1_id = u1.id AND (u1.deactivated_at IS NULL OR u1.deactivated_at > NOW())
         LEFT JOIN users u2 ON m.user2_id = u2.id AND (u2.deactivated_at IS NULL OR u2.deactivated_at > NOW())
         LEFT JOIN restaurants r ON m.restaurant_id = r.id
         WHERE (m.user1_id = $1 OR m.user2_id = $1)
         AND m.status = 'active'
         ORDER BY m.updated_at DESC
         LIMIT $2`,
        [userUuid, limit]
      );

      console.log("✅ マッチ一覧取得成功:", result.rows.length, "件");
      return {
        matches: result.rows,
        totalCount: result.rows.length,
      };
    } catch (err) {
      console.error("❌ マッチ一覧取得失敗:", err);
      throw new functions.https.HttpsError(
        "internal",
        "マッチ一覧の取得に失敗しました"
      );
    }
  }
);

// マッチ詳細取得
export const getMatchDetail = onCall(
  async (request: CallableRequest<{matchId: string}>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {matchId} = request.data;

    console.log(
      "🔍 マッチ詳細取得:",
      `firebaseUid=${firebaseUid}, matchId=${matchId}`
    );

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      const result = await pool.query(
        `SELECT 
          m.id,
          m.user1_id,
          m.user2_id,
          m.restaurant_id,
          m.status,
          m.matched_at,
          m.last_message,
          m.last_message_at,
          m.last_message_sender_id,
          -- 相手ユーザーの詳細情報
          CASE 
            WHEN m.user1_id = $2 THEN u2.name
            ELSE u1.name
          END as partner_name,
          CASE 
            WHEN m.user1_id = $2 THEN u2.image_url
            ELSE u1.image_url
          END as partner_image_url,
          CASE 
            WHEN m.user1_id = $2 THEN u2.id
            ELSE u1.id
          END as partner_id,
          CASE 
            WHEN m.user1_id = $2 THEN u2.age
            ELSE u1.age
          END as partner_age,
          CASE 
            WHEN m.user1_id = $2 THEN u2.gender
            ELSE u1.gender
          END as partner_gender,
          CASE 
            WHEN m.user1_id = $2 THEN u2.occupation
            ELSE u1.occupation
          END as partner_occupation,
          -- レストラン詳細情報
          r.name as restaurant_name,
          r.image_url as restaurant_image_url,
          r.category as restaurant_category,
          r.prefecture as restaurant_prefecture,
          r.nearest_station as restaurant_nearest_station,
          r.price_range as restaurant_price_range
         FROM matches m
         LEFT JOIN users u1 ON m.user1_id = u1.id AND (u1.deactivated_at IS NULL OR u1.deactivated_at > NOW())
         LEFT JOIN users u2 ON m.user2_id = u2.id AND (u2.deactivated_at IS NULL OR u2.deactivated_at > NOW())
         LEFT JOIN restaurants r ON m.restaurant_id = r.id
         WHERE m.id = $1
         AND (m.user1_id = $2 OR m.user2_id = $2)`,
        [matchId, userUuid]
      );

      if (result.rows.length === 0) {
        throw new functions.https.HttpsError(
          "not-found",
          "マッチが見つからないか、アクセス権限がありません"
        );
      }

      console.log("✅ マッチ詳細取得成功");
      return result.rows[0];
    } catch (err) {
      console.error("❌ マッチ詳細取得失敗:", err);
      throw new functions.https.HttpsError(
        "internal",
        "マッチ詳細の取得に失敗しました"
      );
    }
  }
);

// マッチ内のメッセージ取得
export const getMatchMessages = onCall(
  async (request: CallableRequest<{matchId: string; limit?: number}>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {matchId, limit = 50} = request.data;

    console.log(
      "🔍 マッチメッセージ取得:",
      `firebaseUid=${firebaseUid}, matchId=${matchId}`
    );

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      // マッチへのアクセス権限確認とアクティブ状態確認
      const matchCheck = await pool.query(
        `SELECT m.id FROM matches m
         LEFT JOIN users u1 ON m.user1_id = u1.id AND (u1.deactivated_at IS NULL OR u1.deactivated_at > NOW())
         LEFT JOIN users u2 ON m.user2_id = u2.id AND (u2.deactivated_at IS NULL OR u2.deactivated_at > NOW())
         WHERE m.id = $1 
         AND (m.user1_id = $2 OR m.user2_id = $2) 
         AND m.status = 'active'`,
        [matchId, userUuid]
      );

      if (matchCheck.rows.length === 0) {
        throw new functions.https.HttpsError(
          "permission-denied",
          "このマッチにアクセスする権限がありません"
        );
      }

      // メッセージ取得（非表示フラグを考慮）
      const result = await pool.query(
        `SELECT 
          m.id,
          m.sender_id,
          m.content,
          m.sent_at::text as sent_at,
          m.type,
          m.seen,
          m.message_type,
          m.date_request_data,
          m.related_date_request_id,
          u.name as sender_name,
          u.image_url as sender_image_url
         FROM messages m
         LEFT JOIN users u ON m.sender_id = u.id AND (u.deactivated_at IS NULL OR u.deactivated_at > NOW())
         WHERE m.match_id = $1
         AND (
           -- 送信者が非表示にしていない
           (m.sender_id = $2 AND m.hidden_by_sender = FALSE)
           OR
           -- 受信者が非表示にしていない
           (m.sender_id != $2 AND m.hidden_by_receiver = FALSE)
         )
         ORDER BY m.sent_at ASC
         LIMIT $3`,
        [matchId, userUuid, limit]
      );

      console.log("✅ マッチメッセージ取得成功:", result.rows.length, "件");
      return {
        messages: result.rows,
        totalCount: result.rows.length,
      };
    } catch (err) {
      console.error("❌ マッチメッセージ取得失敗:", err);
      throw new functions.https.HttpsError(
        "internal",
        "メッセージの取得に失敗しました"
      );
    }
  }
);

// メッセージ非表示機能
export const hideMessages = onCall(
  async (request: CallableRequest<{matchId: string; hideAsSender?: boolean; hideAsReceiver?: boolean}>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {matchId, hideAsSender = true, hideAsReceiver = true} = request.data;

    console.log(
      "🔍 メッセージ非表示:",
      `firebaseUid=${firebaseUid}, matchId=${matchId}`
    );

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      // マッチへのアクセス権限確認
      const matchCheck = await pool.query(
        `SELECT m.id FROM matches m
         WHERE m.id = $1 
         AND (m.user1_id = $2 OR m.user2_id = $2) 
         AND m.status = 'active'`,
        [matchId, userUuid]
      );

      if (matchCheck.rows.length === 0) {
        throw new functions.https.HttpsError(
          "permission-denied",
          "このマッチにアクセスする権限がありません"
        );
      }

      // メッセージを非表示にする
      const result = await pool.query(
        `UPDATE messages 
         SET 
           hidden_by_sender = CASE 
             WHEN sender_id = $1 THEN $2 
             ELSE hidden_by_sender 
           END,
           hidden_by_receiver = CASE 
             WHEN sender_id != $1 THEN $3 
             ELSE hidden_by_receiver 
           END
         WHERE match_id = $4
         AND (
           (sender_id = $1 AND $2 = TRUE)
           OR 
           (sender_id != $1 AND $3 = TRUE)
         )
         RETURNING id`,
        [userUuid, hideAsSender, hideAsReceiver, matchId]
      );

      console.log("✅ メッセージ非表示成功:", result.rows.length, "件");
      return {
        hiddenCount: result.rows.length,
      };
    } catch (err) {
      console.error("❌ メッセージ非表示失敗:", err);
      throw new functions.https.HttpsError(
        "internal",
        "メッセージの非表示に失敗しました"
      );
    }
  }
);

// 非表示メッセージを表示に戻す機能
export const showMessages = onCall(
  async (request: CallableRequest<{matchId: string; showAsSender?: boolean; showAsReceiver?: boolean}>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {matchId, showAsSender = true, showAsReceiver = true} = request.data;

    console.log(
      "🔍 メッセージ表示復旧:",
      `firebaseUid=${firebaseUid}, matchId=${matchId}`
    );

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      // マッチへのアクセス権限確認
      const matchCheck = await pool.query(
        `SELECT m.id FROM matches m
         WHERE m.id = $1 
         AND (m.user1_id = $2 OR m.user2_id = $2) 
         AND m.status = 'active'`,
        [matchId, userUuid]
      );

      if (matchCheck.rows.length === 0) {
        throw new functions.https.HttpsError(
          "permission-denied",
          "このマッチにアクセスする権限がありません"
        );
      }

      // メッセージを表示に戻す
      const result = await pool.query(
        `UPDATE messages 
         SET 
           hidden_by_sender = CASE 
             WHEN sender_id = $1 THEN NOT $2 
             ELSE hidden_by_sender 
           END,
           hidden_by_receiver = CASE 
             WHEN sender_id != $1 THEN NOT $3 
             ELSE hidden_by_receiver 
           END
         WHERE match_id = $4
         AND (
           (sender_id = $1 AND $2 = TRUE)
           OR 
           (sender_id != $1 AND $3 = TRUE)
         )
         RETURNING id`,
        [userUuid, showAsSender, showAsReceiver, matchId]
      );

      console.log("✅ メッセージ表示復旧成功:", result.rows.length, "件");
      return {
        shownCount: result.rows.length,
      };
    } catch (err) {
      console.error("❌ メッセージ表示復旧失敗:", err);
      throw new functions.https.HttpsError(
        "internal",
        "メッセージの表示復旧に失敗しました"
      );
    }
  }
);

// メッセージ送信
export const sendMessage = onCall(
  async (request: CallableRequest<{
    matchId: string;
    content: string;
    type?: string;
    recipientId?: string; // camelCaseに修正
  }>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {matchId, content, type = "text", recipientId} = request.data;

    console.log(
      "🔍 メッセージ送信:",
      `firebaseUid=${firebaseUid}, matchId=${matchId}`
    );

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      console.log("🔍 ユーザーUUID取得開始:", firebaseUid);
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      console.log("🔍 取得したユーザーUUID:", userUuid);

      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      // usersテーブルで実際に存在するか確認
      const userExists = await pool.query(
        "SELECT id, name FROM users WHERE id = $1 AND (deactivated_at IS NULL OR deactivated_at > NOW())",
        [userUuid]
      );
      console.log("🔍 ユーザー存在確認:", userExists.rows);

      if (userExists.rows.length === 0) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーレコードが見つかりません"
        );
      }

      // メッセージ内容の検証
      if (!content || content.trim().length === 0) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "メッセージ内容が空です"
        );
      }

      // マッチへのアクセス権限確認とアクティブ状態確認
      const matchCheck = await pool.query(
        `SELECT m.id FROM matches m
         LEFT JOIN users u1 ON m.user1_id = u1.id AND (u1.deactivated_at IS NULL OR u1.deactivated_at > NOW())
         LEFT JOIN users u2 ON m.user2_id = u2.id AND (u2.deactivated_at IS NULL OR u2.deactivated_at > NOW())
         WHERE m.id = $1 
         AND (m.user1_id = $2 OR m.user2_id = $2) 
         AND m.status = 'active'`,
        [matchId, userUuid]
      );

      if (matchCheck.rows.length === 0) {
        throw new functions.https.HttpsError(
          "permission-denied",
          "マッチにメッセージを送信する権限がありません"
        );
      }

      // recipientIdが渡された場合はそれを使い、なければ従来通りDBから取得
      let finalRecipientId = recipientId;
      if (!finalRecipientId) {
        const matchResult = await pool.query(
          `SELECT
            CASE
              WHEN user1_id = $1 THEN user2_id
              ELSE user1_id
            END as recipient_user_id
          FROM matches
          WHERE id = $2`,
          [userUuid, matchId]
        );
        finalRecipientId = matchResult.rows[0]?.recipient_user_id;
      }

      // メッセージ送信（recipient_idも保存）
      const result = await pool.query(
        `INSERT INTO messages (sender_id, match_id, content, message_type, recipient_id)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING id, sent_at::text as sent_at`,
        [userUuid, matchId, content.trim(), type, finalRecipientId]
      );

      console.log("✅ メッセージ送信成功:", result.rows[0]);

      // 相手ユーザーを特定して通知を送信
      try {
        // マッチから相手ユーザーのIDを取得
        const matchDetailQuery = `
          SELECT 
            CASE 
              WHEN user1_id = $1 THEN user2_id 
              ELSE user1_id 
            END as recipient_user_id
          FROM matches 
          WHERE id = $2
        `;
        const matchResult = await pool.query(
          matchDetailQuery,
          [userUuid, matchId]
        );

        if (matchResult.rows.length > 0) {
          const recipientUserId = matchResult.rows[0].recipient_user_id;
          const senderName = userExists.rows[0].name || "Unknown";

          // 相手ユーザーのFCMトークンと通知設定を取得
          const targetQuery = `
            SELECT firebase_uid, fcm_token FROM users WHERE id = $1
          `;
          const targetResult = await pool.query(targetQuery, [recipientUserId]);

          if (targetResult.rows.length > 0 && targetResult.rows[0].fcm_token) {
            const targetFirebaseUid = targetResult.rows[0].firebase_uid;
            const fcmToken = targetResult.rows[0].fcm_token;

            // 通知設定を確認
            const settingsDoc = await admin.firestore()
              .collection("users")
              .doc(targetFirebaseUid)
              .collection("settings")
              .doc("notifications")
              .get();

            let shouldSendNotification = true;
            if (settingsDoc.exists) {
              const settings = settingsDoc.data();
              const enableMessage = settings?.enableMessage !== false;
              const enablePush = settings?.enablePush !== false;
              shouldSendNotification = enableMessage && enablePush;
            }

            // FCMトークンがあり、通知設定が有効な場合のみプッシュ通知を送信
            if (shouldSendNotification) {
              const message = {
                token: fcmToken,
                notification: {
                  title: "デリミート",
                  body: `${senderName}さんからメッセージが届いています❤️`,
                },
                data: {
                  type: "message",
                  matchId: matchId,
                  senderId: userUuid,
                  senderName: senderName,
                },
                android: {
                  priority: "high" as const,
                  notification: {
                    channelId: "dating_food_app_channel",
                    priority: "high" as const,
                  },
                },
                apns: {
                  payload: {
                    aps: {
                      alert: {
                        title: "デリミート",
                        body: `${senderName}さんからメッセージが届いています❤️`,
                      },
                      badge: 1,
                      sound: "default",
                    },
                  },
                },
              };

              await admin.messaging().send(message);

              // Firestoreに通知履歴を保存
              const notificationData = {
                userId: targetFirebaseUid,
                type: "message",
                title: "デリミート",
                body: `${senderName}さんからメッセージが届いています❤️`,
                senderId: firebaseUid,
                senderName: senderName,
                data: {
                  type: "message",
                  matchId: matchId,
                  senderId: userUuid,
                  senderName: senderName,
                },
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                isRead: false,
                isDeleted: false,
              };

              await admin.firestore()
                .collection("notifications")
                .add(notificationData);
            }
          }

          console.log("✅ メッセージ通知送信完了:", recipientUserId);
        }
      } catch (notificationError) {
        console.error("⚠️ メッセージ通知送信エラー:", notificationError);
        // 通知エラーはメイン機能に影響しない
      }

      return {
        success: true,
        messageId: result.rows[0].id,
        sentAt: result.rows[0].sent_at,
      };
    } catch (err) {
      console.error("❌ メッセージ送信失敗:", err);
      throw new functions.https.HttpsError(
        "internal",
        "メッセージの送信に失敗しました"
      );
    }
  }
);

// メッセージ既読マーク
export const markMessagesAsRead = onCall(
  async (request: CallableRequest<{matchId: string}>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {matchId} = request.data;

    console.log(
      "🔍 メッセージ既読マーク:",
      `firebaseUid=${firebaseUid}, matchId=${matchId}`
    );

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      // 既読マーク実行
      await pool.query(
        "SELECT mark_messages_as_read($1, $2)",
        [matchId, userUuid]
      );

      console.log("✅ メッセージ既読マーク成功");
      return {success: true};
    } catch (err) {
      console.error("❌ メッセージ既読マーク失敗:", err);
      throw new functions.https.HttpsError(
        "internal",
        "既読マークに失敗しました"
      );
    }
  }
);

// メッセージ削除機能
export const deleteMatchMessages = onCall(
  async (request: CallableRequest<{matchId: string}>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {matchId} = request.data;

    console.log(
      "🔍 メッセージ削除:",
      `firebaseUid=${firebaseUid}, matchId=${matchId}`
    );

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      // マッチへのアクセス権限確認
      const matchCheck = await pool.query(
        `SELECT id FROM matches 
         WHERE id = $1 
         AND (user1_id = $2 OR user2_id = $2) 
         AND status = 'active'`,
        [matchId, userUuid]
      );

      if (matchCheck.rows.length === 0) {
        throw new functions.https.HttpsError(
          "permission-denied",
          "このマッチのメッセージを削除する権限がありません"
        );
      }

      // メッセージを削除
      const deleteResult = await pool.query(
        "DELETE FROM messages WHERE match_id = $1",
        [matchId]
      );

      // マッチの最後のメッセージ情報をクリア
      await pool.query(
        `UPDATE matches 
         SET last_message = NULL, 
             last_message_at = NULL, 
             last_message_sender_id = NULL,
             unread_count_user1 = 0,
             unread_count_user2 = 0,
             updated_at = CURRENT_TIMESTAMP
         WHERE id = $1`,
        [matchId]
      );

      console.log("✅ メッセージ削除成功:", deleteResult.rowCount, "件削除");
      return {
        success: true,
        deletedCount: deleteResult.rowCount,
      };
    } catch (err) {
      console.error("❌ メッセージ削除失敗:", err);
      throw new functions.https.HttpsError(
        "internal",
        "メッセージの削除に失敗しました"
      );
    }
  }
);

// ===== 通報機能 =====
export const reportUser = onCall(
  async (request: CallableRequest<{
    reportedUserId: string;
    reportType: string;
    description?: string;
  }>) => {
    console.log("🚨 ユーザー通報: 開始");

    if (!request.auth) {
      console.log("❌ ユーザー通報: 未認証");
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const {reportedUserId, reportType, description} = request.data;

    if (!reportedUserId || !reportType) {
      console.log("❌ ユーザー通報: 必須パラメータ不足");
      throw new HttpsError(
        "invalid-argument",
        "reportedUserId and reportType are required"
      );
    }

    try {
      // 通報者のユーザー情報取得
      const reporterUuid = await getUserUuidFromFirebaseUid(request.auth.uid);
      if (!reporterUuid) {
        throw new HttpsError("not-found", "通報者が見つかりません");
      }

      console.log(`🚨 通報者: ${reporterUuid}, 被通報者: ${reportedUserId}`);

      // 自分自身を通報することを防ぐ
      if (reporterUuid === reportedUserId) {
        throw new HttpsError(
          "invalid-argument",
          "自分自身を通報することはできません"
        );
      }

      // 被通報者の存在確認
      const reportedUserResult = await pool.query(
        "SELECT id FROM users WHERE id = $1",
        [reportedUserId]
      );

      if (reportedUserResult.rows.length === 0) {
        throw new HttpsError(
          "not-found",
          "通報対象のユーザーが見つかりません"
        );
      }

      // 重複通報チェック
      const existingReport = await pool.query(
        `SELECT id FROM reports 
         WHERE reporter_id = $1 AND reported_user_id = $2`,
        [reporterUuid, reportedUserId]
      );

      if (existingReport.rows.length > 0) {
        throw new HttpsError(
          "already-exists",
          "このユーザーは既に通報済みです"
        );
      }

      // 通報を挿入
      const insertResult = await pool.query(
        `INSERT INTO reports 
         (reporter_id, reported_user_id, report_type, description)
         VALUES ($1, $2, $3, $4)
         RETURNING id, created_at`,
        [reporterUuid, reportedUserId, reportType, description || null]
      );

      const reportId = insertResult.rows[0].id;
      console.log(`✅ 通報作成成功: ${reportId}`);

      // 被通報者の現在の通報数を取得
      const userResult = await pool.query(
        "SELECT report_count, account_status FROM users WHERE id = $1",
        [reportedUserId]
      );

      const reportCount = userResult.rows[0].report_count;
      console.log(`📊 被通報者の通報数: ${reportCount}`);

      // 通報数に基づく制限処理
      await applyUserRestrictions(reportedUserId, reportCount);

      return {
        success: true,
        reportId: reportId,
        message: "通報を受け付けました",
      };
    } catch (error) {
      console.log("❌ ユーザー通報失敗:", error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError("internal", "通報の送信に失敗しました");
    }
  }
);

/**
 * 通報数に基づくユーザー制限処理
 * @param {string} userId - ユーザーID
 * @param {number} reportCount - 通報数
 */
async function applyUserRestrictions(userId: string, reportCount: number) {
  console.log(`🔒 制限処理開始: ユーザー${userId}, 通報数${reportCount}`);

  let newStatus = "active";
  let suspensionUntil = null;
  let shouldNotify = false;
  let notificationMessage = "";

  // 制限レベル判定ログ
  console.log(`📊 制限レベル判定: 通報数${reportCount}`);

  if (reportCount >= 15) {
    // 15回以上: 永久停止
    newStatus = "banned";
    shouldNotify = true;
    notificationMessage =
      "アカウントが永久停止されました。複数の通報により、" +
      "利用規約違反と判断されました。";
    console.log(`🚫 永久停止適用: 通報数${reportCount}回`);
  } else if (reportCount >= 10) {
    // 10回以上: 1ヶ月停止
    newStatus = "suspended";
    const suspensionDate = new Date();
    suspensionDate.setMonth(suspensionDate.getMonth() + 1);
    suspensionUntil = suspensionDate.toISOString();
    shouldNotify = true;
    notificationMessage =
      "アカウントが1ヶ月間停止されました。複数の通報により、" +
      "一時的に利用を制限いたします。";
    console.log(`⏸️ 1ヶ月停止適用: 通報数${reportCount}回, 期限${suspensionUntil}`);
  } else if (reportCount >= 5) {
    // 5回以上: 1週間停止
    newStatus = "suspended";
    const suspensionDate = new Date();
    suspensionDate.setDate(suspensionDate.getDate() + 7);
    suspensionUntil = suspensionDate.toISOString();
    shouldNotify = true;
    notificationMessage =
      "アカウントが1週間停止されました。複数の通報により、" +
      "一時的に利用を制限いたします。";
    console.log(`⏸️ 1週間停止適用: 通報数${reportCount}回, 期限${suspensionUntil}`);
  } else if (reportCount >= 3) {
    // 3回以上: 警告 + 24時間マッチング制限
    newStatus = "warned";
    const suspensionDate = new Date();
    suspensionDate.setDate(suspensionDate.getDate() + 1);
    suspensionUntil = suspensionDate.toISOString();
    shouldNotify = true;
    notificationMessage =
      "警告: 複数の通報を受けています。24時間のマッチング制限が" +
      "適用されました。利用規約をご確認ください。";
    console.log(`⚠️ 警告適用: 通報数${reportCount}回, 24時間制限期限${suspensionUntil}`);
  } else {
    console.log(`✅ 制限なし: 通報数${reportCount}回（3回未満）`);
  }

  if (newStatus !== "active") {
    console.log(`🔄 ユーザーステータス更新開始: ${newStatus}`);

    // ユーザーステータス更新
    await pool.query(
      `UPDATE users
       SET account_status = $1,
           suspension_until = $2,
           last_warning_at = CASE WHEN $1 = 'warned' THEN CURRENT_TIMESTAMP
                              ELSE last_warning_at END
       WHERE id = $3`,
      [newStatus, suspensionUntil, userId]
    );

    console.log(`🔒 制限適用完了: ${newStatus}, 期限: ${suspensionUntil}`);

    // 更新後の状態確認
    const updatedUser = await pool.query(
      `SELECT account_status, suspension_until, last_warning_at, report_count
       FROM users WHERE id = $1`,
      [userId]
    );

    if (updatedUser.rows.length > 0) {
      console.log("📊 更新後ユーザー状態:", updatedUser.rows[0]);
    }

    // TODO: 通知機能実装後にプッシュ通知を送信
    if (shouldNotify) {
      console.log(`📱 通知予定: ${notificationMessage}`);
    }
  }
}

// 管理者用: 通報一覧取得
export const getReports = onCall(
  async (request: CallableRequest<{
    status?: string;
    limit?: number;
    offset?: number;
  }>) => {
    console.log("📋 通報一覧取得: 開始");

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const {status = "pending", limit = 50, offset = 0} = request.data;

    try {
      const result = await pool.query(
        `SELECT 
           r.id,
           r.report_type,
           r.description,
           r.status,
           r.created_at,
           r.reviewed_at,
           r.admin_notes,
           reporter.name as reporter_name,
           reporter.email as reporter_email,
           reported.name as reported_name,
           reported.email as reported_email,
           reported.report_count
         FROM reports r
         JOIN users reporter ON r.reporter_id = reporter.id
         JOIN users reported ON r.reported_user_id = reported.id
         WHERE ($1 = 'all' OR r.status = $1)
         ORDER BY r.created_at DESC
         LIMIT $2 OFFSET $3`,
        [status, limit, offset]
      );

      return {
        reports: result.rows,
        total: result.rows.length,
      };
    } catch (error) {
      console.log("❌ 通報一覧取得失敗:", error);
      throw new HttpsError("internal", "通報一覧の取得に失敗しました");
    }
  }
);

// 削除されたマッチ（メッセージ履歴なし）を取得
export const getDeletedMatches = onCall(
  async (request: CallableRequest<{limit?: number}>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {limit = 20} = request.data;

    console.log(
      "🔍 削除されたマッチ取得:",
      `firebaseUid=${firebaseUid}, limit=${limit}`
    );

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      const result = await pool.query(
        `SELECT 
          m.id,
          m.user1_id,
          m.user2_id,
          m.restaurant_id,
          m.status,
          m.matched_at,
          -- 相手ユーザーの情報
          CASE 
            WHEN m.user1_id = $1 THEN u2.name
            ELSE u1.name
          END as partner_name,
          CASE 
            WHEN m.user1_id = $1 THEN u2.image_url
            ELSE u1.image_url
          END as partner_image_url,
          CASE 
            WHEN m.user1_id = $1 THEN u2.id
            ELSE u1.id
          END as partner_id,
          -- レストラン情報
          r.name as restaurant_name,
          r.image_url as restaurant_image_url
         FROM matches m
         LEFT JOIN users u1 ON m.user1_id = u1.id
         LEFT JOIN users u2 ON m.user2_id = u2.id
         LEFT JOIN restaurants r ON m.restaurant_id = r.id
         WHERE (m.user1_id = $1 OR m.user2_id = $1)
         AND m.status = 'active'
         AND m.last_message IS NULL
         ORDER BY m.matched_at DESC
         LIMIT $2`,
        [userUuid, limit]
      );

      console.log("✅ 削除されたマッチ取得成功:", result.rows.length, "件");
      return {
        matches: result.rows,
        totalCount: result.rows.length,
      };
    } catch (err) {
      console.error("❌ 削除されたマッチ取得失敗:", err);
      throw new functions.https.HttpsError(
        "internal",
        "削除されたマッチの取得に失敗しました"
      );
    }
  }
);

// メールアドレス登録確認
export const checkEmailRegistration = onCall(
  async (request: CallableRequest<{email: string}>) => {
    const {email} = request.data;

    if (!email) {
      throw new HttpsError("invalid-argument", "メールアドレスが必要です");
    }

    console.log("🔍 メールアドレス登録確認:", email);

    try {
      // まず、該当メールアドレスのすべてのレコードを確認
      const allResult = await pool.query(
        `SELECT id, email, provider_id
         FROM users
         WHERE email = $1`,
        [email],
      );

      console.log("🔍 該当メールアドレスの全レコード:", {
        email,
        totalCount: allResult.rows.length,
        records: allResult.rows,
      });

      // メール認証（パスワード方式）のユーザーを検索
      const emailResult = await pool.query(
        `SELECT id, email, provider_id
         FROM users
         WHERE email = $1 AND provider_id = 'email'`,
        [email],
      );

      const isRegistered = emailResult.rows.length > 0;

      console.log("✅ メールアドレス登録確認結果:", {
        email,
        isRegistered,
        emailProviderCount: emailResult.rows.length,
        totalCount: allResult.rows.length,
      });

      return {
        isRegistered,
        email,
        userCount: emailResult.rows.length,
      };
    } catch (err) {
      console.error("❌ メールアドレス登録確認失敗:", err);
      throw new HttpsError("internal", "メールアドレス確認に失敗しました");
    }
  },
);

// LINE認証→Firebaseカスタムトークン発行API
export const verifyLineToken = onCall(
  async (request: CallableRequest<{ accessToken: string }>) => {
    const {accessToken} = request.data;
    if (!accessToken) {
      throw new HttpsError("invalid-argument", "accessToken is required");
    }

    console.log("🔍 LINE認証: アクセストークン検証開始");

    // 1. LINEのアクセストークンを検証してユーザー情報を取得
    let lineUserId: string;
    let lineUserProfile: {
      userId: string;
      displayName: string;
      pictureUrl?: string;
    };
    try {
      // LINE Profile APIでユーザー情報を取得
      const response = await axios.get(
        "https://api.line.me/v2/profile",
        {
          headers: {
            "Authorization": `Bearer ${accessToken}`,
          },
        }
      );

      lineUserId = response.data.userId;
      lineUserProfile = response.data;

      console.log("✅ LINE認証: ユーザー情報取得成功", {
        userId: lineUserId,
        displayName: lineUserProfile.displayName,
      });
    } catch (error) {
      console.error("❌ LINE認証: ユーザー情報取得失敗", error);
      throw new HttpsError("unauthenticated", "Invalid LINE access token");
    }

    // 2. Firebase Firestore にユーザー情報を保存（必要に応じて）
    try {
      const firestore = admin.firestore();
      const userRef = firestore.collection("users").doc(lineUserId);

      await userRef.set({
        displayName: lineUserProfile.displayName,
        pictureUrl: lineUserProfile.pictureUrl || null,
        provider: "line",
        lastLoginAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      console.log("✅ LINE認証: Firestoreユーザー情報保存完了");
    } catch (error) {
      console.warn("⚠️ LINE認証: Firestoreユーザー情報保存失敗", error);
      // Firestoreの保存が失敗してもカスタムトークン生成は続行
    }

    // 3. Firebase カスタムトークンを生成
    try {
      // ユニークなFirebase UIDを生成（LINE User IDベース）
      const firebaseUid = `line_${lineUserId}`;

      // カスタムトークンを生成（サービスアカウント指定）
      const customToken = await admin.auth().createCustomToken(firebaseUid, {
        provider: "line",
        lineUserId: lineUserId,
        displayName: lineUserProfile.displayName,
        pictureUrl: lineUserProfile.pictureUrl || null,
      });

      console.log("✅ LINE認証: Firebaseカスタムトークン生成成功");

      return {
        success: true,
        customToken: customToken,
        uid: firebaseUid,
        lineUser: lineUserProfile,
      };
    } catch (error) {
      console.error("❌ LINE認証: Firebaseカスタムトークン発行エラー", error);
      throw new HttpsError("internal", "Failed to create custom token");
    }
  }
);

// 市町村データを取得する関数
export const getCitiesByPrefecture = functions.https.onCall(
  async (request: CallableRequest<{prefecture: string}>) => {
    try {
      const {prefecture} = request.data;

      if (!prefecture) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "都道府県が指定されていません"
        );
      }

      const query = `
      SELECT DISTINCT city, city_kana, city_en
      FROM cities_master 
      WHERE prefecture = $1 AND is_active = true
      ORDER BY city
    `;

      const result = await pool.query(query, [prefecture]);

      return {
        cities: result.rows,
      };
    } catch (error) {
      console.error("市町村取得エラー:", error);
      throw new functions.https.HttpsError(
        "internal",
        "市町村データの取得に失敗しました"
      );
    }
  }
);

// ユーザーブロック機能
export const blockUser = onCall(
  async (request: CallableRequest<{blockedUserId: string}>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {blockedUserId} = request.data;

    console.log(
      "🔍 ユーザーブロック:",
      `firebaseUid=${firebaseUid}, blockedUserId=${blockedUserId}`
    );

    try {
      // 自分自身をブロックできない
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      if (userUuid === blockedUserId) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "自分自身をブロックすることはできません"
        );
      }

      // ブロック対象ユーザーが存在するかチェック
      const targetUserResult = await pool.query(
        "SELECT id FROM users WHERE id = $1",
        [blockedUserId]
      );

      if (targetUserResult.rows.length === 0) {
        throw new functions.https.HttpsError(
          "not-found",
          "ブロック対象のユーザーが見つかりません"
        );
      }

      // ブロック実行（重複は無視）
      // blocker_idはユーザーUUID、blocked_idもユーザーUUIDで統一
      const result = await pool.query(
        `INSERT INTO user_blocks (blocker_id, blocked_id) 
         VALUES ($1, $2) 
         ON CONFLICT (blocker_id, blocked_id) DO NOTHING 
         RETURNING id`,
        [userUuid, blockedUserId]
      );

      // 既存のマッチを無効化
      await pool.query(
        `UPDATE matches 
         SET status = 'blocked', updated_at = CURRENT_TIMESTAMP
         WHERE ((user1_id = $1 AND user2_id = $2) OR 
                (user1_id = $2 AND user2_id = $1))
         AND status = 'active'`,
        [userUuid, blockedUserId]
      );

      console.log("✅ ユーザーブロック成功:", result.rows);
      return {success: true, isNewBlock: result.rows.length > 0};
    } catch (err: unknown) {
      const error = err as Error;
      console.error("❌ ユーザーブロック失敗:", error);
      throw new functions.https.HttpsError(
        "internal",
        `ブロックに失敗しました: ${error.message}`
      );
    }
  }
);

// ユーザーブロック解除機能
export const unblockUser = onCall(
  async (request: CallableRequest<{blockedUserId: string}>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {blockedUserId} = request.data;

    console.log(
      "🔍 ユーザーブロック解除:",
      `firebaseUid=${firebaseUid}, blockedUserId=${blockedUserId}`
    );

    try {
      // ユーザーUUIDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      const result = await pool.query(
        `DELETE FROM user_blocks 
         WHERE blocker_id = $1 AND blocked_id = $2 
         RETURNING id`,
        [userUuid, blockedUserId]
      );

      console.log("✅ ユーザーブロック解除成功:", result.rows);
      return {success: true, wasBlocked: result.rows.length > 0};
    } catch (err: unknown) {
      const error = err as Error;
      console.error("❌ ユーザーブロック解除失敗:", error);
      throw new functions.https.HttpsError(
        "internal",
        `ブロック解除に失敗しました: ${error.message}`
      );
    }
  }
);

// ブロック状態確認機能
export const getBlockStatus = onCall(
  async (request: CallableRequest<{targetUserId: string}>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {targetUserId} = request.data;

    try {
      // ユーザーUUIDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      // 自分が相手をブロックしているかチェック
      const blockingResult = await pool.query(
        `SELECT id FROM user_blocks 
         WHERE blocker_id = $1 AND blocked_id = $2`,
        [userUuid, targetUserId]
      );

      // 相手が自分をブロックしているかチェック
      const blockedResult = await pool.query(
        `SELECT id FROM user_blocks 
         WHERE blocked_id = $1 AND blocker_id = $2`,
        [userUuid, targetUserId]
      );

      return {
        isBlocking: blockingResult.rows.length > 0,
        isBlocked: blockedResult.rows.length > 0,
      };
    } catch (err: unknown) {
      const error = err as Error;
      console.error("❌ ブロック状態確認失敗:", error);
      throw new functions.https.HttpsError(
        "internal",
        `ブロック状態確認に失敗しました: ${error.message}`
      );
    }
  }
);

// ブロックリスト取得機能
export const getBlockedUsers = onCall(
  async (request: CallableRequest<unknown>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;

    try {
      // ユーザーUUIDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      const result = await pool.query(
        `SELECT 
           ub.blocked_id,
           ub.created_at,
           u.name,
           u.age,
           u.gender,
           u.image_url
         FROM user_blocks ub
         LEFT JOIN users u ON ub.blocked_id = u.id
         WHERE ub.blocker_id = $1::uuid
         ORDER BY ub.created_at DESC`,
        [userUuid]
      );

      return {
        blockedUsers: result.rows,
      };
    } catch (err: unknown) {
      const error = err as Error;
      console.error("❌ ブロックリスト取得失敗:", error);
      throw new functions.https.HttpsError(
        "internal",
        `ブロックリスト取得に失敗しました: ${error.message}`
      );
    }
  }
);

// 身分証明書認証: 画像アップロード
export const uploadIdentityDocument = onCall(
  async (request: CallableRequest<{
    documentType: string;
    frontImageBase64: string;
    backImageBase64?: string;
  }>) => {
    console.log("🆔 身分証明書アップロード: 開始");
    console.log("🆔 受信データ:", {
      documentType: request.data.documentType,
      frontImageBase64Length: request.data.frontImageBase64?.length || 0,
      frontImageBase64Preview: request.data.frontImageBase64?.substring(0, 50) + "...",
      hasBackImage: !!request.data.backImageBase64,
      auth: !!request.auth,
      uid: request.auth?.uid,
    });

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {documentType, frontImageBase64, backImageBase64} = request.data;

    // バリデーション
    if (!documentType || !frontImageBase64) {
      throw new HttpsError("invalid-argument", "必要な情報が不足しています");
    }

    const validDocumentTypes = [
      "drivers_license",
      "passport",
      "mynumber_card",
      "residence_card",
    ];
    if (!validDocumentTypes.includes(documentType)) {
      throw new HttpsError("invalid-argument", "無効な身分証明書の種類です");
    }

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }

      // 既存の認証申請をチェック
      const existingVerification = await pool.query(
        `SELECT id, verification_status FROM identity_verifications
         WHERE user_id = $1 AND verification_status IN ('pending', 'approved')
         ORDER BY created_at DESC LIMIT 1`,
        [userUuid]
      );

      if (existingVerification.rows.length > 0) {
        const status = existingVerification.rows[0].verification_status;
        if (status === "approved") {
          throw new HttpsError("already-exists", "既に身分証明書認証が完了しています");
        }
        if (status === "pending") {
          throw new HttpsError("already-exists", "既に認証申請が審査中です");
        }
      }

      // 画像をCloud Storageにアップロード
      let bucket;
      try {
        // まずデフォルトバケットを試す
        bucket = admin.storage().bucket();
        console.log(`デフォルトバケットを使用: ${bucket.name}`);
      } catch (error) {
        console.log("デフォルトバケット取得エラー:", error);
        throw new HttpsError("internal", "ストレージの初期化に失敗しました");
      }

      const timestamp = Date.now();

      // 表面画像のアップロード
      const frontImageBuffer = Buffer.from(frontImageBase64, "base64");
      const frontImagePath =
        `identity-documents/${userUuid}/${timestamp}_front.jpg`;
      const frontImageFile = bucket.file(frontImagePath);

      await frontImageFile.save(frontImageBuffer, {
        metadata: {
          contentType: "image/jpeg",
          metadata: {
            userId: userUuid,
            documentType: documentType,
            uploadedAt: new Date().toISOString(),
          },
        },
      });

      const frontImageUrl = `gs://${bucket.name}/${frontImagePath}`;
      console.log(`📸 表面画像アップロード完了: ${frontImageUrl}`);

      // 裏面画像のアップロード（必要な場合）
      let backImageUrl = null;
      if (backImageBase64) {
        const backImageBuffer = Buffer.from(backImageBase64, "base64");
        const backImagePath =
          `identity-documents/${userUuid}/${timestamp}_back.jpg`;
        const backImageFile = bucket.file(backImagePath);

        await backImageFile.save(backImageBuffer, {
          metadata: {
            contentType: "image/jpeg",
            metadata: {
              userId: userUuid,
              documentType: documentType,
              uploadedAt: new Date().toISOString(),
            },
          },
        });

        backImageUrl = `gs://${bucket.name}/${backImagePath}`;
        console.log(`📸 裏面画像アップロード完了: ${backImageUrl}`);
      }

      // データベースに認証申請を保存
      const insertResult = await pool.query(
        `INSERT INTO identity_verifications 
         (user_id, document_type, front_image_url, back_image_url, 
          verification_status)
         VALUES ($1, $2, $3, $4, 'pending')
         RETURNING id, submitted_at`,
        [userUuid, documentType, frontImageUrl, backImageUrl]
      );

      const verificationId = insertResult.rows[0].id;
      console.log(`✅ 身分証明書認証申請作成: ${verificationId}`);

      // Base64画像をデコードしてバイト数を取得
      const imageBuffer = Buffer.from(frontImageBase64, "base64");
      const imageSizeBytes = imageBuffer.length;

      // OCR処理を実行
      try {
        console.log("🔍 OCR処理を開始");

        console.log(`📸 画像サイズ: ${imageSizeBytes} bytes`);

        // 改良されたOCR処理（身分証明書の検証）
        const ocrResult = await performAdvancedOCR(
          frontImageBase64,
          documentType,
          imageSizeBytes
        );

        if (ocrResult.requiresManualReview) {
          // 期限確認不可のため審査中
          await pool.query(
            `UPDATE identity_verifications 
             SET 
               extracted_name = $1,
               extracted_birth_date = $2,
               extracted_age = $3,
               verification_method = $4,
               admin_notes = $5
             WHERE id = $6`,
            [
              ocrResult.extractedName || "要確認",
              ocrResult.extractedBirthDate,
              ocrResult.extractedAge,
              "manual", // 手動審査
              `OCR結果: ${ocrResult.reason}, 信頼度: ${ocrResult.confidence}%, ` +
              `画像サイズ: ${imageSizeBytes} bytes, 期限確認: 不可`,
              verificationId,
            ]
          );

          console.log(
            `👁️ 期限確認不可のため手動審査: ${verificationId} ` +
            `(信頼度: ${ocrResult.confidence}%)`
          );

          return {
            success: true,
            verificationId: verificationId,
            message: "身分証明書を受け付けました。有効期限の確認のため審査をお待ちください。",
            autoApproved: false,
          };
        } else if (ocrResult.isValidDocument && ocrResult.confidence >= 80) {
          // 自動承認（身分証明書として認識されれば年齢に関係なく承認）
          await pool.query(
            `UPDATE identity_verifications 
             SET 
               extracted_name = $1,
               extracted_birth_date = $2,
               extracted_age = $3,
               verification_method = $4,
               verification_status = $5,
               reviewed_at = NOW(),
               admin_notes = $6
             WHERE id = $7`,
            [
              ocrResult.extractedName || "身分証明書認証済み",
              ocrResult.extractedBirthDate,
              ocrResult.extractedAge,
              "ocr", // OCR自動認証
              "approved", // 自動承認
              `OCR結果: 身分証明書として認識, 信頼度: ${ocrResult.confidence}%, ` +
              `検出キーワード: ${ocrResult.detectedKeywords.join(", ")}, ` +
              `画像サイズ: ${imageSizeBytes} bytes`,
              verificationId,
            ]
          );

          // usersテーブルも更新
          await pool.query(
            `UPDATE users 
             SET 
               id_verified = true,
               id_verification_date = NOW()
             WHERE id = $1`,
            [userUuid]
          );

          console.log(
            `✅ 自動認証完了: ${verificationId} ` +
            `(信頼度: ${ocrResult.confidence}%)`
          );

          return {
            success: true,
            verificationId: verificationId,
            message: "身分証明書認証が完了しました。",
            autoApproved: true,
          };
        } else if (ocrResult.confidence < 20 ||
                   ocrResult.detectedKeywords.length === 0) {
          // 信頼度が極端に低い、またはキーワードが全く検出されない場合は自動却下
          let rejectionReason = "身分証明書として認識できません";
          let adminNotes = "OCR結果: 身分証明書として認識できません, " +
               `信頼度: ${ocrResult.confidence}%, ` +
               `検出キーワード: ${ocrResult.detectedKeywords.length > 0 ?
                 ocrResult.detectedKeywords.join(", ") : "なし"}, ` +
               `画像サイズ: ${imageSizeBytes} bytes, ` +
               "却下理由: 身分証明書の文字が読み取れないか、身分証明書以外の画像です";

          // 期限切れの場合は特別な処理
          if (ocrResult.reason.includes("期限切れ")) {
            rejectionReason = "有効期限切れ";
            adminNotes = "OCR結果: " + ocrResult.reason + ", " +
               `信頼度: ${ocrResult.confidence}%, ` +
               `検出キーワード: ${ocrResult.detectedKeywords.join(", ")}, ` +
               `画像サイズ: ${imageSizeBytes} bytes, ` +
               "却下理由: 身分証明書の有効期限が切れています";
          }

          await pool.query(
            `UPDATE identity_verifications 
             SET 
               extracted_name = $1,
               extracted_birth_date = $2,
               extracted_age = $3,
               verification_method = $4,
               verification_status = $5,
               reviewed_at = NOW(),
               rejection_reason = $6,
               admin_notes = $7
             WHERE id = $8`,
            [
              ocrResult.extractedName || "認識不可",
              ocrResult.extractedBirthDate,
              ocrResult.extractedAge,
              "ocr", // OCR自動認証
              "rejected", // 自動却下
              rejectionReason,
              adminNotes,
              verificationId,
            ]
          );

          console.log(
            `❌ 自動却下: ${verificationId} ` +
             `(信頼度: ${ocrResult.confidence}%, ` +
             `キーワード: ${ocrResult.detectedKeywords.length}個)`
          );

          // 期限切れの場合は特別なメッセージ
          let userMessage = "申し訳ございませんが、身分証明書として認識できませんでした。" +
               "別の画像で再度お試しください。";

          if (ocrResult.reason.includes("期限切れ")) {
            userMessage = "申し訳ございませんが、アップロードされた身分証明書の有効期限が切れています。" +
               "有効期限内の身分証明書で再度お試しください。";
          }

          return {
            success: true,
            verificationId: verificationId,
            message: userMessage,
            autoApproved: false,
            autoRejected: true,
          };
        } else {
          // 手動審査に回す
          await pool.query(
            `UPDATE identity_verifications 
             SET 
               extracted_name = $1,
               extracted_birth_date = $2,
               extracted_age = $3,
               verification_method = $4,
               admin_notes = $5
             WHERE id = $6`,
            [
              ocrResult.extractedName || "要確認",
              ocrResult.extractedBirthDate,
              ocrResult.extractedAge,
              "manual", // 手動審査
              `OCR結果: ${ocrResult.reason}, 信頼度: ${ocrResult.confidence}%, ` +
              `画像サイズ: ${imageSizeBytes} bytes`,
              verificationId,
            ]
          );

          console.log(
            `👁️ 手動審査に回しました: ${verificationId} ` +
            `(理由: ${ocrResult.reason})`
          );

          return {
            success: true,
            verificationId: verificationId,
            message: "身分証明書を受け付けました。審査をお待ちください。",
            autoApproved: false,
          };
        }
      } catch (ocrError) {
        console.log("⚠️ OCR処理エラー:", ocrError);

        // エラーの詳細を分析
        let errorType = "unknown";
        let errorDetails = "";

        if (ocrError instanceof Error) {
          if (ocrError.message.includes("INVALID_IMAGE") ||
              ocrError.message.includes("image format")) {
            errorType = "invalid_format";
            errorDetails = "画像形式が無効です。JPEG、PNG形式の画像をご利用ください。";
          } else if (ocrError.message.includes("PERMISSION_DENIED")) {
            errorType = "api_error";
            errorDetails = "OCR処理でAPIエラーが発生しました。";
          } else if (ocrError.message.includes("QUOTA_EXCEEDED")) {
            errorType = "quota_exceeded";
            errorDetails = "OCR処理の制限に達しました。しばらく待ってから再試行してください。";
          } else {
            errorType = "processing_error";
            errorDetails = "画像の処理中にエラーが発生しました。別の画像で再試行してください。";
          }
        }

        // エラーの場合は手動審査に回す
        await pool.query(
          `UPDATE identity_verifications 
           SET 
             extracted_name = $1,
             extracted_birth_date = $2,
             extracted_age = $3,
             verification_method = $4,
             admin_notes = $5
           WHERE id = $6`,
          [
            "エラー", // エラー発生
            null,
            null,
            "manual", // 手動審査
            `OCRエラー: ${errorType}, 詳細: ${errorDetails}, ` +
            `画像サイズ: ${imageSizeBytes} bytes, ` +
            `エラーメッセージ: ${(ocrError as Error).message || "Unknown error"}`,
            verificationId,
          ]
        );

        return {
          success: true,
          verificationId: verificationId,
          message: "画像の処理でエラーが発生しました。別の画像で再試行してください。",
          autoApproved: false,
          errorType: errorType,
        };
      }

      // TODO: 管理者への通知を実装

      return {
        success: true,
        verificationId: verificationId,
        message: "身分証明書を受け付けました。審査をお待ちください。",
      };
    } catch (error) {
      console.log("❌ 身分証明書アップロード失敗:", error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError("internal", "アップロードに失敗しました");
    }
  }
);

// 身分証明書認証状態取得
export const getIdentityVerificationStatus = onCall(
  async (request: CallableRequest<Record<string, never>>) => {
    console.log("🆔 身分証明書認証状態取得: 開始");

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }

      // 最新の認証状態を取得
      const result = await pool.query(
        `SELECT 
           iv.id,
           iv.document_type,
           iv.verification_status,
           iv.submitted_at,
           iv.reviewed_at,
           iv.rejection_reason,
           iv.expires_at,
           iv.admin_notes,
           u.id_verified,
           u.id_verification_date
         FROM identity_verifications iv
         JOIN users u ON iv.user_id = u.id
         WHERE iv.user_id = $1
         ORDER BY iv.created_at DESC
         LIMIT 1`,
        [userUuid]
      );

      if (result.rows.length === 0) {
        return {
          hasSubmitted: false,
          isVerified: false,
          status: null,
        };
      }

      const verification = result.rows[0];

      return {
        hasSubmitted: true,
        isVerified: verification.id_verified,
        status: verification.verification_status,
        documentType: verification.document_type,
        submittedAt: verification.submitted_at,
        reviewedAt: verification.reviewed_at,
        rejectionReason: verification.rejection_reason,
        expiresAt: verification.expires_at,
        verificationDate: verification.id_verification_date,
        adminNotes: verification.admin_notes,
      };
    } catch (error) {
      console.log("❌ 身分証明書認証状態取得失敗:", error);
      throw new HttpsError("internal", "認証状態の取得に失敗しました");
    }
  }
);

// 管理者用: 認証待ちの身分証明書一覧取得
export const getPendingIdentityVerifications = onCall(
  async (request: CallableRequest<{
    limit?: number;
    offset?: number;
  }>) => {
    console.log("🆔 認証待ち身分証明書一覧取得: 開始");

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    // TODO: 管理者権限チェックを実装
    const {limit = 50, offset = 0} = request.data;

    try {
      const result = await pool.query(
        `SELECT * FROM pending_identity_verifications
         LIMIT $1 OFFSET $2`,
        [limit, offset]
      );

      return {
        verifications: result.rows,
        total: result.rows.length,
      };
    } catch (error) {
      console.log("❌ 認証待ち一覧取得失敗:", error);
      throw new HttpsError("internal", "認証待ち一覧の取得に失敗しました");
    }
  }
);

// 管理者用: 身分証明書認証の承認/却下
export const reviewIdentityVerification = onCall(
  async (request: CallableRequest<{
    verificationId: string;
    action: "approve" | "reject";
    rejectionReason?: string;
    adminNotes?: string;
    extractedName?: string;
    extractedBirthDate?: string;
  }>) => {
    console.log("🆔 身分証明書認証審査: 開始");

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {
      verificationId,
      action,
      rejectionReason,
      adminNotes,
      extractedName,
      extractedBirthDate,
    } = request.data;

    // バリデーション
    if (!verificationId || !action) {
      throw new HttpsError("invalid-argument", "必要な情報が不足しています");
    }

    if (!["approve", "reject"].includes(action)) {
      throw new HttpsError("invalid-argument", "無効なアクションです");
    }

    if (action === "reject" && !rejectionReason) {
      throw new HttpsError("invalid-argument", "却下理由が必要です");
    }

    try {
      // 管理者のUUID IDを取得
      const adminUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!adminUuid) {
        throw new HttpsError("not-found", "管理者が見つかりません");
      }

      // TODO: 管理者権限チェックを実装

      // 年齢計算（承認の場合）
      let extractedAge = null;
      if (action === "approve" && extractedBirthDate) {
        const birthDate = new Date(extractedBirthDate);
        const today = new Date();
        extractedAge = today.getFullYear() - birthDate.getFullYear();
        const monthDiff = today.getMonth() - birthDate.getMonth();
        if (monthDiff < 0 ||
            (monthDiff === 0 && today.getDate() < birthDate.getDate())) {
          extractedAge--;
        }

        // 18歳未満チェック
        if (extractedAge < 18) {
          throw new HttpsError("failed-precondition", "18歳未満のため認証できません");
        }
      }

      // 認証状態を更新
      const newStatus = action === "approve" ? "approved" : "rejected";
      const expiresAt = action === "approve" ?
        new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString() :
        null;

      await pool.query(
        `UPDATE identity_verifications 
         SET 
           verification_status = $1,
           reviewed_by = $2,
           reviewed_at = CURRENT_TIMESTAMP,
           rejection_reason = $3,
           admin_notes = $4,
           extracted_name = $5,
           extracted_birth_date = $6,
           extracted_age = $7,
           expires_at = $8
         WHERE id = $9`,
        [
          newStatus,
          adminUuid,
          rejectionReason,
          adminNotes,
          extractedName,
          extractedBirthDate,
          extractedAge,
          expiresAt,
          verificationId,
        ]
      );

      console.log(
        `✅ 身分証明書認証審査完了: ${verificationId} - ${action}`
      );

      // TODO: ユーザーへの通知を実装

      return {
        success: true,
        action: action,
        message: action === "approve" ? "認証を承認しました" : "認証を却下しました",
      };
    } catch (error) {
      console.log("❌ 身分証明書認証審査失敗:", error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError("internal", "認証審査に失敗しました");
    }
  }
);

// ユーザーのお気に入りレストランを取得
export const getUserFavoriteRestaurants = onCall(
  async (request: CallableRequest<{userId?: string; limit?: number}>) => {
    console.log("🍽️ ユーザーのお気に入りレストラン取得: 開始");

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    // request.dataがnullの場合は空オブジェクトを使用
    const data = request.data || {};
    const {userId, limit = 10} = data;

    try {
      let targetUserId: string;

      if (userId) {
        // userIdが指定されている場合（他人のプロフィール表示時など）
        targetUserId = userId;
      } else {
        // userIdが指定されていない場合は認証されたユーザーのUUIDを取得
        const firebaseUid = request.auth.uid;
        const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
        if (!userUuid) {
          throw new HttpsError("not-found", "ユーザーが見つかりません");
        }
        targetUserId = userUuid;
      }

      console.log(`🔍 対象ユーザーID: ${targetUserId}`);

      // ユーザーがいいねしたレストランを取得
      const result = await pool.query(`
        SELECT 
          r.id,
          r.name,
          r.category,
          r.address,
          r.image_url,
          r.prefecture,
          r.nearest_station,
          r.price_range,
          r.low_price,
          r.high_price,
          r.hotpepper_url,
          r.operating_hours,
          rl.liked_at::text as liked_at
        FROM restaurants_likes rl
        JOIN restaurants r ON rl.restaurant_id = r.id
        WHERE rl.user_id = $1
        ORDER BY rl.liked_at DESC
        LIMIT $2
      `, [targetUserId, limit]);

      console.log(
        `✅ お気に入りレストラン取得成功: ${result.rows.length}件`
      );

      return {
        success: true,
        restaurants: result.rows,
        totalCount: result.rows.length,
      };
    } catch (err) {
      console.error("❌ お気に入りレストラン取得失敗:", err);
      throw new HttpsError(
        "internal",
        "お気に入りレストランの取得に失敗しました"
      );
    }
  }
);

// 同じレストランが好きなユーザーを取得（10人に満たない場合は同じカテゴリで補完）
export const getUsersWithSimilarRestaurantLikes = onCall(
  async (request: CallableRequest<{limit?: number}>) => {
    console.log("🍽️ 同じレストランが好きなユーザー取得（改良版）: 開始");

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {limit = 10} = request.data;

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      console.log(`🔍 対象ユーザー: ${userUuid}`);

      // Step 1: 自分がいいねしたレストランと同じレストランをいいねした他のユーザーを取得
      const sameLikesResult = await pool.query(`
        WITH my_liked_restaurants AS (
          SELECT restaurant_id 
          FROM restaurants_likes 
          WHERE user_id = $1
        ),
        similar_users AS (
          SELECT 
            rl.user_id,
            u.name,
            u.age,
            u.gender,
            u.image_url,
            u.occupation,
            u.prefecture,
            COUNT(DISTINCT rl.restaurant_id) as common_restaurants_count,
            ARRAY_AGG(DISTINCT r.name) as common_restaurant_names,
            'same_restaurant' as recommendation_type
          FROM restaurants_likes rl
          JOIN users u ON rl.user_id = u.id
          JOIN restaurants r ON rl.restaurant_id = r.id
          WHERE rl.restaurant_id IN (
            SELECT restaurant_id FROM my_liked_restaurants
          )
          AND rl.user_id != $1  -- 自分は除外
          AND u.name IS NOT NULL  -- 名前が設定されているユーザーのみ
          GROUP BY rl.user_id, u.name, u.age, u.gender, u.image_url, 
                   u.occupation, u.prefecture
          HAVING COUNT(DISTINCT rl.restaurant_id) >= 1
          ORDER BY COUNT(DISTINCT rl.restaurant_id) DESC, RANDOM()
          LIMIT $2
        )
        SELECT * FROM similar_users
      `, [userUuid, limit]);

      console.log(`✅ 同じレストランが好きなユーザー: ${sameLikesResult.rows.length}件`);

      let finalUsers = sameLikesResult.rows;

      // Step 2: 10人に満たない場合、同じカテゴリが好きなユーザーで補完
      if (finalUsers.length < limit) {
        const neededCount = limit - finalUsers.length;
        console.log(`🔄 ${neededCount}人分を同じカテゴリユーザーで補完開始`);

        // 既に結果に含まれているユーザーIDを取得
        const existingUserIds = finalUsers.map((user) => user.user_id);
        const existingUserIdsParams = existingUserIds.map((_, i) => `$${i + 3}`).join(", ");
        const existingUserIdsFilter = existingUserIds.length > 0 ?
          `AND rl.user_id NOT IN (${existingUserIdsParams})` :
          "";

        const sameCategoryResult = await pool.query(`
          WITH my_liked_categories AS (
            SELECT DISTINCT r.category 
            FROM restaurants_likes rl
            JOIN restaurants r ON rl.restaurant_id = r.id
            WHERE rl.user_id = $1
          ),
          category_similar_users AS (
            SELECT 
              rl.user_id,
              u.name,
              u.age,
              u.gender,
              u.image_url,
              u.occupation,
              u.prefecture,
              COUNT(DISTINCT r.category) as common_categories_count,
              ARRAY_AGG(DISTINCT r.category) as common_categories,
              'same_category' as recommendation_type
            FROM restaurants_likes rl
            JOIN users u ON rl.user_id = u.id
            JOIN restaurants r ON rl.restaurant_id = r.id
            WHERE r.category IN (
              SELECT category FROM my_liked_categories
            )
            AND rl.user_id != $1  -- 自分は除外
            AND u.name IS NOT NULL  -- 名前が設定されているユーザーのみ
            ${existingUserIdsFilter}  -- 既に結果に含まれているユーザーを除外
            GROUP BY rl.user_id, u.name, u.age, u.gender, u.image_url, 
                     u.occupation, u.prefecture
            HAVING COUNT(DISTINCT r.category) >= 1
            ORDER BY COUNT(DISTINCT r.category) DESC, RANDOM()
            LIMIT $2
          )
          SELECT * FROM category_similar_users
        `, [userUuid, neededCount, ...existingUserIds]);

        console.log(`✅ 同じカテゴリが好きなユーザー: ${sameCategoryResult.rows.length}件`);

        // 結果を統合
        finalUsers = [...finalUsers, ...sameCategoryResult.rows];
      }

      console.log(
        `✅ 同じレストラン・カテゴリが好きなユーザー取得成功: ${finalUsers.length}件`
      );

      // ログで推薦理由を出力
      finalUsers.forEach((user, index) => {
        if (user.recommendation_type === "same_restaurant") {
          console.log(
            `👤 ${index + 1}. ${user.name}: ${user.common_restaurants_count}個の共通レストラン`
          );
        } else {
          console.log(
            `👤 ${index + 1}. ${user.name}: ${user.common_categories_count}個の共通カテゴリ（補完）`
          );
        }
      });

      return {
        users: finalUsers,
        totalCount: finalUsers.length,
        breakdown: {
          sameRestaurant: finalUsers.filter((u) => u.recommendation_type === "same_restaurant").length,
          sameCategory: finalUsers.filter((u) => u.recommendation_type === "same_category").length,
        },
      };
    } catch (err) {
      console.error("❌ 同じレストランが好きなユーザー取得失敗:", err);
      throw new HttpsError(
        "internal",
        "同じレストランが好きなユーザーの取得に失敗しました"
      );
    }
  }
);

// 「このレストランを好きな人は、こんなレストランも好きです」推薦機能
export const getRestaurantsBasedOnSimilarTastes = onCall(
  async (request: CallableRequest<{limit?: number}>) => {
    console.log("🍽️ アイテムベース協調フィルタリング: 開始");

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {limit = 20} = request.data;

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      console.log(`🔍 対象ユーザー: ${userUuid}`);

      // アイテムベース協調フィルタリング
      const result = await pool.query(`
        WITH user_liked_restaurants AS (
          -- 自分がいいねしたレストラン
          SELECT restaurant_id FROM restaurants_likes WHERE user_id = $1
        ),
        similar_restaurants AS (
          SELECT 
            r2.id as restaurant_id,
            r2.name,
            r2.category,
            r2.prefecture,
            r2.nearest_station,
            r2.price_range,
            r2.low_price,
            r2.high_price,
            r2.image_url,
            r2.address,
            r2.hotpepper_url,
            r2.operating_hours,
            COUNT(DISTINCT rl1.user_id) as common_likers_count,
            ARRAY_AGG(DISTINCT u.name) as common_liker_names,
            -- 類似度計算（Jaccard係数）
            COUNT(DISTINCT rl1.user_id)::float / (
              -- 分母：A∪B（レストラン1またはレストラン2をいいねしたユーザー数）
              SELECT COUNT(DISTINCT user_id) 
              FROM restaurants_likes 
              WHERE restaurant_id IN (r1.restaurant_id, r2.id)
            ) as jaccard_similarity,
            -- 共通いいねユーザー数の比率
            COUNT(DISTINCT rl1.user_id)::float / (
              SELECT COUNT(DISTINCT user_id) 
              FROM restaurants_likes 
              WHERE restaurant_id = r1.restaurant_id
            ) as recommendation_strength
          FROM user_liked_restaurants r1
          JOIN restaurants_likes rl1 ON r1.restaurant_id = rl1.restaurant_id
          JOIN restaurants_likes rl2 ON rl1.user_id = rl2.user_id
          JOIN restaurants r2 ON rl2.restaurant_id = r2.id
          JOIN users u ON rl1.user_id = u.id
          WHERE rl2.restaurant_id NOT IN (
            SELECT restaurant_id FROM user_liked_restaurants
          )
          AND u.name IS NOT NULL  -- 名前が設定されているユーザーのみ
          GROUP BY r2.id, r2.name, r2.category, r2.prefecture, r2.nearest_station, 
                   r2.price_range, r2.low_price, r2.high_price, r2.image_url, 
                   r2.address, r2.hotpepper_url, r2.operating_hours, r1.restaurant_id
          HAVING COUNT(DISTINCT rl1.user_id) >= 2  -- 最低2人の共通いいね
          ORDER BY 
            jaccard_similarity DESC,
            common_likers_count DESC,
            recommendation_strength DESC
        )
        SELECT DISTINCT
          restaurant_id,
          name,
          category,
          prefecture,
          nearest_station,
          price_range,
          low_price,
          high_price,
          image_url,
          address,
          hotpepper_url,
          operating_hours,
          AVG(jaccard_similarity) as avg_similarity,
          MAX(common_likers_count) as max_common_likers,
          AVG(recommendation_strength) as avg_recommendation_strength
        FROM similar_restaurants
        GROUP BY restaurant_id, name, category, prefecture, nearest_station, 
                 price_range, low_price, high_price, image_url, address, 
                 hotpepper_url, operating_hours
        ORDER BY avg_similarity DESC, max_common_likers DESC
        LIMIT $2
      `, [userUuid, limit]);

      console.log(
        `✅ アイテムベース協調フィルタリング完了: ${result.rows.length}件`
      );

      // ログで推薦理由を出力
      result.rows.forEach((restaurant, index) => {
        console.log(
          `🍽️ ${index + 1}. ${restaurant.name}（${restaurant.category}）: ` +
          `類似度=${restaurant.avg_similarity?.toFixed(3)}, ` +
          `共通いいね=${restaurant.max_common_likers}人`
        );
      });

      return {
        restaurants: result.rows,
        totalCount: result.rows.length,
        algorithm: "item_based_collaborative_filtering",
        description: "このレストランを好きな人は、こんなレストランも好きです",
      };
    } catch (err) {
      console.error("❌ アイテムベース協調フィルタリング失敗:", err);
      throw new HttpsError(
        "internal",
        "レストラン推薦の取得に失敗しました"
      );
    }
  }
);

// デート成功率ベース推薦機能
export const getRestaurantsBasedOnDateSuccess = onCall(
  async (request: CallableRequest<{limit?: number}>) => {
    console.log("📅 デート成功率ベース推薦: 開始");

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {limit = 20} = request.data;

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      console.log(`🔍 対象ユーザー: ${userUuid}`);

      // デート成功率ベース推薦
      const result = await pool.query(`
        WITH user_preferences AS (
          -- ユーザーの好みカテゴリを取得
          SELECT DISTINCT r.category 
          FROM restaurants_likes rl
          JOIN restaurants r ON rl.restaurant_id = r.id
          WHERE rl.user_id = $1
        ),
        restaurant_success_rates AS (
          SELECT 
            r.id as restaurant_id,
            r.name,
            r.category,
            r.prefecture,
            r.nearest_station,
            r.price_range,
            r.low_price,
            r.high_price,
            r.image_url,
            r.address,
            r.hotpepper_url,
            r.operating_hours,
            COUNT(CASE WHEN dr.status = 'completed' THEN 1 END) as successful_dates,
            COUNT(CASE WHEN dr.status = 'cancelled' THEN 1 END) as cancelled_dates,
            COUNT(CASE WHEN dr.status = 'rejected' THEN 1 END) as rejected_dates,
            COUNT(dr.id) as total_dates,
            -- 成功率計算
            CASE 
              WHEN COUNT(dr.id) = 0 THEN 0.5  -- データがない場合は中性的な値
              ELSE COUNT(CASE WHEN dr.status = 'completed' THEN 1 END)::float / COUNT(dr.id)
            END as success_rate,
            -- 好みカテゴリマッチング
            CASE 
              WHEN r.category IN (SELECT category FROM user_preferences) THEN 1.0
              ELSE 0.3
            END as category_preference_score
          FROM restaurants r
          LEFT JOIN date_requests dr ON r.id = dr.restaurant_id
          WHERE r.id NOT IN (
            SELECT restaurant_id FROM restaurants_likes WHERE user_id = $1
          )
          GROUP BY r.id, r.name, r.category, r.prefecture, r.nearest_station, 
                   r.price_range, r.low_price, r.high_price, r.image_url, 
                   r.address, r.hotpepper_url, r.operating_hours
          HAVING COUNT(dr.id) >= 2  -- 最低2回のデート実績
        ),
        weighted_recommendations AS (
          SELECT 
            *,
            -- 複合スコア計算
            (
              success_rate * 0.6 +  -- 成功率の重み
              category_preference_score * 0.3 +  -- 好みカテゴリの重み
              LEAST(total_dates::float / 50, 1.0) * 0.1  -- 実績数の重み（最大50でキャップ）
            ) as recommendation_score
          FROM restaurant_success_rates
        )
        SELECT 
          restaurant_id,
          name,
          category,
          prefecture,
          nearest_station,
          price_range,
          low_price,
          high_price,
          image_url,
          address,
          hotpepper_url,
          operating_hours,
          successful_dates,
          cancelled_dates,
          rejected_dates,
          total_dates,
          success_rate,
          category_preference_score,
          recommendation_score
        FROM weighted_recommendations
        ORDER BY 
          recommendation_score DESC,
          success_rate DESC,
          total_dates DESC
        LIMIT $2
      `, [userUuid, limit]);

      console.log(
        `✅ デート成功率ベース推薦完了: ${result.rows.length}件`
      );

      // ログで推薦理由を出力
      result.rows.forEach((restaurant, index) => {
        console.log(
          `📅 ${index + 1}. ${restaurant.name}（${restaurant.category}）: ` +
          `成功率=${(restaurant.success_rate * 100).toFixed(1)}% ` +
          `(${restaurant.successful_dates}/${restaurant.total_dates}), ` +
          `スコア=${restaurant.recommendation_score?.toFixed(3)}`
        );
      });

      return {
        restaurants: result.rows,
        totalCount: result.rows.length,
        algorithm: "date_success_rate_based",
        description: "デート成功率が高いレストランを推薦",
      };
    } catch (err) {
      console.error("❌ デート成功率ベース推薦失敗:", err);
      throw new HttpsError(
        "internal",
        "デート成功率ベース推薦の取得に失敗しました"
      );
    }
  }
);

// 統合推薦機能（複数アルゴリズムの切り替え機能付き）
export const getRestaurantRecommendations = onCall(
  async (request: CallableRequest<{
    algorithm?: "basic" | "collaborative" | "date_success" | "all";
    limit?: number;
  }>) => {
    console.log("🎯 統合推薦機能: 開始");

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {algorithm = "all", limit = 20} = request.data;

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      console.log(`🔍 対象ユーザー: ${userUuid}, アルゴリズム: ${algorithm}`);

      let result: {
        restaurants: any[];
        totalCount: number;
        algorithm: string;
        description: string;
        breakdown?: any;
      };

      switch (algorithm) {
      case "basic":
        // 基本的な推薦（カテゴリベース）
        result = await getBasicRecommendations(userUuid, limit);
        break;

      case "collaborative":
        // 協調フィルタリング
        result = await getCollaborativeRecommendations(userUuid, limit);
        break;

      case "date_success":
        // デート成功率ベース
        result = await getDateSuccessRecommendations(userUuid, limit);
        break;

      case "all":
      default:
        // 全アルゴリズムの結果を統合
        result = await getAllRecommendations(userUuid, limit);
        break;
      }

      console.log(
        `✅ 統合推薦完了: ${result.restaurants.length}件 (${algorithm})`
      );

      return result;
    } catch (err) {
      console.error("❌ 統合推薦失敗:", err);
      throw new HttpsError(
        "internal",
        "推薦の取得に失敗しました"
      );
    }
  }
);

/**
 * 基本的な推薦（カテゴリベース）
 * @param {string} userUuid - ユーザーのUUID
 * @param {number} limit - 推薦数の上限
 * @return {Promise<any>} 推薦結果
 */
async function getBasicRecommendations(userUuid: string, limit: number): Promise<{restaurants: any[], totalCount: number, algorithm: string, description: string}> {
  const result = await pool.query(`
    WITH user_info AS (
      SELECT prefecture FROM users WHERE id = $1
    ),
    user_liked_categories AS (
      -- ユーザーがいいねしたレストランのカテゴリを取得
      SELECT DISTINCT r.category, COUNT(*) as like_count
      FROM restaurants_likes rl
      JOIN restaurants r ON rl.restaurant_id = r.id
      WHERE rl.user_id = $1
      GROUP BY r.category
      ORDER BY like_count DESC
    ),
    similar_restaurants AS (
      SELECT 
        r.id as restaurant_id,
        r.name,
        r.category,
        r.prefecture,
        r.nearest_station,
        r.price_range,
        r.low_price,
        r.high_price,
        r.image_url,
        r.address,
        r.hotpepper_url,
        r.operating_hours,
        ulc.like_count as category_popularity
      FROM restaurants r
      JOIN user_liked_categories ulc ON r.category = ulc.category
      CROSS JOIN user_info ui
      WHERE r.prefecture = ui.prefecture  -- 同じ都道府県に限定
        AND r.id NOT IN (
          SELECT restaurant_id FROM restaurants_likes WHERE user_id = $1
        )
      ORDER BY ulc.like_count DESC, RANDOM()  -- いいね数が多いカテゴリを優先、同カテゴリ内はランダム
      LIMIT $2
    )
    SELECT 
      restaurant_id,
      name,
      category,
      prefecture,
      nearest_station,
      price_range,
      low_price,
      high_price,
      image_url,
      address,
      hotpepper_url,
      operating_hours,
      category_popularity
    FROM similar_restaurants
  `, [userUuid, limit]);

  // カテゴリ別の内訳を取得
  const categoryBreakdown = await pool.query(`
    SELECT DISTINCT r.category, COUNT(*) as like_count
    FROM restaurants_likes rl
    JOIN restaurants r ON rl.restaurant_id = r.id
    WHERE rl.user_id = $1
    GROUP BY r.category
    ORDER BY like_count DESC
  `, [userUuid]);

  // いいねしたレストランがない場合のフォールバック処理
  if (result.rows.length === 0) {
    console.log("🔍 いいねしたレストランがないため、人気レストランを推薦");
    const fallbackResult = await pool.query(`
      SELECT 
        r.id as restaurant_id,
        r.name,
        r.category,
        r.prefecture,
        r.nearest_station,
        r.price_range,
        r.low_price,
        r.high_price,
        r.image_url,
        r.address,
        r.hotpepper_url,
        r.operating_hours,
        COUNT(rl.user_id) as popularity
      FROM restaurants r
      LEFT JOIN restaurants_likes rl ON r.id = rl.restaurant_id
      WHERE r.prefecture = (SELECT prefecture FROM users WHERE id = $1)
      GROUP BY r.id, r.name, r.category, r.prefecture, r.nearest_station, 
               r.price_range, r.low_price, r.high_price, r.image_url, 
               r.address, r.hotpepper_url, r.operating_hours
      ORDER BY popularity DESC, RANDOM()
      LIMIT $2
    `, [userUuid, limit]);

    return {
      restaurants: fallbackResult.rows,
      totalCount: fallbackResult.rows.length,
      algorithm: "basic",
      description: "あなたの地域で人気のレストランを推薦",
    };
  }

  const categories = categoryBreakdown.rows.map((row) =>
    `${row.category}(${row.like_count}件)`
  ).join(", ");

  return {
    restaurants: result.rows,
    totalCount: result.rows.length,
    algorithm: "basic",
    description: `あなたがいいねした${categories}と似たレストランを推薦`,
  };
}

/**
 * 協調フィルタリング推薦
 * @param {string} userUuid - ユーザーのUUID
 * @param {number} limit - 推薦数の上限
 * @return {Promise<any>} 推薦結果
 */
async function getCollaborativeRecommendations(userUuid: string, limit: number): Promise<{restaurants: any[], totalCount: number, algorithm: string, description: string}> {
  const result = await pool.query(`
    WITH user_info AS (
      SELECT prefecture FROM users WHERE id = $1
    ),
    user_liked_restaurants AS (
      SELECT restaurant_id FROM restaurants_likes WHERE user_id = $1
    ),
    similar_restaurants AS (
      SELECT 
        r2.id as restaurant_id,
        r2.name,
        r2.category,
        r2.prefecture,
        r2.nearest_station,
        r2.price_range,
        r2.low_price,
        r2.high_price,
        r2.image_url,
        r2.address,
        r2.hotpepper_url,
        r2.operating_hours,
        COUNT(DISTINCT rl1.user_id) as common_likers_count,
        COUNT(DISTINCT rl1.user_id)::float / (
          SELECT COUNT(DISTINCT user_id) 
          FROM restaurants_likes 
          WHERE restaurant_id IN (r1.restaurant_id, r2.id)
        ) as jaccard_similarity,
        CASE 
          WHEN r2.prefecture = (SELECT prefecture FROM user_info) THEN 0.2
          ELSE 0.0
        END as prefecture_bonus
      FROM user_liked_restaurants r1
      JOIN restaurants_likes rl1 ON r1.restaurant_id = rl1.restaurant_id
      JOIN restaurants_likes rl2 ON rl1.user_id = rl2.user_id
      JOIN restaurants r2 ON rl2.restaurant_id = r2.id
      WHERE rl2.restaurant_id NOT IN (
        SELECT restaurant_id FROM user_liked_restaurants
      )
      GROUP BY r2.id, r2.name, r2.category, r2.prefecture, r2.nearest_station, 
               r2.price_range, r2.low_price, r2.high_price, r2.image_url, 
               r2.address, r2.hotpepper_url, r2.operating_hours, r1.restaurant_id
      HAVING COUNT(DISTINCT rl1.user_id) >= 1  -- 最低条件を1人に緩和
      ORDER BY (jaccard_similarity + prefecture_bonus) DESC, common_likers_count DESC
    )
    SELECT DISTINCT
      restaurant_id,
      name,
      category,
      prefecture,
      nearest_station,
      price_range,
      low_price,
      high_price,
      image_url,
      address,
      hotpepper_url,
      operating_hours,
      AVG(jaccard_similarity) as avg_similarity,
      MAX(common_likers_count) as max_common_likers,
      AVG(prefecture_bonus) as prefecture_score
    FROM similar_restaurants
    GROUP BY restaurant_id, name, category, prefecture, nearest_station, 
             price_range, low_price, high_price, image_url, address, 
             hotpepper_url, operating_hours
    ORDER BY (avg_similarity + prefecture_score) DESC, max_common_likers DESC
    LIMIT $2
  `, [userUuid, limit]);

  return {
    restaurants: result.rows,
    totalCount: result.rows.length,
    algorithm: "collaborative",
    description: "似た好みのユーザーが好きなレストランを推薦",
  };
}

/**
 * デート成功率ベース推薦
 * @param {string} userUuid - ユーザーのUUID
 * @param {number} limit - 推薦数の上限
 * @return {Promise<any>} 推薦結果
 */
async function getDateSuccessRecommendations(userUuid: string, limit: number): Promise<{restaurants: any[], totalCount: number, algorithm: string, description: string}> {
  const result = await pool.query(`
    WITH user_info AS (
      SELECT prefecture, favorite_categories FROM users WHERE id = $1
    ),
    user_preferences AS (
      SELECT unnest(favorite_categories) as category
      FROM user_info
      WHERE favorite_categories IS NOT NULL AND array_length(favorite_categories, 1) > 0
    ),
    restaurant_success_rates AS (
      SELECT 
        r.id as restaurant_id,
        r.name,
        r.category,
        r.prefecture,
        r.nearest_station,
        r.price_range,
        r.low_price,
        r.high_price,
        r.image_url,
        r.address,
        r.hotpepper_url,
        r.operating_hours,
        COUNT(CASE WHEN dr.status = 'completed' THEN 1 END) as successful_dates,
        COUNT(dr.id) as total_dates,
        CASE 
          WHEN COUNT(dr.id) = 0 THEN 0.5
          ELSE COUNT(CASE WHEN dr.status = 'completed' THEN 1 END)::float / COUNT(dr.id)
        END as success_rate,
        CASE 
          WHEN r.category IN (SELECT category FROM user_preferences) THEN 1.0
          ELSE 0.1  -- マッチしないカテゴリのスコアを大幅に下げる
        END as category_preference_score,
        CASE 
          WHEN r.prefecture = (SELECT prefecture FROM user_info LIMIT 1) THEN 0.2
          ELSE 0.0
        END as prefecture_preference_score
      FROM restaurants r
      LEFT JOIN date_requests dr ON r.id = dr.restaurant_id
      WHERE r.id NOT IN (
        SELECT restaurant_id FROM restaurants_likes WHERE user_id = $1
      )
      GROUP BY r.id, r.name, r.category, r.prefecture, r.nearest_station, 
               r.price_range, r.low_price, r.high_price, r.image_url, 
               r.address, r.hotpepper_url, r.operating_hours
      HAVING COUNT(dr.id) >= 0  -- 条件を緩和：0件以上
    )
    SELECT 
      *,
      (success_rate * 0.5 + category_preference_score * 0.3 + 
       prefecture_preference_score * 0.1 + 
       LEAST(total_dates::float / 50, 1.0) * 0.1) as recommendation_score
    FROM restaurant_success_rates
    ORDER BY recommendation_score DESC, success_rate DESC
    LIMIT $2
  `, [userUuid, limit]);

  return {
    restaurants: result.rows,
    totalCount: result.rows.length,
    algorithm: "date_success",
    description: "デート成功率が高いレストランを推薦",
  };
}
/**
 * 全アルゴリズムの統合推薦
 * @param {string} userUuid - ユーザーのUUID
 * @param {number} limit - 推薦数の上限
 * @return {Promise<any>} 推薦結果
 */
async function getAllRecommendations(userUuid: string, limit: number): Promise<{restaurants: any[], totalCount: number, algorithm: string, description: string, breakdown: any}> {
  const perAlgorithmLimit = Math.ceil(limit / 3);

  const [basicRecs, collaborativeRecs, dateSuccessRecs] = await Promise.all([
    getBasicRecommendations(userUuid, perAlgorithmLimit),
    getCollaborativeRecommendations(userUuid, perAlgorithmLimit),
    getDateSuccessRecommendations(userUuid, perAlgorithmLimit),
  ]);

  // 重複を排除しながら統合
  const allRestaurants = new Map();
  const weights = {basic: 0.3, collaborative: 0.4, date_success: 0.3};

  // 基本推薦を追加
  basicRecs.restaurants.forEach((restaurant: any) => {
    allRestaurants.set(restaurant.restaurant_id, {
      ...restaurant,
      final_score: (restaurant.category_match_score || 0.5) * weights.basic,
      algorithm_sources: ["basic"],
    });
  });

  // 協調フィルタリング推薦を追加
  collaborativeRecs.restaurants.forEach((restaurant: any) => {
    const existing = allRestaurants.get(restaurant.restaurant_id);
    if (existing) {
      existing.final_score += (restaurant.avg_similarity || 0.5) * weights.collaborative;
      existing.algorithm_sources.push("collaborative");
    } else {
      allRestaurants.set(restaurant.restaurant_id, {
        ...restaurant,
        final_score: (restaurant.avg_similarity || 0.5) * weights.collaborative,
        algorithm_sources: ["collaborative"],
      });
    }
  });

  // デート成功率推薦を追加
  dateSuccessRecs.restaurants.forEach((restaurant: any) => {
    const existing = allRestaurants.get(restaurant.restaurant_id);
    if (existing) {
      existing.final_score += (restaurant.recommendation_score || 0.5) * weights.date_success;
      existing.algorithm_sources.push("date_success");
    } else {
      allRestaurants.set(restaurant.restaurant_id, {
        ...restaurant,
        final_score: (restaurant.recommendation_score || 0.5) * weights.date_success,
        algorithm_sources: ["date_success"],
      });
    }
  });

  // ファイナルスコアでソート
  const sortedRestaurants = Array.from(allRestaurants.values())
    .sort((a, b) => b.final_score - a.final_score)
    .slice(0, limit);

  return {
    restaurants: sortedRestaurants,
    totalCount: sortedRestaurants.length,
    algorithm: "all",
    description: "複数アルゴリズムの統合推薦",
    breakdown: {
      basic: basicRecs.totalCount,
      collaborative: collaborativeRecs.totalCount,
      date_success: dateSuccessRecs.totalCount,
      total_unique: sortedRestaurants.length,
    },
  };
}

// ユーザー用: 身分証明書認証申請のリセット
export const resetIdentityVerification = onCall(
  async (request: CallableRequest<Record<string, never>>) => {
    console.log("🔄 身分証明書認証申請リセット: 開始");

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }

      // 既存の認証申請を削除
      const deleteResult = await pool.query(
        `DELETE FROM identity_verifications 
         WHERE user_id = $1`,
        [userUuid]
      );

      // usersテーブルの身分証明書関連フィールドをリセット
      await pool.query(
        `UPDATE users 
         SET 
           id_verified = false,
           id_verification_date = NULL
         WHERE id = $1`,
        [userUuid]
      );

      console.log(
        `✅ ユーザー ${userUuid} の身分証明書認証申請をリセット: ${deleteResult.rowCount}件削除`
      );

      return {
        success: true,
        message: "身分証明書認証申請をリセットしました",
        deletedRecords: deleteResult.rowCount,
      };
    } catch (error) {
      console.log("❌ 認証申請リセット失敗:", error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError("internal", "認証申請のリセットに失敗しました");
    }
  }
);

/**
 * 実際のOCR処理関数（Google Vision API使用）
 * @param {string} imageBase64 - Base64エンコードされた画像データ
 * @param {string} documentType - 文書タイプ
 * @param {number} imageSizeBytes - 画像サイズ（バイト）
 * @return {Promise} OCR処理結果
 */
async function performAdvancedOCR(
  imageBase64: string,
  documentType: string,
  imageSizeBytes: number
): Promise<{
  isValidDocument: boolean;
  extractedName: string | null;
  extractedBirthDate: string | null;
  extractedAge: number | null;
  confidence: number;
  detectedKeywords: string[];
  reason: string;
  requiresManualReview?: boolean;
}> {
  try {
    // 画像サイズチェック（最低限の品質確保）
    if (imageSizeBytes < 50000) { // 50KB未満
      return {
        isValidDocument: false,
        extractedName: null,
        extractedBirthDate: null,
        extractedAge: null,
        confidence: 0,
        detectedKeywords: [],
        reason: "画像サイズが小さすぎます",
      };
    }

    // Google Vision APIを使用した実際のOCR処理
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const vision = require("@google-cloud/vision");
    const client = new vision.ImageAnnotatorClient({
      projectId: "dating-food-apps",
    });

    console.log("🔍 Google Vision APIでOCR処理を開始");

    // Base64画像をGoogle Vision APIに送信
    const [result] = await client.textDetection({
      image: {
        content: imageBase64,
      },
    });

    const detections = result.textAnnotations;
    console.log("🔍 Google Vision API応答:", JSON.stringify(result, null, 2));
    console.log("🔍 textAnnotations:", detections);

    if (!detections || detections.length === 0) {
      console.log("❌ OCR結果: テキスト検出なし");
      console.log("🔍 OCR応答の詳細:", JSON.stringify(result, null, 2));
      return {
        isValidDocument: false,
        extractedName: null,
        extractedBirthDate: null,
        extractedAge: null,
        confidence: 0,
        detectedKeywords: [],
        reason: "画像からテキストを検出できませんでした",
      };
    }

    // 検出されたテキスト全体を取得
    const fullText = detections[0].description || "";
    console.log(`🔍 OCR検出成功: ${detections.length}個のテキスト要素`);
    console.log(`🔍 検出されたテキスト長: ${fullText.length}文字`);
    console.log(`🔍 検出されたテキスト（最初の500文字）: ${fullText.substring(0, 500)}`);
    console.log(`🔍 文書タイプ: ${documentType}`);

    // 全てのテキスト検出結果をログ出力（デバッグ用）
    if (detections.length > 1) {
      console.log("🔍 個別テキスト検出結果:");
      detections.slice(1, 11).forEach(
        (detection: {description?: string}, index: number) => {
          console.log(`  ${index + 1}: "${detection.description}"`);
        }
      );
    }

    console.log(`🔍 検出されたテキスト: ${fullText.substring(0, 200)}...`);
    console.log(`🔍 文書タイプ: ${documentType}`);
    console.log(
      `🔍 検出されたテキスト全体（デバッグ用）: ${fullText}`
    );

    // 文書タイプ別のキーワード検証
    const requiredKeywords = getRequiredKeywords(documentType);
    const detectedKeywords: string[] = [];

    console.log(`🔍 documentType値: "${documentType}"`);
    console.log(`🔍 documentType型: ${typeof documentType}`);
    console.log(`🔍 mynumber_card比較: ${documentType === "mynumber_card"}`);
    console.log(`🔍 residence_card比較: ${documentType === "residence_card"}`);
    console.log(`🔍 requiredKeywords: ${JSON.stringify(requiredKeywords)}`);

    // キーワード検出（大文字小文字を区別しない）
    let keywordMatches = 0;
    for (const keyword of requiredKeywords) {
      const found = fullText.toLowerCase().includes(keyword.toLowerCase()) ||
                   fullText.includes(keyword);
      console.log(`🔍 基本キーワード「${keyword}」: ${found ? "検出" : "未検出"}`);
      if (found) {
        detectedKeywords.push(keyword);
        keywordMatches++;
      }
    }

    console.log(`🔍 基本キーワードマッチ: ${keywordMatches}個`);

    console.log(
      `🔍 キーワードマッチ: ${keywordMatches}/${requiredKeywords.length}`
    );
    console.log(`🔍 検出キーワード: ${detectedKeywords.join(", ")}`);

    // 身分証明書として有効かどうかの判定
    let validationThreshold = Math.ceil(requiredKeywords.length * 0.6);
    let regexScore = 0;

    // マイナンバーカード専用の追加検証
    if (documentType === "mynumber_card") {
      console.log("🔍 マイナンバーカード専用検証を実行");

      // マイナンバーカード特有のキーワードパターン（厳格化）
      const additionalPatterns = [
        // マイナンバーカード特有の表記のみ
        "個人番号カード", "マイナンバーカード",
        // 電子証明書関連（マイナンバーカード特有）
        "電子証明書の有効期限", "電子証明書",
        // 臓器提供関連（マイナンバーカード特有の表記）
        "臓器提供意思", "臓器提供",
        // 英語表記（マイナンバーカード特有）
        "INDIVIDUAL NUMBER CARD", "INDIVIDUAL", "PERSONAL", "IDENTIFICATION",
      ];

      // マイナンバーカード特有の正規表現パターン（緩和版）
      const regexPatterns = [
        // 12桁の個人番号パターン（マイナンバーカード特有）
        {pattern: /\d{4}\s?\d{4}\s?\d{4}/, name: "12桁個人番号", score: 6},
        // 一般的な日付パターン（より広範囲）
        {pattern: /\d{4}年\d{1,2}月\d{1,2}日/, name: "日付パターン", score: 3},
        // 電子証明書関連（より広範囲）
        {pattern: /電子証明書/, name: "電子証明書", score: 4},
        // 臓器提供関連（より広範囲）
        {pattern: /臓器提供/, name: "臓器提供", score: 3},
        // 自治体長パターン
        {pattern: /(市長|区長|町長|村長|知事)/, name: "自治体長", score: 3},
        // 住所パターン（より一般的）
        {pattern: /(県|市|区|町|村|丁目|番地)/, name: "住所パターン", score: 2},
      ];

      let additionalMatches = 0;

      // 基本キーワードパターンの検証
      for (const pattern of additionalPatterns) {
        const found = fullText.toLowerCase().includes(pattern.toLowerCase()) ||
                     fullText.includes(pattern);
        console.log(`🔍 パターン「${pattern}」: ${found ? "検出" : "未検出"}`);
        if (found) {
          if (!detectedKeywords.includes(pattern)) {
            detectedKeywords.push(pattern);
            additionalMatches++;
            console.log(`✅ 新規キーワード追加: ${pattern}`);
          } else {
            console.log(`⚠️ 既存キーワード: ${pattern}`);
          }
        }
      }

      // 正規表現パターンの検証
      console.log("🔍 正規表現パターン検証開始");
      for (const regexPattern of regexPatterns) {
        const match = fullText.match(regexPattern.pattern);
        const found = match !== null;
        const matchText = found ? ` (マッチ: ${match[0]})` : "";
        console.log(
          `🔍 正規表現「${regexPattern.name}」: ${found ? "検出" : "未検出"}${matchText}`
        );
        if (found) {
          regexScore += regexPattern.score;
          detectedKeywords.push(regexPattern.name);
          console.log(
            `✅ 正規表現マッチ: ${regexPattern.name} (+${regexPattern.score}点)`
          );
        }
      }

      // 正規表現スコアを追加マッチ数に変換（2点で1マッチとして計算）
      const regexMatches = Math.floor(regexScore / 2);
      console.log(
        `🔍 正規表現スコア: ${regexScore}点 → ${regexMatches}マッチ相当`
      );

      console.log(`🔍 基本パターンマッチ: ${additionalMatches}個`);
      console.log(`🔍 正規表現マッチ: ${regexMatches}個`);
      keywordMatches += additionalMatches + regexMatches;

      // 基本キーワードの70%以上 AND 正規表現スコア10点以上が必要
      const basicThreshold = Math.ceil(requiredKeywords.length * 0.7);
      const minRegexScore = 10;

      console.log(`🔍 マイナンバー基本キーワード: ${basicThreshold}個以上必要`);
      console.log(`🔍 マイナンバー正規表現スコア: ${minRegexScore}点以上必要`);

      // 基本キーワード70%以上 AND 正規表現スコア10点以上で合格
      if (keywordMatches >= basicThreshold && regexScore >= minRegexScore) {
        validationThreshold = Math.min(basicThreshold, keywordMatches);
        console.log(
          `✅ マイナンバーカード検証合格: キーワード${keywordMatches}個 OR 正規表現${regexScore}点`
        );
      } else {
        console.log(
          `❌ マイナンバーカード検証不合格: キーワード${keywordMatches}個 < ${basicThreshold}個 ` +
          `AND 正規表現${regexScore}点 < ${minRegexScore}点`
        );
        validationThreshold = basicThreshold;
      }
    } else if (documentType === "residence_card") {
      console.log("🔍 在留カード専用検証を実行");

      // 在留カード特有のキーワードパターン（緩和版）
      const additionalPatterns = [
        // 在留カード特有の表記
        "在留カード", "RESIDENCE CARD",
        // 在留関連
        "在留期間", "在留資格", "就労", "永住者",
        // 英語表記
        "PERIOD OF STAY", "STATUS OF RESIDENCE", "WORK", "PERMANENT RESIDENT",
        // 法務省関連
        "法務大臣", "入国管理局", "MINISTER OF JUSTICE",
      ];

      // 在留カード特有の正規表現パターン（厳格化）
      const regexPatterns = [
        // 在留期間パターン（在留カード特有）
        {pattern: /\d{4}年\d{1,2}月\d{1,2}日まで/, name: "在留期限", score: 6},
        // 在留番号パターン（英数字、在留カード特有）
        {pattern: /[A-Z]{2}\d{8}/, name: "在留番号", score: 8},
        // 法務大臣パターン（在留カード特有）
        {pattern: /法務大臣/, name: "法務大臣", score: 5},
        // 在留資格パターン（在留カード特有）
        {pattern: /在留資格/, name: "在留資格", score: 4},
      ];

      let additionalMatches = 0;

      // 基本キーワードパターンの検証
      for (const pattern of additionalPatterns) {
        const found = fullText.toLowerCase().includes(pattern.toLowerCase()) ||
                     fullText.includes(pattern);
        console.log(`🔍 パターン「${pattern}」: ${found ? "検出" : "未検出"}`);
        if (found) {
          if (!detectedKeywords.includes(pattern)) {
            detectedKeywords.push(pattern);
            additionalMatches++;
            console.log(`✅ 新規キーワード追加: ${pattern}`);
          } else {
            console.log(`⚠️ 既存キーワード: ${pattern}`);
          }
        }
      }

      // 正規表現パターンの検証
      console.log("🔍 正規表現パターン検証開始");
      for (const regexPattern of regexPatterns) {
        const match = fullText.match(regexPattern.pattern);
        const found = match !== null;
        const matchText = found ? ` (マッチ: ${match[0]})` : "";
        console.log(
          `🔍 正規表現「${regexPattern.name}」: ${found ? "検出" : "未検出"}${matchText}`
        );
        if (found) {
          regexScore += regexPattern.score;
          detectedKeywords.push(regexPattern.name);
          console.log(
            `✅ 正規表現マッチ: ${regexPattern.name} (+${regexPattern.score}点)`
          );
        }
      }

      // 正規表現スコアを追加マッチ数に変換（2点で1マッチとして計算）
      const regexMatches = Math.floor(regexScore / 2);
      console.log(
        `🔍 正規表現スコア: ${regexScore}点 → ${regexMatches}マッチ相当`
      );

      console.log(`🔍 基本パターンマッチ: ${additionalMatches}個`);
      console.log(`🔍 正規表現マッチ: ${regexMatches}個`);
      keywordMatches += additionalMatches + regexMatches;

      // 基本キーワードの50%以上 OR 正規表現スコア6点以上が必要（緩和）
      const basicThreshold = Math.ceil(requiredKeywords.length * 0.5);
      const minRegexScore = 6;

      console.log(`🔍 在留カード基本キーワード: ${basicThreshold}個以上必要`);
      console.log(`🔍 在留カード正規表現スコア: ${minRegexScore}点以上必要`);

      // 基本キーワード50%以上 OR 正規表現スコア6点以上で合格（緩和）
      if (keywordMatches >= basicThreshold || regexScore >= minRegexScore) {
        validationThreshold = Math.min(basicThreshold, keywordMatches);
        console.log(
          `✅ 在留カード検証合格: キーワード${keywordMatches}個 OR 正規表現${regexScore}点`
        );
      } else {
        console.log(
          `❌ 在留カード検証不合格: キーワード${keywordMatches}個 < ${basicThreshold}個 ` +
          `OR 正規表現${regexScore}点 < ${minRegexScore}点`
        );
        validationThreshold = basicThreshold;
      }
    } else {
      console.log(`❌ 専用検証をスキップ: documentType="${documentType}"`);
    }

    // 期限チェック（確認できる場合のみ必須）
    let expiryCheckResult: "valid" | "expired" | "not_found" = "not_found";
    let extractedExpiryDate: string | null = null;

    console.log("🔍 期限チェック開始");

    // 文書タイプ別の期限パターン
    const expiryPatterns = getExpiryPatterns(documentType);

    for (const pattern of expiryPatterns) {
      const match = fullText.match(pattern.regex);
      if (match) {
        console.log(`✅ 期限パターン検出: ${pattern.name} - ${match[0]}`);

        let year: number; let month: number; let day: number;

        // パスポートの英語形式の場合
        if (pattern.name === "DATE OF EXPIRY" ||
            pattern.name === "EXPIRY DATE") {
          day = parseInt(match[1]);
          const monthStr = match[2];
          year = parseInt(match[3]);

          // 月名を数値に変換
          const monthMap: {[key: string]: number} = {
            "JAN": 1, "FEB": 2, "MAR": 3, "APR": 4, "MAY": 5, "JUN": 6,
            "JUL": 7, "AUG": 8, "SEP": 9, "OCT": 10, "NOV": 11, "DEC": 12,
          };
          month = monthMap[monthStr.toUpperCase()] || 0;
        } else {
          // 通常の日本語形式
          year = parseInt(match[1]);
          month = parseInt(match[2]);
          day = parseInt(match[3]);
        }

        if (year && month && day && month >= 1 && month <= 12 &&
            day >= 1 && day <= 31) {
          extractedExpiryDate =
            `${year}-${month.toString().padStart(2, "0")}-` +
            `${day.toString().padStart(2, "0")}`;

          // 期限が未来の日付かチェック
          const expiryDate = new Date(year, month - 1, day);
          const today = new Date();

          if (expiryDate > today) {
            expiryCheckResult = "valid";
            console.log(`✅ 有効な期限: ${extractedExpiryDate}`);
            break;
          } else {
            expiryCheckResult = "expired";
            console.log(`❌ 期限切れ検出: ${extractedExpiryDate}`);
            console.log(
              `🔍 期限切れ詳細: 検出された期限=${extractedExpiryDate}, ` +
              `今日=${new Date().toISOString().split("T")[0]}`
            );
            // 期限切れが見つかった場合は即座に失敗
            return {
              isValidDocument: false,
              extractedName: null,
              extractedBirthDate: null,
              extractedAge: null,
              confidence: 0,
              detectedKeywords,
              reason: `期限切れのため使用できません (有効期限: ${extractedExpiryDate})`,
              requiresManualReview: false,
            };
          }
        }
      }
    }

    // 信頼度計算（専用検証後の最終的なkeywordMatchesを使用）
    const confidence = Math.min(
      (keywordMatches / Math.max(requiredKeywords.length, 1)) * 100,
      95
    );

    console.log(
      `🔍 最終信頼度計算: ${keywordMatches}/${requiredKeywords.length} = ${confidence}%`
    );

    // 期限チェック結果に基づく判定
    const isValidDocument = keywordMatches >= validationThreshold;
    let requiresManualReview = false;

    if (expiryCheckResult === "not_found") {
      console.log("⚠️ 期限が確認できません - 他の条件で判定");
      // 期限が確認できない場合、信頼度が極端に低くなければ審査中
      if (confidence >= 30 && confidence < 80) {
        requiresManualReview = true;
        console.log(`⚠️ 期限確認不可 + 信頼度${confidence}% → 審査中`);
      }
    } else if (expiryCheckResult === "valid") {
      console.log("✅ 有効な期限が確認されました");
      // 期限が有効な場合は通常の判定
    }
    // expired の場合は既に上で return している

    // 年齢・名前の抽出（実際のテキストから）
    let extractedAge: number | null = null;
    let extractedName: string | null = null;
    let extractedBirthDate: string | null = null;

    if (isValidDocument) {
      // 生年月日の抽出を試行
      const birthDateMatch = fullText.match(
        /(\d{4})[年\-/](\d{1,2})[月\-/](\d{1,2})/
      );
      if (birthDateMatch) {
        const year = parseInt(birthDateMatch[1]);
        const month = parseInt(birthDateMatch[2]);
        const day = parseInt(birthDateMatch[3]);
        extractedBirthDate = `${year}-${month.toString().padStart(2, "0")}-` +
          `${day.toString().padStart(2, "0")}`;

        // 年齢計算
        const today = new Date();
        const birthDate = new Date(year, month - 1, day);
        extractedAge = today.getFullYear() - birthDate.getFullYear();
        if (today.getMonth() < birthDate.getMonth() ||
            (today.getMonth() === birthDate.getMonth() &&
             today.getDate() < birthDate.getDate())) {
          extractedAge--;
        }
      }

      // 名前の抽出（簡易版）
      extractedName = "OCR認証済みユーザー";
    }

    // 最終的な判定とreason設定
    let reasonText: string;
    let finalIsValid: boolean;

    if (requiresManualReview) {
      reasonText = "期限確認不可のため審査中";
      finalIsValid = false; // 審査中は一旦false、後でstatusで制御
    } else if (isValidDocument) {
      if (expiryCheckResult === "valid") {
        reasonText = "身分証明書として認識（期限確認済み）";
      } else {
        reasonText = "身分証明書として認識（期限確認不可）";
      }
      finalIsValid = true;
    } else {
      reasonText = `不足 (${keywordMatches}/${validationThreshold}個必要)`;
      finalIsValid = false;
    }

    return {
      isValidDocument: finalIsValid,
      extractedName,
      extractedBirthDate,
      extractedAge,
      confidence,
      detectedKeywords,
      reason: reasonText,
      requiresManualReview, // 新しいフィールドを追加
    };
  } catch (error) {
    console.log("OCR処理エラー:", error);
    return {
      isValidDocument: false,
      extractedName: null,
      extractedBirthDate: null,
      extractedAge: null,
      confidence: 0,
      detectedKeywords: [],
      reason: "OCR処理中にエラーが発生しました",
      requiresManualReview: false,
    };
  }
}

/**
 * 文書タイプ別の期限パターンを取得
 * @param {string} documentType - 文書タイプ
 * @return {Array<{name: string, regex: RegExp}>} 期限パターンの配列
 */
function getExpiryPatterns(
  documentType: string
): Array<{name: string, regex: RegExp}> {
  switch (documentType) {
  case "drivers_license":
    return [
      // 運転免許証の有効期限パターン
      {name: "免許証有効期限", regex: /(\d{4})年(\d{1,2})月(\d{1,2})日まで有効/},
      {name: "免許証期限", regex: /有効期限.*(\d{4})年(\d{1,2})月(\d{1,2})日/},
      {name: "一般期限", regex: /(\d{4})年(\d{1,2})月(\d{1,2})日/},
    ];
  case "passport":
    return [
      // パスポートの有効期限パターン
      {name: "パスポート有効期限", regex: /(\d{4})年(\d{1,2})月(\d{1,2})日まで有効/},
      {name: "パスポート期限", regex: /有効期限.*(\d{4})年(\d{1,2})月(\d{1,2})日/},
      {
        name: "DATE OF EXPIRY",
        regex: /DATE OF EXPIRY.*?(\d{2})\s?(\w{3})\s?(\d{4})/i,
      },
      {
        name: "EXPIRY DATE",
        regex: /(\d{2})\s?(\w{3})\s?(\d{4})/,
      },
      {name: "一般期限", regex: /(\d{4})年(\d{1,2})月(\d{1,2})日/},
    ];
  case "mynumber_card":
    return [
      // マイナンバーカードの有効期限パターン
      {name: "カード有効期限", regex: /(\d{4})年(\d{1,2})月(\d{1,2})日まで有効/},
      {name: "電子証明書期限", regex: /電子証明書.*(\d{4})年(\d{1,2})月(\d{1,2})日/},
      {name: "一般期限", regex: /(\d{4})年(\d{1,2})月(\d{1,2})日/},
    ];
  case "residence_card":
    return [
      // 在留カードの有効期限パターン
      {name: "在留期限", regex: /(\d{4})年(\d{1,2})月(\d{1,2})日まで/},
      {name: "在留期間", regex: /在留期間.*(\d{4})年(\d{1,2})月(\d{1,2})日/},
      {name: "PERIOD OF STAY", regex: /(\d{4})\.(\d{1,2})\.(\d{1,2})/}, // 英語形式
      {name: "一般期限", regex: /(\d{4})年(\d{1,2})月(\d{1,2})日/},
    ];
  default:
    return [
      {name: "一般期限", regex: /(\d{4})年(\d{1,2})月(\d{1,2})日/},
    ];
  }
}

/**
 * 文書タイプ別の必須キーワードを取得
 * @param {string} documentType - 文書タイプ
 * @return {string[]} 必須キーワードの配列
 */
function getRequiredKeywords(documentType: string): string[] {
  switch (documentType) {
  case "drivers_license":
    return ["運転免許証", "免許証", "公安委員会", "運転", "免許", "交付"];
  case "passport":
    return ["パスポート", "旅券", "PASSPORT", "日本国", "JAPAN"];
  case "mynumber_card":
    return [
      "個人番号", "電子証明書", "市長", "区長",
    ];
  case "residence_card":
    return ["在留カード", "在留", "在留期間", "在留資格", "RESIDENCE", "CARD"];
  default:
    return ["身分", "証明", "ID"];
  }
}

// 複数画像管理機能
export const uploadUserImage = onCall(
  async (request: CallableRequest<{
    imageUrl: string;
    displayOrder?: number;
    isPrimary?: boolean;
  }>) => {
    if (!request.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "ユーザーが認証されていません"
      );
    }

    const {imageUrl, displayOrder, isPrimary} = request.data;
    const firebaseUid = request.auth.uid;

    if (!imageUrl) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "画像URLが必要です"
      );
    }

    try {
      // Firebase UIDからUUID形式のuser IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      // 現在の画像数をチェック
      const existingImagesQuery = `
        SELECT id FROM user_images WHERE user_id = $1
      `;
      const existingImagesResult = await pool.query(
        existingImagesQuery,
        [userUuid]
      );

      if (existingImagesResult.rows.length >= 10) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "画像は最大10枚まで登録できます"
        );
      }

      // プライマリ画像の場合、他の画像のプライマリフラグを解除
      if (isPrimary) {
        const updatePrimaryQuery = `
          UPDATE user_images SET is_primary = false WHERE user_id = $1
        `;
        await pool.query(updatePrimaryQuery, [userUuid]);
      }

      // 表示順序が指定されていない場合、最後に追加
      let finalDisplayOrder = displayOrder;
      if (finalDisplayOrder === undefined || finalDisplayOrder === null) {
        const maxOrderQuery = `
          SELECT display_order FROM user_images 
          WHERE user_id = $1 
          ORDER BY display_order DESC 
          LIMIT 1
        `;
        const maxOrderResult = await pool.query(maxOrderQuery, [userUuid]);

        finalDisplayOrder = maxOrderResult.rows.length > 0 ?
          maxOrderResult.rows[0].display_order + 1 :
          1;
      }

      // 新しい画像を追加
      const insertImageQuery = `
        INSERT INTO user_images (user_id, image_url, display_order, is_primary)
        VALUES ($1, $2, $3, $4)
        RETURNING *
      `;
      const newImageResult = await pool.query(insertImageQuery, [
        userUuid,
        imageUrl,
        finalDisplayOrder,
        isPrimary || false,
      ]);

      const newImage = newImageResult.rows[0];

      // プライマリ画像の場合、usersテーブルのimage_urlも更新
      if (isPrimary) {
        const updateUserQuery = `
          UPDATE users SET image_url = $1 WHERE id = $2
        `;
        await pool.query(updateUserQuery, [imageUrl, userUuid]);
      }

      return {
        success: true,
        image: newImage,
      };
    } catch (error) {
      console.error("uploadUserImage エラー:", error);
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }
      throw new functions.https.HttpsError(
        "internal",
        "画像のアップロードに失敗しました"
      );
    }
  }
);

export const deleteUserImage = onCall(
  async (request: CallableRequest<{
    imageId: string;
  }>) => {
    if (!request.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "ユーザーが認証されていません"
      );
    }

    const {imageId} = request.data;
    const firebaseUid = request.auth.uid;

    if (!imageId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "画像IDが必要です"
      );
    }

    try {
      // Firebase UIDからUUID形式のuser IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      // 画像の存在確認と所有者チェック
      const fetchImageQuery = `
        SELECT * FROM user_images WHERE id = $1 AND user_id = $2
      `;
      const imageResult = await pool.query(fetchImageQuery, [
        imageId,
        userUuid,
      ]);

      if (imageResult.rows.length === 0) {
        throw new functions.https.HttpsError(
          "not-found",
          "画像が見つかりません"
        );
      }

      const image = imageResult.rows[0];

      // 画像を削除
      const deleteImageQuery = `
        DELETE FROM user_images WHERE id = $1 AND user_id = $2
      `;
      await pool.query(deleteImageQuery, [imageId, userUuid]);

      // プライマリ画像が削除された場合、次の画像をプライマリに設定
      if (image.is_primary) {
        const nextImageQuery = `
          SELECT * FROM user_images 
          WHERE user_id = $1 
          ORDER BY display_order ASC 
          LIMIT 1
        `;
        const nextImageResult = await pool.query(nextImageQuery, [userUuid]);

        if (nextImageResult.rows.length > 0) {
          const nextImage = nextImageResult.rows[0];

          const updatePrimaryQuery = `
            UPDATE user_images SET is_primary = true WHERE id = $1
          `;
          await pool.query(updatePrimaryQuery, [nextImage.id]);

          // usersテーブルのimage_urlも更新
          const updateUserQuery = `
            UPDATE users SET image_url = $1 WHERE id = $2
          `;
          await pool.query(updateUserQuery, [
            nextImage.image_url,
            userUuid,
          ]);
        } else {
          // 他に画像がない場合、usersテーブルのimage_urlをnullに
          const updateUserQuery = `
            UPDATE users SET image_url = NULL WHERE id = $1
          `;
          await pool.query(updateUserQuery, [userUuid]);
        }
      }

      return {
        success: true,
        message: "画像を削除しました",
      };
    } catch (error) {
      console.error("deleteUserImage エラー:", error);
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }
      throw new functions.https.HttpsError(
        "internal",
        "画像の削除に失敗しました"
      );
    }
  }
);

export const getUserImages = onCall(
  async (request: CallableRequest<{
    targetUserId?: string;
  }>) => {
    if (!request.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "ユーザーが認証されていません"
      );
    }

    const {targetUserId} = request.data;
    const firebaseUid = request.auth.uid;

    try {
      let userUuid: string | null;

      if (targetUserId) {
        // 他人の画像を取得する場合、targetUserIdはUUID形式
        userUuid = targetUserId;
      } else {
        // 自分の画像を取得する場合、Firebase UIDからUUIDに変換
        userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
        if (!userUuid) {
          throw new functions.https.HttpsError(
            "not-found",
            "ユーザーが見つかりません"
          );
        }
      }

      const imagesQuery = `
        SELECT * FROM user_images 
        WHERE user_id = $1 
        ORDER BY display_order ASC
      `;
      const imagesResult = await pool.query(imagesQuery, [userUuid]);

      return {
        success: true,
        images: imagesResult.rows || [],
      };
    } catch (error) {
      console.error("getUserImages エラー:", error);
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }
      throw new functions.https.HttpsError(
        "internal",
        "画像の取得に失敗しました"
      );
    }
  }
);

export const setPrimaryImage = onCall(
  async (request: CallableRequest<{
    imageId: string;
  }>) => {
    if (!request.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "ユーザーが認証されていません"
      );
    }

    const {imageId} = request.data;
    const firebaseUid = request.auth.uid;

    if (!imageId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "画像IDが必要です"
      );
    }

    try {
      // Firebase UIDからUUID形式のuser IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      // 画像の存在確認と所有者チェック
      const fetchImageQuery = `
        SELECT * FROM user_images WHERE id = $1 AND user_id = $2
      `;
      const imageResult = await pool.query(fetchImageQuery, [
        imageId,
        userUuid,
      ]);

      if (imageResult.rows.length === 0) {
        throw new functions.https.HttpsError(
          "not-found",
          "画像が見つかりません"
        );
      }

      const image = imageResult.rows[0];

      // 他の画像のプライマリフラグを解除
      const updateOthersQuery = `
        UPDATE user_images SET is_primary = false WHERE user_id = $1
      `;
      await pool.query(updateOthersQuery, [userUuid]);

      // 指定された画像をプライマリに設定
      const updatePrimaryQuery = `
        UPDATE user_images SET is_primary = true WHERE id = $1
      `;
      await pool.query(updatePrimaryQuery, [imageId]);

      // usersテーブルのimage_urlも更新
      const updateUserQuery = `
        UPDATE users SET image_url = $1 WHERE id = $2
      `;
      await pool.query(updateUserQuery, [
        image.image_url,
        userUuid,
      ]);

      return {
        success: true,
        message: "プライマリ画像を設定しました",
      };
    } catch (error) {
      console.error("setPrimaryImage エラー:", error);
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }
      throw new functions.https.HttpsError(
        "internal",
        "プライマリ画像の設定に失敗しました"
      );
    }
  }
);

// 画像メタデータ（キャプション、レストラン情報）を更新
export const updateUserImageMetadata = onCall(
  async (request: CallableRequest<{
    imageId: string;
    caption?: string;
    restaurantId?: string;
    restaurantName?: string;
  }>) => {
    if (!request.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "ユーザーが認証されていません"
      );
    }

    const {imageId, caption, restaurantId, restaurantName} = request.data;
    const firebaseUid = request.auth.uid;

    if (!imageId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "画像IDが必要です"
      );
    }

    try {
      // Firebase UIDからUUID形式のuser IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new functions.https.HttpsError(
          "not-found",
          "ユーザーが見つかりません"
        );
      }

      // 画像の存在確認と所有者チェック
      const fetchImageQuery = `
        SELECT * FROM user_images WHERE id = $1 AND user_id = $2
      `;
      const imageResult = await pool.query(fetchImageQuery, [
        imageId,
        userUuid,
      ]);

      if (imageResult.rows.length === 0) {
        throw new functions.https.HttpsError(
          "not-found",
          "画像が見つかりません"
        );
      }

      // メタデータを更新
      const updateQuery = `
        UPDATE user_images 
        SET 
          caption = COALESCE($3, caption),
          restaurant_id = COALESCE($4, restaurant_id),
          restaurant_name = COALESCE($5, restaurant_name),
          updated_at = NOW()
        WHERE id = $1 AND user_id = $2
        RETURNING *
      `;

      const updateResult = await pool.query(updateQuery, [
        imageId,
        userUuid,
        caption || null,
        restaurantId || null,
        restaurantName || null,
      ]);

      console.log(`画像メタデータ更新完了: ${imageId}`);

      return {
        success: true,
        message: "画像メタデータを更新しました",
        image: updateResult.rows[0],
      };
    } catch (error) {
      console.error("updateUserImageMetadata エラー:", error);
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }
      throw new functions.https.HttpsError(
        "internal",
        "画像メタデータの更新に失敗しました"
      );
    }
  }
);

/**
 * アカウント退会処理
 */
export const deactivateUserAccount = onCall(async (request: CallableRequest<{
  uid: string;
}>): Promise<{
  success: boolean;
  message: string;
}> => {
  try {
    console.log("🔥 deactivateUserAccount: 開始");

    // 認証チェック
    if (!request.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "ユーザーが認証されていません"
      );
    }

    const {uid} = request.data;
    const firebaseUid = request.auth.uid;

    // パラメータチェック
    if (!uid) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "UIDが必要です"
      );
    }

    // 自分のアカウントのみ退会可能
    if (uid !== firebaseUid) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "自分のアカウントのみ退会できます"
      );
    }

    console.log("🔥 deactivateUserAccount: Firebase UID =", firebaseUid);

    // Firebase UIDからユーザーUUIDを取得
    const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
    if (!userUuid) {
      throw new functions.https.HttpsError(
        "not-found",
        "ユーザーが見つかりません"
      );
    }

    console.log("🔥 deactivateUserAccount: ユーザーUUID =", userUuid);

    // 退会処理を実行
    // 1. アカウントステータスをdeactivatedに変更
    // 2. 退会日時を記録
    // 3. データは保持して復元可能にする
    const deactivationDate = new Date();

    await pool.query(
      `UPDATE users 
       SET account_status = 'deactivated',
           deactivated_at = $1,
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $2`,
      [deactivationDate, userUuid]
    );

    console.log("🔥 deactivateUserAccount: アカウント停止完了");

    // 関連データの処理
    // 1. マッチを無効化（復元時に再度有効化可能）
    await pool.query(
      `UPDATE matches 
       SET status = 'deactivated',
           updated_at = CURRENT_TIMESTAMP
       WHERE (user1_id = $1 OR user2_id = $1) 
       AND status = 'active'`,
      [userUuid]
    );

    // 2. デートリクエストをキャンセル（復元時に再度有効化可能）
    await pool.query(
      `UPDATE date_requests 
       SET status = 'cancelled',
           updated_at = CURRENT_TIMESTAMP
       WHERE (requester_id = $1 OR recipient_id = $1) 
       AND status IN ('pending', 'voted')`,
      [userUuid]
    );

    // 3. グループ関連の処理
    // Firestoreのグループからも退会
    const firestore = admin.firestore();

    // ユーザーが参加しているグループを取得
    const groupsSnapshot = await firestore
      .collection("groups")
      .where("members", "array-contains", firebaseUid)
      .get();

    for (const groupDoc of groupsSnapshot.docs) {
      const groupData = groupDoc.data();
      const members = groupData.members || [];
      const admins = groupData.admins || [];

      // メンバーリストから削除
      const updatedMembers = members.filter((memberId: string) => memberId !== firebaseUid);
      const updatedAdmins = admins.filter((adminId: string) => adminId !== firebaseUid);

      // グループを更新
      await groupDoc.ref.update({
        members: updatedMembers,
        admins: updatedAdmins,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // グループチャットに退会メッセージを送信
      if (updatedMembers.length > 0) {
        const systemMessage = {
          sender_id: "system",
          group_id: groupDoc.id,
          message: `${groupData.name}から退会しました。`,
          message_type: "member_left",
          sent_at: admin.firestore.FieldValue.serverTimestamp(),
          read_by: [],
        };

        await firestore.collection("group_messages").add(systemMessage);
      }
    }

    console.log("🔥 deactivateUserAccount: 関連データ処理完了");

    return {
      success: true,
      message: "アカウントを退会しました。いつでも復元可能です。",
    };
  } catch (error) {
    console.error("🔥 deactivateUserAccount エラー:", error);

    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    // データベース制約エラーの詳細処理
    if ((error as any).code === "23514") {
      console.error("🔥 deactivateUserAccount: データベース制約エラー -", (error as any).detail);
      throw new functions.https.HttpsError(
        "internal",
        "データベースの設定に問題があります。管理者にお問い合わせください。"
      );
    }

    // PostgreSQLエラーの詳細処理
    if ((error as any).code === "42703") {
      console.error("🔥 deactivateUserAccount: カラム不存在エラー -", (error as any).detail);
      throw new functions.https.HttpsError(
        "internal",
        "データベースの設定が不完全です。管理者にお問い合わせください。"
      );
    }

    throw new functions.https.HttpsError(
      "internal",
      "アカウント退会に失敗しました"
    );
  }
});

/**
 * アカウント復元処理
 */
export const reactivateUserAccount = onCall(async (request: CallableRequest<{
  uid: string;
}>): Promise<{
  success: boolean;
  message: string;
}> => {
  try {
    console.log("🔥 reactivateUserAccount: 開始");

    // 認証チェック
    if (!request.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "ユーザーが認証されていません"
      );
    }

    const {uid} = request.data;
    const firebaseUid = request.auth.uid;

    // パラメータチェック
    if (!uid) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "UIDが必要です"
      );
    }

    // 自分のアカウントのみ復元可能
    if (uid !== firebaseUid) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "自分のアカウントのみ復元できます"
      );
    }

    console.log("🔥 reactivateUserAccount: Firebase UID =", firebaseUid);

    // Firebase UIDからユーザーUUIDを取得（復元時は停止中ユーザーも含める）
    const userUuidResult = await pool.query(
      "SELECT id FROM users WHERE firebase_uid = $1",
      [firebaseUid]
    );

    if (userUuidResult.rows.length === 0) {
      throw new functions.https.HttpsError(
        "not-found",
        "ユーザーが見つかりません"
      );
    }

    const userUuid = userUuidResult.rows[0].id;

    // ユーザーの現在の状態を確認
    const userResult = await pool.query(
      `SELECT account_status, deactivated_at
       FROM users 
       WHERE id = $1`,
      [userUuid]
    );

    if (userResult.rows.length === 0) {
      throw new functions.https.HttpsError(
        "not-found",
        "ユーザーが見つかりません"
      );
    }

    const user = userResult.rows[0];

    if (user.account_status !== "deactivated") {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "アカウントは停止状態ではありません"
      );
    }

    // 復元可能期間をチェック（30日以内）
    const deactivatedAt = new Date(user.deactivated_at);
    const now = new Date();
    const daysSinceDeactivation = Math.floor((now.getTime() - deactivatedAt.getTime()) / (1000 * 60 * 60 * 24));

    if (daysSinceDeactivation > 30) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "退会から30日が経過しているため、復元できません"
      );
    }

    // アカウントを復元
    await pool.query(
      `UPDATE users 
       SET account_status = 'active',
           deactivated_at = NULL,
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $1`,
      [userUuid]
    );

    console.log("🔥 reactivateUserAccount: アカウント復元完了");

    // マッチを復元（statusを'active'に戻す）
    const matchesResult = await pool.query(
      `UPDATE matches 
       SET status = 'active',
           updated_at = CURRENT_TIMESTAMP
       WHERE (user1_id = $1 OR user2_id = $1) 
       AND status = 'deactivated'`,
      [userUuid]
    );

    console.log(`🔥 reactivateUserAccount: マッチ復元完了 - ${matchesResult.rowCount}件`);

    return {
      success: true,
      message: "アカウントを復元しました。",
    };
  } catch (error) {
    console.error("🔥 reactivateUserAccount エラー:", error);

    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    throw new functions.https.HttpsError(
      "internal",
      "アカウント復元に失敗しました"
    );
  }
});

/**
 * 退会アカウントの完全削除処理（定期実行用）
 */
export const cleanupDeactivatedAccounts = onCall(async (request: CallableRequest): Promise<{
  success: boolean;
  deletedCount: number;
  message: string;
}> => {
  try {
    console.log("🔥 cleanupDeactivatedAccounts: 開始");

    // 削除期限を過ぎた退会アカウントを取得（30日以上経過）
    const expiredAccounts = await pool.query(
      `SELECT id, firebase_uid, name, email
       FROM users 
       WHERE account_status = 'deactivated' 
       AND deactivated_at < CURRENT_TIMESTAMP - INTERVAL '30 days'`
    );

    console.log(`🔥 cleanupDeactivatedAccounts: 削除対象 ${expiredAccounts.rows.length}件`);

    let deletedCount = 0;

    for (const account of expiredAccounts.rows) {
      try {
        // 関連データを完全削除
        await pool.query("BEGIN");

        // 1. マッチを削除
        await pool.query(
          `DELETE FROM matches 
           WHERE user1_id = $1 OR user2_id = $1`,
          [account.id]
        );

        // 2. いいねを削除
        await pool.query(
          `DELETE FROM likes 
           WHERE from_user_id = $1 OR to_user_id = $1`,
          [account.id]
        );

        // 3. デートリクエストを削除
        await pool.query(
          `DELETE FROM date_requests 
           WHERE requester_id = $1 OR recipient_id = $1`,
          [account.id]
        );

        // 4. メッセージを削除
        await pool.query(
          `DELETE FROM messages 
           WHERE sender_id = $1 OR receiver_id = $1`,
          [account.id]
        );

        // 5. 通報を削除
        await pool.query(
          `DELETE FROM reports 
           WHERE reporter_id = $1 OR reported_user_id = $1`,
          [account.id]
        );

        // 6. 身分証明書認証データを削除
        await pool.query(
          `DELETE FROM identity_verifications 
           WHERE user_id = $1`,
          [account.id]
        );

        // 7. ユーザーを削除
        await pool.query(
          `DELETE FROM users 
           WHERE id = $1`,
          [account.id]
        );

        await pool.query("COMMIT");
        deletedCount++;

        console.log(`🔥 cleanupDeactivatedAccounts: アカウント削除完了 - ${account.name} (${account.email})`);

        // Firebase Authenticationからも削除（オプション）
        try {
          await admin.auth().deleteUser(account.firebase_uid);
          console.log(`🔥 cleanupDeactivatedAccounts: Firebase認証削除完了 - ${account.firebase_uid}`);
        } catch (firebaseError) {
          console.warn(`🔥 cleanupDeactivatedAccounts: Firebase認証削除失敗 - ${account.firebase_uid}:`, firebaseError);
        }
      } catch (error) {
        await pool.query("ROLLBACK");
        console.error(`🔥 cleanupDeactivatedAccounts: アカウント削除失敗 - ${account.id}:`, error);
      }
    }

    console.log(`🔥 cleanupDeactivatedAccounts: 完了 - ${deletedCount}件削除`);

    return {
      success: true,
      deletedCount,
      message: `${deletedCount}件の退会アカウントを削除しました。`,
    };
  } catch (error) {
    console.error("🔥 cleanupDeactivatedAccounts エラー:", error);

    if (error instanceof HttpsError) {
      throw error;
    }

    throw new HttpsError(
      "internal",
      "退会アカウントの削除に失敗しました"
    );
  }
});

// テスト用のプッシュ通知送信関数（開発環境のみ）
export const sendTestNotification = onCall(
  async (request: CallableRequest<{
    notificationType: "like" | "match" | "message";
    customTitle?: string;
    customBody?: string;
  }>) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "ユーザーが認証されていません"
      );
    }

    const {notificationType, customTitle, customBody} = request.data;
    const userFirebaseUid = request.auth.uid;

    try {
      // 現在のユーザーのFCMトークンを取得
      const userUuid = await getUserUuidFromFirebaseUid(userFirebaseUid);
      if (!userUuid) {
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }

      const userQuery = "SELECT fcm_token FROM users WHERE id = $1";
      const userResult = await pool.query(userQuery, [userUuid]);

      if (userResult.rows.length === 0 || !userResult.rows[0].fcm_token) {
        throw new HttpsError(
          "not-found",
          "FCMトークンが見つかりません。アプリを再起動してください。"
        );
      }

      const fcmToken = userResult.rows[0].fcm_token;

      // 通知タイプ別のメッセージを設定
      let title: string;
      let body: string;
      let notificationData: {[key: string]: unknown} = {};

      switch (notificationType) {
      case "like":
        title = customTitle || "デリミート";
        body = customBody || "テストユーザーさんからいいねされました";
        notificationData = {type: "like", senderId: "test-user"};
        break;
      case "match":
        title = customTitle || "デリミート";
        body = customBody || "テストユーザーさんとマッチしました！";
        notificationData = {
          type: "match",
          senderId: "test-user",
          matchId: "test-match",
        };
        break;
      case "message":
        title = customTitle || "デリミート";
        body = customBody || "テストユーザーさんからメッセージが届いています❤️";
        notificationData = {
          type: "message",
          senderId: "test-user",
          chatId: "test-chat",
        };
        break;
      default:
        title = customTitle || "デリミート";
        body = customBody || "これはテスト通知です";
      }

      // プッシュ通知を送信
      const message = {
        token: fcmToken,
        notification: {
          title,
          body,
        },
        data: {
          ...notificationData,
          testNotification: "true",
        },
        android: {
          priority: "high" as const,
          notification: {
            channelId: "dating_food_app_channel",
            priority: "high" as const,
            color: "#FF69B4", // ピンク色
          },
        },
        apns: {
          payload: {
            aps: {
              alert: {
                title,
                body,
              },
              badge: 1,
              sound: "default",
              category: notificationType,
            },
          },
        },
      };

      await admin.messaging().send(message);

      const successMsg = `✅ テスト通知送信成功: ${notificationType} ` +
        `to ${userFirebaseUid}`;
      console.log(successMsg);

      return {
        success: true,
        message: `${notificationType}タイプのテスト通知を送信しました`,
        title,
        body,
        fcmToken: fcmToken.substring(0, 20) + "...",
      };
    } catch (error) {
      console.error("sendTestNotification エラー:", error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError(
        "internal",
        `テスト通知の送信に失敗しました: ${error}`
      );
    }
  }
);

export const updateNotificationSettings = onCall(
  async (request: CallableRequest<{
    enablePush?: boolean;
    enableLike?: boolean;
    enableMatch?: boolean;
    enableMessage?: boolean;
    enableFriendRequest?: boolean;
  }>) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "ユーザーが認証されていません"
      );
    }

    const settings = request.data;
    const firebaseUid = request.auth.uid;

    try {
      // Firestoreの通知設定を更新
      const settingsRef = admin.firestore()
        .collection("users")
        .doc(firebaseUid)
        .collection("settings")
        .doc("notifications");

      await settingsRef.set(settings, {merge: true});

      console.log(`通知設定更新完了: ${firebaseUid}`);

      return {
        success: true,
        message: "通知設定を更新しました",
      };
    } catch (error) {
      console.error("updateNotificationSettings エラー:", error);
      throw new HttpsError(
        "internal",
        "通知設定の更新に失敗しました"
      );
    }
  }
);

// 自動日程調整用のインターフェース

interface DateSuggestion {
  date: string; // ISO date string
  timeSlot: string;
  confidence: number; // 0-1の信頼度
}

/**
 * ユーザーの空き時間を登録するFirebase Function
 */
export const setUserAvailability = onCall(
  async (request: CallableRequest<{
    availability: Array<{
      dayOfWeek: number;
      timeSlots: string[];
      isAvailable: boolean;
    }>;
  }>): Promise<{success: boolean}> => {
    console.log("🔍 setUserAvailability関数開始");

    try {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "認証が必要です");
      }

      const firebaseUid = request.auth.uid;
      const {availability} = request.data;

      console.log("🔍 空き時間設定:", {firebaseUid, availability});

      // Firebase UIDからユーザーUUIDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }

      // 既存の空き時間データを削除
      await pool.query(
        "DELETE FROM user_availability WHERE user_id = $1",
        [userUuid]
      );

      // 新しい空き時間データを挿入
      for (const slot of availability) {
        if (slot.isAvailable && slot.timeSlots.length > 0) {
          await pool.query(
            `INSERT INTO user_availability 
             (user_id, day_of_week, time_slots, is_available, created_at, updated_at) 
             VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
            [userUuid, slot.dayOfWeek, JSON.stringify(slot.timeSlots), slot.isAvailable]
          );
        }
      }

      console.log("✅ 空き時間設定完了");
      return {success: true};
    } catch (error) {
      console.error("❌ 空き時間設定エラー:", error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError("internal", "空き時間の設定に失敗しました");
    }
  }
);

/**
 * 2人のユーザーの共通の空き時間を自動判定するFirebase Function
 */
export const suggestDateTimes = onCall(
  async (request: CallableRequest<{
    partnerId: string;
    daysAhead?: number; // 何日先まで提案するか（デフォルト: 14日）
  }>): Promise<{
    suggestions: DateSuggestion[];
    message: string;
  }> => {
    console.log("🔍 suggestDateTimes関数開始");

    try {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "認証が必要です");
      }

      const firebaseUid = request.auth.uid;
      const {partnerId, daysAhead = 14} = request.data;

      console.log("🔍 日程提案パラメータ:", {firebaseUid, partnerId, daysAhead});

      // Firebase UIDからユーザーUUIDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }

      // 両方のユーザーの空き時間を取得
      const availabilityQuery = `
        SELECT user_id, day_of_week, time_slots, is_available
        FROM user_availability 
        WHERE user_id IN ($1, $2) AND is_available = true
        ORDER BY user_id, day_of_week
      `;

      const availabilityResult = await pool.query(availabilityQuery, [userUuid, partnerId]);
      console.log("🔍 取得した空き時間データ:", availabilityResult.rows.length, "件");

      if (availabilityResult.rows.length === 0) {
        return {
          suggestions: [],
          message: "お互いの空き時間が設定されていません。まず空き時間を設定してください。",
        };
      }

      // ユーザーごとに空き時間を整理
      const userAvailability = new Map<string, Map<number, string[]>>();

      for (const row of availabilityResult.rows) {
        if (!userAvailability.has(row.user_id)) {
          userAvailability.set(row.user_id, new Map());
        }
        const timeSlots = JSON.parse(row.time_slots);
        userAvailability.get(row.user_id)!.set(row.day_of_week, timeSlots);
      }

      // 共通の空き時間を計算
      const suggestions: DateSuggestion[] = [];
      const today = new Date();

      for (let dayOffset = 1; dayOffset <= daysAhead; dayOffset++) {
        const targetDate = new Date(today);
        targetDate.setDate(today.getDate() + dayOffset);
        const dayOfWeek = targetDate.getDay();

        // 両方のユーザーがその曜日に空いているかチェック
        const user1Slots = userAvailability.get(userUuid)?.get(dayOfWeek) || [];
        const user2Slots = userAvailability.get(partnerId)?.get(dayOfWeek) || [];

        // 共通の時間帯を見つける
        const commonSlots = user1Slots.filter((slot) => user2Slots.includes(slot));

        for (const timeSlot of commonSlots) {
          // 信頼度を計算（今後の機能拡張用）
          const confidence = 0.8; // 基本的な信頼度

          suggestions.push({
            date: targetDate.toISOString().split("T")[0],
            timeSlot,
            confidence,
          });
        }
      }

      // 信頼度順にソート
      suggestions.sort((a, b) => b.confidence - a.confidence);

      // 最大5つの提案に制限
      const limitedSuggestions = suggestions.slice(0, 5);

      const message = limitedSuggestions.length > 0 ?
        `${limitedSuggestions.length}つの日程候補が見つかりました！` :
        "お互いに都合の良い時間が見つかりませんでした。空き時間を調整してみてください。";

      console.log("✅ 日程提案完了:", limitedSuggestions.length, "件");
      return {
        suggestions: limitedSuggestions,
        message,
      };
    } catch (error) {
      console.error("❌ 日程提案エラー:", error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError("internal", "日程提案の生成に失敗しました");
    }
  }
);


// 予約代行用のインターフェース

interface ReservationResponse {
  success: boolean;
  reservationId?: string;
  confirmationNumber?: string;
  message: string;
  estimatedCallTime?: number; // 予約電話にかかる予想時間（分）
}

/**
 * レストラン予約代行を行うFirebase Function
 */
export const requestReservation = onCall(
  async (request: CallableRequest<{
    matchId: string;
    restaurantId: string;
    dateTime: string;
    partySize: number;
    specialRequests?: string;
    customerName: string;
    customerPhone: string;
    paymentOption: "treat" | "split" | "discuss";
  }>): Promise<ReservationResponse> => {
    console.log("🔍 requestReservation関数開始");

    try {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "認証が必要です");
      }

      const firebaseUid = request.auth.uid;
      const {
        matchId,
        restaurantId,
        dateTime,
        partySize,
        specialRequests,
        customerName,
        customerPhone,
        paymentOption,
      } = request.data;

      console.log("🔍 予約代行パラメータ:", {
        firebaseUid,
        matchId,
        restaurantId,
        dateTime,
        partySize,
        paymentOption,
      });

      // Firebase UIDからユーザーUUIDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }

      // レストラン情報を取得
      const restaurantQuery = `
        SELECT id, name, phone, address, prefecture, category, 
               reservation_policy, average_prep_time
        FROM restaurants 
        WHERE id = $1
      `;

      const restaurantResult = await pool.query(restaurantQuery, [restaurantId]);

      if (restaurantResult.rows.length === 0) {
        throw new HttpsError("not-found", "レストランが見つかりません");
      }

      const restaurant = restaurantResult.rows[0];
      console.log("🔍 レストラン情報:", restaurant.name);

      // 予約リクエストをデータベースに保存
      const reservationId = await saveReservationRequest({
        userUuid,
        matchId,
        restaurantId,
        dateTime,
        partySize,
        specialRequests,
        customerName,
        customerPhone,
        paymentOption,
        restaurant,
      });

      // 予約代行の種類を判定
      const reservationType = determineReservationType(restaurant);

      let result: ReservationResponse;

      switch (reservationType) {
      case "auto":
        // 自動予約（提携レストラン）
        result = await processAutoReservation(reservationId, restaurant, {
          dateTime,
          partySize,
          specialRequests,
          customerName,
          customerPhone,
          paymentOption,
        });
        break;

      case "staff":
        // スタッフ代行予約
        result = await processStaffReservation(reservationId, restaurant, {
          dateTime,
          partySize,
          specialRequests,
          customerName,
          customerPhone,
          paymentOption,
        });
        break;

      case "manual":
        // 手動予約（ユーザー自身）
        result = await processManualReservation(reservationId, restaurant, {
          dateTime,
          partySize,
          specialRequests,
          customerName,
          customerPhone,
          paymentOption,
        });
        break;

      default:
        throw new HttpsError("internal", "予約方法を判定できませんでした");
      }

      // 予約結果をデータベースに更新
      await updateReservationStatus(reservationId, result);

      console.log("✅ 予約代行完了:", result);
      return result;
    } catch (error) {
      console.error("❌ 予約代行エラー:", error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError("internal", "予約代行の処理に失敗しました");
    }
  }
);

/**
 * 予約リクエストをデータベースに保存
 */
async function saveReservationRequest(data: {
  userUuid: string;
  matchId: string;
  restaurantId: string;
  dateTime: string;
  partySize: number;
  specialRequests?: string;
  customerName: string;
  customerPhone: string;
  paymentOption: string;
  restaurant: any;
}): Promise<string> {
  const insertQuery = `
    INSERT INTO reservation_requests 
    (id, user_id, match_id, restaurant_id, restaurant_name, 
     reservation_datetime, party_size, special_requests, 
     customer_name, customer_phone, payment_option, 
     status, created_at, updated_at)
    VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 
            'pending', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    RETURNING id
  `;

  const result = await pool.query(insertQuery, [
    data.userUuid,
    data.matchId,
    data.restaurantId,
    data.restaurant.name,
    data.dateTime,
    data.partySize,
    data.specialRequests || null,
    data.customerName,
    data.customerPhone,
    data.paymentOption,
  ]);

  return result.rows[0].id;
}

/**
 * 予約方法を判定
 */
function determineReservationType(restaurant: any): "auto" | "staff" | "manual" {
  // 提携レストランかどうかチェック
  if (restaurant.reservation_policy === "auto") {
    return "auto";
  }

  // 電話番号があるかチェック
  if (restaurant.phone && restaurant.phone.trim() !== "") {
    return "staff";
  }

  // 手動予約
  return "manual";
}

/**
 * 自動予約処理（提携レストラン）
 */
async function processAutoReservation(
  reservationId: string,
  restaurant: any,
  data: any
): Promise<ReservationResponse> {
  console.log("🔍 自動予約処理開始:", restaurant.name);

  // 実際の提携システムとの連携（模擬実装）
  // 本番環境では外部APIとの連携を実装

  const confirmationNumber = `AUTO-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;

  return {
    success: true,
    reservationId,
    confirmationNumber,
    message: `${restaurant.name}の予約が自動で完了しました！確認番号: ${confirmationNumber}`,
    estimatedCallTime: 0,
  };
}

/**
 * スタッフ代行予約処理
 */
async function processStaffReservation(
  reservationId: string,
  restaurant: any,
  data: any
): Promise<ReservationResponse> {
  console.log("🔍 スタッフ代行予約処理開始:", restaurant.name);

  // 予約代行キューに追加
  await addToReservationQueue(reservationId, restaurant, data);

  // 予想待ち時間を計算
  const estimatedCallTime = await calculateEstimatedCallTime();

  return {
    success: true,
    reservationId,
    message: `${restaurant.name}への予約代行を開始しました。スタッフが代わりに予約を取ります。`,
    estimatedCallTime,
  };
}

/**
 * 手動予約処理
 */
async function processManualReservation(
  reservationId: string,
  restaurant: any,
  data: any
): Promise<ReservationResponse> {
  console.log("🔍 手動予約処理開始:", restaurant.name);

  return {
    success: true,
    reservationId,
    message: `${restaurant.name}は手動予約が必要です。お店に直接連絡して予約を取ってください。`,
    estimatedCallTime: 0,
  };
}

/**
 * 予約代行キューに追加
 */
async function addToReservationQueue(
  reservationId: string,
  restaurant: any,
  data: any
): Promise<void> {
  const queueQuery = `
    INSERT INTO reservation_queue 
    (reservation_id, restaurant_phone, priority, created_at)
    VALUES ($1, $2, $3, CURRENT_TIMESTAMP)
  `;

  // 優先度計算（予約日時が近いほど高い）
  const reservationDate = new Date(data.dateTime);
  const now = new Date();
  const hoursUntilReservation = (reservationDate.getTime() - now.getTime()) / (1000 * 60 * 60);
  const priority = Math.max(1, Math.min(10, Math.round(10 - (hoursUntilReservation / 24))));

  await pool.query(queueQuery, [reservationId, restaurant.phone, priority]);
}

/**
 * 予想待ち時間を計算
 */
async function calculateEstimatedCallTime(): Promise<number> {
  const queueCountQuery = `
    SELECT COUNT(*) as queue_count 
    FROM reservation_queue 
    WHERE status = 'pending'
  `;

  const result = await pool.query(queueCountQuery);
  const queueCount = parseInt(result.rows[0]?.queue_count || "0");

  // 1件あたり平均5分として計算
  return Math.max(5, queueCount * 5);
}

/**
 * 予約結果をデータベースに更新
 */
async function updateReservationStatus(
  reservationId: string,
  result: ReservationResponse
): Promise<void> {
  const updateQuery = `
    UPDATE reservation_requests 
    SET status = $1, 
        confirmation_number = $2,
        response_message = $3,
        estimated_call_time = $4,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = $5
  `;

  const status = result.success ? "confirmed" : "failed";

  await pool.query(updateQuery, [
    status,
    result.confirmationNumber || null,
    result.message,
    result.estimatedCallTime || null,
    reservationId,
  ]);
}

/**
 * 予約状況を取得するFirebase Function
 */
export const getReservationStatus = onCall(
  async (request: CallableRequest<{
    reservationId: string;
  }>): Promise<{
    status: string;
    message: string;
    confirmationNumber?: string;
    estimatedCallTime?: number;
  }> => {
    try {
      if (!request.auth) {
        throw new functions.https.HttpsError("unauthenticated", "認証が必要です");
      }

      const {reservationId} = request.data;

      const statusQuery = `
        SELECT status, response_message, confirmation_number, estimated_call_time
        FROM reservation_requests 
        WHERE id = $1
      `;

      const result = await pool.query(statusQuery, [reservationId]);

      if (result.rows.length === 0) {
        throw new functions.https.HttpsError("not-found", "予約が見つかりません");
      }

      const reservation = result.rows[0];

      return {
        status: reservation.status,
        message: reservation.response_message || "",
        confirmationNumber: reservation.confirmation_number,
        estimatedCallTime: reservation.estimated_call_time,
      };
    } catch (error) {
      console.error("❌ 予約状況取得エラー:", error);
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }
      throw new functions.https.HttpsError("internal", "予約状況の取得に失敗しました");
    }
  }
);

/**
 * Web版用画像プロキシ機能
 * HotPepperの画像をCORS制限なく取得するためのプロキシ
 */

export const getImageProxy = onRequest(
  {
    cors: [
      "https://delimeet.jp",
      "http://localhost:3000",
      "http://127.0.0.1:3000",
    ],
  },
  async (request, response) => {
    console.log("🔍 getImageProxy関数開始");
    console.log("🔍 Request method:", request.method);

    try {
      // OPTIONSリクエストの処理
      if (request.method === "OPTIONS") {
        response.status(200).send();
        return;
      }

      // POSTリクエストのみ許可
      if (request.method !== "POST") {
        response.status(405).json({
          success: false,
          error: "Method not allowed",
        });
        return;
      }

      // リクエストボディから imageUrl を取得
      console.log("🔍 request.body:", JSON.stringify(request.body, null, 2));
      console.log("🔍 request.body type:", typeof request.body);
      console.log("🔍 request.headers:", JSON.stringify(request.headers, null, 2));
      console.log("🔍 request.rawBody:", request.rawBody);

      // リクエストボディの解析
      let bodyData;
      if (typeof request.body === "string") {
        try {
          bodyData = JSON.parse(request.body);
          console.log("🔍 Parsed body data:", bodyData);
        } catch (e) {
          console.error("❌ JSON解析エラー:", e);
          response.status(400).json({
            success: false,
            error: "リクエストボディのJSON形式が正しくありません",
          });
          return;
        }
      } else {
        bodyData = request.body;
      }

      const {imageUrl} = bodyData || {};
      console.log("🔍 imageUrl extracted:", imageUrl);
      console.log("🔍 imageUrl type:", typeof imageUrl);

      // 入力バリデーション
      if (!imageUrl || typeof imageUrl !== "string") {
        console.error("❌ バリデーション失敗:", {
          imageUrl,
          type: typeof imageUrl,
          isEmpty: !imageUrl,
          isString: typeof imageUrl === "string",
          originalBody: request.body,
          parsedBody: bodyData,
        });
        response.status(400).json({
          success: false,
          error: "画像URLが必要です",
        });
        return;
      }

      // HotPepperとFirebase Storageの画像URLを許可（セキュリティ）
      const allowedDomains = [
        "imgfp.hotp.jp",
        "imgfp.hotpepper.jp",
        "image.hotpepper.jp",
        "firebasestorage.googleapis.com", // Firebase Storage
      ];

      console.log("🔍 URL解析開始:", imageUrl);
      const url = new URL(imageUrl);
      console.log("🔍 parsed URL hostname:", url.hostname);
      console.log("🔍 allowed domains:", allowedDomains);

      if (!allowedDomains.includes(url.hostname)) {
        console.error("❌ ドメインバリデーション失敗:", {
          hostname: url.hostname,
          allowedDomains,
          imageUrl,
        });
        response.status(400).json({
          success: false,
          error: "許可されていないドメインです",
        });
        return;
      }
      console.log("✅ ドメインバリデーション成功");

      // HotPepperドメイン判定
      const isHotPepperImage = url.hostname.includes("hotp.jp") || url.hostname.includes("hotpepper.jp");

      // HotPepperの画像に対する特別なヘッダー設定
      const requestHeaders = isHotPepperImage ? {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "image/webp,image/apng,image/jpeg,image/png,*/*;q=0.8",
        "Accept-Language": "ja-JP,ja;q=0.9,en;q=0.8",
        "Referer": "https://www.hotpepper.jp/",
        "Sec-Fetch-Dest": "image",
        "Sec-Fetch-Mode": "no-cors",
        "Sec-Fetch-Site": "same-site",
      } : {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "image/webp,image/apng,image/*,*/*;q=0.8",
        "Accept-Language": "ja-JP,ja;q=0.9,en;q=0.8",
      };

      console.log("🔍 リクエストヘッダー:", requestHeaders);

      // リトライ機能付きの画像取得
      let axiosResponse: any = null;
      let retryCount = 0;
      const maxRetries = isHotPepperImage ? 3 : 1;

      while (retryCount <= maxRetries) {
        try {
          axiosResponse = await axios.get(imageUrl, {
            responseType: "arraybuffer",
            timeout: isHotPepperImage ? 15000 : 10000, // HotPepperは少し長めのタイムアウト
            headers: requestHeaders,
            maxContentLength: 10 * 1024 * 1024, // 10MB制限
            maxBodyLength: 10 * 1024 * 1024,
          });
          break; // 成功した場合はループを抜ける
        } catch (error) {
          retryCount++;
          const errorMessage = error instanceof Error ? error.message : "Unknown error";
          console.log(`🔄 リトライ ${retryCount}/${maxRetries} for ${imageUrl}:`, errorMessage);

          if (retryCount > maxRetries) {
            throw error; // 最大リトライ回数に達した場合は例外を投げる
          }

          // リトライ前に少し待機
          await new Promise((resolve) => setTimeout(resolve, 1000 * retryCount));
        }
      }

      if (!axiosResponse) {
        throw new Error("画像の取得に失敗しました");
      }

      // Content-TypeからmimeTypeを取得
      const mimeType = axiosResponse.headers["content-type"] || "image/jpeg";

      // ArrayBufferをBase64に変換
      const buffer = Buffer.from(axiosResponse.data, "binary");

      // サイズチェック（5MB制限）
      if (buffer.length > 5 * 1024 * 1024) {
        console.error("❌ 画像サイズが大きすぎます:", {
          size: buffer.length,
          url: imageUrl,
        });
        response.status(400).json({
          success: false,
          error: "画像サイズが大きすぎます（5MB以下にしてください）",
        });
        return;
      }

      const base64Data = buffer.toString("base64");

      console.log("✅ 画像取得成功:", {
        size: buffer.length,
        mimeType,
        url: imageUrl,
        retryCount: retryCount,
        isHotPepperImage,
      });

      response.json({
        success: true,
        imageData: base64Data,
        mimeType,
      });
    } catch (error) {
      console.error("❌ 画像プロキシエラー:", error);

      const err = error as Error;
      console.error("❌ エラー詳細:", {
        name: err.name,
        message: err.message,
        stack: err.stack,
      });

      // axios エラーの場合は詳細情報を取得
      if (axios.isAxiosError(error)) {
        const axiosError = error;
        console.error("❌ Axiosエラー詳細:", {
          status: axiosError.response?.status,
          statusText: axiosError.response?.statusText,
          data: axiosError.response?.data,
        });

        response.status(500).json({
          success: false,
          error: `画像の取得に失敗しました: ${axiosError.response?.status || "Network Error"}`,
        });
        return;
      }

      response.status(500).json({
        success: false,
        error: `画像の取得に失敗しました: ${err.message}`,
      });
    }
  },
);

/**
 * 予約代行リクエストを処理する関数
 * グルメコンシェルジュサービスとの連携を行う
 */
export const requestReservationConcierge = onCall(async (request: CallableRequest<{
  dateRequestId: string;
  restaurantName: string;
  restaurantId?: string;
  selectedDateTime: string;
  partySize?: number;
  specialRequests?: string;
  userPreferences?: any;
}>): Promise<{
  success: boolean;
  reservationRequestId: string;
  message: string;
  estimatedResponseTime: string;
}> => {
  try {
    // 認証チェック
    if (!request.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated to request reservation."
      );
    }

    const {
      dateRequestId,
      restaurantName,
      restaurantId,
      selectedDateTime,
      partySize = 2,
      specialRequests = "",
      userPreferences = {},
    } = request.data;

    // 必須パラメータチェック
    if (!dateRequestId || !restaurantName || !selectedDateTime) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Missing required parameters: dateRequestId, restaurantName, selectedDateTime"
      );
    }

    const userId = request.auth.uid;

    // 予約代行リクエストをデータベースに保存
    const reservationRequestRef = admin.firestore().collection("reservation_requests").doc();
    const reservationRequest = {
      id: reservationRequestRef.id,
      userId: userId,
      dateRequestId: dateRequestId,
      restaurantName: restaurantName,
      restaurantId: restaurantId || null,
      selectedDateTime: admin.firestore.Timestamp.fromDate(new Date(selectedDateTime)),
      partySize: partySize,
      specialRequests: specialRequests,
      userPreferences: userPreferences,
      status: "pending", // pending, processing, confirmed, failed
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      // 予約代行サービス情報
      conciergeService: {
        provider: "DelimeatConcierge", // 独自のコンシェルジュサービス
        assignedStaff: null,
        contactAttempts: 0,
        lastContactAt: null,
        estimatedResponseTime: "15-30分",
        priority: "standard",
      },
    };

    // Firestoreに保存
    await reservationRequestRef.set(reservationRequest);

    // 予約代行スタッフに通知を送信
    await notifyReservationStaff(reservationRequest);

    // ユーザーに確認メッセージを送信
    await sendReservationConfirmationMessage(userId, dateRequestId, reservationRequest);

    // 外部予約サービスとの連携を開始
    await initiateExternalReservationService(reservationRequest);

    return {
      success: true,
      reservationRequestId: reservationRequest.id,
      message: "Dineスタッフが予約手続きを開始しました。15-30分以内にご連絡いたします。",
      estimatedResponseTime: "15-30分",
    };
  } catch (error) {
    console.error("Error in requestReservation:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Failed to process reservation request",
      error instanceof Error ? error.message : "Unknown error"
    );
  }
});

/**
 * 予約代行スタッフに通知を送信
 */
async function notifyReservationStaff(reservationRequest: any): Promise<void> {
  try {
    console.log("🔔 予約代行スタッフに通知送信:", {
      requestId: reservationRequest.id,
      restaurant: reservationRequest.restaurantName,
      dateTime: reservationRequest.selectedDateTime,
      partySize: reservationRequest.partySize,
    });

    // 予約代行チーム用のコレクションに追加
    await admin.firestore()
      .collection("staff_notifications")
      .add({
        type: "reservation_request",
        requestId: reservationRequest.id,
        restaurantName: reservationRequest.restaurantName,
        dateTime: reservationRequest.selectedDateTime,
        partySize: reservationRequest.partySize,
        priority: "high",
        status: "unread",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
  } catch (error) {
    console.error("Error notifying reservation staff:", error);
  }
}

/**
 * ユーザーに予約確認メッセージを送信
 */
async function sendReservationConfirmationMessage(userId: string, dateRequestId: string, reservationRequest: any): Promise<void> {
  try {
    // date_requestsから関連情報を取得
    const dateRequestDoc = await admin.firestore()
      .collection("date_requests")
      .doc(dateRequestId)
      .get();

    if (!dateRequestDoc.exists) {
      throw new Error("Date request not found");
    }

    const dateRequestData = dateRequestDoc.data();
    const matchId = dateRequestData?.match_id;

    if (!matchId) {
      throw new Error("Match ID not found");
    }

    // システムメッセージを送信
    const systemMessage = {
      sender_id: "system",
      receiver_id: userId,
      match_id: matchId,
      message: `🎉 予約代行を承りました！\n\n📍 ${reservationRequest.restaurantName}\n📅 ${reservationRequest.selectedDateTime.toDate().toLocaleString("ja-JP")}\n👥 ${reservationRequest.partySize}名\n\nDineスタッフが予約手続きを開始いたします。\n通常15-30分以内にご連絡いたします。`,
      message_type: "system",
      reservation_data: {
        requestId: reservationRequest.id,
        status: "processing",
        restaurantName: reservationRequest.restaurantName,
        dateTime: reservationRequest.selectedDateTime,
        partySize: reservationRequest.partySize,
      },
      sent_at: admin.firestore.FieldValue.serverTimestamp(),
      read_at: null,
    };

    await admin.firestore()
      .collection("messages")
      .add(systemMessage);
  } catch (error) {
    console.error("Error sending reservation confirmation:", error);
  }
}

/**
 * 外部予約サービスとの連携を開始
 */
async function initiateExternalReservationService(reservationRequest: any): Promise<void> {
  try {
    // レストラン情報に基づいて最適なプロバイダーを選択
    const selectedProvider = await selectOptimalProvider(
      reservationRequest.restaurantName,
      reservationRequest.restaurantId
    );

    console.log("🔄 外部予約サービス連携開始:", {
      provider: selectedProvider,
      restaurant: reservationRequest.restaurantName,
      requestId: reservationRequest.id,
    });

    // 予約リクエストステータスを更新
    await admin.firestore()
      .collection("reservation_requests")
      .doc(reservationRequest.id)
      .update({
        "conciergeService.provider": selectedProvider,
        "conciergeService.lastContactAt": admin.firestore.FieldValue.serverTimestamp(),
        "status": "processing",
        "updatedAt": admin.firestore.FieldValue.serverTimestamp(),
      });

    // 実際の予約処理を非同期で実行
    processReservationAsync(reservationRequest.id, selectedProvider);
  } catch (error) {
    console.error("Error initiating external reservation service:", error);
  }
}

/**
 * 最適な予約プロバイダーを選択
 */
async function selectOptimalProvider(restaurantName: string, restaurantId?: string): Promise<string> {
  if (restaurantName.includes("海外") || restaurantName.includes("外国")) {
    return "OpenTable";
  } else if (restaurantName.includes("チェーン")) {
    return "HotPepper";
  } else {
    return "DirectCall"; // デフォルトは直接電話
  }
}

/**
 * 非同期で予約処理を実行
 */
function processReservationAsync(requestId: string, provider: string): void {
  try {
    setTimeout(async () => {
      try {
        // 予約成功をシミュレート（実際はAPI呼び出し結果）
        const success = Math.random() > 0.2; // 80%の成功率

        if (success) {
          await handleReservationSuccess(requestId, provider);
        } else {
          await handleReservationFailure(requestId, provider);
        }
      } catch (error) {
        console.error("Error in async reservation processing:", error);
        await handleReservationFailure(requestId, provider, error instanceof Error ? error.message : "Unknown error");
      }
    }, Math.random() * 1800000 + 900000); // 15-30分後にランダムで完了
  } catch (error) {
    console.error("Error in processReservationAsync:", error);
  }
}

/**
 * 予約成功時の処理
 */
async function handleReservationSuccess(requestId: string, provider: string): Promise<void> {
  try {
    const reservationDoc = await admin.firestore()
      .collection("reservation_requests")
      .doc(requestId)
      .get();

    if (!reservationDoc.exists) return;

    const reservationData = reservationDoc.data();

    // 予約成功情報を更新
    await admin.firestore()
      .collection("reservation_requests")
      .doc(requestId)
      .update({
        "status": "confirmed",
        "conciergeService.contactAttempts": admin.firestore.FieldValue.increment(1),
        "conciergeService.lastContactAt": admin.firestore.FieldValue.serverTimestamp(),
        "confirmedAt": admin.firestore.FieldValue.serverTimestamp(),
        "reservationDetails": {
          confirmationNumber: `DM${Date.now()}`,
          provider: provider,
          specialInstructions: "予約確定のお知らせをお送りしました",
        },
        "updatedAt": admin.firestore.FieldValue.serverTimestamp(),
      });

    // ユーザーに成功通知を送信
    await sendReservationSuccessNotification(reservationData);
  } catch (error) {
    console.error("Error handling reservation success:", error);
  }
}

/**
 * 予約失敗時の処理
 */
async function handleReservationFailure(requestId: string, provider: string, errorMessage = ""): Promise<void> {
  try {
    const reservationDoc = await admin.firestore()
      .collection("reservation_requests")
      .doc(requestId)
      .get();

    if (!reservationDoc.exists) return;

    const reservationData = reservationDoc.data();

    // 予約失敗情報を更新
    await admin.firestore()
      .collection("reservation_requests")
      .doc(requestId)
      .update({
        "status": "failed",
        "conciergeService.contactAttempts": admin.firestore.FieldValue.increment(1),
        "conciergeService.lastContactAt": admin.firestore.FieldValue.serverTimestamp(),
        "failureReason": errorMessage || "予約が取れませんでした",
        "updatedAt": admin.firestore.FieldValue.serverTimestamp(),
      });

    // ユーザーに代替案を提案
    await sendAlternativeReservationOptions(reservationData);
  } catch (error) {
    console.error("Error handling reservation failure:", error);
  }
}

/**
 * 予約成功通知を送信
 */
async function sendReservationSuccessNotification(reservationData: any): Promise<void> {
  try {
    // date_requestsから関連情報を取得
    const dateRequestDoc = await admin.firestore()
      .collection("date_requests")
      .doc(reservationData.dateRequestId)
      .get();

    if (!dateRequestDoc.exists) return;

    const dateRequestData = dateRequestDoc.data();

    // 成功通知メッセージを送信
    const successMessage = {
      sender_id: "system",
      receiver_id: reservationData.userId,
      match_id: dateRequestData?.match_id,
      message: `🎉 予約が確定しました！\n\n📍 ${reservationData.restaurantName}\n📅 ${reservationData.selectedDateTime.toDate().toLocaleString("ja-JP")}\n👥 ${reservationData.partySize}名\n\n確認番号: ${reservationData.reservationDetails?.confirmationNumber}\n\n素敵なデートをお楽しみください！`,
      message_type: "system",
      reservation_data: {
        requestId: reservationData.id,
        status: "confirmed",
        confirmationNumber: reservationData.reservationDetails?.confirmationNumber,
        restaurantName: reservationData.restaurantName,
        dateTime: reservationData.selectedDateTime,
        partySize: reservationData.partySize,
      },
      sent_at: admin.firestore.FieldValue.serverTimestamp(),
      read_at: null,
    };

    await admin.firestore()
      .collection("messages")
      .add(successMessage);

    // 予約確定の通知はシステムメッセージで送信済み
  } catch (error) {
    console.error("Error sending success notification:", error);
  }
}

/**
 * 代替案提案を送信
 */
async function sendAlternativeReservationOptions(reservationData: any): Promise<void> {
  try {
    // date_requestsから関連情報を取得
    const dateRequestDoc = await admin.firestore()
      .collection("date_requests")
      .doc(reservationData.dateRequestId)
      .get();

    if (!dateRequestDoc.exists) return;

    const dateRequestData = dateRequestDoc.data();

    // 代替案メッセージを送信
    const alternativeMessage = {
      sender_id: "system",
      receiver_id: reservationData.userId,
      match_id: dateRequestData?.match_id,
      message: `申し訳ございません。${reservationData.restaurantName}の予約が取れませんでした。\n\n以下の代替案をご提案いたします：\n\n1️⃣ 別の日時での予約\n2️⃣ 近隣の類似レストラン\n3️⃣ 同じ料理ジャンルの別店舗\n\nDineスタッフがお客様のご希望に合う最適な選択肢をご提案いたします。`,
      message_type: "system",
      reservation_data: {
        requestId: reservationData.id,
        status: "needs_alternative",
        originalRestaurant: reservationData.restaurantName,
        originalDateTime: reservationData.selectedDateTime,
        partySize: reservationData.partySize,
      },
      sent_at: admin.firestore.FieldValue.serverTimestamp(),
      read_at: null,
    };

    await admin.firestore()
      .collection("messages")
      .add(alternativeMessage);
  } catch (error) {
    console.error("Error sending alternative options:", error);
  }
}

/**
 * 予約案内情報を取得する関数
 * ホットペッパー等の予約サイトへの案内を行う
 */
export const getReservationGuidance = onCall(async (request: CallableRequest<{
  requestId: string;
  restaurantName: string;
  restaurantId?: string;
}>): Promise<{
  success: boolean;
  reservationOptions: any[];
  message: string;
}> => {
  try {
    console.log("🔍 getReservationGuidance 開始:", request.data);

    // 認証チェック
    if (!request.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated to get reservation guidance."
      );
    }

    const {
      requestId,
      restaurantName,
      restaurantId,
    } = request.data;

    console.log("🔍 パラメータ:", {
      requestId,
      restaurantName,
      restaurantId,
    });

    // 必須パラメータチェック
    if (!requestId || !restaurantName) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Missing required parameters: requestId, restaurantName"
      );
    }

    const userId = request.auth.uid;
    console.log("🔍 ユーザーID:", userId);

    // データベースからレストラン情報を取得
    let restaurantInfo = null;
    let hotpepperUrl = null;
    let phoneNumber = null;

    try {
      // PostgreSQLからレストラン情報を取得（phone_numberも含む）
      let restaurantResult;

      if (restaurantId) {
        // レストランIDがある場合は確実にIDで検索
        console.log("🔍 レストランIDで検索:", restaurantId);
        const restaurantQuery = `
          SELECT id, name, hotpepper_url, phone_number 
          FROM restaurants 
          WHERE id = $1 
          LIMIT 1
        `;
        restaurantResult = await pool.query(restaurantQuery, [restaurantId]);
      } else {
        // レストランIDがない場合は従来の名前検索（フォールバック）
        console.log("🔍 レストラン名で検索（フォールバック）:", restaurantName);

        // まず完全一致を試す
        let restaurantQuery = `
          SELECT id, name, hotpepper_url, phone_number 
          FROM restaurants 
          WHERE name = $1 
          LIMIT 1
        `;
        restaurantResult = await pool.query(restaurantQuery, [restaurantName]);

        // 完全一致が見つからない場合は部分一致検索
        if (restaurantResult.rows.length === 0) {
          restaurantQuery = `
            SELECT id, name, hotpepper_url, phone_number 
            FROM restaurants 
            WHERE name ILIKE $1 
            ORDER BY char_length(name) ASC
            LIMIT 1
          `;
          const searchPattern = `%${restaurantName}%`;
          console.log("🔍 部分一致検索パターン:", searchPattern);
          restaurantResult = await pool.query(restaurantQuery, [searchPattern]);
        }
      }

      console.log("🔍 クエリ結果件数:", restaurantResult.rows.length);

      if (restaurantResult.rows.length > 0) {
        restaurantInfo = restaurantResult.rows[0];
        hotpepperUrl = restaurantInfo.hotpepper_url;
        phoneNumber = restaurantInfo.phone_number; // DBから直接取得

        console.log("🔍 レストラン情報取得成功:", {
          id: restaurantInfo.id,
          name: restaurantInfo.name,
          hotpepperUrl: hotpepperUrl || "null",
          hotpepperUrlLength: hotpepperUrl ? hotpepperUrl.length : 0,
          phoneNumber: phoneNumber || "null",
          phoneNumberLength: phoneNumber ? phoneNumber.length : 0,
        });
      } else {
        console.log("🔍 レストラン情報が見つかりません");

        // 類似する名前のレストランを検索してデバッグ
        const debugQuery = `
          SELECT name
          FROM restaurants
          WHERE name ILIKE $1
          LIMIT 5
        `;
        const debugResult = await pool.query(debugQuery, ["%猫%"]);
        console.log("🔍 '猫'を含むレストラン:", debugResult.rows.map((r) => r.name));
      }
    } catch (error) {
      console.error("レストラン情報取得エラー:", error);
    }

    // 予約オプションを構築
    const reservationOptions = [];

    // ホットペッパー予約オプション（DBのURLを優先使用）
    if (hotpepperUrl && hotpepperUrl.trim() !== "") {
      reservationOptions.push({
        platform: "ホットペッパーグルメ",
        type: "web",
        url: hotpepperUrl.trim(),
        description: "ネット予約可能・ポイント付与",
        priority: 1,
        icon: "web",
      });
      console.log("🔍 ホットペッパーDB URL使用:", hotpepperUrl.trim());
    } else {
      // DBにURLがない場合は検索URLを使用
      const searchUrl = `https://www.hotpepper.jp/strJ001/?sw=${encodeURIComponent(restaurantName)}`;
      reservationOptions.push({
        platform: "ホットペッパーグルメ",
        type: "web",
        url: searchUrl,
        description: "ネット予約可能・ポイント付与",
        priority: 1,
        icon: "web",
      });
      console.log("🔍 ホットペッパー検索URL使用:", searchUrl);
    }

    // 電話予約オプション（DBから取得した電話番号を使用）
    console.log("🔍 電話番号チェック:", {
      phoneNumber: phoneNumber,
      type: typeof phoneNumber,
      length: phoneNumber ? phoneNumber.length : 0,
      trimmed: phoneNumber ? phoneNumber.trim() : "null",
      isEmpty: phoneNumber ? phoneNumber.trim() === "" : true,
    });

    if (phoneNumber && phoneNumber.trim() !== "") {
      reservationOptions.push({
        platform: "電話予約",
        type: "phone",
        phoneNumber: phoneNumber.trim(),
        description: `${restaurantName}に直接電話`,
        priority: 2,
        icon: "phone",
      });
      console.log("🔍 電話番号付きオプション追加:", phoneNumber.trim());
    } else {
      console.log("🔍 電話番号なし、電話オプションをスキップ");
      console.log("🔍 電話番号なしの理由:", {
        isNull: phoneNumber === null,
        isUndefined: phoneNumber === undefined,
        isEmpty: phoneNumber === "",
        isEmptyAfterTrim: phoneNumber ? phoneNumber.trim() === "" : "phoneNumber is falsy",
      });
      // 電話番号がない場合はオプションを追加しない
    }

    // 優先度順にソート
    reservationOptions.sort((a, b) => a.priority - b.priority);

    console.log("🔍 予約オプション生成完了:", reservationOptions.length, "件");

    return {
      success: true,
      reservationOptions,
      message: "予約案内を取得しました。お好みの方法で予約をお取りください。",
    };
  } catch (error) {
    console.error("Error in getReservationGuidance:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Failed to get reservation guidance",
      error instanceof Error ? error.message : "Unknown error"
    );
  }
});

/**
 * 予約完了報告を処理する関数
 */
export const reportReservationCompleted = onCall(async (request: CallableRequest<{
  dateRequestId: string;
  confirmationNumber?: string;
  reservationDetails?: string;
}>): Promise<{
  success: boolean;
  message: string;
}> => {
  try {
    // 認証チェック
    if (!request.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated to report reservation completion."
      );
    }

    const {
      dateRequestId,
      confirmationNumber = "",
      reservationDetails = "",
    } = request.data;

    // 必須パラメータチェック
    if (!dateRequestId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Missing required parameter: dateRequestId"
      );
    }

    const userId = request.auth.uid;

    console.log("🔍 【予約完了報告】受信パラメータ:", {
      dateRequestId,
      confirmationNumber,
      reservationDetails,
      userId,
    });

    // PostgreSQLのdate_requestsテーブルから関連情報を取得
    console.log("🔍 【予約完了報告】PostgreSQL date_requests検索開始:", dateRequestId);

    let dateRequestData: any;
    let matchId: string;
    try {
      // まずテーブル構造を確認
      const schemaQuery = `
        SELECT column_name, data_type 
        FROM information_schema.columns 
        WHERE table_name = 'date_requests'
        ORDER BY ordinal_position
      `;

      const schemaResult = await pool.query(schemaQuery);
      console.log("🔍 【予約完了報告】date_requestsテーブル構造:", schemaResult.rows);

      const query = `
        SELECT *
        FROM date_requests 
        WHERE id = $1
      `;

      const result = await pool.query(query, [dateRequestId]);
      console.log("🔍 【予約完了報告】PostgreSQL検索結果:", {
        rowCount: result.rowCount,
        rows: result.rows,
      });

      if (result.rowCount === 0) {
        // デバッグのため、date_requestsテーブル内のIDをいくつか確認
        const allQuery = `
          SELECT id, status
          FROM date_requests 
          ORDER BY created_at DESC
          LIMIT 10
        `;
        const allResult = await pool.query(allQuery);
        const existingIds = allResult.rows.map((row) => `${row.id}(${row.status})`);
        console.log("🔍 【予約完了報告】既存のdate_request IDs:", existingIds);

        throw new functions.https.HttpsError(
          "not-found",
          `Date request not found in PostgreSQL. Searched ID: ${dateRequestId}. Recent IDs: ${existingIds.join(", ")}`
        );
      }

      dateRequestData = result.rows[0];
      console.log("🔍 【予約完了報告】取得したdate_request:", dateRequestData);

      matchId = dateRequestData?.match_id;

      if (!matchId) {
        throw new Error("Match ID not found");
      }
    } catch (dbError) {
      console.error("🔍 【予約完了報告】PostgreSQL検索エラー:", dbError);
      throw new functions.https.HttpsError(
        "internal",
        `Database error while searching for date request: ${dbError}`
      );
    }

    // 予約完了メッセージを構築
    let message = "🎉 予約完了の報告をいただきました！\n\n";
    message += `📍 ${dateRequestData.restaurant_name || dateRequestData.restaurant_data?.name || "レストラン"}\n`;
    message += `📅 ${dateRequestData.accepted_date ? new Date(dateRequestData.accepted_date).toLocaleString("ja-JP") : "日程未定"}\n\n`;

    if (confirmationNumber) {
      message += `予約番号: ${confirmationNumber}\n`;
    }
    if (reservationDetails) {
      message += `詳細: ${reservationDetails}\n`;
    }

    message += "\n素敵なデートをお楽しみください！✨";

    // システムメッセージを送信
    const systemMessage = {
      sender_id: "system",
      receiver_id: userId,
      match_id: matchId,
      message: message,
      message_type: "reservation_completed",
      reservation_completed_data: {
        dateRequestId: dateRequestId,
        confirmationNumber: confirmationNumber,
        reservationDetails: reservationDetails,
        reportedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      sent_at: admin.firestore.FieldValue.serverTimestamp(),
      read_at: null,
    };

    await admin.firestore()
      .collection("messages")
      .add(systemMessage);

    return {
      success: true,
      message: "予約完了を報告しました。素敵なデートをお楽しみください！",
    };
  } catch (error) {
    console.error("Error in reportReservationCompleted:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Failed to report reservation completion",
      error instanceof Error ? error.message : "Unknown error"
    );
  }
});

// 学校検索機能（Supabase対応版）
export const searchSchools = onCall(async (request) => {
  try {
    console.log("🔍 searchSchools: 開始");

    if (!request.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "ユーザーが認証されていません"
      );
    }

    const {query, limit = 20} = request.data;

    if (!query || query.trim().length < 2) {
      return {schools: []};
    }

    const searchQuery = query.trim();
    console.log("🔍 searchSchools: 検索クエリ =", searchQuery);

    // 学校名と別名を含む検索（Supabase対応版）
    const result = await pool.query(`
      WITH school_matches AS (
        -- 正式名称からの完全一致検索
        SELECT DISTINCT
          s.id,
          s.school_name,
          s.school_type,
          s.prefecture_name,
          s.establishment_type,
          s.campus_type,
          s.is_active,
          1 as match_priority,
          s.school_name as matched_name
        FROM schools s
        WHERE s.is_active = true
          AND LOWER(s.school_name) = LOWER($1)
        
        UNION
        
        -- 別名・略称からの完全一致検索
        SELECT DISTINCT
          s.id,
          s.school_name,
          s.school_type,
          s.prefecture_name,
          s.establishment_type,
          s.campus_type,
          s.is_active,
          2 as match_priority,
          sa.alias_name as matched_name
        FROM schools s
        JOIN school_aliases sa ON s.id = sa.school_id
        WHERE s.is_active = true
          AND LOWER(sa.alias_name) = LOWER($1)
        
        UNION
        
        -- 正式名称からの前方一致検索
        SELECT DISTINCT
          s.id,
          s.school_name,
          s.school_type,
          s.prefecture_name,
          s.establishment_type,
          s.campus_type,
          s.is_active,
          3 as match_priority,
          s.school_name as matched_name
        FROM schools s
        WHERE s.is_active = true
          AND LOWER(s.school_name) LIKE LOWER($2)
        
        UNION
        
        -- 別名・略称からの前方一致検索
        SELECT DISTINCT
          s.id,
          s.school_name,
          s.school_type,
          s.prefecture_name,
          s.establishment_type,
          s.campus_type,
          s.is_active,
          4 as match_priority,
          sa.alias_name as matched_name
        FROM schools s
        JOIN school_aliases sa ON s.id = sa.school_id
        WHERE s.is_active = true
          AND LOWER(sa.alias_name) LIKE LOWER($2)
        
        UNION
        
        -- 部分一致検索
        SELECT DISTINCT
          s.id,
          s.school_name,
          s.school_type,
          s.prefecture_name,
          s.establishment_type,
          s.campus_type,
          s.is_active,
          5 as match_priority,
          s.school_name as matched_name
        FROM schools s
        WHERE s.is_active = true
          AND LOWER(s.school_name) LIKE LOWER($3)
      )
      SELECT *
      FROM school_matches
      ORDER BY match_priority, 
               CASE 
                 WHEN establishment_type = 'national' THEN 1
                 WHEN establishment_type = 'public' THEN 2
                 WHEN establishment_type = 'private' THEN 3
               END,
               school_name
      LIMIT $4
    `, [
      searchQuery, // 完全一致用
      `${searchQuery}%`, // 前方一致用
      `%${searchQuery}%`, // 部分一致用
      limit,
    ]);

    const schools = result.rows.map((row) => ({
      id: row.id,
      school_name: row.school_name,
      school_type: row.school_type,
      prefecture_name: row.prefecture_name,
      establishment_type: row.establishment_type,
      campus_type: row.campus_type,
      matched_name: row.matched_name,
      display_name: `${row.school_name}${row.campus_type === "branch" ? " (分校)" : ""}`,
      type_label: (() => {
        switch (row.school_type) {
        case "university": return "大学";
        case "graduate_school": return "大学院";
        case "junior_college": return "短期大学";
        case "technical_college": return "高等専門学校";
        default: return "大学";
        }
      })(),
      establishment_label: (() => {
        switch (row.establishment_type) {
        case "national": return "国立";
        case "public": return "公立";
        case "private": return "私立";
        default: return "";
        }
      })(),
    }));

    console.log(`✅ searchSchools: ${schools.length}件の学校を検索`);
    return {schools};
  } catch (error) {
    console.error("🔥 searchSchools エラー:", error);

    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    throw new functions.https.HttpsError(
      "internal",
      "学校検索に失敗しました"
    );
  }
});


