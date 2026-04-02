const admin = require("firebase-admin");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");

admin.initializeApp();

const HEARTBEAT_STALE_MS = 7 * 60 * 1000;
const ROOM_TTL_MS = 15 * 60 * 1000;

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
      .ref("users")
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
        affectedUsers += 1;
      }
      return false;
    });

    if (affectedUsers == 0) {
      logger.info("Stale users found, but none were online.");
      return;
    }

    await admin.database().ref("users").update(updates);
    logger.info("Marked stale users offline.", { affectedUsers });
  },
);

exports.cleanupRooms = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "Etc/UTC",
  },
  async () => {
    const cutoff = Date.now() - ROOM_TTL_MS;
    const snapshot = await admin.database().ref("rooms").get();

    if (!snapshot.exists()) {
      logger.info("No rooms found for cleanup.");
      return;
    }

    const updates = {};
    let deletedRooms = 0;

    snapshot.forEach((child) => {
      const room = child.val() || {};
      const offerTs = typeof room.offer?.ts === "number" ? room.offer.ts : 0;
      const answerTs = typeof room.answer?.ts === "number" ? room.answer.ts : 0;
      const lastActivity = Math.max(offerTs, answerTs);

      if (lastActivity === 0 || lastActivity < cutoff) {
        updates[child.key] = null;
        deletedRooms += 1;
      }
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
