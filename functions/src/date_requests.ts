import {
  onCall,
  HttpsError,
  CallableRequest,
} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {pool} from "./index";

/**
 * デートリクエスト送信
 */
export const sendDateRequest = onCall(
  async (request: CallableRequest<{
    matchId: string;
    restaurantId: string;
    additionalRestaurantIds?: string[]; // 追加店舗IDs
    message?: string;
    proposedDates: string[]; // ISO 8601 format
    paymentOption?: string; // 支払いオプション
  }>) => {
    console.log("💕 デートリクエスト送信: 開始");

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const {matchId, restaurantId, additionalRestaurantIds, message, proposedDates, paymentOption} = request.data;

    if (!matchId || !restaurantId || !proposedDates ||
        proposedDates.length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "必須パラメータが不足しています",
      );
    }

    if (proposedDates.length > 3) {
      throw new HttpsError(
        "invalid-argument",
        "提案日時は最大3つまでです"
      );
    }

    if (additionalRestaurantIds && additionalRestaurantIds.length > 4) {
      throw new HttpsError(
        "invalid-argument",
        "追加店舗は最大4つまでです"
      );
    }

    try {
      // リクエスト送信者のUUID取得
      const requesterUuid = await getUserUuidFromFirebaseUid(request.auth.uid);
      if (!requesterUuid) {
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }

      // マッチの存在確認と相手ユーザー特定
      const matchResult = await pool.query(
        `SELECT
          CASE
            WHEN user1_id = $1 THEN user2_id
            ELSE user1_id
          END as recipient_id,
          status
         FROM matches
         WHERE id = $2 AND (user1_id = $1 OR user2_id = $1)`,
        [requesterUuid, matchId]
      );

      if (matchResult.rows.length === 0) {
        throw new HttpsError("not-found", "マッチが見つかりません");
      }

      if (matchResult.rows[0].status !== "active") {
        throw new HttpsError(
          "failed-precondition",
          "アクティブでないマッチです",
        );
      }

      const recipientId = matchResult.rows[0].recipient_id;

      // メインレストランの存在確認
      const restaurantResult = await pool.query(
        "SELECT name, image_url, category, prefecture, nearest_station, price_range FROM restaurants WHERE id = $1",
        [restaurantId]
      );

      if (restaurantResult.rows.length === 0) {
        throw new HttpsError("not-found", "レストランが見つかりません");
      }

      // 追加店舗の存在確認
      let additionalRestaurants = [];
      if (additionalRestaurantIds && additionalRestaurantIds.length > 0) {
        const additionalRestaurantsResult = await pool.query(
          `SELECT id, name, image_url, category, prefecture 
           FROM restaurants 
           WHERE id = ANY($1)`,
          [additionalRestaurantIds]
        );
        additionalRestaurants = additionalRestaurantsResult.rows;

        if (additionalRestaurants.length !== additionalRestaurantIds.length) {
          throw new HttpsError("not-found", "一部の追加店舗が見つかりません");
        }
      }

      // 提案日時を配列に変換（最大3つ）
      const dates = proposedDates.slice(0, 3);
      const proposedDate1 = dates[0] || null;
      const proposedDate2 = dates[1] || null;
      const proposedDate3 = dates[2] || null;

      // デートリクエスト作成
      const insertResult = await pool.query(
        `INSERT INTO date_requests 
         (requester_id, recipient_id, match_id, restaurant_id, message, 
          proposed_date_1, proposed_date_2, proposed_date_3, 
          additional_restaurant_ids, payment_option)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
         RETURNING id, created_at`,
        [
          requesterUuid,
          recipientId,
          matchId,
          restaurantId,
          message || null,
          proposedDate1,
          proposedDate2,
          proposedDate3,
          additionalRestaurantIds ? JSON.stringify(additionalRestaurantIds) : null,
          paymentOption || "discuss",
        ]
      );

      const requestId = insertResult.rows[0].id;
      console.log(`✅ デートリクエスト作成成功: ${requestId}`);

      const restaurantDetail = restaurantResult.rows[0];

      // チャットにデートリクエストメッセージを追加
      await insertDateRequestMessage(
        matchId,
        requesterUuid,
        requestId,
        restaurantId,
        restaurantDetail,
        proposedDates,
        message || "",
        additionalRestaurantIds || [],
        paymentOption || "discuss"
      );

      // 相手に通知送信
      await sendDateRequestNotification(
        recipientId,
        requesterUuid,
        restaurantDetail.name,
        message || ""
      );

      return {
        success: true,
        requestId: requestId,
        message: "デートリクエストを送信しました",
      };
    } catch (error) {
      console.error("❌ デートリクエスト送信失敗:", error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError(
        "internal",
        "デートリクエストの送信に失敗しました",
      );
    }
  }
);

/**
 * デートリクエスト一覧取得
 */
export const getDateRequests = onCall(
  async (request: CallableRequest<{
    type?: "sent" | "received"; // 送信したもの or 受信したもの
    status?: string;
  }>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const {type = "received", status} = request.data;

    try {
      const userUuid = await getUserUuidFromFirebaseUid(request.auth.uid);
      if (!userUuid) {
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }

      let query = `
        SELECT 
          dr.id,
          dr.requester_id,
          dr.recipient_id,
          dr.match_id,
          dr.restaurant_id,
          dr.message,
          dr.proposed_date_1,
          dr.proposed_date_2,
          dr.proposed_date_3,
          dr.status,
          dr.response_message,
          dr.accepted_date,
          dr.created_at,
          dr.expires_at,
          
          -- レストラン情報
          r.name as restaurant_name,
          r.image_url as restaurant_image_url,
          r.category as restaurant_category,
          r.prefecture as restaurant_prefecture,
          
          -- 相手ユーザー情報
          CASE 
            WHEN dr.requester_id = $1 THEN recipient.name
            ELSE requester.name
          END as partner_name,
          CASE 
            WHEN dr.requester_id = $1 THEN recipient.image_url
            ELSE requester.image_url
          END as partner_image_url,
          CASE 
            WHEN dr.requester_id = $1 THEN recipient.age
            ELSE requester.age
          END as partner_age
          
        FROM date_requests dr
        LEFT JOIN restaurants r ON dr.restaurant_id = r.id
        LEFT JOIN users requester ON dr.requester_id = requester.id
        LEFT JOIN users recipient ON dr.recipient_id = recipient.id
        WHERE `;

      const params = [userUuid];

      if (type === "sent") {
        query += "dr.requester_id = $1";
      } else {
        query += "dr.recipient_id = $1";
      }

      if (status) {
        query += " AND dr.status = $" + (params.length + 1);
        params.push(status);
      }

      query += " ORDER BY dr.created_at DESC";

      const result = await pool.query(query, params);

      console.log(`✅ デートリクエスト取得成功: ${result.rows.length}件`);
      return {
        requests: result.rows,
        totalCount: result.rows.length,
      };
    } catch (error) {
      console.error("❌ デートリクエスト取得失敗:", error);
      throw new HttpsError("internal", "デートリクエストの取得に失敗しました");
    }
  }
);

/**
 * デートリクエスト回答
 */
export const respondToDateRequest = onCall(
  async (request: CallableRequest<{
    requestId: string;
    response: "vote" | "reject";
    selectedDates?: string[]; // 複数日程選択（投票時）
    responseMessage?: string;
  }>) => {
    console.log("💕 デートリクエスト回答: 開始");

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const {requestId, response, selectedDates, responseMessage} = request.data;

    if (!requestId || !response) {
      throw new HttpsError(
        "invalid-argument",
        "必須パラメータが不足しています"
      );
    }

    if (response === "vote" && (!selectedDates || selectedDates.length === 0)) {
      throw new HttpsError(
        "invalid-argument",
        "投票時は選択日時が必要です"
      );
    }

    try {
      const userUuid = await getUserUuidFromFirebaseUid(request.auth.uid);
      if (!userUuid) {
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }

      // リクエストの存在確認と権限チェック
      const requestResult = await pool.query(
        `SELECT dr.*, requester.name as requester_name, 
         r.name as restaurant_name, r.image_url as restaurant_image_url,
         r.category as restaurant_category, r.prefecture as restaurant_prefecture
         FROM date_requests dr
         LEFT JOIN users requester ON dr.requester_id = requester.id
         LEFT JOIN restaurants r ON dr.restaurant_id = r.id
         WHERE dr.id = $1 AND dr.recipient_id = $2`,
        [requestId, userUuid]
      );

      if (requestResult.rows.length === 0) {
        throw new HttpsError("not-found", "リクエストが見つかりません");
      }

      const dateRequest = requestResult.rows[0];

      if (dateRequest.status !== "pending") {
        throw new HttpsError(
          "failed-precondition",
          "既に回答済みのリクエストです"
        );
      }

      // 期限切れチェック
      if (new Date(dateRequest.expires_at) < new Date()) {
        throw new HttpsError("failed-precondition", "期限切れのリクエストです");
      }

      if (response === "reject") {
        // 辞退の場合
        await pool.query(
          `UPDATE date_requests 
           SET status = 'rejected', response_message = $1, updated_at = CURRENT_TIMESTAMP
           WHERE id = $2`,
          [responseMessage || null, requestId]
        );

        // チャットに辞退メッセージを追加
        await insertDateResponseMessage(
          dateRequest.match_id,
          userUuid,
          requestId,
          "reject",
          "",
          responseMessage || ""
        );

        // リクエスト送信者に通知
        await sendDateResponseNotification(
          dateRequest.requester_id,
          userUuid,
          "reject",
          dateRequest.restaurant_name,
          responseMessage || ""
        );

        return {
          success: true,
          status: "rejected",
          message: "リクエストを断りました",
        };
      } else {
        // 投票の場合
        const selectedDatesJson = JSON.stringify(selectedDates);

        await pool.query(
          `UPDATE date_requests 
           SET status = 'voted', selected_dates = $1, response_message = $2, updated_at = CURRENT_TIMESTAMP
           WHERE id = $3`,
          [selectedDatesJson, responseMessage || null, requestId]
        );

        // チャットに投票メッセージを追加
        await insertDateResponseMessage(
          dateRequest.match_id,
          userUuid,
          requestId,
          "vote",
          selectedDatesJson,
          responseMessage || ""
        );

        // 日程決定ロジックを実行
        const decisionResult = await processDateDecision(dateRequest, selectedDates || []);

        // リクエスト送信者に通知
        await sendDateResponseNotification(
          dateRequest.requester_id,
          userUuid,
          "vote",
          dateRequest.restaurant_name,
          responseMessage || ""
        );

        return {
          success: true,
          status: "voted",
          message: "",
          decisionResult,
        };
      }
    } catch (error) {
      console.error("❌ デートリクエスト回答失敗:", error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError(
        "internal",
        "デートリクエストの回答に失敗しました",
      );
    }
  }
);

/**
 * 日程決定処理
 */
async function processDateDecision(
  dateRequest: any,
  selectedDates: string[]
): Promise<any> {
  try {
    console.log("🎯 日程決定処理開始");

    const proposedDates = [
      dateRequest.proposed_date_1,
      dateRequest.proposed_date_2,
      dateRequest.proposed_date_3,
    ].filter((date) => date !== null);

    // 投票者の選択日程と提案日程の重複をチェック（日付の正規化して比較）
    const validSelectedDates = selectedDates.filter((selectedDate) => {
      const selectedDateTime = new Date(selectedDate).getTime();
      return proposedDates.some((proposedDate) => {
        const proposedDateTime = new Date(proposedDate).getTime();
        return Math.abs(selectedDateTime - proposedDateTime) < 60000; // 1分以内の差を許容
      });
    });

    console.log(`🔍 日程比較結果: proposedDates=${JSON.stringify(proposedDates)}, selectedDates=${JSON.stringify(selectedDates)}, validSelectedDates=${JSON.stringify(validSelectedDates)}`);

    if (validSelectedDates.length === 0) {
      // 重複する日程がない場合は自動的に辞退扱い
      await pool.query(
        `UPDATE date_requests 
         SET status = 'no_match', updated_at = CURRENT_TIMESTAMP
         WHERE id = $1`,
        [dateRequest.id]
      );

      await insertDateDecisionMessage(
        dateRequest.match_id,
        dateRequest.id,
        "no_match",
        null,
        {
          requestId: dateRequest.id,
          proposedDates,
          selectedDates: validSelectedDates,
        },
        dateRequest.requester_id
      );

      return {status: "no_match", decidedDate: null};
    }

    // 複数の候補がある場合は、昇順ソートして最初の日程を選択
    const sortedDates = validSelectedDates.sort((a, b) =>
      new Date(a).getTime() - new Date(b).getTime()
    );
    const decidedDate = sortedDates[0];

    // 日程をISO形式で正規化
    const normalizedDecidedDate = new Date(decidedDate).toISOString();

    console.log(`🎯 日程決定: ${decidedDate} → ${normalizedDecidedDate} (requestId: ${dateRequest.id})`);

    await pool.query(
      `UPDATE date_requests 
       SET status = 'decided', decided_date = $1, updated_at = CURRENT_TIMESTAMP
       WHERE id = $2`,
      [normalizedDecidedDate, dateRequest.id]
    );

    console.log(`✅ date_requests ステータス更新完了: status=decided, decided_date=${normalizedDecidedDate}`);

    await insertDateDecisionMessage(
      dateRequest.match_id,
      dateRequest.id,
      "decided",
      normalizedDecidedDate,
      {
        requestId: dateRequest.id,
        restaurantId: dateRequest.restaurant_id,
        restaurantName: dateRequest.restaurant_name,
        proposedDates,
        selectedDates: validSelectedDates,
        additionalRestaurantIds: dateRequest.additional_restaurant_ids || [],
      },
      dateRequest.requester_id
    );

    // 追加店舗がある場合は自動的に店舗投票を開始
    const additionalRestaurantIds = dateRequest.additional_restaurant_ids || [];
    if (additionalRestaurantIds.length > 0) {
      console.log("🏪 追加店舗があるため自動的に店舗投票を開始します");

      // メイン店舗と追加店舗の情報を取得
      const allRestaurantIds = [dateRequest.restaurant_id, ...additionalRestaurantIds];
      const restaurantResult = await pool.query(
        `SELECT id, name, image_url, category, prefecture, nearest_station, price_range
         FROM restaurants 
         WHERE id = ANY($1)`,
        [allRestaurantIds]
      );

      const restaurants = restaurantResult.rows.map((row) => ({
        id: row.id,
        name: row.name,
        image_url: row.image_url,
        category: row.category,
        prefecture: row.prefecture,
        nearest_station: row.nearest_station,
        price_range: row.price_range,
      }));

      if (restaurants.length > 1) {
        // 複数店舗がある場合は店舗投票を開始
        await insertRestaurantVotingMessage(
          dateRequest.match_id,
          dateRequest.requester_id,
          dateRequest.id,
          restaurants,
          normalizedDecidedDate
        );
        console.log("✅ 店舗投票メッセージを自動送信しました");
      } else {
        // 1店舗の場合は自動決定
        console.log("🎯 候補店舗が1つのため自動決定します");
        await insertRestaurantDecisionMessage(
          dateRequest.match_id,
          dateRequest.id,
          "decided",
          restaurants[0].id,
          restaurants[0].name,
          normalizedDecidedDate,
          {
            requestId: dateRequest.id,
            restaurants: restaurants,
            decidedDate: normalizedDecidedDate,
            type: "restaurant_voting",
          },
          dateRequest.requester_id
        );
      }
    } else {
      console.log("🏪 追加店舗なし - メイン店舗で自動決定");
      // 追加店舗がない場合はメイン店舗で自動決定
      const restaurantResult = await pool.query(
        "SELECT id, name FROM restaurants WHERE id = $1",
        [dateRequest.restaurant_id]
      );

      if (restaurantResult.rows.length > 0) {
        const restaurant = restaurantResult.rows[0];
        await insertRestaurantDecisionMessage(
          dateRequest.match_id,
          dateRequest.id,
          "decided",
          restaurant.id,
          restaurant.name,
          normalizedDecidedDate,
          {
            requestId: dateRequest.id,
            restaurants: [restaurant],
            decidedDate: normalizedDecidedDate,
            type: "restaurant_voting",
          },
          dateRequest.requester_id
        );
      }
    }

    return {status: "decided", decidedDate: normalizedDecidedDate};
  } catch (error) {
    console.error("❌ 日程決定処理エラー:", error);
    throw error;
  }
}

/**
 * デートリクエスト通知を送信
 * @param {string} recipientId - 受信者ID
 * @param {string} senderId - 送信者ID
 * @param {string} restaurantName - レストラン名
 * @param {string} message - メッセージ
 * @return {Promise<void>} Promise
 */
async function sendDateRequestNotification(
  recipientId: string,
  senderId: string,
  restaurantName: string,
  message: string
): Promise<void> {
  try {
    // 受信者のFCMトークン取得
    const userResult = await pool.query(
      "SELECT firebase_uid, fcm_token, name FROM users WHERE id = $1",
      [recipientId]
    );

    if (userResult.rows.length === 0 || !userResult.rows[0].fcm_token) {
      console.log("通知対象ユーザーまたはFCMトークンが見つかりません");
      return;
    }

    const senderResult = await pool.query(
      "SELECT name FROM users WHERE id = $1",
      [senderId]
    );

    const senderName = senderResult.rows[0]?.name || "Unknown";
    const fcmToken = userResult.rows[0].fcm_token;

    const notificationMessage = {
      token: fcmToken,
      notification: {
        title: "デリミート",
        body: `${senderName}さんから${restaurantName}でのデートのお誘いです💕`,
      },
      data: {
        type: "date_request",
        senderId: senderId,
        senderName: senderName,
        restaurantName: restaurantName,
        message: message,
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
              body: `${senderName}さんから${restaurantName}でのデートのお誘いです💕`,
            },
            badge: 1,
            sound: "default",
          },
        },
      },
    };

    await admin.messaging().send(notificationMessage);
    console.log("✅ デートリクエスト通知送信完了");
  } catch (error) {
    console.error("⚠️ デートリクエスト通知送信エラー:", error);
  }
}

/**
 * デートリクエスト回答通知を送信
 * @param {string} recipientId - 受信者ID
 * @param {string} senderId - 送信者ID
 * @param {string} response - 回答
 * @param {string} restaurantName - レストラン名
 * @param {string} message - メッセージ
 * @return {Promise<void>} Promise
 */
async function sendDateResponseNotification(
  recipientId: string,
  senderId: string,
  response: "vote" | "reject",
  restaurantName: string,
  message: string
): Promise<void> {
  try {
    const userResult = await pool.query(
      "SELECT firebase_uid, fcm_token FROM users WHERE id = $1",
      [recipientId]
    );

    if (userResult.rows.length === 0 || !userResult.rows[0].fcm_token) {
      return;
    }

    const senderResult = await pool.query(
      "SELECT name FROM users WHERE id = $1",
      [senderId]
    );

    const senderName = senderResult.rows[0]?.name || "Unknown";
    const fcmToken = userResult.rows[0].fcm_token;

    let responseText = "";
    let emoji = "";

    switch (response) {
    case "vote":
      responseText = "デートの日程を選択されました";
      emoji = "🗳️";
      break;
    case "reject":
      responseText = "お断りされました";
      emoji = "💔";
      break;
    }

    const notificationMessage = {
      token: fcmToken,
      notification: {
        title: "デリミート",
        body: `${senderName}さんがデートのお誘いを${responseText}${emoji}`,
      },
      data: {
        type: "date_response",
        senderId: senderId,
        senderName: senderName,
        response: response,
        restaurantName: restaurantName,
        message: message,
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
              body: `${senderName}さんがデートのお誘いを${responseText}${emoji}`,
            },
            badge: 1,
            sound: "default",
          },
        },
      },
    };

    await admin.messaging().send(notificationMessage);
    console.log("✅ デート回答通知送信完了");
  } catch (error) {
    console.error("⚠️ デート回答通知送信エラー:", error);
  }
}

/**
 * デートリクエストメッセージを挿入
 * @param {string} matchId - マッチID
 * @param {string} senderId - 送信者ID
 * @param {string} requestId - リクエストID
 * @param {string} restaurantId - レストランID
 * @param {object} restaurantDetail - レストラン詳細
 * @param {string[]} proposedDates - 提案日時
 * @param {string} message - メッセージ
 * @param {string[]} additionalRestaurantIds - 追加店舗IDs
 * @param {string} paymentOption - 支払いオプション
 * @return {Promise<void>} Promise
 */
async function insertDateRequestMessage(
  matchId: string,
  senderId: string,
  requestId: string,
  restaurantId: string,
  restaurantDetail: {
    name: string;
    image_url?: string;
    category?: string;
    prefecture?: string;
    nearest_station?: string;
    price_range?: string;
  },
  proposedDates: string[],
  message: string,
  additionalRestaurantIds: string[],
  paymentOption: string
): Promise<void> {
  try {
    const dateRequestData = {
      requestId,
      restaurantId,
      restaurantName: restaurantDetail.name,
      restaurantImageUrl: restaurantDetail.image_url || "",
      restaurantCategory: restaurantDetail.category || "",
      restaurantPrefecture: restaurantDetail.prefecture || "",
      restaurantNearestStation: restaurantDetail.nearest_station || "",
      restaurantPriceRange: restaurantDetail.price_range || "",
      proposedDates,
      message: message || "",
      type: "date_request",
      additionalRestaurantIds,
      paymentOption,
    };

    // PostgreSQLのmessagesテーブルに保存（JSONBとして保存）
    await pool.query(
      `INSERT INTO messages 
       (sender_id, match_id, content, type, message_type, date_request_data, related_date_request_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [
        senderId,
        matchId,
        `デートのお誘いが届きました！\n\n📍 ${restaurantDetail.name}`,
        "text",
        "date_request",
        JSON.stringify(dateRequestData), // JSONBとして保存
        requestId,
      ]
    );

    console.log("✅ デートリクエストメッセージを挿入しました");
  } catch (error) {
    console.error("⚠️ デートリクエストメッセージ挿入エラー:", error);
  }
}

/**
 * デートリクエスト回答メッセージを挿入
 * @param {string} matchId - マッチID
 * @param {string} senderId - 送信者ID
 * @param {string} requestId - リクエストID
 * @param {string} response - 回答
 * @param {string} selectedData - 選択データ（日程JSON）
 * @param {string} responseMessage - 回答メッセージ
 * @return {Promise<void>} Promise
 */
async function insertDateResponseMessage(
  matchId: string,
  senderId: string,
  requestId: string,
  response: "vote" | "reject",
  selectedData: string,
  responseMessage?: string
): Promise<void> {
  try {
    const responseData = {
      originalRequestId: requestId,
      response: response,
      selectedData: selectedData,
      type: "date_response",
    };

    const defaultMessage = response === "vote" ?
      "" :
      "申し訳ありませんが、今回はお断りします💔";

    // PostgreSQLのmessagesテーブルに保存
    await pool.query(
      `INSERT INTO messages 
       (sender_id, match_id, content, type, message_type, date_request_data, related_date_request_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [
        senderId,
        matchId,
        responseMessage || defaultMessage,
        "text",
        "date_response",
        JSON.stringify(responseData),
        requestId,
      ]
    );

    console.log("✅ デートリクエスト回答メッセージを挿入しました");
  } catch (error) {
    console.error("⚠️ デートリクエスト回答メッセージ挿入エラー:", error);
  }
}

/**
 * 日程決定メッセージを挿入
 */
async function insertDateDecisionMessage(
  matchId: string,
  requestId: string,
  status: "decided" | "no_match",
  decidedDate: string | null,
  originalData: any,
  senderId: string
): Promise<void> {
  try {
    let message = "";

    switch (status) {
    case "decided":
      // 日程決定時は空のメッセージ（UIで適切に表示される）
      message = "";
      break;
    case "no_match":
      message = "残念ながら、お互いの予定が合いませんでした 😔";
      break;
    }

    const decisionData = {
      originalRequestId: requestId,
      status: status,
      decidedDate: decidedDate,
      originalVotingData: originalData,
      type: "date_decision",
    };

    // PostgreSQLのmessagesテーブルに保存
    await pool.query(
      `INSERT INTO messages 
       (sender_id, match_id, content, type, message_type, date_request_data, related_date_request_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [
        senderId, // リクエスト送信者のIDを使用
        matchId,
        message,
        "text",
        "date_decision",
        JSON.stringify(decisionData),
        requestId,
      ]
    );

    console.log(`✅ 日程決定メッセージを挿入: ${status}`);
  } catch (error) {
    console.error("⚠️ 日程決定メッセージ挿入エラー:", error);
  }
}

/**
 * 店舗投票メッセージを挿入
 */
async function insertRestaurantVotingMessage(
  matchId: string,
  senderId: string,
  requestId: string,
  restaurants: any[],
  decidedDate: string
): Promise<void> {
  try {
    console.log(`🏪 店舗投票メッセージ挿入開始: matchId=${matchId}, senderId=${senderId}, requestId=${requestId}`);
    console.log(`🏪 レストラン数: ${restaurants.length}, 決定日程: ${decidedDate}`);

    // 元のrequestId（UUID形式）をrestaurantVotingIdとして使用
    const restaurantVotingId = requestId;
    const restaurantVotingData = {
      restaurantVotingId: restaurantVotingId,
      originalRequestId: requestId,
      restaurants: restaurants,
      decidedDate: decidedDate,
      type: "restaurant_voting",
    };

    const restaurantNames = restaurants.map((r) => r.name).join("、");
    const message = `🏪 店舗投票を開始します！\n\n候補店舗：${restaurantNames}`;

    console.log(`🏪 挿入するデータ: message_type=restaurant_voting, related_date_request_id=${requestId}`);
    console.log(`🏪 メッセージ内容: ${message}`);

    // PostgreSQLのmessagesテーブルに保存
    const result = await pool.query(
      `INSERT INTO messages 
       (sender_id, match_id, content, type, message_type, date_request_data, related_date_request_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING id, sent_at`,
      [
        senderId,
        matchId,
        message,
        "text",
        "restaurant_voting",
        JSON.stringify(restaurantVotingData),
        requestId,
      ]
    );

    console.log(`✅ 店舗投票メッセージを挿入しました: id=${result.rows[0].id}, sent_at=${result.rows[0].sent_at}`);

    // 挿入後に実際にメッセージが存在するかチェック
    const checkResult = await pool.query(
      `SELECT id, message_type, related_date_request_id, content 
       FROM messages 
       WHERE match_id = $1 AND message_type = 'restaurant_voting' AND related_date_request_id = $2`,
      [matchId, requestId]
    );

    console.log(`🔍 挿入確認: 見つかったメッセージ数=${checkResult.rows.length}`);
    if (checkResult.rows.length > 0) {
      console.log(`🔍 メッセージ詳細: ${JSON.stringify(checkResult.rows[0])}`);
    }
  } catch (error) {
    console.error("⚠️ 店舗投票メッセージ挿入エラー:", error);
    throw error;
  }
}

/**
 * 店舗投票回答メッセージを挿入
 */
async function insertRestaurantVotingResponseMessage(
  matchId: string,
  senderId: string,
  requestId: string,
  selectedRestaurantIds: string[],
  responseMessage?: string
): Promise<void> {
  try {
    const responseData = {
      originalRequestId: requestId,
      selectedRestaurantIds: selectedRestaurantIds,
      type: "restaurant_voting_response",
    };

    const defaultMessage = "店舗を選択しました！🏪";

    // PostgreSQLのmessagesテーブルに保存
    await pool.query(
      `INSERT INTO messages 
       (sender_id, match_id, content, type, message_type, date_request_data, related_date_request_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [
        senderId,
        matchId,
        responseMessage || defaultMessage,
        "text",
        "restaurant_voting_response",
        JSON.stringify(responseData),
        requestId,
      ]
    );

    console.log("✅ 店舗投票回答メッセージを挿入しました");
  } catch (error) {
    console.error("⚠️ 店舗投票回答メッセージ挿入エラー:", error);
  }
}

/**
 * Firebase UIDからユーザーUUIDを取得
 * @param {string} firebaseUid - Firebase UID
 * @return {Promise<string | null>} ユーザーUUID
 */
async function getUserUuidFromFirebaseUid(
  firebaseUid: string
): Promise<string | null> {
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

/**
 * 店舗投票回答（1対1マッチング用）
 */
export const respondToMatchRestaurantVoting = onCall(
  async (request: CallableRequest<{
    restaurantVotingId: string;
    selectedRestaurantIds: string[];
    responseMessage?: string;
  }>) => {
    console.log("🏪 店舗投票回答");

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const {restaurantVotingId, selectedRestaurantIds, responseMessage} = request.data;

    if (!restaurantVotingId || !selectedRestaurantIds || selectedRestaurantIds.length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "店舗投票IDと選択店舗IDが必要です"
      );
    }

    try {
      const userUuid = await getUserUuidFromFirebaseUid(request.auth.uid);
      if (!userUuid) {
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }

      // 店舗投票メッセージを取得してマッチIDを確認
      const votingMessageResult = await pool.query(
        `SELECT match_id FROM messages 
         WHERE message_type = $1 AND related_date_request_id = $2`,
        ["restaurant_voting", restaurantVotingId]
      );

      if (votingMessageResult.rows.length === 0) {
        throw new HttpsError("not-found", "店舗投票が見つかりません");
      }

      const matchId = votingMessageResult.rows[0].match_id;

      // 送信者かチェック（1対1マッチでは受信者のみ投票可能）
      const dateRequestResult = await pool.query(
        "SELECT requester_id, recipient_id FROM date_requests WHERE id = $1",
        [restaurantVotingId]
      );

      if (dateRequestResult.rows.length === 0) {
        throw new HttpsError("not-found", "デートリクエストが見つかりません");
      }

      const {requester_id: requesterId, recipient_id: recipientId} = dateRequestResult.rows[0];

      console.log(`🔍 投票権限チェック: userUuid=${userUuid}, requesterId=${requesterId}, recipientId=${recipientId}`);

      // 送信者（requester）が投票しようとした場合はエラー
      if (userUuid === requesterId) {
        console.log(`⚠️ 送信者による不正な投票を拒否: ${userUuid}`);
        throw new HttpsError("permission-denied", "送信者は店舗投票できません。受信者のみが投票可能です。");
      }

      // 受信者以外が投票しようとした場合もエラー
      if (userUuid !== recipientId) {
        console.log(`⚠️ 受信者以外による不正な投票を拒否: ${userUuid}`);
        throw new HttpsError("permission-denied", "このユーザーは店舗投票する権限がありません。");
      }

      console.log("✅ 投票権限確認完了: 受信者による正当な投票");

      // 既に回答済みかチェック
      const existingResponseResult = await pool.query(
        `SELECT id FROM messages 
         WHERE message_type = $1 AND related_date_request_id = $2 AND sender_id = $3`,
        ["restaurant_voting_response", restaurantVotingId, userUuid]
      );

      if (existingResponseResult.rows.length > 0) {
        throw new HttpsError("already-exists", "既に店舗投票に回答済みです");
      }

      // 店舗投票回答メッセージを挿入
      try {
        await insertRestaurantVotingResponseMessage(
          matchId,
          userUuid,
          restaurantVotingId,
          selectedRestaurantIds,
          responseMessage
        );
        console.log("✅ 店舗投票回答メッセージ挿入成功");
      } catch (insertError) {
        console.error("❌ 店舗投票回答メッセージ挿入失敗:", insertError);
        const errorMessage = insertError instanceof Error ? insertError.message : String(insertError);
        throw new HttpsError("internal", `店舗投票回答の保存に失敗しました: ${errorMessage}`);
      }

      // 1対1マッチの店舗決定処理
      console.log("🏆 店舗決定処理を開始します");

      let decisionResult;
      try {
        decisionResult = await processMatchRestaurantDecision(
          matchId,
          restaurantVotingId
        );
        console.log(`🏆 店舗決定処理結果: ${JSON.stringify(decisionResult)}`);
      } catch (decisionError) {
        console.error("❌ 店舗決定処理中にエラーが発生:", decisionError);
        // 店舗決定でエラーが発生してもレスポンスは成功として返す（投票回答は完了している）
        decisionResult = {
          status: "error",
          message: "店舗決定処理でエラーが発生しましたが、投票は正常に記録されました",
          error: decisionError instanceof Error ? decisionError.message : String(decisionError),
        };
      }

      return {
        success: true,
        message: "店舗投票に回答しました",
        decisionResult: decisionResult,
      };
    } catch (error) {
      console.error("❌ 店舗投票回答失敗:", error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError("internal", "店舗投票回答の処理に失敗しました");
    }
  }
);

/**
 * 店舗決定メッセージを挿入（1対1マッチ用）
 */
async function insertRestaurantDecisionMessage(
  matchId: string,
  requestId: string,
  status: "decided" | "tie",
  decidedRestaurantId: string | null,
  decidedRestaurantName: string | null,
  decidedDate: string,
  originalVotingData: any,
  senderId: string
): Promise<void> {
  try {
    console.log("🏆 【店舗決定メッセージ挿入】開始");
    console.log(`🏆 パラメータ: matchId=${matchId}, requestId=${requestId}, status=${status}`);
    console.log(`🏆 店舗情報: id=${decidedRestaurantId}, name=${decidedRestaurantName}`);
    console.log(`🏆 決定日程: ${decidedDate}`);
    console.log(`🏆 送信者ID: ${senderId}`);

    const decisionData = {
      type: "restaurant_decision",
      status: status,
      decidedRestaurantId: decidedRestaurantId,
      decidedRestaurantName: decidedRestaurantName,
      decidedDate: decidedDate,
      originalRequestId: requestId,
      originalVotingData: originalVotingData,
    };

    console.log(`🏆 【店舗決定メッセージ】作成データ: ${JSON.stringify(decisionData)}`);

    let content = "";
    if (status === "decided") {
      content = `🎉 デート確定！\n📅 ${decidedDate}\n🏪 ${decidedRestaurantName}`;
    } else {
      content = "🤔 投票が引き分けです。再投票を行ってください。";
    }

    console.log(`🏆 【店舗決定メッセージ】コンテンツ: ${content}`);

    const result = await pool.query(
      `INSERT INTO messages (sender_id, match_id, content, type, message_type, date_request_data, related_date_request_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING id, sent_at`,
      [
        senderId,
        matchId,
        content,
        "text",
        "restaurant_decision",
        JSON.stringify(decisionData),
        requestId,
      ]
    );

    console.log(`✅ 店舗決定メッセージを挿入しました: id=${result.rows[0].id}, sent_at=${result.rows[0].sent_at}`);

    // 挿入後の確認クエリ
    const checkResult = await pool.query(
      `SELECT id, message_type, related_date_request_id, content, date_request_data 
       FROM messages 
       WHERE match_id = $1 AND message_type = 'restaurant_decision' AND related_date_request_id = $2
       ORDER BY sent_at DESC LIMIT 1`,
      [matchId, requestId]
    );

    console.log(`🔍 【挿入確認】店舗決定メッセージ数: ${checkResult.rows.length}`);
    if (checkResult.rows.length > 0) {
      console.log(`🔍 【挿入確認】メッセージ詳細: ${JSON.stringify(checkResult.rows[0])}`);
    }
  } catch (error) {
    console.error("⚠️ 店舗決定メッセージ挿入エラー:", error);
    throw error; // エラーを再スローして上位で捕捉できるようにする
  }
}

/**
 * 1対1マッチの店舗決定処理
 */
async function processMatchRestaurantDecision(
  matchId: string,
  restaurantVotingId: string
): Promise<any> {
  try {
    console.log("🏆 1対1マッチ店舗決定処理開始");

    // マッチの参加者を取得
    const matchResult = await pool.query(
      "SELECT user1_id, user2_id FROM matches WHERE id = $1",
      [matchId]
    );

    if (matchResult.rows.length === 0) {
      console.log("❌ マッチが見つかりません");
      return {status: "error", message: "マッチが見つかりません"};
    }

    const {user1_id: user1Id} = matchResult.rows[0];

    // 1対1マッチでは受信者（recipient）の投票のみで店舗決定
    // 元のdate_requestを取得して受信者と送信者を特定
    const dateRequestResult = await pool.query(
      "SELECT recipient_id, requester_id FROM date_requests WHERE id = $1",
      [restaurantVotingId]
    );

    if (dateRequestResult.rows.length === 0) {
      console.log("❌ 対応するdate_requestが見つかりません");
      return {status: "error", message: "対応するdate_requestが見つかりません"};
    }

    const recipientId = dateRequestResult.rows[0].recipient_id;
    const requesterId = dateRequestResult.rows[0].requester_id;
    console.log(`🎯 1対1マッチ: 送信者ID=${requesterId}, 受信者ID=${recipientId}`);

    // 全ての投票を取得して送信者の投票を除外
    const allVotesResult = await pool.query(
      `SELECT sender_id, date_request_data 
       FROM messages 
       WHERE message_type = $1 AND related_date_request_id = $2`,
      ["restaurant_voting_response", restaurantVotingId]
    );

    console.log(`🗳️ 全投票数: ${allVotesResult.rows.length}`);

    // 送信者の投票を除外して受信者の投票のみを抽出
    const recipientVotes = allVotesResult.rows.filter((vote) => {
      const isRecipientVote = vote.sender_id === recipientId;
      console.log(`🔍 投票チェック: sender_id=${vote.sender_id}, 受信者ID=${recipientId}, 受信者の投票=${isRecipientVote}`);
      if (vote.sender_id === requesterId) {
        console.log(`⚠️ 送信者の投票を検出して除外: ${requesterId}`);
      }
      return isRecipientVote;
    });

    console.log(`🗳️ 受信者の投票数: ${recipientVotes.length}/1（送信者の投票は除外）`);

    // 受信者の投票があるかチェック
    if (recipientVotes.length === 0) {
      console.log("⏳ 受信者の投票が完了していません");
      return {status: "waiting", message: "受信者の投票待ち中"};
    }

    // 1対1マッチでは受信者の選択が即決定
    const voteRow = recipientVotes[0];
    let decidedRestaurantId = null;
    let decidedRestaurantName = "不明";

    try {
      // date_request_dataが既にオブジェクトの場合とJSON文字列の場合の両方に対応
      let voteData;
      if (typeof voteRow.date_request_data === "string") {
        voteData = JSON.parse(voteRow.date_request_data);
      } else {
        voteData = voteRow.date_request_data;
      }
      const selectedRestaurantIds = voteData.selectedRestaurantIds || [];

      if (selectedRestaurantIds.length > 0) {
        decidedRestaurantId = selectedRestaurantIds[0]; // 1対1マッチでは最初の選択を採用
        console.log(`🎯 受信者が選択した店舗ID: ${decidedRestaurantId}`);
      }
    } catch (error) {
      console.error("❌ 投票データ解析エラー:", error);
      return {status: "error", message: "投票データの解析に失敗しました"};
    }

    if (!decidedRestaurantId) {
      console.log("❌ 決定店舗IDが見つかりません");
      return {status: "error", message: "決定店舗IDが見つかりません"};
    }

    // 店舗名を取得
    const restaurantResult = await pool.query(
      "SELECT name FROM restaurants WHERE id = $1",
      [decidedRestaurantId]
    );

    if (restaurantResult.rows.length > 0) {
      decidedRestaurantName = restaurantResult.rows[0].name;
    }

    console.log(`🎉 1対1マッチ店舗決定: ${decidedRestaurantName} (ID: ${decidedRestaurantId})`);

    // 元の店舗投票データを取得
    const originalVotingResult = await pool.query(
      `SELECT date_request_data FROM messages 
       WHERE message_type = $1 AND related_date_request_id = $2`,
      ["restaurant_voting", restaurantVotingId]
    );

    console.log(`🔍 【日程取得】店舗投票メッセージ検索結果: ${originalVotingResult.rows.length}件`);

    let decidedDate = "";
    let formattedDecidedDate = "";
    if (originalVotingResult.rows.length > 0) {
      try {
        // date_request_dataが既にオブジェクトの場合とJSON文字列の場合の両方に対応
        let originalData;
        if (typeof originalVotingResult.rows[0].date_request_data === "string") {
          originalData = JSON.parse(originalVotingResult.rows[0].date_request_data);
        } else {
          originalData = originalVotingResult.rows[0].date_request_data;
        }
        decidedDate = originalData.decidedDate || "";
        console.log(`🔍 【日程取得】元の投票データ: ${JSON.stringify(originalData)}`);
        console.log(`🔍 【日程取得】決定日程（生データ）: ${decidedDate}`);

        // 日付を日本語形式にフォーマット
        if (decidedDate) {
          try {
            const date = new Date(decidedDate);
            const year = date.getFullYear();
            const month = date.getMonth() + 1;
            const day = date.getDate();
            const hours = date.getHours();
            const minutes = date.getMinutes();

            // 曜日の取得
            const weekdays = ["日", "月", "火", "水", "木", "金", "土"];
            const weekday = weekdays[date.getDay()];

            formattedDecidedDate = `${year}年${month}月${day}日(${weekday}) ${hours.toString().padStart(2, "0")}:${minutes.toString().padStart(2, "0")}`;
            console.log(`🔍 【日程フォーマット】フォーマット後: ${formattedDecidedDate}`);
          } catch (dateError) {
            console.error("日付フォーマットエラー:", dateError);
            formattedDecidedDate = decidedDate; // フォーマット失敗時は元のデータを使用
          }
        }
      } catch (error) {
        console.error("元投票データ解析エラー:", error);
      }
    } else {
      console.log("⚠️ 【日程取得】店舗投票メッセージが見つかりません");
    }

    // 1対1マッチでは受信者の選択で即決定
    await insertRestaurantDecisionMessage(
      matchId,
      restaurantVotingId,
      "decided",
      decidedRestaurantId,
      decidedRestaurantName,
      formattedDecidedDate || decidedDate, // フォーマット済みがあればそれを使用、なければ元データ
      {selectedRestaurantId: decidedRestaurantId, selectedRestaurantName: decidedRestaurantName},
      user1Id // システムメッセージとして user1Id を使用
    );

    return {
      status: "decided",
      decidedRestaurantId: decidedRestaurantId,
      decidedRestaurantName: decidedRestaurantName,
      decidedDate: decidedDate,
    };
  } catch (error) {
    console.error("❌ 店舗決定処理エラー:", error);
    return {status: "error", message: "店舗決定処理に失敗しました"};
  }
}

/**
 * 店舗投票開始
 */
export const startDateRestaurantVoting = onCall(
  async (request: CallableRequest<{
    requestId: string;
    mainRestaurantId: string;
    additionalRestaurantIds: string[];
    decidedDate: string;
  }>) => {
    console.log("🏪 店舗投票開始");

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const {requestId, mainRestaurantId, additionalRestaurantIds, decidedDate} = request.data;

    try {
      const userUuid = await getUserUuidFromFirebaseUid(request.auth.uid);
      if (!userUuid) {
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }

      // リクエストの確認
      const requestResult = await pool.query(
        `SELECT * FROM date_requests 
         WHERE id = $1 AND (requester_id = $2 OR recipient_id = $2)`,
        [requestId, userUuid]
      );

      if (requestResult.rows.length === 0) {
        throw new HttpsError("not-found", "リクエストが見つかりません");
      }

      const dateRequest = requestResult.rows[0];

      // 日程が決定されているかチェック（decidedまたはvotedかつdecided_dateがある場合）
      if (dateRequest.status !== "decided" && !(dateRequest.status === "voted" && dateRequest.decided_date)) {
        console.log(`❌ 日程決定チェック失敗: status=${dateRequest.status}, decided_date=${dateRequest.decided_date}`);

        // no_matchの場合は特別なエラーメッセージ
        if (dateRequest.status === "no_match") {
          throw new HttpsError("failed-precondition", "選択された日程に重複がないため、店舗投票を開始できません。日程を再調整してください。");
        }

        throw new HttpsError("failed-precondition", "日程が決定されていません");
      }

      console.log(`✅ 日程決定確認: status=${dateRequest.status}, decided_date=${dateRequest.decided_date}`);

      // 店舗情報を取得
      const allRestaurantIds = [mainRestaurantId, ...additionalRestaurantIds];
      const restaurantsResult = await pool.query(
        `SELECT id, name, image_url, category, prefecture 
         FROM restaurants WHERE id = ANY($1)`,
        [allRestaurantIds]
      );

      const restaurants = restaurantsResult.rows;

      // 店舗投票メッセージを送信
      await insertRestaurantVotingMessage(
        dateRequest.match_id,
        userUuid,
        requestId,
        restaurants,
        decidedDate
      );

      return {
        success: true,
        message: "店舗投票を開始しました",
      };
    } catch (error) {
      console.error("❌ 店舗投票開始失敗:", error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError("internal", "店舗投票の開始に失敗しました");
    }
  }
);


