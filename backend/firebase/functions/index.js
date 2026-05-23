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

exports.cleanupVoiceCalls = onSchedule(
  {
    schedule: "every 5 minutes",
    timeZone: "Etc/UTC",
  },
  async () => {
    const now = Date.now();
    const root = admin.database().ref();
    const [callsSnapshot, locksSnapshot] = await Promise.all([
      root.child("voiceCalls").orderByChild("expiresAt").endAt(now).get(),
      root.child("activeVoicePairs").orderByChild("expiresAt").endAt(now).get(),
    ]);

    const updates = {};
    let deletedCalls = 0;
    let deletedLocks = 0;

    if (callsSnapshot.exists()) {
      callsSnapshot.forEach((child) => {
        const call = child.val() || {};
        updates[`voiceCalls/${child.key}`] = null;
        if (call.callee) {
          updates[`voiceCallInboxes/${call.callee}/${child.key}`] = null;
        }
        if (call.pairId) {
          updates[`activeVoicePairs/${call.pairId}`] = null;
        }
        deletedCalls += 1;
        return false;
      });
    }

    if (locksSnapshot.exists()) {
      locksSnapshot.forEach((child) => {
        updates[`activeVoicePairs/${child.key}`] = null;
        deletedLocks += 1;
        return false;
      });
    }

    if (Object.keys(updates).length === 0) {
      logger.info("No expired voice calls found.");
      return;
    }

    await root.update(updates);
    logger.info("Deleted expired voice call signaling data.", {
      deletedCalls,
      deletedLocks,
    });
  },
);
