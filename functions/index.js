const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

admin.initializeApp();

/**
 * Send push notification when a notification document is created
 */
exports.sendPushNotification = onDocumentCreated(
    "notifications/{notificationId}",
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const notification = snap.data();

      // Prevent double processing
      if (notification.processed) return;

      const {recipientId, fcmToken, fcmTokens, title, body, data} =
          notification;

      const tokens = new Set();
      const addToken = (token) => {
        if (typeof token === "string" && token.trim()) {
          tokens.add(token.trim());
        }
      };
      const addTokensFromCollection = (value) => {
        if (Array.isArray(value)) {
          for (const token of value) addToken(token);
          return;
        }
        if (value && typeof value === "object") {
          for (const token of Object.values(value)) addToken(token);
        }
      };

      addToken(fcmToken);
      addTokensFromCollection(fcmTokens);

      if (tokens.size === 0 && typeof recipientId === "string" &&
          recipientId.trim()) {
        try {
          const userSnap = await admin.firestore()
              .collection("users")
              .doc(recipientId.trim())
              .get();
          const userData = userSnap.data();
          if (userData) {
            addToken(userData.fcmToken);
            addTokensFromCollection(userData.fcmTokens);
          }
        } catch (error) {
          console.log("Failed to resolve recipient tokens:", error);
        }
      }

      const targetTokens = Array.from(tokens);
      if (targetTokens.length === 0) {
        console.log("No FCM tokens available");
        return;
      }

      const normalizedData = {};
      if (data && typeof data === "object") {
        for (const [key, value] of Object.entries(data)) {
          if (value === null || value === undefined) continue;
          normalizedData[key] =
            typeof value === "string" ? value : JSON.stringify(value);
        }
      }

      const isCallOffer = normalizedData.type === "call_offer";
      const message = {
        data: normalizedData,
        android: {
          priority: "high",
          ...(isCallOffer
            ? {}
            : {
              notification: {
                sound: "default",
                channelId: "high_importance_channel",
              },
            }),
        },
        apns: {
          headers: isCallOffer
            ? {
              "apns-push-type": "background",
              "apns-priority": "5",
            }
            : undefined,
          payload: {
            aps: isCallOffer
              ? {"content-available": 1}
              : {
                sound: "default",
                badge: 1,
              },
          },
        },
      };

      if (!isCallOffer) {
        message.notification = {title, body};
      }

      let successCount = 0;
      let failureCount = 0;
      const failedTokens = [];

      try {
        if (targetTokens.length === 1) {
          await admin.messaging().send({
            ...message,
            token: targetTokens[0],
          });
          successCount = 1;
        } else {
          const multicastResponse = await admin
              .messaging()
              .sendEachForMulticast({
                ...message,
                tokens: targetTokens,
              });
          successCount = multicastResponse.successCount;
          failureCount = multicastResponse.failureCount;

          multicastResponse.responses.forEach((response, index) => {
            if (!response.success) {
              failedTokens.push(targetTokens[index]);
            }
          });
        }

        await snap.ref.update({
          processed: true,
          successCount,
          failureCount,
          failedTokens,
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(
            "Notification sent: success=%s, failed=%s",
            successCount,
            failureCount,
        );
      } catch (error) {
        console.error("Error sending notification:", error);

        await snap.ref.update({
          processed: true,
          failed: true,
          error: error.message,
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    },
);

/**
 * Cleanup old notifications (runs every 24 hours)
 */
exports.cleanupOldNotifications = onSchedule(
    "every 24 hours",
    async () => {
      const cutoffDate = new Date();
      cutoffDate.setDate(cutoffDate.getDate() - 7);

      const snapshot = await admin.firestore()
          .collection("notifications")
          .where("processed", "==", true)
          .where("createdAt", "<", cutoffDate)
          .get();

      const batch = admin.firestore().batch();
      snapshot.docs.forEach((doc) => {
        batch.delete(doc.ref);
      });

      await batch.commit();
      console.log(`Deleted ${snapshot.size} old notifications`);
    },
);
