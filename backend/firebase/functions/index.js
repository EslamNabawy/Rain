const admin = require("firebase-admin");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");

admin.initializeApp();

const HEARTBEAT_STALE_MS = 7 * 60 * 1000;

exports.cleanupPresence = onSchedule(
  {
    schedule: "every 3 minutes",
    timeZone: "Etc/UTC",
  },
  async () => {
    const now = Date.now();
    const cutoff = now - HEARTBEAT_STALE_MS;
    const snapshot = await admin
      .database()
      .ref("presence")
      .orderByChild("lastHeartbeat")
      .endAt(cutoff)
      .get();

    if (!snapshot.exists()) {
      logger.info("No stale users found.");
      return;
    }

    const updates = {};
    let affectedUsers = 0;

    snapshot.forEach((child) => {
      const value = child.val() || {};
      if (value.online === true) {
        updates[`${child.key}/online`] = false;
        updates[`${child.key}/lastSeen`] = now;
        updates[`${child.key}/updatedAt`] = now;
        affectedUsers += 1;
      }
      return false;
    });

    if (affectedUsers == 0) {
      logger.info("Stale users found, but none were online.");
      return;
    }

    await admin.database().ref("presence").update(updates);
    logger.info("Marked stale users offline.", { affectedUsers });
  },
);

exports.cleanupRooms = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "Etc/UTC",
  },
  async () => {
    const now = Date.now();
    const snapshot = await admin
      .database()
      .ref("rooms")
      .orderByChild("expiresAt")
      .endAt(now)
      .get();

    if (!snapshot.exists()) {
      logger.info("No rooms found for cleanup.");
      return;
    }

    const updates = {};
    let deletedRooms = 0;

    snapshot.forEach((child) => {
      updates[child.key] = null;
      deletedRooms += 1;
      return false;
    });

    if (deletedRooms == 0) {
      logger.info("No expired rooms found.");
      return;
    }

    await admin.database().ref("rooms").update(updates);
    logger.info("Deleted expired signaling rooms.", { deletedRooms });
  },
);
