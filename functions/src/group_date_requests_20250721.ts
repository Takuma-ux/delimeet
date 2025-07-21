import {
  onCall,
  HttpsError,
  CallableRequest,
} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {pool} from "./index";

/**
 * FirebaseUIDからユーザーUUIDを取得
 */
async function getUserUuidFromFirebaseUid(firebaseUid: string): Promise<string | null> {
  try {
    const result = await pool.query(
      "SELECT id FROM users WHERE firebase_uid = $1",
      [firebaseUid]
    );
    return result.rows.length > 0 ? result.rows[0].id : null;
  } catch (error) {
    console.error("Error getting user UUID:", error);
    return null;
  }
}

/**
 * グループデートリクエスト送信
 */
export const sendGroupDateRequest = onCall(
  async (request: CallableRequest<{
    groupId: string;
    restaurantId: string;
    additionalRestaurantIds?: string[]; // 2段階目投票用の追加店舗
    message?: string;
    proposedDates: string[]; // ISO8601形式の日時配列
    isRetry?: boolean; // 再投票フラグ
    restaurantLowPrice?: number;
    restaurantHighPrice?: number;
    restaurantNearestStation?: string;
  }>) => {
    console.log("💕 グループデートリクエスト送信: 開始");

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const {groupId, restaurantId, additionalRestaurantIds, message, proposedDates, isRetry, restaurantLowPrice, restaurantHighPrice, restaurantNearestStation} = request.data;

    // デバッグログ追加
    console.log("🔍 sendGroupDateRequest受信データ:");
    console.log(`   - restaurantId: ${restaurantId}`);
    console.log(`   - additionalRestaurantIds: ${JSON.stringify(additionalRestaurantIds)}`);
    console.log(`   - additionalRestaurantIds.length: ${additionalRestaurantIds?.length || 0}`);

    if (!groupId || !restaurantId || !proposedDates || proposedDates.length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "必須パラメータが不足しています"
      );
    }

    if (proposedDates.length > 3) {
      throw new HttpsError(
        "invalid-argument",
        "提案日時は最大3つまでです"
      );
    }

    try {
      // リクエスト送信者の情報を取得
      console.log(`🔍 リクエスト送信者情報取得開始: Firebase UID = ${request.auth.uid}`);

      let requesterInfo: {
        name?: string;
        image_url?: string | null;
      } = {};
      let requesterUuid = "";

      try {
        // PostgreSQLのusersテーブルから直接検索（アカウント停止中ユーザーを除外）
        const userQuery = "SELECT id, name, image_url FROM users WHERE firebase_uid = $1 AND (deactivated_at IS NULL OR deactivated_at > NOW())";
        const userResult = await pool.query(userQuery, [request.auth.uid]);

        if (userResult.rows.length > 0) {
          const userData = userResult.rows[0];
          requesterUuid = userData.id;
          requesterInfo = {
            name: userData.name || "ユーザー",
            image_url: userData.image_url || null,
          };
          console.log(`✅ リクエスト送信者情報取得成功（PostgreSQL）: UUID=${requesterUuid}, name=${userData.name}, image_url=${userData.image_url}`);
        } else {
          console.log(`⚠️ PostgreSQLでリクエスト送信者情報が見つかりません: Firebase UID ${request.auth.uid}`);
          requesterInfo = {
            name: "ユーザー",
            image_url: null,
          };
        }
      } catch (error) {
        console.error("❌ PostgreSQLからのリクエスト送信者情報取得エラー:", error);
        requesterInfo = {
          name: "ユーザー",
          image_url: null,
        };
      }

      console.log("🔍 最終的なrequesterInfo:", JSON.stringify(requesterInfo, null, 2));
      console.log("🔍 requesterUuid:", requesterUuid);

      // レストランの存在確認
      const restaurantResult = await pool.query(
        "SELECT name, image_url, category, prefecture, nearest_station, price_range, low_price, high_price FROM restaurants WHERE id = $1",
        [restaurantId]
      );

      if (restaurantResult.rows.length === 0) {
        throw new HttpsError("not-found", "レストランが見つかりません");
      }

      const restaurant = restaurantResult.rows[0];

      // 既存の未回答リクエストチェックを削除（複数リクエスト許可）
      if (isRetry) {
        console.log("🔄 再投票リクエスト - 既存チェックをスキップ");
      } else {
        console.log("✅ 通常リクエスト - 複数リクエスト許可のため既存チェックをスキップ");
      }

      // リクエストIDを生成
      const requestId = `group_date_request_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

      // リクエスト送信時のグループメンバーIDを取得
      const groupDoc = await admin.firestore()
        .collection("groups")
        .doc(groupId)
        .get();

      if (!groupDoc.exists) {
        throw new HttpsError("not-found", "グループが見つかりません");
      }

      const groupData = groupDoc.data();
      const memberIds = groupData?.members || [];

      // Firestoreにグループデートリクエストメッセージを挿入
      await insertGroupDateRequestMessage(
        groupId,
        request.auth.uid, // Firebase UID
        requestId,
        restaurantId,
        restaurant,
        proposedDates,
        message || "",
        requesterInfo,
        memberIds, // リクエスト送信時のメンバーIDを渡す
        requesterUuid, // UUIDを追加で渡す
        additionalRestaurantIds, // 追加店舗IDsを渡す
        {
          lowPrice: restaurantLowPrice,
          highPrice: restaurantHighPrice,
          nearestStation: restaurantNearestStation,
        }
      );

      // 候補日時が1つの場合は自動的に日程決定
      if (proposedDates.length === 1) {
        console.log("🎯 候補日時が1つのため自動決定します");

        // 通知は送信（リクエスト自体は投稿されるため）
        await sendGroupDateRequestNotifications(
          groupId,
          requesterUuid,
          requesterInfo.name || "ユーザー",
          restaurant.name,
          message || ""
        );

        setTimeout(async () => {
          try {
            const originalRequestData = {
              requestId,
              restaurantId,
              restaurantName: restaurant.name,
              proposedDates,
              memberIds,
              additionalRestaurantIds: additionalRestaurantIds || [],
            };

            await sendDateDecisionMessage(
              groupId,
              requestId,
              "decided",
              proposedDates[0], // 唯一の候補日時を決定日時として設定
              originalRequestData,
              memberIds.length // 全員承認扱い
            );
          } catch (error) {
            console.error("❌ 自動日程決定エラー:", error);
          }
        }, 1000); // 1秒後に実行（メッセージ投稿完了を待つ）
      } else {
        // グループメンバーに通知送信（送信者以外）
        await sendGroupDateRequestNotifications(
          groupId,
          requesterUuid,
          requesterInfo.name || "ユーザー",
          restaurant.name,
          message || ""
        );
      }

      return {
        success: true,
        requestId: requestId,
        message: "グループデートリクエストを送信しました",
      };
    } catch (error) {
      console.error("❌ グループデートリクエスト送信失敗:", error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError(
        "internal",
        "グループデートリクエストの送信に失敗しました",
      );
    }
  }
);

/**
 * グループデートリクエスト回答
 */
export const respondToGroupDateRequest = onCall(
  async (request: CallableRequest<{
    requestId: string;
    response: "accept" | "reject";
    selectedDate?: string;
    responseMessage?: string;
  }>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const {requestId, response, selectedDate, responseMessage} = request.data;

    if (!requestId || !response) {
      throw new HttpsError(
        "invalid-argument",
        "リクエストIDと回答が必要です"
      );
    }

    if (!["accept", "reject"].includes(response)) {
      throw new HttpsError(
        "invalid-argument",
        "回答は accept または reject である必要があります"
      );
    }

    try {
      const userUuid = await getUserUuidFromFirebaseUid(request.auth.uid);
      if (!userUuid) {
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }

      // Firestoreからリクエスト情報を取得
      const groupsRef = admin.firestore().collection("groups");
      let requestDoc = null;
      let groupId = "";

      // 全グループを検索してリクエストを見つける
      const groupsSnapshot = await groupsRef.get();

      for (const groupDoc of groupsSnapshot.docs) {
        const messagesRef = groupDoc.ref.collection("messages");

        // type='group_date_request'でrequestIdが一致するメッセージを検索
        const requestQuery = messagesRef
          .where("type", "==", "group_date_request")
          .where("dateRequestData.requestId", "==", requestId);

        const requestSnapshot = await requestQuery.get();

        if (!requestSnapshot.empty) {
          requestDoc = requestSnapshot.docs[0];
          groupId = groupDoc.id;
          break;
        }
      }

      if (!requestDoc || !requestDoc.exists) {
        throw new HttpsError("not-found", "リクエストが見つかりません");
      }

      const requestData = requestDoc.data();

      if (requestData?.type !== "group_date_request") {
        throw new HttpsError("invalid-argument", "無効なリクエストタイプです");
      }

      // 自分のリクエストには回答できない
      if (requestData.senderId === request.auth.uid) {
        throw new HttpsError("permission-denied", "自分のリクエストには回答できません");
      }

      // 期限切れチェック（7日後）
      const requestTimestamp = requestData.timestamp?.toDate();
      if (requestTimestamp) {
        const expiryDate = new Date(requestTimestamp.getTime() + 7 * 24 * 60 * 60 * 1000);
        if (new Date() > expiryDate) {
          throw new HttpsError("failed-precondition", "期限切れのリクエストです");
        }
      }

      // 既に回答済みかチェック
      const responsesRef = admin.firestore()
        .collection("groups")
        .doc(groupId)
        .collection("messages")
        .where("type", "==", "group_date_response")
        .where("relatedDateRequestId", "==", requestId)
        .where("senderId", "==", request.auth.uid);

      const existingResponseSnapshot = await responsesRef.get();

      if (!existingResponseSnapshot.empty) {
        throw new HttpsError("already-exists", "既に回答済みです");
      }

      // 回答者情報を取得
      console.log(`🔍 回答者情報取得開始: Firebase UID = ${request.auth.uid}`);

      let responderInfo: {
        name?: string;
        image_url?: string | null;
      } = {};
      let responderUuid = "";

      try {
        // PostgreSQLのusersテーブルから直接検索（アカウント停止中ユーザーを除外）
        const userQuery = "SELECT id, name, image_url FROM users WHERE firebase_uid = $1 AND (deactivated_at IS NULL OR deactivated_at > NOW())";
        const userResult = await pool.query(userQuery, [request.auth.uid]);

        if (userResult.rows.length > 0) {
          const userData = userResult.rows[0];
          responderUuid = userData.id;
          responderInfo = {
            name: userData.name || "ユーザー",
            image_url: userData.image_url || null,
          };
          console.log(`✅ 回答者情報取得成功（PostgreSQL）: UUID=${responderUuid}, name=${userData.name}, image_url=${userData.image_url}`);
        } else {
          console.log(`⚠️ PostgreSQLで回答者情報が見つかりません: Firebase UID ${request.auth.uid}`);
          responderInfo = {
            name: "ユーザー",
            image_url: null,
          };
        }
      } catch (error) {
        console.error("❌ PostgreSQLからの回答者情報取得エラー:", error);
        responderInfo = {
          name: "ユーザー",
          image_url: null,
        };
      }

      console.log("🔍 最終的なresponderInfo:", JSON.stringify(responderInfo, null, 2));
      console.log("🔍 responderUuid:", responderUuid);

      // 個別回答メッセージを送信
      await insertGroupDateResponseMessage(
        groupId,
        request.auth.uid, // Firebase UID
        requestId,
        response,
        selectedDate || "",
        responseMessage || "",
        responderInfo,
        responderUuid // UUIDを追加で渡す
      );

      console.log(`✅ グループデートリクエスト回答成功: ${response}`);

      // 全員の回答状況をチェックして自動決定処理
      await checkAndProcessAllResponses(groupId, requestId);

      return {
        success: true,
        response: response,
        message: response === "accept" ? "デートリクエストを承認しました！" : "デートリクエストを辞退しました",
      };
    } catch (error) {
      console.error("❌ グループデートリクエスト回答失敗:", error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError(
        "internal",
        "グループデートリクエストの回答に失敗しました"
      );
    }
  }
);

/**
 * グループデートリクエスト一覧取得
 */
/**
 * 店舗投票回答
 */
export const respondToRestaurantVoting = onCall(
  async (request: CallableRequest<{
    restaurantVotingId: string;
    selectedRestaurantIds: string[]; // 複数選択対応
    responseMessage?: string;
  }>) => {
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

      // 店舗投票情報を取得
      const groupsRef = admin.firestore().collection("groups");
      let votingDoc = null;
      let groupId = "";

      const groupsSnapshot = await groupsRef.get();

      for (const groupDoc of groupsSnapshot.docs) {
        const messagesRef = groupDoc.ref.collection("messages");
        const votingQuery = messagesRef
          .where("type", "==", "restaurant_voting")
          .where("restaurantVotingData.restaurantVotingId", "==", restaurantVotingId);

        const votingSnapshot = await votingQuery.get();

        if (!votingSnapshot.empty) {
          votingDoc = votingSnapshot.docs[0];
          groupId = groupDoc.id;
          break;
        }
      }

      if (!votingDoc) {
        throw new HttpsError("not-found", "店舗投票が見つかりません");
      }

      // 既に回答済みかチェック（重複投票防止）
      const existingResponseQuery = admin.firestore()
        .collection("groups")
        .doc(groupId)
        .collection("messages")
        .where("type", "==", "restaurant_voting_response")
        .where("relatedRestaurantVotingId", "==", restaurantVotingId)
        .where("senderId", "==", request.auth.uid);

      const existingResponseSnapshot = await existingResponseQuery.get();

      if (!existingResponseSnapshot.empty) {
        throw new HttpsError(
          "already-exists",
          "既に店舗投票に回答済みです"
        );
      }

      // 回答者情報を取得
      let responderInfo: {
        name?: string;
        image_url?: string | null;
      } = {};

      try {
        const userQuery = "SELECT name, image_url FROM users WHERE firebase_uid = $1";
        const userResult = await pool.query(userQuery, [request.auth.uid]);

        if (userResult.rows.length > 0) {
          const userData = userResult.rows[0];
          responderInfo = {
            name: userData.name || "ユーザー",
            image_url: userData.image_url || null,
          };
        }
      } catch (error) {
        console.error("回答者情報取得エラー:", error);
        responderInfo = {
          name: "ユーザー",
          image_url: null,
        };
      }

      // 回答メッセージを挿入
      await insertRestaurantVotingResponseMessage(
        groupId,
        request.auth.uid,
        restaurantVotingId,
        selectedRestaurantIds,
        responseMessage || "",
        responderInfo,
        userUuid
      );

      // 全員の回答をチェック
      await checkAndProcessRestaurantVotingResponses(groupId, restaurantVotingId);

      return {
        success: true,
        message: "店舗投票に回答しました",
      };
    } catch (error) {
      console.error("店舗投票回答エラー:", error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError(
        "internal",
        "店舗投票回答の処理に失敗しました",
      );
    }
  }
);

export const getGroupDateRequests = onCall(
  async (request: CallableRequest<{
    groupId: string;
    status?: string;
  }>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const {groupId} = request.data;

    if (!groupId) {
      throw new HttpsError("invalid-argument", "グループIDが必要です");
    }

    try {
      const userUuid = await getUserUuidFromFirebaseUid(request.auth.uid);
      if (!userUuid) {
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }

      // Firestoreからグループデートリクエストを取得
      const query = admin.firestore()
        .collection("groups")
        .doc(groupId)
        .collection("messages")
        .where("type", "==", "group_date_request")
        .orderBy("timestamp", "desc");

      const snapshot = await query.get();

      const requests = snapshot.docs.map((doc) => {
        const data = doc.data();
        return {
          id: doc.id,
          ...data,
          timestamp: data.timestamp?.toDate()?.toISOString(),
        };
      });

      return {
        success: true,
        requests: requests,
      };
    } catch (error) {
      console.error("❌ グループデートリクエスト一覧取得失敗:", error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError(
        "internal",
        "グループデートリクエスト一覧の取得に失敗しました",
      );
    }
  }
);

/**
 * グループデートリクエストメッセージを挿入
 */
async function insertGroupDateRequestMessage(
  groupId: string,
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
    low_price?: number;
    high_price?: number;
  },
  proposedDates: string[],
  message: string,
  requesterInfo: {
    name?: string;
    image_url?: string | null;
  },
  memberIds: string[], // リクエスト送信時のメンバーID
  requesterUuid: string,
  additionalRestaurantIds?: string[], // 追加店舗IDs
  frontendRestaurantData?: {
    lowPrice?: number;
    highPrice?: number;
    nearestStation?: string;
  }
): Promise<void> {
  try {
    const dateRequestData = {
      requestId,
      restaurantId,
      restaurantName: restaurantDetail.name,
      restaurantImageUrl: restaurantDetail.image_url,
      restaurantCategory: restaurantDetail.category,
      restaurantPrefecture: restaurantDetail.prefecture,
      restaurantNearestStation: frontendRestaurantData?.nearestStation || restaurantDetail.nearest_station,
      restaurantPriceRange: restaurantDetail.price_range,
      restaurantLowPrice: frontendRestaurantData?.lowPrice || restaurantDetail.low_price,
      restaurantHighPrice: frontendRestaurantData?.highPrice || restaurantDetail.high_price,
      additionalRestaurantIds: additionalRestaurantIds || [], // 追加店舗IDs
      proposedDates,
      message: message || "",
      type: "group_date_request",
      requesterName: requesterInfo.name || "ユーザー",
      requesterImageUrl: requesterInfo.image_url,
      memberIds, // リクエスト送信時のメンバーID
    };

    // Firestoreのサブコレクションに追加
    const messageData = {
      groupId: groupId,
      senderId: senderId, // Firebase UID
      senderName: requesterInfo.name || "ユーザー",
      senderImageUrl: requesterInfo.image_url || null,
      senderUuid: requesterUuid, // PostgreSQLから取得したUUID
      message: `グループデートのお誘いが届きました！\n\n📍 ${restaurantDetail.name}`,
      type: "group_date_request",
      imageUrl: null,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      dateRequestData: dateRequestData,
      relatedDateRequestId: requestId,
      readBy: {},
    };

    console.log("🎯 Firestore保存データ:", JSON.stringify(messageData, null, 2));
    await admin.firestore()
      .collection("groups")
      .doc(groupId)
      .collection("messages")
      .add(messageData);

    // グループの最新メッセージ情報を更新
    await admin.firestore()
      .collection("groups")
      .doc(groupId)
      .update({
        lastMessage: message || `${restaurantDetail.name}でグループデートしませんか？💕`,
        lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
        lastMessageBy: senderId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    console.log("✅ グループデートリクエストメッセージを挿入しました");
  } catch (error) {
    console.error("⚠️ グループデートリクエストメッセージ挿入エラー:", error);
  }
}

/**
 * グループデートリクエスト回答メッセージを挿入
 */
async function insertGroupDateResponseMessage(
  groupId: string,
  senderId: string, // Firebase UID
  requestId: string,
  response: "accept" | "reject",
  selectedDate: string, // カンマ区切りの日程文字列（複数選択対応）
  responseMessage: string,
  responderInfo: {
    name?: string;
    image_url?: string | null;
  },
  responderUuid: string
): Promise<void> {
  try {
    console.log("🔍 レスポンスメッセージ挿入開始:");
    console.log(`   - senderId (Firebase UID): ${senderId}`);
    console.log(`   - responderUuid: ${responderUuid}`);
    console.log("   - responderInfo:", JSON.stringify(responderInfo, null, 2));

    const responseData = {
      originalRequestId: requestId,
      response: response,
      selectedDate: selectedDate,
      type: "group_date_response",
      responderName: responderInfo.name || "ユーザー",
      responderImageUrl: responderInfo.image_url || null,
    };

    const defaultMessage = response === "accept" ?
      "グループデートのお誘いを承認しました！🎉" :
      "申し訳ありませんが、今回はお断りします💔";

    console.log(`🔍 senderName設定: ${responderInfo.name || "ユーザー"}`);
    console.log(`🔍 senderImageUrl設定: ${responderInfo.image_url || null}`);

    // Firestoreのサブコレクションに追加
    const messageData = {
      groupId: groupId,
      senderId: senderId, // Firebase UID
      senderName: responderInfo.name || "ユーザー",
      senderImageUrl: responderInfo.image_url || null,
      senderUuid: responderUuid, // PostgreSQLから取得したUUID
      message: responseMessage || defaultMessage,
      type: "group_date_response",
      imageUrl: null,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      dateRequestData: responseData,
      relatedDateRequestId: requestId,
      readBy: {},
    };

    console.log("🔍 Firestore保存データ:", JSON.stringify(messageData, null, 2));
    await admin.firestore()
      .collection("groups")
      .doc(groupId)
      .collection("messages")
      .add(messageData);

    // グループの最新メッセージ情報を更新
    await admin.firestore()
      .collection("groups")
      .doc(groupId)
      .update({
        lastMessage: responseMessage || defaultMessage,
        lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
        lastMessageBy: senderId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    console.log("✅ グループデートリクエスト回答メッセージを挿入しました");
  } catch (error) {
    console.error("⚠️ グループデートリクエスト回答メッセージ挿入エラー:", error);
  }
}

/**
 * 全員の回答をチェックして自動決定処理
 */
async function checkAndProcessAllResponses(
  groupId: string,
  requestId: string
): Promise<void> {
  try {
    console.log(`🔍 全員回答チェック開始: ${requestId}`);
    console.log(`🔍 groupId: ${groupId}`);

    // リクエスト送信時のグループメンバー数を取得（リクエストメッセージから）
    // 現在のメンバー数ではなく、リクエスト送信時点のメンバー数を使用

    // リクエスト情報を取得
    const requestQuery = admin.firestore()
      .collection("groups")
      .doc(groupId)
      .collection("messages")
      .where("type", "==", "group_date_request")
      .where("dateRequestData.requestId", "==", requestId);

    const requestSnapshot = await requestQuery.get();
    console.log(`🔍 リクエスト検索結果: ${requestSnapshot.size}件`);

    if (requestSnapshot.empty) {
      console.log("❌ リクエストメッセージが見つかりません");
      return;
    }

    const requestDoc = requestSnapshot.docs[0];
    const requestData = requestDoc.data();
    console.log("🔍 リクエストデータ取得完了:");
    console.log(`   - senderId: ${requestData.senderId}`);
    console.log(`   - type: ${requestData.type}`);
    console.log(`   - timestamp: ${requestData.timestamp}`);

    const senderId = requestData.senderId; // Firebase UID
    const originalRequestData = requestData.dateRequestData;
    console.log("🔍 originalRequestData:", JSON.stringify(originalRequestData, null, 2));

    // リクエスト送信時のメンバー数を取得
    const requestTimeMembers = originalRequestData?.memberIds || [];
    const totalMembers = requestTimeMembers.length;
    console.log(`🔍 リクエスト時メンバーIDs: [${requestTimeMembers.join(", ")}]`);
    console.log(`🔍 リクエスト時メンバー数: ${totalMembers}`);

    // メンバー数が0の場合は現在のグループメンバー数を使用（後方互換性）
    let actualTotalMembers = totalMembers;
    if (actualTotalMembers === 0) {
      console.log("⚠️ リクエスト時メンバー数が0 - 現在のメンバー数を使用");
      const groupDoc = await admin.firestore()
        .collection("groups")
        .doc(groupId)
        .get();

      if (groupDoc.exists) {
        const groupData = groupDoc.data();
        const currentMembers = groupData?.members || [];
        actualTotalMembers = currentMembers.length;
        console.log(`🔍 現在のメンバー数を使用: ${actualTotalMembers}`);
        console.log(`🔍 現在のメンバーIDs: [${currentMembers.join(", ")}]`);
      }
    } else {
      console.log(`🔍 リクエスト時メンバー数を使用: ${actualTotalMembers}`);
    }

    // このリクエストに対する回答を取得
    const responseQuery = admin.firestore()
      .collection("groups")
      .doc(groupId)
      .collection("messages")
      .where("type", "==", "group_date_response")
      .where("relatedDateRequestId", "==", requestId);

    const responseSnapshot = await responseQuery.get();
    console.log(`🔍 回答メッセージ検索結果: ${responseSnapshot.size}件`);

    // 回答者を集計（Firebase UIDからUUIDに変換）
    const respondedFirebaseUids = new Set<string>();
    const memberResponses = new Map<string, string>();
    const memberSelectedDates = new Map<string, string>();
    const approvedMembers = new Set<string>([senderId]); // 送信者は自動承認
    console.log(`🔍 承認者初期値（送信者）: [${senderId}]`);

    for (const responseDoc of responseSnapshot.docs) {
      const data = responseDoc.data();
      const firebaseUid = data.senderId;
      const response = data.dateRequestData?.response;
      const selectedDate = data.dateRequestData?.selectedDate;

      console.log("🔍 回答処理中:");
      console.log(`   - docId: ${responseDoc.id}`);
      console.log(`   - firebaseUid: ${firebaseUid}`);
      console.log(`   - response: ${response}`);
      console.log(`   - selectedDate: ${selectedDate}`);
      console.log(`   - senderId比較: ${firebaseUid} !== ${senderId} = ${firebaseUid !== senderId}`);

      if (firebaseUid && firebaseUid !== senderId) {
        // Firebase UIDからUUIDに変換
        console.log(`🔍 Firebase UIDからUUID変換開始: ${firebaseUid}`);
        const userUuid = await getUserUuidFromFirebaseUid(firebaseUid);
        console.log(`🔍 変換結果UUID: ${userUuid}`);

        if (userUuid) {
          respondedFirebaseUids.add(firebaseUid);
          memberResponses.set(userUuid, response || "reject");
          console.log(`🔍 回答者追加: ${userUuid} -> ${response || "reject"}`);

          if (response === "accept") {
            approvedMembers.add(userUuid);
            console.log(`🔍 承認者追加: ${userUuid}`);
            if (selectedDate) {
              memberSelectedDates.set(userUuid, selectedDate);
              console.log(`🔍 選択日程追加: ${userUuid} -> ${selectedDate}`);
            }
          }
        } else {
          console.log(`⚠️ UUID変換失敗: ${firebaseUid}`);
        }
      } else {
        console.log("🔍 スキップ: 送信者自身または無効なUID");
      }
    }

    // 送信者以外の全員が回答したかチェック
    const requiredResponses = actualTotalMembers - 1; // 送信者を除く
    const actualResponses = respondedFirebaseUids.size;

    // 詳細な集計結果ログ
    console.log("📊 最終集計結果:");
    console.log(`📊 回答状況: ${actualResponses}/${requiredResponses}`);
    console.log(`📊 リクエスト送信時メンバー数: ${totalMembers}`);
    console.log(`📊 実際使用メンバー数: ${actualTotalMembers}`);
    console.log(`📊 必要回答数: ${requiredResponses}`);
    console.log(`📊 実際回答数: ${actualResponses}`);
    console.log(`📊 回答者Firebase UIDs: [${Array.from(respondedFirebaseUids).join(", ")}]`);
    console.log(`📊 回答内容（UUID->response）: ${JSON.stringify(Object.fromEntries(memberResponses))}`);
    console.log(`📊 承認者UUIDs: [${Array.from(approvedMembers).join(", ")}]`);
    console.log(`📊 選択日程: ${JSON.stringify(Object.fromEntries(memberSelectedDates))}`);
    console.log(`📊 approvedMembers.size: ${approvedMembers.size}`);
    console.log(`📊 approvedMembers.size型: ${typeof approvedMembers.size}`);

    if (actualResponses < requiredResponses) {
      console.log("⏳ まだ全員の回答が揃っていません");
      return;
    }

    // 全員の回答が揃った！結果を処理
    console.log("🎯 全員回答完了 - 日程決定処理開始");
    console.log(`🎯 承認者数: ${approvedMembers.size}`);

    if (approvedMembers.size === 1) {
      // 全員拒否
      console.log(`🚫 全員拒否パターン - approvedMembers.size: ${approvedMembers.size}`);
      await sendDateDecisionMessage(
        groupId,
        requestId,
        "all_rejected",
        null,
        originalRequestData,
        approvedMembers?.size || 0
      );
    } else {
      console.log("✅ 承認者有りパターン - 日程投票開始");
      // 日程決定処理
      const proposedDates = Array.isArray(originalRequestData?.proposedDates) ?
        originalRequestData.proposedDates :
        [];
      const dateVotes = new Map<string, number>();

      // 承認者の選択日程を集計（送信者を除く）
      for (const selectedDateString of memberSelectedDates.values()) {
        // 複数選択の場合はカンマ区切りで分割
        const selectedDates = selectedDateString.split(",").map((d) => d.trim()).filter((d) => d);

        for (const selectedDate of selectedDates) {
          dateVotes.set(selectedDate, (dateVotes.get(selectedDate) || 0) + 1);
          console.log(`🗳️ メンバーの投票: ${selectedDate} (+1票)`);
        }
      }

      console.log(`🗳️ 送信者以外の投票結果: ${JSON.stringify(Object.fromEntries(dateVotes))}`);

      // 送信者は全ての候補日程に1票ずつ投票（どの日程でも参加可能）
      for (const proposedDate of proposedDates) {
        dateVotes.set(proposedDate, (dateVotes.get(proposedDate) || 0) + 1);
        console.log(`🗳️ 送信者の投票: ${proposedDate} (+1票)`);
      }

      if (dateVotes.size === 0) {
        console.log("❌ 選択された日程がありません");
        return;
      }

      console.log(`🗳️ 最終投票結果: ${JSON.stringify(Object.fromEntries(dateVotes))}`);

      // 最多得票の日程を決定
      const maxVotes = Math.max(...Array.from(dateVotes.values()));
      const topDates = Array.from(dateVotes.entries())
        .filter(([, votes]) => votes === maxVotes)
        .map(([date]) => date);

      console.log(`🗳️ 最多得票数: ${maxVotes}`);
      console.log(`🗳️ 最多得票日程: ${JSON.stringify(topDates)}`);

      if (topDates.length > 1) {
        // 引き分け
        await sendDateDecisionMessage(
          groupId,
          requestId,
          "tie",
          null,
          originalRequestData,
          approvedMembers?.size || 0,
          topDates
        );
      } else {
        // 日程決定
        const decidedDate = topDates[0];

        // 決定された日程に実際に参加できる人数を計算
        let actualParticipants = 0;

        // 送信者は常に参加（全ての日程に対応可能）
        actualParticipants += 1;
        console.log(`🎯 送信者が参加: ${decidedDate} (常時参加可能)`);

        // 他のメンバーでその日程を選択した人をカウント
        for (const [memberUuid, selectedDateString] of memberSelectedDates.entries()) {
          // 複数選択の場合はカンマ区切りで分割してチェック
          const selectedDates = selectedDateString.split(",").map((d) => d.trim()).filter((d) => d);

          if (selectedDates.includes(decidedDate)) {
            actualParticipants += 1;
            console.log(`🎯 メンバー ${memberUuid} が参加: ${decidedDate}`);
          }
        }

        console.log(`🎯 決定日程 ${decidedDate} の実際の参加者数: ${actualParticipants}`);

        await sendDateDecisionMessage(
          groupId,
          requestId,
          "decided",
          decidedDate,
          originalRequestData,
          actualParticipants
        );
      }
    }

    console.log("✅ 全員回答処理完了");
  } catch (error) {
    console.error("❌ 全員回答チェックエラー:", error);
  }
}

/**
 * 日程決定結果メッセージを送信
 */
async function sendDateDecisionMessage(
  groupId: string,
  requestId: string,
  status: string,
  decidedDate: string | null,
  originalRequestData: Record<string, unknown>,
  approvedCount: number,
  tiedDates?: string[]
): Promise<void> {
  try {
    console.log("🎯 日程決定メッセージ送信開始:");
    console.log(`   - groupId: ${groupId}`);
    console.log(`   - requestId: ${requestId}`);
    console.log(`   - status: ${status}`);
    console.log(`   - decidedDate: ${decidedDate}`);
    console.log(`   - approvedCount: ${approvedCount}`);
    console.log(`   - approvedCount型: ${typeof approvedCount}`);
    console.log(`   - tiedDates: ${JSON.stringify(tiedDates)}`);
    console.log(`   - originalRequestData: ${JSON.stringify(originalRequestData)}`);

    let message = "";

    switch (status) {
    case "all_rejected":
      message = "申し訳ありませんが、今回のグループデートは開催を見送らせていただきます。😔";
      break;
    case "tie":
      message = `日程が引き分けとなりました。再調整をお願いします。🤔\n候補: ${tiedDates?.join(", ")}`;
      break;
    case "decided":
      if (decidedDate) {
        const date = new Date(decidedDate);
        const formattedDate = date.toLocaleDateString("ja-JP", {
          month: "numeric",
          day: "numeric",
          weekday: "short",
          hour: "2-digit",
          minute: "2-digit",
        });
        message = `🎉 日程決定！\n\n📅 ${formattedDate}\n\n参加者: ${approvedCount || 0}名`;
      }
      break;
    }

    // システムメッセージとして投稿
    console.log("🎯 Firestoreメッセージ保存準備中:");
    const messageData = {
      groupId: groupId,
      senderId: "system",
      senderName: "システム",
      senderImageUrl: null,
      senderUuid: "system",
      message: message,
      type: "date_decision",
      imageUrl: null,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      dateDecisionData: {
        originalRequestId: requestId,
        status: status,
        decidedDate: decidedDate,
        approvedCount: approvedCount,
        proposedDates: originalRequestData?.proposedDates || [],
        tiedDates: tiedDates || null,
        originalVotingData: originalRequestData,
      },
      relatedDateRequestId: requestId,
      readBy: {},
    };
    console.log("🎯 保存するデータ:", JSON.stringify(messageData, null, 2));

    await admin.firestore()
      .collection("groups")
      .doc(groupId)
      .collection("messages")
      .add(messageData);

    console.log("🎯 Firestoreメッセージ保存完了");

    // グループの最新メッセージ情報を更新
    await admin.firestore()
      .collection("groups")
      .doc(groupId)
      .update({
        lastMessage: message,
        lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
        lastMessageBy: "system",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    console.log(`✅ 日程決定メッセージ送信完了: ${status}`);

    // 日程が決定した場合は店舗投票を自動開始
    console.log("🔍 レストラン投票開始チェック:");
    console.log(`   - status: ${status}`);
    console.log(`   - originalRequestData: ${JSON.stringify(originalRequestData, null, 2)}`);
    console.log(`   - originalRequestData?.restaurantId: ${originalRequestData?.restaurantId}`);

    if (status === "decided" && originalRequestData?.restaurantId) {
      const mainRestaurantId = originalRequestData.restaurantId as string;
      const additionalRestaurantIds = (originalRequestData.additionalRestaurantIds as string[]) || [];

      // メイン店舗がある場合は常に店舗投票を開始
      console.log("🏪 日程決定により店舗投票を開始します");
      console.log(`   - mainRestaurantId: ${mainRestaurantId}`);
      console.log(`   - additionalRestaurantIds: ${JSON.stringify(additionalRestaurantIds)}`);
      console.log(`   - additionalRestaurantIds.length: ${additionalRestaurantIds.length}`);
      console.log(`   - decidedDate: ${decidedDate}`);
      console.log(`   - memberIds: ${JSON.stringify(originalRequestData.memberIds)}`);

      console.log("🔍 店舗投票開始関数を呼び出し中...");
      await startRestaurantVoting(
        groupId,
        requestId,
        mainRestaurantId,
        additionalRestaurantIds,
        decidedDate || "",
        originalRequestData.memberIds as string[]
      );
      console.log("🔍 店舗投票開始関数完了");
    } else {
      console.log("❌ レストラン投票開始条件が満たされていません");
      if (status !== "decided") {
        console.log(`   - status が "decided" ではありません: ${status}`);
      }
      if (!originalRequestData?.restaurantId) {
        console.log("   - originalRequestData.restaurantId が存在しません");
      }
    }
  } catch (error) {
    console.error("❌ 日程決定メッセージ送信エラー:", error);
  }
}


/**
 * 営業時間内の店舗がない場合のメッセージ送信
 */

/**
 * 店舗投票を開始
 */
async function startRestaurantVoting(
  groupId: string,
  originalRequestId: string,
  mainRestaurantId: string,
  additionalRestaurantIds: string[],
  decidedDate: string,
  memberIds: string[]
): Promise<void> {
  try {
    console.log("🏪 店舗投票開始処理:");
    console.log(`   - mainRestaurantId: ${mainRestaurantId}`);
    console.log(`   - additionalRestaurantIds: ${JSON.stringify(additionalRestaurantIds)}`);
    console.log(`   - additionalRestaurantIds.length: ${additionalRestaurantIds?.length || 0}`);
    console.log(`   - decidedDate: ${decidedDate}`);

    // 全ての店舗ID（メイン + 追加）
    const allRestaurantIds = [mainRestaurantId, ...additionalRestaurantIds];
    console.log(`🔍 allRestaurantIds: ${JSON.stringify(allRestaurantIds)}`);
    console.log(`🔍 allRestaurantIds.length: ${allRestaurantIds.length}`);

    // 店舗情報を取得（営業時間チェックは不要 - リクエスト作成時に既に警告済み）
    const restaurantResult = await pool.query(`
      SELECT 
        r.id, 
        r.name, 
        r.image_url, 
        r.category, 
        r.prefecture, 
        r.nearest_station, 
        r.price_range,
        r.low_price,
        r.high_price,
        r.hotpepper_url
      FROM restaurants r 
      WHERE r.id = ANY($1)
    `, [allRestaurantIds]);

    console.log(`🔍 データベースクエリ結果: ${restaurantResult.rows.length}件`);
    console.log(`🔍 取得された店舗IDs: ${restaurantResult.rows.map((row) => row.id).join(", ")}`);

    const restaurants = restaurantResult.rows.map((row) => ({
      id: row.id,
      name: row.name,
      image_url: row.image_url,
      category: row.category,
      prefecture: row.prefecture,
      nearest_station: row.nearest_station,
      price_range: row.price_range,
      low_price: row.low_price,
      high_price: row.high_price,
      hotpepper_url: row.hotpepper_url,
    }));

    console.log(`✅ 投票候補店舗: ${restaurants.map((r) => r.name).join(", ")}`);
    console.log(`🔍 最終的な店舗数: ${restaurants.length}`);

    // 店舗が1つの場合は自動的に決定
    if (restaurants.length === 1) {
      console.log("🎯 候補店舗が1つのため自動決定します");
      console.log(`🎯 決定された店舗: ${restaurants[0].name} (ID: ${restaurants[0].id})`);

      // 店舗決定メッセージを直接送信
      const votingData = {
        restaurantVotingId: `restaurant_voting_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
        originalRequestId,
        restaurants,
        decidedDate,
        type: "restaurant_voting",
        memberIds,
      };

      console.log("🎯 店舗決定メッセージを送信中...");
      await sendRestaurantDecisionMessage(
        groupId,
        votingData.restaurantVotingId,
        "decided",
        restaurants[0].id,
        votingData,
        memberIds.length // 全員承認扱い
      );
      console.log("🎯 店舗決定メッセージ送信完了");
      return;
    }

    // 店舗投票リクエストIDを生成
    const restaurantVotingId = `restaurant_voting_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

    console.log("🗳️ 複数店舗のため投票を開始します");
    console.log(`🗳️ 投票ID: ${restaurantVotingId}`);
    console.log(`🗳️ 投票対象店舗: ${restaurants.map((r) => `${r.name}(${r.id})`).join(", ")}`);

    // 店舗投票メッセージをFirestoreに投稿
    await insertRestaurantVotingMessage(
      groupId,
      restaurantVotingId,
      originalRequestId,
      restaurants,
      decidedDate,
      memberIds
    );

    console.log("✅ 店舗投票開始完了");
  } catch (error) {
    console.error("❌ 店舗投票開始エラー:", error);
  }
}

/**
 * 店舗投票メッセージを挿入
 */
async function insertRestaurantVotingMessage(
  groupId: string,
  restaurantVotingId: string,
  originalRequestId: string,
  restaurants: Array<{
    id: string;
    name: string;
    image_url?: string;
    category?: string;
    prefecture?: string;
    nearest_station?: string;
    price_range?: string;
    low_price?: number;
    high_price?: number;
    hotpepper_url?: string;
  }>,
  decidedDate: string,
  memberIds: string[]
): Promise<void> {
  try {
    const votingData = {
      restaurantVotingId,
      originalRequestId,
      restaurants,
      decidedDate,
      type: "restaurant_voting",
      memberIds, // 投票対象メンバー
    };

    const messageData = {
      groupId: groupId,
      senderId: "system",
      senderName: "システム",
      senderImageUrl: null,
      senderUuid: "system",
      message: `日程が決定しました！続いて、どの店舗にするか決めましょう🏪\n\n📅 ${new Date(decidedDate).toLocaleDateString("ja-JP", {
        month: "numeric",
        day: "numeric",
        weekday: "short",
        hour: "2-digit",
        minute: "2-digit",
      })}`,
      type: "restaurant_voting",
      imageUrl: null,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      restaurantVotingData: votingData,
      relatedDateRequestId: originalRequestId,
      readBy: {},
    };

    await admin.firestore()
      .collection("groups")
      .doc(groupId)
      .collection("messages")
      .add(messageData);

    // グループの最新メッセージ情報を更新
    await admin.firestore()
      .collection("groups")
      .doc(groupId)
      .update({
        lastMessage: "店舗投票が開始されました！",
        lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
        lastMessageBy: "system",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    console.log("✅ 店舗投票メッセージを挿入しました");
  } catch (error) {
    console.error("⚠️ 店舗投票メッセージ挿入エラー:", error);
  }
}

/**
 * 店舗投票回答メッセージを挿入
 */
async function insertRestaurantVotingResponseMessage(
  groupId: string,
  senderId: string,
  restaurantVotingId: string,
  selectedRestaurantIds: string[],
  responseMessage: string,
  responderInfo: {
    name?: string;
    image_url?: string | null;
  },
  responderUuid: string
): Promise<void> {
  try {
    const responseData = {
      originalVotingId: restaurantVotingId,
      selectedRestaurantIds: selectedRestaurantIds.join(","), // カンマ区切りで保存
      type: "restaurant_voting_response",
      responderName: responderInfo.name || "ユーザー",
      responderImageUrl: responderInfo.image_url || null,
    };

    const defaultMessage = "店舗を選択しました！🏪";

    const messageData = {
      groupId: groupId,
      senderId: senderId,
      senderName: responderInfo.name || "ユーザー",
      senderImageUrl: responderInfo.image_url || null,
      senderUuid: responderUuid,
      message: responseMessage || defaultMessage,
      type: "restaurant_voting_response",
      imageUrl: null,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      restaurantVotingResponseData: responseData,
      relatedRestaurantVotingId: restaurantVotingId,
      readBy: {},
    };

    await admin.firestore()
      .collection("groups")
      .doc(groupId)
      .collection("messages")
      .add(messageData);

    // グループの最新メッセージ情報を更新
    await admin.firestore()
      .collection("groups")
      .doc(groupId)
      .update({
        lastMessage: responseMessage || defaultMessage,
        lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
        lastMessageBy: senderId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    console.log("✅ 店舗投票回答メッセージを挿入しました");
  } catch (error) {
    console.error("⚠️ 店舗投票回答メッセージ挿入エラー:", error);
  }
}

/**
 * 店舗投票の全員回答をチェックして自動決定処理
 */
async function checkAndProcessRestaurantVotingResponses(
  groupId: string,
  restaurantVotingId: string
): Promise<void> {
  try {
    console.log(`🔍 店舗投票全員回答チェック開始: ${restaurantVotingId}`);

    // 元の投票情報を取得
    const votingQuery = admin.firestore()
      .collection("groups")
      .doc(groupId)
      .collection("messages")
      .where("type", "==", "restaurant_voting")
      .where("restaurantVotingData.restaurantVotingId", "==", restaurantVotingId);

    const votingSnapshot = await votingQuery.get();

    if (votingSnapshot.empty) {
      console.log("❌ 店舗投票メッセージが見つかりません");
      return;
    }

    const votingDoc = votingSnapshot.docs[0];
    const votingData = votingDoc.data();
    const originalVotingData = votingData.restaurantVotingData;
    const memberIds = originalVotingData?.memberIds || [];
    const totalMembers = memberIds.length;

    // リクエスト送信者を特定
    const originalRequestId = originalVotingData?.originalRequestId as string;
    let requestSenderId: string | null = null;

    if (originalRequestId) {
      try {
        const originalRequestQuery = admin.firestore()
          .collection("groups")
          .doc(groupId)
          .collection("messages")
          .where("type", "==", "group_date_request")
          .where("relatedDateRequestId", "==", originalRequestId);

        const originalRequestSnapshot = await originalRequestQuery.get();

        if (!originalRequestSnapshot.empty) {
          const originalRequestDoc = originalRequestSnapshot.docs[0];
          const originalRequestData = originalRequestDoc.data();
          requestSenderId = originalRequestData.senderId;
        }
      } catch (error) {
        console.error("❌ リクエスト送信者特定エラー:", error);
      }
    }

    // 辞退者を特定（originalRequestIdに対してreject回答したユーザー）
    const rejectUsersSet = new Set<string>();
    if (originalRequestId) {
      try {
        const rejectResponseQuery = admin.firestore()
          .collection("groups")
          .doc(groupId)
          .collection("messages")
          .where("type", "==", "group_date_response")
          .where("relatedDateRequestId", "==", originalRequestId);

        const rejectResponseSnapshot = await rejectResponseQuery.get();

        rejectResponseSnapshot.docs.forEach((doc) => {
          const responseData = doc.data();
          const response = responseData.dateRequestData?.response;
          const senderId = responseData.senderId;

          if (response === "reject" && senderId) {
            rejectUsersSet.add(senderId);
          }
        });

        console.log(`🚫 辞退者: ${Array.from(rejectUsersSet)}`);
      } catch (error) {
        console.error("❌ 辞退者特定エラー:", error);
      }
    }

    // 回答を集計
    const responseQuery = admin.firestore()
      .collection("groups")
      .doc(groupId)
      .collection("messages")
      .where("type", "==", "restaurant_voting_response")
      .where("relatedRestaurantVotingId", "==", restaurantVotingId);

    const responseSnapshot = await responseQuery.get();

    // リクエスト送信者が投票済みかチェック
    const senderResponseExists = requestSenderId ?
      responseSnapshot.docs.some((doc) => doc.data().senderId === requestSenderId) :
      false;

    // 辞退者を除外したメンバー数を計算
    const activeMembers = memberIds.filter((memberId: string) => !rejectUsersSet.has(memberId));
    const activeMembersCount = activeMembers.length;

    // 必要な回答数を計算（辞退者とリクエスト送信者（投票していない場合）を除外）
    let requiredResponses = activeMembersCount;
    if (requestSenderId && !senderResponseExists && !rejectUsersSet.has(requestSenderId)) {
      requiredResponses = activeMembersCount - 1; // リクエスト送信者を除外
    }

    console.log(`🔍 総メンバー: ${totalMembers}, 辞退者: ${rejectUsersSet.size}, 参加者: ${activeMembersCount}`);
    console.log(`🔍 回答数: ${responseSnapshot.size}/${requiredResponses}`);
    console.log(`🔍 リクエスト送信者: ${requestSenderId}, 投票済み: ${senderResponseExists}`);
    console.log(`🔍 メンバーIDs: ${JSON.stringify(memberIds)}`);
    console.log(`🔍 辞退者IDs: ${JSON.stringify(Array.from(rejectUsersSet))}`);
    console.log(`🔍 参加者IDs: ${JSON.stringify(activeMembers)}`);

    if (responseSnapshot.size < requiredResponses) {
      console.log("⏳ まだ全員の回答が揃っていません");
      return;
    }

    // 投票結果を集計（辞退者の投票は除外）
    const restaurantVotes: { [restaurantId: string]: number } = {};
    let validVoteCount = 0;
    let excludedVoteCount = 0;

    console.log(`🗳️ 投票集計開始 - 回答総数: ${responseSnapshot.size}`);

    responseSnapshot.docs.forEach((doc) => {
      const responseData = doc.data();
      const senderId = responseData.senderId;
      const selectedRestaurantIdsString = responseData.restaurantVotingResponseData?.selectedRestaurantIds;

      // 辞退者の投票は除外
      if (rejectUsersSet.has(senderId)) {
        console.log(`🚫 辞退者の投票を除外: ${senderId}`);
        excludedVoteCount++;
        return;
      }

      if (selectedRestaurantIdsString) {
        // カンマ区切りの文字列を分割して各店舗に票を入れる
        const selectedIds = selectedRestaurantIdsString.split(",").map((id: string) => id.trim()).filter((id: string) => id);
        console.log(`✅ ${senderId} の投票: [${selectedIds.join(", ")}]`);
        selectedIds.forEach((restaurantId: string) => {
          restaurantVotes[restaurantId] = (restaurantVotes[restaurantId] || 0) + 1;
        });
        validVoteCount++;
      }
    });

    console.log(`🗳️ 投票集計結果 - 有効票: ${validVoteCount}, 除外票: ${excludedVoteCount}`);

    // リクエスト送信者の自動投票を追加（投票していない場合かつ辞退者でない場合のみ）
    if (requestSenderId && !senderResponseExists && !rejectUsersSet.has(requestSenderId)) {
      console.log("🎯 リクエスト送信者の自動投票を追加:", requestSenderId);

      // 全店舗に+1票を追加
      const restaurants = originalVotingData?.restaurants as Array<{id: string}> || [];
      console.log(`🎯 自動投票対象店舗: ${restaurants.length}店`);
      restaurants.forEach((restaurant) => {
        const beforeVotes = restaurantVotes[restaurant.id] || 0;
        restaurantVotes[restaurant.id] = beforeVotes + 1;
        console.log(`🎯 ${restaurant.id}: ${beforeVotes} → ${restaurantVotes[restaurant.id]}`);
      });

      console.log("✅ リクエスト送信者の自動投票完了");
    } else if (senderResponseExists) {
      console.log("👤 リクエスト送信者は既に投票済み");
    } else if (rejectUsersSet.has(requestSenderId || "")) {
      console.log("🚫 リクエスト送信者は辞退者のため自動投票なし");
    } else {
      console.log("ℹ️ リクエスト送信者の自動投票条件を満たしていません");
    }

    console.log("🗳️ 最終投票結果:", restaurantVotes);

    // 最多得票を取得
    const voteValues = Object.values(restaurantVotes);
    const maxVotes = voteValues.length > 0 ? Math.max(...voteValues) : 0;
    const winningRestaurants = Object.keys(restaurantVotes).filter(
      (restaurantId) => restaurantVotes[restaurantId] === maxVotes
    );

    console.log(`🏆 最多得票数: ${maxVotes}`);
    console.log(`🏆 最多得票店舗: ${winningRestaurants.length}店 [${winningRestaurants.join(", ")}]`);

    if (winningRestaurants.length === 1) {
      // 店舗決定
      console.log(`🎉 店舗決定: ${winningRestaurants[0]} (${maxVotes}票)`);
      await sendRestaurantDecisionMessage(
        groupId,
        restaurantVotingId,
        "decided",
        winningRestaurants[0],
        originalVotingData,
        maxVotes
      );
    } else if (winningRestaurants.length > 1) {
      // 引き分け
      console.log(`🤝 引き分け: ${winningRestaurants.length}店が${maxVotes}票で同票`);
      await sendRestaurantDecisionMessage(
        groupId,
        restaurantVotingId,
        "tie",
        null,
        originalVotingData,
        maxVotes,
        winningRestaurants
      );
    } else {
      console.log("⚠️ 有効な投票がありません");
    }

    console.log("✅ 店舗投票全員回答処理完了");
  } catch (error) {
    console.error("❌ 店舗投票全員回答チェックエラー:", error);
  }
}

/**
 * 店舗決定結果メッセージを送信
 */
async function sendRestaurantDecisionMessage(
  groupId: string,
  restaurantVotingId: string,
  status: string,
  decidedRestaurantId: string | null,
  originalVotingData: Record<string, unknown>,
  voteCount: number,
  tiedRestaurants?: string[]
): Promise<void> {
  try {
    console.log("🏪 店舗決定メッセージ送信開始:", {status, decidedRestaurantId, voteCount});

    let message = "";
    let decidedRestaurantName = "";

    if (status === "decided" && decidedRestaurantId) {
      // 決定した店舗の詳細を取得
      const restaurantResult = await pool.query(
        "SELECT name FROM restaurants WHERE id = $1",
        [decidedRestaurantId]
      );

      if (restaurantResult.rows.length > 0) {
        decidedRestaurantName = restaurantResult.rows[0].name;
        const decidedDate = originalVotingData?.decidedDate as string;
        const formattedDate = new Date(decidedDate).toLocaleDateString("ja-JP", {
          month: "numeric",
          day: "numeric",
          weekday: "short",
          hour: "2-digit",
          minute: "2-digit",
        });

        message = `グループデートが確定しました！🎉\n\n📅 ${formattedDate}\n🏪 ${decidedRestaurantName}\n\n素敵な時間をお過ごしください💕`;
      }
    } else if (status === "tie") {
      message = `店舗投票が引き分けとなりました。再度相談してください🤔\n引き分けの店舗: ${tiedRestaurants?.length || 0}店舗`;
    }

    // システムメッセージとして投稿
    const messageData = {
      groupId: groupId,
      senderId: "system",
      senderName: "システム",
      senderImageUrl: null,
      senderUuid: "system",
      message: message,
      type: "restaurant_decision",
      imageUrl: null,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      restaurantDecisionData: {
        originalVotingId: restaurantVotingId,
        status: status,
        decidedRestaurantId: decidedRestaurantId,
        decidedRestaurantName: decidedRestaurantName,
        voteCount: voteCount,
        decidedDate: originalVotingData?.decidedDate || null,
        tiedRestaurants: tiedRestaurants || null,
        originalVotingData: originalVotingData,
      },
      relatedRestaurantVotingId: restaurantVotingId,
      readBy: {},
    };

    await admin.firestore()
      .collection("groups")
      .doc(groupId)
      .collection("messages")
      .add(messageData);

    // グループの最新メッセージ情報を更新
    await admin.firestore()
      .collection("groups")
      .doc(groupId)
      .update({
        lastMessage: message,
        lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
        lastMessageBy: "system",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    console.log(`✅ 店舗決定メッセージ送信完了: ${status}`);
  } catch (error) {
    console.error("❌ 店舗決定メッセージ送信エラー:", error);
  }
}

/**
 * グループメンバーに通知送信
 */
async function sendGroupDateRequestNotifications(
  groupId: string,
  requesterId: string,
  requesterName: string,
  restaurantName: string,
  message: string
): Promise<void> {
  try {
    // Firestoreからグループメンバーを取得
    const groupDoc = await admin.firestore()
      .collection("groups")
      .doc(groupId)
      .get();

    if (!groupDoc.exists) {
      console.log("グループが見つかりません");
      return;
    }

    const groupData = groupDoc.data();
    const memberIds = groupData?.members || [];

    // 送信者を除くメンバーのFirebase UIDを取得
    const targetMemberIds = memberIds.filter((memberId: string) => memberId !== requesterId);

    if (targetMemberIds.length === 0) {
      console.log("通知送信対象のユーザーがいません");
      return;
    }

    console.log(`📧 通知送信対象: ${targetMemberIds.length}人`);

    // FCM通知を送信
    const notificationPayload = {
      notification: {
        title: "新しいグループデートリクエスト",
        body: `${requesterName}さんから${restaurantName}でのグループデートの提案があります`,
      },
      data: {
        type: "group_date_request",
        groupId: groupId,
        restaurantName: restaurantName,
        requesterName: requesterName,
        message: message,
      },
    };

    // FCM通知を個別に送信
    let successCount = 0;
    for (const memberId of targetMemberIds) {
      try {
        await admin.messaging().send({
          token: memberId, // memberIdがFirebase UIDと仮定
          ...notificationPayload,
        });
        successCount++;
      } catch (error) {
        console.error(`FCM送信エラー (memberId: ${memberId}):`, error);
      }
    }

    console.log(`✅ グループデートリクエスト通知送信完了: ${successCount}/${targetMemberIds.length}人`);
  } catch (error) {
    console.error("⚠️ グループデートリクエスト通知送信エラー:", error);
  }
}

export const startRestaurantTieBreakVoting = onCall(
  async (request: CallableRequest<{
    originalVotingId: string;
    tiedRestaurantIds: string[];
    originalData: Record<string, unknown>;
  }>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const {originalVotingId, tiedRestaurantIds, originalData} = request.data;

    if (!originalVotingId || !tiedRestaurantIds || tiedRestaurantIds.length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "元の投票IDと引き分け店舗IDが必要です"
      );
    }

    try {
      const userUuid = await getUserUuidFromFirebaseUid(request.auth.uid);
      if (!userUuid) {
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }

      // グループIDを取得
      let groupId = "";
      const votingQuery = admin.firestore()
        .collectionGroup("messages")
        .where("type", "==", "restaurant_voting")
        .where("restaurantVotingData.restaurantVotingId", "==", originalVotingId);

      const votingSnapshot = await votingQuery.get();
      if (!votingSnapshot.empty) {
        const votingDoc = votingSnapshot.docs[0];
        groupId = votingDoc.data().groupId;
      }

      if (!groupId) {
        throw new HttpsError("not-found", "グループが見つかりません");
      }

      // 引き分け店舗の詳細を取得
      const restaurantQuery = `
        SELECT id, name, image_url, category, prefecture, nearest_station, price_range, low_price, high_price
        FROM restaurants 
        WHERE id = ANY($1)
      `;
      const restaurantResult = await pool.query(restaurantQuery, [tiedRestaurantIds]);

      if (restaurantResult.rows.length === 0) {
        throw new HttpsError("not-found", "引き分け店舗が見つかりません");
      }

      const restaurants = restaurantResult.rows.map((row) => ({
        id: row.id,
        name: row.name,
        image_url: row.image_url,
        category: row.category,
        prefecture: row.prefecture,
        nearest_station: row.nearest_station,
        price_range: row.price_range,
        low_price: row.low_price,
        high_price: row.high_price,
      }));

      // 新しい店舗投票IDを生成
      const newVotingId = `restaurant_tiebreak_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

      // メンバーIDを取得（元の投票データから）
      const memberIds = originalData?.memberIds as string[] || [];
      const decidedDate = originalData?.decidedDate as string || "";
      const originalRequestId = originalData?.originalRequestId as string || "";

      // 再投票メッセージを挿入
      await insertRestaurantTieBreakVotingMessage(
        groupId,
        newVotingId,
        originalVotingId,
        restaurants,
        decidedDate,
        memberIds,
        originalRequestId
      );

      return {
        success: true,
        message: "店舗再投票を開始しました",
        newVotingId: newVotingId,
      };
    } catch (error) {
      console.error("店舗再投票開始エラー:", error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError(
        "internal",
        "店舗再投票の開始に失敗しました",
      );
    }
  }
);

/**
 * 店舗再投票メッセージを挿入
 */
async function insertRestaurantTieBreakVotingMessage(
  groupId: string,
  newVotingId: string,
  originalVotingId: string,
  restaurants: Array<{
    id: string;
    name: string;
    image_url?: string;
    category?: string;
    prefecture?: string;
    nearest_station?: string;
    price_range?: string;
    low_price?: number;
    high_price?: number;
  }>,
  decidedDate: string,
  memberIds: string[],
  originalRequestId: string
): Promise<void> {
  try {
    const restaurantVotingData = {
      restaurantVotingId: newVotingId,
      originalVotingId: originalVotingId,
      originalRequestId: originalRequestId,
      restaurants: restaurants,
      decidedDate: decidedDate,
      memberIds: memberIds,
      type: "restaurant_tiebreak_voting",
    };

    // Firestoreのサブコレクションに追加
    const messageData = {
      groupId: groupId,
      senderId: "system",
      senderName: "システム",
      senderImageUrl: null,
      senderUuid: "system",
      message: "店舗投票の引き分けによる再投票が始まりました！\n引き分けの店舗から選択してください 🏪",
      type: "restaurant_voting",
      imageUrl: null,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      restaurantVotingData: restaurantVotingData,
      relatedRestaurantVotingId: newVotingId,
      readBy: {},
    };

    await admin.firestore()
      .collection("groups")
      .doc(groupId)
      .collection("messages")
      .add(messageData);

    // グループの最新メッセージ情報を更新
    await admin.firestore()
      .collection("groups")
      .doc(groupId)
      .update({
        lastMessage: "店舗投票の再投票が始まりました",
        lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
        lastMessageBy: "system",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    console.log("✅ 店舗再投票メッセージを挿入しました");
  } catch (error) {
    console.error("❌ 店舗再投票メッセージ挿入エラー:", error);
    throw error;
  }
}

export const respondToRestaurantTieBreakVoting = onCall(
  async (request: CallableRequest<{
    votingId: string;
    selectedRestaurantIds: string[];
  }>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const {votingId, selectedRestaurantIds} = request.data;

    if (!votingId || !selectedRestaurantIds || selectedRestaurantIds.length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "投票IDと選択した店舗IDが必要です"
      );
    }

    try {
      const userUuid = await getUserUuidFromFirebaseUid(request.auth.uid);
      if (!userUuid) {
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }

      // グループIDを取得
      let groupId = "";
      const votingQuery = admin.firestore()
        .collectionGroup("messages")
        .where("type", "==", "restaurant_voting")
        .where("restaurantVotingData.restaurantVotingId", "==", votingId);

      const votingSnapshot = await votingQuery.get();
      if (!votingSnapshot.empty) {
        const votingDoc = votingSnapshot.docs[0];
        groupId = votingDoc.data().groupId;
      }

      if (!groupId) {
        throw new HttpsError("not-found", "グループが見つかりません");
      }

      // 既に回答しているかチェック
      const existingResponseQuery = admin.firestore()
        .collection("groups")
        .doc(groupId)
        .collection("messages")
        .where("type", "==", "restaurant_voting_response")
        .where("relatedRestaurantVotingId", "==", votingId)
        .where("senderId", "==", request.auth.uid);

      const existingResponseSnapshot = await existingResponseQuery.get();
      if (!existingResponseSnapshot.empty) {
        throw new HttpsError("already-exists", "既に投票済みです");
      }

      // ユーザー名を取得
      const userQuery = "SELECT name FROM users WHERE firebase_uid = $1";
      const userResult = await pool.query(userQuery, [request.auth.uid]);
      const userName = userResult.rows[0]?.name || "Unknown";

      // 店舗再投票回答を挿入
      await insertRestaurantVotingResponseMessage(
        groupId,
        request.auth.uid,
        votingId,
        selectedRestaurantIds,
        "店舗を選択しました！🏪",
        {name: userName, image_url: null},
        userUuid
      );

      // 全員が回答したかチェック
      await checkAndProcessRestaurantVotingResponses(groupId, votingId);

      return {
        success: true,
        message: "店舗再投票回答を送信しました",
      };
    } catch (error) {
      console.error("店舗再投票回答エラー:", error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError(
        "internal",
        "店舗再投票回答の送信に失敗しました",
      );
    }
  }
);
