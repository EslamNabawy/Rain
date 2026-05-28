const admin = require("firebase-admin");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const connectionRequests = require("./connectionRequests");

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
    const [callsSnapshot, pairLocksSnapshot, userLocksSnapshot] = await Promise.all([
      root.child("voiceCalls").orderByChild("expiresAt").endAt(now).get(),
      root.child("activeVoicePairs").orderByChild("expiresAt").endAt(now).get(),
      root.child("activeVoiceUsers").orderByChild("expiresAt").endAt(now).get(),
    ]);

    const updates = {};
    const expiredLocks = new Map();
    let deletedCalls = 0;
    let deletedLocks = 0;

    if (callsSnapshot.exists()) {
      callsSnapshot.forEach((child) => {
        const call = child.val() || {};
        updates[`voiceCalls/${child.key}`] = null;
        if (call.callee) {
          updates[`voiceCallInboxes/${call.callee}/${child.key}`] = null;
        }
        queueExpiredVoiceLock(expiredLocks, {
          path: call.pairId ? `activeVoicePairs/${call.pairId}` : null,
          value: { callId: child.key },
        });
        queueExpiredVoiceLock(expiredLocks, {
          path: call.caller ? `activeVoiceUsers/${call.caller}` : null,
          value: { callId: child.key },
        });
        queueExpiredVoiceLock(expiredLocks, {
          path: call.callee ? `activeVoiceUsers/${call.callee}` : null,
          value: { callId: child.key },
        });
        deletedCalls += 1;
        return false;
      });
    }

    if (pairLocksSnapshot.exists()) {
      pairLocksSnapshot.forEach((child) => {
        queueExpiredVoiceLock(expiredLocks, {
          path: `activeVoicePairs/${child.key}`,
          value: child.val() || {},
        });
        return false;
      });
    }

    if (userLocksSnapshot.exists()) {
      userLocksSnapshot.forEach((child) => {
        queueExpiredVoiceLock(expiredLocks, {
          path: `activeVoiceUsers/${child.key}`,
          value: child.val() || {},
        });
        return false;
      });
    }

    if (Object.keys(updates).length > 0) {
      await root.update(updates);
    }

    await Promise.all(
      Array.from(expiredLocks.values()).map(async (lock) => {
        const removed = await removeExpiredVoiceLockIfCurrent(
          root.child(lock.path),
          lock.value,
        );
        if (removed) {
          deletedLocks += 1;
        }
      }),
    );

    if (deletedCalls === 0 && deletedLocks === 0) {
      logger.info("No expired voice calls found.");
      return;
    }

    logger.info("Deleted expired voice call signaling data.", {
      deletedCalls,
      deletedLocks,
    });
  },
);

exports.createConnectionRequest = connectionRequests.createConnectionRequest;
exports.cancelConnectionRequest = connectionRequests.cancelConnectionRequest;
exports.acceptConnectionRequest = connectionRequests.acceptConnectionRequest;
exports.rejectConnectionRequest = connectionRequests.rejectConnectionRequest;
exports.markConnectionRequestSeen =
  connectionRequests.markConnectionRequestSeen;
exports.muteConnectionRequestsFromPeer =
  connectionRequests.muteConnectionRequestsFromPeer;
exports.unmuteConnectionRequestsFromPeer =
  connectionRequests.unmuteConnectionRequestsFromPeer;
exports.getConnectionRequestQuotaSummary =
  connectionRequests.getConnectionRequestQuotaSummary;

function queueExpiredVoiceLock(lockMap, expected) {
  if (!expected.path || !expected.value || !expected.value.callId) {
    return;
  }
  const existing = lockMap.get(expected.path);
  if (existing && existing.value.createdAt !== undefined) {
    return;
  }
  lockMap.set(expected.path, expected);
}

async function removeExpiredVoiceLockIfCurrent(ref, expected) {
  const result = await ref.transaction((current) => {
    if (!current) {
      return undefined;
    }
    if (voiceLockMatchesExpected(current, expected)) {
      return null;
    }
    return undefined;
  }, undefined, false);
  return result.committed === true;
}

function voiceLockMatchesExpected(current, expected) {
  if (current.callId !== expected.callId) {
    return false;
  }
  for (const field of ["createdAt", "updatedAt", "expiresAt"]) {
    if (expected[field] !== undefined && current[field] !== expected[field]) {
      return false;
    }
  }
  return true;
}
