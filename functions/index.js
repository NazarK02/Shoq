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

      const {fcmToken, title, body, data} = notification;

      if (!fcmToken) {
        console.log("No FCM token available");
        return;
      }

      const message = {
        token: fcmToken,
        notification: {
          title,
          body,
        },
        data: data || {},
        android: {
          priority: "high",
          notification: {
            sound: "default",
            channelId: "high_importance_channel",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
      };

      try {
        await admin.messaging().send(message);

        await snap.ref.update({
          processed: true,
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log("Notification sent successfully");
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
