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
    // エラーハンドリング
    console.error("getUserUuidFromFirebaseUid エラー:", error);
    return null;
  }
}

// レビュー投稿
export const submitRestaurantReview = functions.https.onCall(
  async (request: CallableRequest<{
    restaurantId: string;
    rating: number;
    comment?: string;
    visitDate?: string;
    dateRequestId?: string;
    isGroupDate?: boolean;
    isOrganizer?: boolean;
  }>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {
      restaurantId,
      rating,
      comment,
      visitDate,
      dateRequestId,
      isGroupDate = false,
      isOrganizer = false,
    } = request.data;

    // バリデーション
    if (!restaurantId || !rating) {
      throw new HttpsError("invalid-argument", "必要な情報が不足しています");
    }

    if (rating < 1 || rating > 5) {
      throw new HttpsError("invalid-argument", "評価は1-5の範囲で入力してください");
    }

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }

      // 既存のレビューをチェック
      const existingReview = await pool.query(
        `SELECT id FROM restaurant_reviews 
         WHERE user_id = $1 AND restaurant_id = $2`,
        [userUuid, restaurantId]
      );

      if (existingReview.rows.length > 0) {
        throw new HttpsError("already-exists", "既にこのレストランのレビューを投稿済みです");
      }

      // レビューを投稿
      const reviewResult = await pool.query(
        `INSERT INTO restaurant_reviews 
         (user_id, restaurant_id, rating, comment, visit_date, date_request_id, is_group_date, is_organizer)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         RETURNING id`,
        [userUuid, restaurantId, rating, comment, visitDate, dateRequestId, isGroupDate, isOrganizer]
      );

      const reviewId = reviewResult.rows[0].id;

      // 地元案内人バッジの得点を更新
      await updateLocalGuideScore(userUuid, "review", {
        isGroupDate,
        isOrganizer,
      });


      return {
        success: true,
        reviewId,
        message: "レビューを投稿しました",
      };
    } catch (error) {
    // エラーハンドリング
      console.error("❌ レビュー投稿エラー:", error);
      throw new HttpsError("internal", "レビューの投稿に失敗しました");
    }
  }
);

// レビュー一覧取得
export const getRestaurantReviews = functions.https.onCall(
  async (request: CallableRequest<{
    restaurantId: string;
    limit?: number;
    offset?: number;
  }>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const {restaurantId, limit = 20, offset = 0} = request.data;

    if (!restaurantId) {
      throw new HttpsError("invalid-argument", "レストランIDが必要です");
    }

    try {
      // レビュー一覧を取得
      const reviewsResult = await pool.query(
        `SELECT 
           r.id,
           r.user_id,
           r.rating,
           r.comment,
           r.visit_date,
           r.helpful_count,
           r.created_at,
           r.is_group_date,
           r.is_organizer,
           u.name as user_name,
           u.image_url as user_image_url,
           lgb.badge_level,
           lgb.total_score
         FROM restaurant_reviews r
         JOIN users u ON r.user_id = u.id
         LEFT JOIN local_guide_badges lgb ON r.user_id = lgb.user_id
         WHERE r.restaurant_id = $1
         ORDER BY r.created_at DESC
         LIMIT $2 OFFSET $3`,
        [restaurantId, limit, offset]
      );

      // 総レビュー数と平均評価を取得
      const statsResult = await pool.query(
        `SELECT 
           COUNT(*) as total_reviews,
           AVG(rating) as average_rating,
           COUNT(CASE WHEN rating = 5 THEN 1 END) as five_star_count,
           COUNT(CASE WHEN rating = 4 THEN 1 END) as four_star_count,
           COUNT(CASE WHEN rating = 3 THEN 1 END) as three_star_count,
           COUNT(CASE WHEN rating = 2 THEN 1 END) as two_star_count,
           COUNT(CASE WHEN rating = 1 THEN 1 END) as one_star_count
         FROM restaurant_reviews
         WHERE restaurant_id = $1`,
        [restaurantId]
      );

      const stats = statsResult.rows[0];


      return {
        reviews: reviewsResult.rows,
        stats: {
          totalReviews: parseInt(stats.total_reviews),
          averageRating: parseFloat(stats.average_rating || "0"),
          ratingDistribution: {
            fiveStar: parseInt(stats.five_star_count),
            fourStar: parseInt(stats.four_star_count),
            threeStar: parseInt(stats.three_star_count),
            twoStar: parseInt(stats.two_star_count),
            oneStar: parseInt(stats.one_star_count),
          },
        },
      };
    } catch (error) {
    // エラーハンドリング
      console.error("❌ レビュー一覧取得エラー:", error);
      throw new HttpsError("internal", "レビュー一覧の取得に失敗しました");
    }
  }
);

// レビューにいいね
export const likeReview = functions.https.onCall(
  async (request: CallableRequest<{
    reviewId: string;
  }>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {reviewId} = request.data;

    if (!reviewId) {
      throw new HttpsError("invalid-argument", "レビューIDが必要です");
    }

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }

      // レビューが存在するかチェック
      const reviewResult = await pool.query(
        "SELECT user_id FROM restaurant_reviews WHERE id = $1",
        [reviewId]
      );

      if (reviewResult.rows.length === 0) {
        throw new HttpsError("not-found", "レビューが見つかりません");
      }

      // 自分のレビューにはいいねできない
      if (reviewResult.rows[0].user_id === userUuid) {
        throw new HttpsError("invalid-argument", "自分のレビューにはいいねできません");
      }

      // 既にいいね済みかチェック
      const existingLike = await pool.query(
        "SELECT id FROM review_likes WHERE review_id = $1 AND user_id = $2",
        [reviewId, userUuid]
      );

      if (existingLike.rows.length > 0) {
        throw new HttpsError("already-exists", "既にいいね済みです");
      }

      // いいねを追加
      await pool.query(
        "INSERT INTO review_likes (review_id, user_id) VALUES ($1, $2)",
        [reviewId, userUuid]
      );

      // レビュー投稿者の地元案内人バッジの得点を更新
      await updateLocalGuideScore(reviewResult.rows[0].user_id, "helpful");


      return {
        success: true,
        message: "レビューにいいねしました",
      };
    } catch (error) {
    // エラーハンドリング
      console.error("❌ レビューいいねエラー:", error);
      throw new HttpsError("internal", "レビューへのいいねに失敗しました");
    }
  }
);

// レビューのいいねを削除
export const unlikeReview = functions.https.onCall(
  async (request: CallableRequest<{
    reviewId: string;
  }>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {reviewId} = request.data;

    if (!reviewId) {
      throw new HttpsError("invalid-argument", "レビューIDが必要です");
    }

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }

      // いいねを削除
      const deleteResult = await pool.query(
        "DELETE FROM review_likes WHERE review_id = $1 AND user_id = $2",
        [reviewId, userUuid]
      );

      if (deleteResult.rowCount === 0) {
        throw new HttpsError("not-found", "いいねが見つかりません");
      }


      return {
        success: true,
        message: "レビューのいいねを削除しました",
      };
    } catch (error) {
    // エラーハンドリング
      console.error("❌ レビューいいね削除エラー:", error);
      throw new HttpsError("internal", "レビューのいいね削除に失敗しました");
    }
  }
);

// 地元案内人バッジ情報取得
export const getLocalGuideBadge = functions.https.onCall(
  async (request: CallableRequest<{
    userId?: string;
  }>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {userId} = request.data;

    try {
      let targetUserUuid: string;

      if (userId) {
        // 指定されたユーザーのバッジを取得
        targetUserUuid = userId;
      } else {
        // else処理
        // 自分のバッジを取得
        const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
        if (!userUuid) {
          throw new HttpsError("not-found", "ユーザーが見つかりません");
        }
        targetUserUuid = userUuid;
      }

      // バッジ情報を取得
      const badgeResult = await pool.query(
        `SELECT 
           badge_level,
           total_score,
           review_points,
           helpful_points,
           favorite_restaurant_points,
           created_at,
           updated_at
         FROM local_guide_badges
         WHERE user_id = $1`,
        [targetUserUuid]
      );

      if (badgeResult.rows.length === 0) {
        // バッジが存在しない場合は初期バッジを作成
        const newBadgeResult = await pool.query(
          `INSERT INTO local_guide_badges (user_id, badge_level, total_score)
           VALUES ($1, 'bronze', 0)
           RETURNING badge_level, total_score, review_points, helpful_points, favorite_restaurant_points`,
          [targetUserUuid]
        );


        return {
          badge: newBadgeResult.rows[0],
          isNew: true,
        };
      }


      return {
        badge: badgeResult.rows[0],
        isNew: false,
      };
    } catch (error) {
    // エラーハンドリング
      console.error("❌ バッジ情報取得エラー:", error);
      throw new HttpsError("internal", "バッジ情報の取得に失敗しました");
    }
  }
);

/**
 * 地元案内人バッジの得点を更新する関数
 * @param {string} userUuid - ユーザーのUUID
 * @param {string} action - アクションタイプ
 * @param {object} options - オプション
 */
async function updateLocalGuideScore(
  userUuid: string,
  action: "review" | "helpful" | "favorite_restaurant",
  options?: {
    isGroupDate?: boolean;
    isOrganizer?: boolean;
  }
) {
  try {
    // 現在のバッジ情報を取得
    let badgeResult = await pool.query(
      `SELECT id, total_score, review_points, helpful_points, favorite_restaurant_points
       FROM local_guide_badges
       WHERE user_id = $1`,
      [userUuid]
    );

    let pointsToAdd = 0;
    const updateFields: string[] = [];
    const updateValues: any[] = [userUuid];

    if (badgeResult.rows.length === 0) {
      // バッジが存在しない場合は新規作成
      await pool.query(
        `INSERT INTO local_guide_badges (user_id, badge_level, total_score)
         VALUES ($1, 'bronze', 0)`,
        [userUuid]
      );
      badgeResult = await pool.query(
        `SELECT id, total_score, review_points, helpful_points, favorite_restaurant_points
         FROM local_guide_badges
         WHERE user_id = $1`,
        [userUuid]
      );
    }

    // アクションに応じて得点を計算
    switch (action) {
    case "review":
      if (options?.isGroupDate) {
        pointsToAdd = options.isOrganizer ? 10 : 5; // 団体デート: 主催者10点、メンバー5点
      } else {
        // else処理
        pointsToAdd = 5; // 個人デート: 5点
      }
      updateFields.push(`review_points = review_points + $${updateValues.length + 1}`);
      updateValues.push(pointsToAdd);
      break;

    case "helpful":
      pointsToAdd = 3; // レビューの参考になった: 3点
      updateFields.push(`helpful_points = helpful_points + $${updateValues.length + 1}`);
      updateValues.push(pointsToAdd);
      break;

    case "favorite_restaurant":
      pointsToAdd = 5; // お気に入りレストラン設定: 5点
      updateFields.push(`favorite_restaurant_points = favorite_restaurant_points + $${updateValues.length + 1}`);
      updateValues.push(pointsToAdd);
      break;
    }

    // 総得点を更新
    updateFields.push(`total_score = total_score + $${updateValues.length + 1}`);
    updateValues.push(pointsToAdd);

    // バッジ情報を更新
    await pool.query(
      `UPDATE local_guide_badges 
       SET ${updateFields.join(", ")}, updated_at = CURRENT_TIMESTAMP
       WHERE user_id = $1`,
      updateValues
    );
  } catch (error) {
    // エラーハンドリング
    console.error("❌ バッジ得点更新エラー:", error);
    throw error;
  }
}

// レストランの平均評価を取得
export const getRestaurantAverageRating = functions.https.onCall(
  async (request: CallableRequest<{
    restaurantId: string;
  }>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const {restaurantId} = request.data;

    if (!restaurantId) {
      throw new HttpsError("invalid-argument", "レストランIDが必要です");
    }

    try {
      const result = await pool.query(
        `SELECT 
           COUNT(*) as total_reviews,
           AVG(rating) as average_rating
         FROM restaurant_reviews
         WHERE restaurant_id = $1`,
        [restaurantId]
      );

      const stats = result.rows[0];


      return {
        totalReviews: parseInt(stats.total_reviews),
        averageRating: parseFloat(stats.average_rating || "0"),
      };
    } catch (error) {
    // エラーハンドリング
      console.error("❌ 平均評価取得エラー:", error);
      throw new HttpsError("internal", "平均評価の取得に失敗しました");
    }
  }
);

// お気に入りレストラン設定時のバッジ得点更新
export const updateFavoriteRestaurantScore = functions.https.onCall(
  async (request: CallableRequest<{
    restaurantId: string;
  }>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const firebaseUid = request.auth.uid;
    const {restaurantId} = request.data;

    if (!restaurantId) {
      throw new HttpsError("invalid-argument", "レストランIDが必要です");
    }

    try {
      // Firebase UIDからユーザーのUUID IDを取得
      const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
      if (!userUuid) {
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }

      // 既にこのレストランで得点を獲得しているかチェック
      const existingScore = await pool.query(
        `SELECT id FROM local_guide_badges 
         WHERE user_id = $1 AND favorite_restaurant_points > 0`,
        [userUuid]
      );

      if (existingScore.rows.length > 0) {
        return {
          success: true,
          message: "既に得点を獲得済みです",
        };
      }

      // 地元案内人バッジの得点を更新
      await updateLocalGuideScore(userUuid, "favorite_restaurant");


      return {
        success: true,
        message: "地元案内人バッジの得点を更新しました",
      };
    } catch (error) {
    // エラーハンドリング
      console.error("❌ お気に入りレストラン設定時のバッジ得点更新エラー:", error);
      throw new HttpsError("internal", "バッジ得点の更新に失敗しました");
    }
  }
);
