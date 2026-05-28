"use strict";

const admin = require("firebase-admin");
const logger = require("firebase-functions/logger");
const { onSchedule } = require("firebase-functions/v2/scheduler");

const guardrails = require("./connectionRequestGuardrails");

const DEFAULT_STALE_RESERVATION_MS = 10 * 60 * 1000;
const DEFAULT_AUDIT_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

function rootFromDeps(deps) {
  if (deps && deps.root) {
    return deps.root;
  }
  return admin.database().ref();
}

function nowFromDeps(deps) {
  return guardrails.serverNow(deps && deps.clock);
}

const cleanupConnectionRequests = onSchedule(
  {
    schedule: "every 10 minutes",
    timeZone: "Etc/UTC",
  },
  async () => {
    const stats = await cleanupConnectionRequestsCore();
    logger.info("Connection request cleanup completed.", stats);
  },
);

async function cleanupConnectionRequestsCore(deps = {}) {
  const root = rootFromDeps(deps);
  const now = nowFromDeps(deps);
  const stats = {
    expiredRequests: 0,
    corruptRequests: 0,
    expiredPairLocks: 0,
    staleReservations: 0,
    oldAuditDays: 0,
    expiredEntitlements: 0,
  };

  await cleanupExpiredAndCorruptRequests(root, now, stats);
  await cleanupExpiredPairLocks(root, now, stats);
  await cleanupStaleReservations(root, now, stats, deps.staleReservationMs);
  await cleanupOldAudit(root, now, stats, deps.auditRetentionMs);
  await cleanupExpiredEntitlements(root, now, stats);

  return stats;
}

async function cleanupExpiredAndCorruptRequests(root, now, stats) {
  const snapshot = await root.child("connectionRequests").get();
  if (!snapshot.exists()) {
    return;
  }

  const updates = {};
  const pairLocksToClear = [];
  let auditIndex = 0;

  snapshot.forEach((receiverChild) => {
    const receiver = receiverChild.key;
    const receiverRequests = receiverChild.val() || {};
    for (const [requestId, value] of Object.entries(receiverRequests)) {
      const parsed = parseRequestRecord(value, requestId, receiver);
      if (!parsed.ok) {
        updates[`connectionRequests/${receiver}/${requestId}`] = null;
        const from = safeUsername(value && value.from);
        if (from) {
          updates[`connectionRequestOutboxes/${from}/${requestId}`] = null;
        }
        addAuditEvent(updates, now, auditIndex, "corrupt_request_removed", {
          requestId,
          receiver,
          error: parsed.error,
        });
        auditIndex += 1;
        stats.corruptRequests += 1;
        continue;
      }

      const record = parsed.value;
      if (
        !guardrails.isTerminalRequestStatus(record.status) &&
        record.expiresAt <= now
      ) {
        updates[`connectionRequests/${record.to}/${record.requestId}`] = null;
        updates[
          `connectionRequestOutboxes/${record.from}/${record.requestId}`
        ] = {
          ...record,
          status: "expired",
          updatedAt: now,
          expiredAt: now,
        };
        pairLocksToClear.push(record);
        queueFinalizeReservation(updates, record.requestId, now);
        addAuditEvent(updates, now, auditIndex, "expired_request_removed", {
          requestId: record.requestId,
          from: record.from,
          to: record.to,
          pairKey: record.pairKey,
        });
        auditIndex += 1;
        stats.expiredRequests += 1;
      }
    }
    return false;
  });

  if (Object.keys(updates).length > 0) {
    await root.update(updates);
  }
  await Promise.all(
    pairLocksToClear.map((record) =>
      clearPairLockIfCurrent(root, record.pairKey, record.requestId),
    ),
  );
}

async function cleanupExpiredPairLocks(root, now, stats) {
  const snapshot = await root.child("connectionRequestPairLocks").get();
  if (!snapshot.exists()) {
    return;
  }

  const locks = [];
  snapshot.forEach((child) => {
    const value = child.val() || {};
    const expiresAt = Number(value.expiresAt);
    if (
      guardrails.isTerminalRequestStatus(value.status) ||
      (Number.isFinite(expiresAt) && expiresAt <= now)
    ) {
      locks.push({
        pairKey: child.key,
        requestId: value.requestId,
        status: value.status,
        expiresAt: value.expiresAt,
      });
    }
    return false;
  });

  await Promise.all(
    locks.map(async (lock) => {
      const removed = await clearPairLockIfCurrent(
        root,
        lock.pairKey,
        lock.requestId,
      );
      if (removed) {
        stats.expiredPairLocks += 1;
      }
    }),
  );
}

async function cleanupStaleReservations(root, now, stats, staleMsOverride) {
  const staleMs = positiveNumberOrDefault(
    staleMsOverride,
    DEFAULT_STALE_RESERVATION_MS,
  );
  const snapshot = await root.child("connectionNotificationReservations").get();
  if (!snapshot.exists()) {
    return;
  }

  const reservations = [];
  snapshot.forEach((child) => {
    const value = child.val() || {};
    const createdAt = Number(value.createdAt);
    if (
      value.status === "reserved" &&
      Number.isFinite(createdAt) &&
      createdAt <= now - staleMs
    ) {
      reservations.push({ requestId: child.key, value });
    }
    return false;
  });

  for (const reservation of reservations) {
    await rollbackTargetUsage(
      root,
      reservation.value.sender,
      reservation.value.peer,
      reservation.value.dayKey,
      reservation.value.target,
    );
    await rollbackDailyUsage(
      root,
      reservation.value.sender,
      reservation.value.dayKey,
      reservation.value.daily,
    );
    await root
      .child(`connectionNotificationReservations/${reservation.requestId}`)
      .transaction(
        (current) => {
          if (current && current.status === "reserved") {
            return null;
          }
          return undefined;
        },
        undefined,
        false,
      );
    stats.staleReservations += 1;
  }
}

async function cleanupOldAudit(root, now, stats, retentionMsOverride) {
  const retentionMs = positiveNumberOrDefault(
    retentionMsOverride,
    DEFAULT_AUDIT_RETENTION_MS,
  );
  const snapshot = await root.child("connectionNotificationAudit").get();
  if (!snapshot.exists()) {
    return;
  }
  const cutoffDay = Number(guardrails.utcDayKey(now - retentionMs));
  const updates = {};
  snapshot.forEach((child) => {
    const day = Number(child.key);
    if (Number.isFinite(day) && day < cutoffDay) {
      updates[`connectionNotificationAudit/${child.key}`] = null;
      stats.oldAuditDays += 1;
    }
    return false;
  });
  if (Object.keys(updates).length > 0) {
    await root.update(updates);
  }
}

async function cleanupExpiredEntitlements(root, now, stats) {
  const snapshot = await root.child("connectionNotificationEntitlements").get();
  if (!snapshot.exists()) {
    return;
  }
  const updates = {};
  snapshot.forEach((child) => {
    const value = child.val() || {};
    const expiresAt = Number(value.expiresAt);
    if (Number.isFinite(expiresAt) && expiresAt <= now) {
      updates[`connectionNotificationEntitlements/${child.key}`] = null;
      stats.expiredEntitlements += 1;
    }
    return false;
  });
  if (Object.keys(updates).length > 0) {
    await root.update(updates);
  }
}

function parseRequestRecord(value, expectedRequestId, receiverKey) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return { ok: false, error: "missing" };
  }
  try {
    const requestId = guardrails.validateRequestId(
      value.requestId || expectedRequestId,
    );
    if (requestId !== expectedRequestId) {
      return { ok: false, error: "requestIdMismatch" };
    }
    const from = guardrails.normalizeUsername(value.from);
    const to = guardrails.normalizeUsername(value.to || receiverKey);
    const status = String(value.status || "");
    if (
      status !== "pending" &&
      status !== "seen" &&
      !guardrails.isTerminalRequestStatus(status)
    ) {
      return { ok: false, error: "invalidStatus" };
    }
    const createdAt = Number(value.createdAt);
    const updatedAt = Number(value.updatedAt);
    const expiresAt = Number(value.expiresAt);
    if (
      !Number.isFinite(createdAt) ||
      !Number.isFinite(updatedAt) ||
      !Number.isFinite(expiresAt)
    ) {
      return { ok: false, error: "invalidTimestamp" };
    }
    return {
      ok: true,
      value: {
        ...value,
        requestId,
        from,
        to,
        status,
        pairKey:
          typeof value.pairKey === "string"
            ? value.pairKey
            : guardrails.connectionRequestPairKey(from, to),
        createdAt,
        updatedAt,
        expiresAt,
      },
    };
  } catch (error) {
    return { ok: false, error: guardrails.sanitizeError(error) };
  }
}

function queueFinalizeReservation(updates, requestId, now) {
  updates[`connectionNotificationReservations/${requestId}/status`] = "spent";
  updates[`connectionNotificationReservations/${requestId}/finalizedAt`] = now;
  updates[`connectionNotificationReservations/${requestId}/updatedAt`] = now;
}

function addAuditEvent(updates, now, index, eventName, details) {
  const dayKey = guardrails.utcDayKey(now);
  const eventId = `connection_request_cleanup_${now}_${index}`;
  updates[`connectionNotificationAudit/${dayKey}/${eventId}`] = {
    eventName,
    createdAt: now,
    ...details,
  };
}

async function clearPairLockIfCurrent(root, pairKey, requestId) {
  if (!pairKey || !requestId) {
    return false;
  }
  const result = await root
    .child(`connectionRequestPairLocks/${pairKey}`)
    .transaction(
      (current) => {
        if (current && current.requestId === requestId) {
          return null;
        }
        return undefined;
      },
      undefined,
      false,
    );
  return result && result.committed === true;
}

async function rollbackDailyUsage(root, sender, dayKey, reservation) {
  if (!sender || !dayKey || !reservation) {
    return;
  }
  await root
    .child(`connectionNotificationUsage/${sender}/${dayKey}`)
    .transaction(
      (current) => {
        const usage = normalizeUsage(current);
        if (reservation.usedFreeDaily) {
          usage.freeUsed = Math.max(0, usage.freeUsed - 1);
        }
        if (reservation.usedExtraCredit) {
          usage.extraUsed = Math.max(0, usage.extraUsed - 1);
        }
        if (reservation.unlimited) {
          usage.unlimitedUsed = Math.max(0, usage.unlimitedUsed - 1);
        }
        usage.totalReserved = Math.max(0, usage.totalReserved - 1);
        return usage;
      },
      undefined,
      false,
    );
  if (reservation.usedExtraCredit && reservation.extraCreditDecremented) {
    await root
      .child(`connectionNotificationEntitlements/${sender}/extraCredits`)
      .transaction(
        (current) => Math.max(0, positiveIntegerOrDefault(current, 0)) + 1,
        undefined,
        false,
      );
  }
}

async function rollbackTargetUsage(root, sender, peer, dayKey, reservation) {
  if (!sender || !peer || !dayKey || !reservation) {
    return;
  }
  await root
    .child(`connectionNotificationTargetUsage/${sender}/${peer}/${dayKey}`)
    .transaction(
      (current) => {
        const usage = normalizeTargetUsage(current);
        usage.count = Math.max(0, usage.count - 1);
        return usage;
      },
      undefined,
      false,
    );
}

function normalizeUsage(value) {
  const source = value && typeof value === "object" ? value : {};
  return {
    freeUsed: Math.max(0, positiveIntegerOrDefault(source.freeUsed, 0)),
    extraUsed: Math.max(0, positiveIntegerOrDefault(source.extraUsed, 0)),
    unlimitedUsed: Math.max(
      0,
      positiveIntegerOrDefault(source.unlimitedUsed, 0),
    ),
    totalReserved: Math.max(
      0,
      positiveIntegerOrDefault(source.totalReserved, 0),
    ),
  };
}

function normalizeTargetUsage(value) {
  const source = value && typeof value === "object" ? value : {};
  return {
    count: Math.max(0, positiveIntegerOrDefault(source.count, 0)),
  };
}

function safeUsername(value) {
  try {
    return guardrails.normalizeUsername(value);
  } catch (_error) {
    return null;
  }
}

function positiveNumberOrDefault(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? number : fallback;
}

function positiveIntegerOrDefault(value, fallback) {
  const number = Number(value);
  return Number.isInteger(number) && number >= 0 ? number : fallback;
}

module.exports = {
  cleanupConnectionRequests,
  __test: {
    cleanupConnectionRequestsCore,
    parseRequestRecord,
  },
};
