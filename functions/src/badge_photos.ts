import * as functions from "firebase-functions";
import {HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {pool} from "./index";

/**
 * Firebase UIDからユーザーのUUIDを取得する関数
 * @param {string} firebaseUid - Firebase UID
 * @returns {Promise<string | null>} ユーザーのUUID
 */
async function getUserUuidFromFirebaseUid(firebaseUid: string): Promise<string | null> {
  try {
    const result = await pool.query(
      "SELECT id FROM users WHERE firebase_uid = $1",
      [firebaseUid]
    );
    return result.rows.length > 0 ? result.rows[0].id : null;
  } catch (error) {
    console.error("getUserUuidFromFirebaseUid エラー:", error);
    return null;
  }
}

// バッジ写真を設定
export const setBadgePhoto = functions.https.onCall(
  async (request: CallableRequest<{
    restaurantId: string;
    photoUrl: string;
    photoOrder: number;
  }>) => {
    console.log("📸 バッジ写真設定開始");

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {restaurantId, photoUrl, photoOrder} = request.data;

    // バリデーション
    if (!restaurantId || !photoUrl || !photoOrder) {
      throw new HttpsError("invalid-argument", "必要な情報が不足しています");
    }

    if (photoOrder < 1 || photoOrder > 9) {
      throw new HttpsError("invalid-argument", "写真の順序は1-9の範囲で指定してください");
    }

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }

      // レストランが存在するかチェック
      const restaurantResult = await pool.query(
        "SELECT id FROM restaurants WHERE id = $1",
        [restaurantId]
      );

      if (restaurantResult.rows.length === 0) {
        throw new HttpsError("not-found", "レストランが見つかりません");
      }

      // 既存のバッジ写真をチェック（同じ順序で同じレストラン）
      const existingPhoto = await pool.query(
        `SELECT id FROM badge_photos 
         WHERE user_id = $1 AND restaurant_id = $2 AND photo_order = $3`,
        [userUuid, restaurantId, photoOrder]
      );

      if (existingPhoto.rows.length > 0) {
        // 既存の写真を更新
        await pool.query(
          `UPDATE badge_photos 
           SET photo_url = $1, updated_at = CURRENT_TIMESTAMP
           WHERE user_id = $2 AND restaurant_id = $3 AND photo_order = $4`,
          [photoUrl, userUuid, restaurantId, photoOrder]
        );
        console.log(`✅ バッジ写真更新完了: ${existingPhoto.rows[0].id}`);
      } else {
        // 新しい写真を追加
        const photoResult = await pool.query(
          `INSERT INTO badge_photos (user_id, restaurant_id, photo_url, photo_order)
           VALUES ($1, $2, $3, $4)
           RETURNING id`,
          [userUuid, restaurantId, photoUrl, photoOrder]
        );
        console.log(`✅ バッジ写真追加完了: ${photoResult.rows[0].id}`);
      }

      return {
        success: true,
        message: "バッジ写真を設定しました",
      };
    } catch (error) {
      console.error("❌ バッジ写真設定エラー:", error);
      throw new HttpsError("internal", "バッジ写真の設定に失敗しました");
    }
  }
);

// ユーザーのバッジ写真一覧を取得
export const getUserBadgePhotos = functions.https.onCall(
  async (request: CallableRequest<{
    userId?: string;
  }>) => {
    console.log("📸 ユーザーバッジ写真一覧取得開始");

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {userId} = request.data;

    try {
      let targetUserUuid: string;

      if (userId) {
        // 指定されたユーザーのバッジ写真を取得
        targetUserUuid = userId;
      } else {
        // 自分のバッジ写真を取得
        const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
        if (!userUuid) {
          throw new HttpsError("not-found", "ユーザーが見つかりません");
        }
        targetUserUuid = userUuid;
      }

      // バッジ写真一覧を取得
      const photosResult = await pool.query(
        `SELECT 
           bp.id,
           bp.photo_url,
           bp.photo_order,
           bp.created_at,
           r.id as restaurant_id,
           r.name as restaurant_name,
           r.category as restaurant_category,
           r.prefecture as restaurant_prefecture
         FROM badge_photos bp
         JOIN restaurants r ON bp.restaurant_id = r.id
         WHERE bp.user_id = $1
         ORDER BY bp.photo_order`,
        [targetUserUuid]
      );

      console.log(`✅ バッジ写真一覧取得完了: ${photosResult.rows.length}件`);

      return {
        photos: photosResult.rows,
      };
    } catch (error) {
      console.error("❌ バッジ写真一覧取得エラー:", error);
      throw new HttpsError("internal", "バッジ写真一覧の取得に失敗しました");
    }
  }
);

// レストランのバッジ写真一覧を取得
export const getRestaurantBadgePhotos = functions.https.onCall(
  async (request: CallableRequest<{
    restaurantId: string;
  }>) => {
    console.log("📸 レストランバッジ写真一覧取得開始");

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const {restaurantId} = request.data;

    if (!restaurantId) {
      throw new HttpsError("invalid-argument", "レストランIDが必要です");
    }

    try {
      // レストランのバッジ写真一覧を取得
      const photosResult = await pool.query(
        `SELECT 
           bp.id,
           bp.photo_url,
           bp.photo_order,
           bp.created_at,
           u.name as user_name,
           u.image_url as user_image_url,
           lgb.badge_level,
           lgb.total_score
         FROM badge_photos bp
         JOIN users u ON bp.user_id = u.id
         LEFT JOIN local_guide_badges lgb ON bp.user_id = lgb.user_id
         WHERE bp.restaurant_id = $1
         ORDER BY bp.photo_order, bp.created_at DESC`,
        [restaurantId]
      );

      console.log(`✅ レストランバッジ写真一覧取得完了: ${photosResult.rows.length}件`);

      return {
        photos: photosResult.rows,
      };
    } catch (error) {
      console.error("❌ レストランバッジ写真一覧取得エラー:", error);
      throw new HttpsError("internal", "レストランバッジ写真一覧の取得に失敗しました");
    }
  }
);

// バッジ写真を削除
export const deleteBadgePhoto = functions.https.onCall(
  async (request: CallableRequest<{
    photoId: string;
  }>) => {
    console.log("🗑️ バッジ写真削除開始");

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {photoId} = request.data;

    if (!photoId) {
      throw new HttpsError("invalid-argument", "写真IDが必要です");
    }

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }

      // 自分のバッジ写真かチェック
      const photoResult = await pool.query(
        "SELECT id FROM badge_photos WHERE id = $1 AND user_id = $2",
        [photoId, userUuid]
      );

      if (photoResult.rows.length === 0) {
        throw new HttpsError("not-found", "バッジ写真が見つからないか、削除権限がありません");
      }

      // バッジ写真を削除
      await pool.query(
        "DELETE FROM badge_photos WHERE id = $1",
        [photoId]
      );

      console.log(`✅ バッジ写真削除完了: ${photoId}`);

      return {
        success: true,
        message: "バッジ写真を削除しました",
      };
    } catch (error) {
      console.error("❌ バッジ写真削除エラー:", error);
      throw new HttpsError("internal", "バッジ写真の削除に失敗しました");
    }
  }
);
