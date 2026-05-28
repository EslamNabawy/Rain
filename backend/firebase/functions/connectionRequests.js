"use strict";

const admin = require("firebase-admin");
const { onCall } = require("firebase-functions/v2/https");

const guardrails = require("./connectionRequestGuardrails");

const callableOptions = {
  region: "us-central1",
};

const actionTypes = Object.freeze({
  createConnectionRequest: "createConnectionRequest",
  cancelConnectionRequest: "cancelConnectionRequest",
  acceptConnectionRequest: "acceptConnectionRequest",
  rejectConnectionRequest: "rejectConnectionRequest",
  markConnectionRequestSeen: "markConnectionRequestSeen",
  muteConnectionRequestsFromPeer: "muteConnectionRequestsFromPeer",
  unmuteConnectionRequestsFromPeer: "unmuteConnectionRequestsFromPeer",
  getConnectionRequestQuotaSummary: "getConnectionRequestQuotaSummary",
});

const DEFAULT_REQUEST_TTL_MS = 45 * 1000;
const DEFAULT_MAX_PENDING_INBOUND = 25;
const DEFAULT_DAILY_FREE_LIMIT = 20;
const DEFAULT_PER_TARGET_DAILY_LIMIT = 3;
const DEFAULT_BURST_LIMIT = 3;
const DEFAULT_BURST_WINDOW_MS = 60 * 1000;
const DEFAULT_COOLDOWN_MS = 15 * 1000;
const PRESENCE_FRESHNESS_MS = 90 * 1000;

function rootFromDeps(deps) {
  if (deps && deps.root) {
    return deps.root;
  }
  return admin.database().ref();
}

function nowFromDeps(deps) {
  return guardrails.serverNow(deps && deps.clock);
}

async function preparePeerOperation(data, request, deps, action) {
  const now = nowFromDeps(deps);
  let peer;
  try {
    peer = guardrails.peerFromData(data);
  } catch (error) {
    return {
      ok: false,
      response: guardrails.denied(error.reasonCode || "malformedRequest", {
        diagnostics: {
          action,
          serverNow: now,
        },
      }),
    };
  }

  const auth = await guardrails.resolveAuthUsername(rootFromDeps(deps), request);
  if (!auth.ok) {
    return {
      ok: false,
      response: attachDiagnostics(auth.response, {
        action,
        serverNow: now,
      }),
    };
  }

  if (auth.username === peer) {
    return {
      ok: false,
      response: guardrails.denied("selfRequest", {
        peerLabel: peer,
        diagnostics: {
          action,
          serverNow: now,
          sender: auth.username,
          peer,
        },
      }),
    };
  }

  return {
    ok: true,
    action,
    now,
    sender: auth.username,
    peer,
    pairKey: guardrails.connectionRequestPairKey(auth.username, peer),
  };
}

async function prepareRequestOperation(data, request, deps, action) {
  const now = nowFromDeps(deps);
  let requestId;
  try {
    requestId = guardrails.requestIdFromData(data);
  } catch (error) {
    return {
      ok: false,
      response: guardrails.denied(error.reasonCode || "malformedRequest", {
        diagnostics: {
          action,
          serverNow: now,
        },
      }),
    };
  }

  const auth = await guardrails.resolveAuthUsername(rootFromDeps(deps), request);
  if (!auth.ok) {
    return {
      ok: false,
      response: attachDiagnostics(auth.response, {
        action,
        serverNow: now,
        requestId,
      }),
    };
  }

  return {
    ok: true,
    action,
    now,
    requestId,
    sender: auth.username,
  };
}

async function prepareAccountOperation(request, deps, action) {
  const now = nowFromDeps(deps);
  const auth = await guardrails.resolveAuthUsername(rootFromDeps(deps), request);
  if (!auth.ok) {
    return {
      ok: false,
      response: attachDiagnostics(auth.response, {
        action,
        serverNow: now,
      }),
    };
  }

  return {
    ok: true,
    action,
    now,
    sender: auth.username,
  };
}

async function createConnectionRequestCore(data, request, deps = {}) {
  const prepared = await preparePeerOperation(
    data,
    request,
    deps,
    actionTypes.createConnectionRequest,
  );
  if (!prepared.ok) {
    return prepared.response;
  }

  const root = rootFromDeps(deps);
  try {
    const protection = await evaluateReceiverProtections(root, prepared);
    if (!protection.allowed) {
      return protection.response;
    }

    const requestId = createRequestId(prepared, deps);
    const expiresAt = prepared.now + protection.config.requestTtlMs;
    const pairClaim = await claimPairLock(root, prepared, requestId, expiresAt);
    if (!pairClaim.allowed) {
      return pairClaim.response;
    }

    const inboxCap = await evaluateReceiverPendingCap(
      root,
      prepared,
      protection.config.maxPendingInbound,
    );
    if (!inboxCap.allowed) {
      await rollbackPairLock(root, prepared.pairKey, requestId);
      return inboxCap.response;
    }

    const quota = await reserveSenderQuota(
      prepared,
      requestId,
      deps,
      protection.config,
      protection.entitlement,
    );
    if (!quota.allowed) {
      await rollbackPairLock(root, prepared.pairKey, requestId);
      return quota.response;
    }

    const payload = buildConnectionRequestPayload({
      data,
      prepared,
      requestId,
      expiresAt,
      receiverPresence: protection.receiverPresence,
      quota: quota.quota,
    });

    try {
      await root.update({
        [`connectionRequests/${prepared.peer}/${requestId}`]: payload.inbox,
        [`connectionRequestOutboxes/${prepared.sender}/${requestId}`]:
          payload.outbox,
        [`connectionNotificationReservations/${requestId}/status`]: "spent",
        [`connectionNotificationReservations/${requestId}/finalizedAt`]:
          prepared.now,
        [`connectionNotificationReservations/${requestId}/updatedAt`]:
          prepared.now,
      });
    } catch (error) {
      await rollbackPairLock(root, prepared.pairKey, requestId);
      await releaseSenderQuota(prepared, requestId, deps);
      return denyPrepared(prepared, "backendUnavailable", {
        requestId,
        diagnostics: {
          error: guardrails.sanitizeError(error),
          rollbackPairLock: true,
          rollbackQuota: true,
        },
      });
    }

    return guardrails.allowedResponse({
      requestId,
      status: "pending",
      userMessage: `Connection request sent to @${prepared.peer}.`,
      quota: quota.quota,
      diagnostics: preparedDiagnostics(prepared, {
        requestId,
        pairKey: prepared.pairKey,
        receiverPresenceAt: protection.receiverPresence.lastHeartbeat,
        receiverPendingCount: inboxCap.pendingCount,
        pairLockClaimed: true,
        quotaFinalized: true,
      }),
    });
  } catch (error) {
    return denyPrepared(prepared, "backendUnavailable", {
      diagnostics: {
        error: guardrails.sanitizeError(error),
      },
    });
  }
}

async function cancelConnectionRequestCore(data, request, deps = {}) {
  return requestShell(data, request, deps, actionTypes.cancelConnectionRequest);
}

async function acceptConnectionRequestCore(data, request, deps = {}) {
  return requestShell(data, request, deps, actionTypes.acceptConnectionRequest);
}

async function rejectConnectionRequestCore(data, request, deps = {}) {
  return requestShell(data, request, deps, actionTypes.rejectConnectionRequest);
}

async function markConnectionRequestSeenCore(data, request, deps = {}) {
  return requestShell(
    data,
    request,
    deps,
    actionTypes.markConnectionRequestSeen,
  );
}

async function muteConnectionRequestsFromPeerCore(data, request, deps = {}) {
  const prepared = await preparePeerOperation(
    data,
    request,
    deps,
    actionTypes.muteConnectionRequestsFromPeer,
  );
  if (!prepared.ok) {
    return prepared.response;
  }
  return foundationNotReady(prepared);
}

async function unmuteConnectionRequestsFromPeerCore(data, request, deps = {}) {
  const prepared = await preparePeerOperation(
    data,
    request,
    deps,
    actionTypes.unmuteConnectionRequestsFromPeer,
  );
  if (!prepared.ok) {
    return prepared.response;
  }
  return foundationNotReady(prepared);
}

async function getConnectionRequestQuotaSummaryCore(_data, request, deps = {}) {
  const prepared = await prepareAccountOperation(
    request,
    deps,
    actionTypes.getConnectionRequestQuotaSummary,
  );
  if (!prepared.ok) {
    return prepared.response;
  }

  const root = rootFromDeps(deps);
  try {
    const config = await readConnectionNotificationConfig(root);
    const entitlement = await readSenderEntitlement(
      root,
      prepared.sender,
      prepared.now,
    );
    const dayKey = guardrails.utcDayKey(prepared.now);
    const usage = normalizeUsage(
      await readValue(
        root,
        `connectionNotificationUsage/${prepared.sender}/${dayKey}`,
      ),
    );
    return guardrails.allowedResponse({
      status: "current",
      userMessage: "Connection request quota loaded.",
      quota: quotaSummary({
        config,
        entitlement,
        usage,
        targetUsage: null,
        dayKey,
        now: prepared.now,
      }),
      diagnostics: preparedDiagnostics(prepared, {
        dayKey,
        entitlementExpired: entitlement.expired,
      }),
    });
  } catch (error) {
    return guardrails.denied("backendUnavailable", {
      diagnostics: {
        action: prepared.action,
        serverNow: prepared.now,
        sender: prepared.sender,
        error: guardrails.sanitizeError(error),
      },
    });
  }
}

async function requestShell(data, request, deps, action) {
  const prepared = await prepareRequestOperation(data, request, deps, action);
  if (!prepared.ok) {
    return prepared.response;
  }
  return foundationNotReady(prepared);
}

function foundationNotReady(prepared) {
  return guardrails.denied("backendUnavailable", {
    requestId: prepared.requestId,
    peerLabel: prepared.peer,
    diagnostics: {
      action: prepared.action,
      foundationReady: true,
      serverNow: prepared.now,
      sender: prepared.sender,
      peer: prepared.peer,
      pairKey: prepared.pairKey,
      requestId: prepared.requestId,
    },
  });
}

async function evaluateReceiverProtections(root, prepared) {
  const friendship = await hasAcceptedFriendship(
    root,
    prepared.sender,
    prepared.peer,
  );
  if (!friendship) {
    return denyResult(prepared, "notAcceptedFriend");
  }

  const blocked = await hasBlockBetween(root, prepared.sender, prepared.peer);
  if (blocked) {
    return denyResult(prepared, "blocked");
  }

  const muted = await isReceiverMuted(root, prepared.peer, prepared.sender);
  if (muted) {
    return denyResult(prepared, "mutedByReceiver");
  }

  const receiverPresence = await readValue(root, `presence/${prepared.peer}`);
  if (!isFreshOnlinePresence(receiverPresence, prepared.now)) {
    return denyResult(prepared, "peerOffline", {
      diagnostics: {
        receiverOnline: receiverPresence && receiverPresence.online === true,
        receiverLastHeartbeat:
          receiverPresence && receiverPresence.lastHeartbeat,
      },
    });
  }

  const config = await readConnectionNotificationConfig(root);
  if (config.enabled === false) {
    return denyResult(prepared, "notificationsDisabledByAdmin");
  }

  const entitlement = await readSenderEntitlement(
    root,
    prepared.sender,
    prepared.now,
  );
  if (entitlement.disabled === true) {
    return denyResult(prepared, "permissionDenied", {
      diagnostics: {
        entitlementDisabled: true,
        entitlementExpired: entitlement.expired,
      },
    });
  }

  return {
    allowed: true,
    config,
    entitlement,
    receiverPresence,
  };
}

async function hasAcceptedFriendship(root, sender, peer) {
  const [senderToPeer, peerToSender] = await Promise.all([
    exists(root, `friendships/${sender}/${peer}`),
    exists(root, `friendships/${peer}/${sender}`),
  ]);
  return senderToPeer && peerToSender;
}

async function hasBlockBetween(root, sender, peer) {
  const [senderBlockedPeer, peerBlockedSender] = await Promise.all([
    exists(root, `blocks/${sender}/${peer}`),
    exists(root, `blocks/${peer}/${sender}`),
  ]);
  return senderBlockedPeer || peerBlockedSender;
}

async function isReceiverMuted(root, receiver, sender) {
  const mute = await readValue(
    root,
    `connectionNotificationMutes/${receiver}/${sender}`,
  );
  return mute === true || (mute && mute.muted === true);
}

function isFreshOnlinePresence(value, now) {
  if (!value || typeof value !== "object") {
    return false;
  }
  const lastHeartbeat = Number(value.lastHeartbeat);
  return (
    value.online === true &&
    Number.isFinite(lastHeartbeat) &&
    now - lastHeartbeat < PRESENCE_FRESHNESS_MS
  );
}

async function readConnectionNotificationConfig(root) {
  const rootConfig = (await readValue(root, "connectionNotificationConfig")) || {};
  const globalConfig =
    rootConfig && typeof rootConfig.global === "object"
      ? rootConfig.global
      : rootConfig;
  return {
    enabled: globalConfig.enabled !== false,
    requestTtlMs: positiveNumberOrDefault(
      globalConfig.requestTtlMs,
      DEFAULT_REQUEST_TTL_MS,
    ),
    maxPendingInbound: Math.max(
      0,
      positiveIntegerOrDefault(
        globalConfig.maxPendingInboundPerUser,
        DEFAULT_MAX_PENDING_INBOUND,
      ),
    ),
    dailyFreeLimit: Math.max(
      0,
      positiveIntegerOrDefault(
        globalConfig.dailyFreeLimit ??
          globalConfig.freeDailyLimit ??
          globalConfig.dailyLimit,
        DEFAULT_DAILY_FREE_LIMIT,
      ),
    ),
    perTargetDailyLimit: Math.max(
      0,
      positiveIntegerOrDefault(
        globalConfig.perTargetDailyLimit ?? globalConfig.perTargetLimit,
        DEFAULT_PER_TARGET_DAILY_LIMIT,
      ),
    ),
    burstLimit: Math.max(
      1,
      positiveIntegerOrDefault(globalConfig.burstLimit, DEFAULT_BURST_LIMIT),
    ),
    burstWindowMs: positiveNumberOrDefault(
      globalConfig.burstWindowMs,
      DEFAULT_BURST_WINDOW_MS,
    ),
    cooldownMs: positiveNumberOrDefault(
      globalConfig.cooldownMs,
      DEFAULT_COOLDOWN_MS,
    ),
  };
}

async function readSenderEntitlement(root, username, now) {
  const raw =
    (await readValue(root, `connectionNotificationEntitlements/${username}`)) ||
    {};
  const expiresAt = Number(raw.expiresAt);
  const expired = Number.isFinite(expiresAt) && expiresAt <= now;
  if (expired) {
    return {
      disabled: false,
      extraCredits: 0,
      unlimitedUntil: null,
      expired: true,
      raw,
    };
  }
  const unlimitedUntil = Number(raw.unlimitedUntil);
  return {
    disabled: raw.disabled === true,
    extraCredits: Math.max(0, positiveIntegerOrDefault(raw.extraCredits, 0)),
    unlimitedUntil: Number.isFinite(unlimitedUntil) ? unlimitedUntil : null,
    expired: false,
    raw,
  };
}

async function claimPairLock(root, prepared, requestId, expiresAt) {
  const lockRef = root.child(`connectionRequestPairLocks/${prepared.pairKey}`);
  let duplicateLock = null;
  const result = await lockRef.transaction(
    (current) => {
      if (isLiveOpenRequest(current, prepared.now)) {
        duplicateLock = current;
        return undefined;
      }
      return {
        requestId,
        pairKey: prepared.pairKey,
        from: prepared.sender,
        to: prepared.peer,
        status: "pending",
        createdAt: prepared.now,
        updatedAt: prepared.now,
        expiresAt,
      };
    },
    undefined,
    false,
  );

  if (duplicateLock) {
    return {
      allowed: false,
      response: denyPrepared(prepared, "duplicatePendingRequest", {
        requestId: duplicateLock.requestId || null,
        status: duplicateLock.status || "pending",
        diagnostics: {
          duplicateRequestId: duplicateLock.requestId || null,
          duplicateExpiresAt: duplicateLock.expiresAt || null,
        },
      }),
    };
  }

  if (!result || result.committed !== true) {
    return {
      allowed: false,
      response: denyPrepared(prepared, "backendUnavailable", {
        requestId,
        diagnostics: { pairLockCommitted: false },
      }),
    };
  }

  return { allowed: true };
}

function isLiveOpenRequest(request, now) {
  if (!request || typeof request !== "object") {
    return false;
  }
  if (guardrails.isTerminalRequestStatus(request.status)) {
    return false;
  }
  const expiresAt = Number(request.expiresAt);
  return Number.isFinite(expiresAt) && expiresAt > now;
}

async function evaluateReceiverPendingCap(root, prepared, maxPendingInbound) {
  const pendingCount = await countLivePendingInboxRequests(
    root,
    prepared.peer,
    prepared.now,
    maxPendingInbound + 1,
  );
  if (pendingCount >= maxPendingInbound) {
    return {
      allowed: false,
      pendingCount,
      response: denyPrepared(prepared, "receiverInboxFull", {
        diagnostics: {
          receiverPendingCount: pendingCount,
          maxPendingInbound,
        },
      }),
    };
  }
  return { allowed: true, pendingCount };
}

async function countLivePendingInboxRequests(root, username, now, limit) {
  const snapshot = await root
    .child(`connectionRequests/${username}`)
    .orderByChild("status")
    .equalTo("pending")
    .limitToFirst(limit)
    .get();
  let count = 0;
  snapshot.forEach((child) => {
    const value = child.val();
    if (isLiveOpenRequest(value, now)) {
      count += 1;
    }
    return count >= limit;
  });
  return count;
}

async function reserveSenderQuota(
  prepared,
  requestId,
  deps,
  config,
  entitlement,
) {
  if (typeof deps.reserveSenderQuota !== "function") {
    return reserveConnectionRequestQuota({
      root: rootFromDeps(deps),
      prepared,
      requestId,
      config,
      entitlement,
    });
  }
  const reservation = await deps.reserveSenderQuota({
    action: prepared.action,
    now: prepared.now,
    requestId,
    sender: prepared.sender,
    peer: prepared.peer,
    pairKey: prepared.pairKey,
  });
  if (!reservation || reservation.allowed === true || reservation.ok === true) {
    return { allowed: true, quota: reservation ? reservation.quota || null : null };
  }
  return {
    allowed: false,
    response: denyPrepared(prepared, reservation.reasonCode || "rateLimited", {
      requestId,
      retryAfterMs: reservation.retryAfterMs,
      quota: reservation.quota || null,
      diagnostics: {
        quotaReservationDenied: true,
        quotaReasonCode: reservation.reasonCode || "rateLimited",
      },
    }),
  };
}

async function releaseSenderQuota(prepared, requestId, deps) {
  if (typeof deps.releaseSenderQuota !== "function") {
    await releaseQuotaReservation(rootFromDeps(deps), requestId);
    return;
  }
  await deps.releaseSenderQuota({
    action: prepared.action,
    now: prepared.now,
    requestId,
    sender: prepared.sender,
    peer: prepared.peer,
    pairKey: prepared.pairKey,
  });
}

async function reserveConnectionRequestQuota({
  root,
  prepared,
  requestId,
  config,
  entitlement,
}) {
  const dayKey = guardrails.utcDayKey(prepared.now);
  const unlimited =
    Number.isFinite(entitlement.unlimitedUntil) &&
    entitlement.unlimitedUntil > prepared.now;

  const daily = await reserveDailyUsage({
    root,
    prepared,
    config,
    entitlement,
    requestId,
    dayKey,
    unlimited,
  });
  if (!daily.allowed) {
    return daily;
  }

  const target = await reserveTargetUsage({
    root,
    prepared,
    config,
    requestId,
    dayKey,
  });
  if (!target.allowed) {
    await rollbackDailyUsage(root, prepared.sender, dayKey, daily.reservation);
    return target;
  }

  const reservation = {
    requestId,
    sender: prepared.sender,
    peer: prepared.peer,
    pairKey: prepared.pairKey,
    status: "reserved",
    createdAt: prepared.now,
    updatedAt: prepared.now,
    dayKey,
    daily: daily.reservation,
    target: target.reservation,
    finalizedAt: null,
  };

  const reservationClaim = await root
    .child(`connectionNotificationReservations/${requestId}`)
    .transaction(
      (current) => {
        if (current) {
          return undefined;
        }
        return reservation;
      },
      undefined,
      false,
    );

  if (!reservationClaim || reservationClaim.committed !== true) {
    await rollbackTargetUsage(
      root,
      prepared.sender,
      prepared.peer,
      dayKey,
      target.reservation,
    );
    await rollbackDailyUsage(root, prepared.sender, dayKey, daily.reservation);
    return {
      allowed: false,
      response: denyPrepared(prepared, "backendUnavailable", {
        requestId,
        diagnostics: { quotaReservationCommitted: false, dayKey },
      }),
    };
  }

  const quota = quotaSummary({
    config,
    entitlement: daily.reservation.usedExtraCredit
      ? {
          ...entitlement,
          extraCredits: daily.reservation.extraCreditsAfter,
        }
      : entitlement,
    usage: daily.usage,
    targetUsage: target.usage,
    dayKey,
    reservation,
    now: prepared.now,
  });
  return {
    allowed: true,
    quota,
    reservation,
  };
}

async function reserveDailyUsage({
  root,
  prepared,
  config,
  entitlement,
  requestId,
  dayKey,
  unlimited,
}) {
  const usageRef = root.child(
    `connectionNotificationUsage/${prepared.sender}/${dayKey}`,
  );
  let denied = null;
  let reservation = null;
  let usageAfter = null;
  const result = await usageRef.transaction(
    (current) => {
      const usage = normalizeUsage(current);
      if (Number.isFinite(usage.cooldownUntil) && usage.cooldownUntil > prepared.now) {
        denied = {
          reasonCode: "rateLimited",
          retryAfterMs: usage.cooldownUntil - prepared.now,
          usage,
        };
        return undefined;
      }

      const recent = usage.recentRequestTimes.filter(
        (timestamp) => prepared.now - timestamp < config.burstWindowMs,
      );
      if (recent.length >= config.burstLimit) {
        const cooldownUntil = prepared.now + config.cooldownMs;
        usage.cooldownUntil = cooldownUntil;
        usage.recentRequestTimes = recent;
        usage.updatedAt = prepared.now;
        denied = {
          reasonCode: "rateLimited",
          retryAfterMs: config.cooldownMs,
          usage,
        };
        usageAfter = { ...usage };
        return usage;
      }

      const updated = {
        ...usage,
        updatedAt: prepared.now,
        recentRequestTimes: [...recent, prepared.now],
      };

      if (unlimited) {
        updated.unlimitedUsed += 1;
        updated.totalReserved += 1;
        reservation = {
          usedFreeDaily: false,
          usedExtraCredit: false,
          unlimited: true,
          timestamp: prepared.now,
          extraCreditDecremented: false,
          extraCreditRestored: false,
        };
      } else if (updated.freeUsed < config.dailyFreeLimit) {
        updated.freeUsed += 1;
        updated.totalReserved += 1;
        reservation = {
          usedFreeDaily: true,
          usedExtraCredit: false,
          unlimited: false,
          timestamp: prepared.now,
          extraCreditDecremented: false,
          extraCreditRestored: false,
        };
      } else if (entitlement.extraCredits > 0) {
        updated.extraUsed += 1;
        updated.totalReserved += 1;
        reservation = {
          usedFreeDaily: false,
          usedExtraCredit: true,
          unlimited: false,
          timestamp: prepared.now,
          extraCreditDecremented: false,
          extraCreditRestored: false,
        };
      } else {
        denied = {
          reasonCode: "dailyLimitExceeded",
          usage,
        };
        return undefined;
      }

      updated.lastRequestId = requestId;
      updated.lastPeer = prepared.peer;
      usageAfter = { ...updated };
      return updated;
    },
    undefined,
    false,
  );

  if (denied) {
    return {
      allowed: false,
      response: denyPrepared(prepared, denied.reasonCode, {
        retryAfterMs: denied.retryAfterMs,
        quota: quotaSummary({
          config,
          entitlement,
          usage: denied.usage,
          targetUsage: null,
          dayKey,
          now: prepared.now,
        }),
        diagnostics: {
          quotaDeniedAt: "daily",
          dayKey,
        },
      }),
    };
  }

  if (!result || result.committed !== true || !reservation) {
    return {
      allowed: false,
      response: denyPrepared(prepared, "backendUnavailable", {
        requestId,
        diagnostics: { quotaDailyCommitted: false, dayKey },
      }),
    };
  }

  if (reservation.usedExtraCredit) {
    const credit = await decrementExtraCredit(root, prepared.sender);
    if (!credit.allowed) {
      await rollbackDailyUsage(root, prepared.sender, dayKey, reservation);
      return {
        allowed: false,
        response: denyPrepared(prepared, "extraCreditsExhausted", {
          requestId,
          quota: quotaSummary({
            config,
            entitlement: {
              ...entitlement,
              extraCredits: credit.extraCredits,
            },
            usage: usageAfter,
            targetUsage: null,
            dayKey,
            now: prepared.now,
          }),
          diagnostics: {
            quotaDeniedAt: "extraCredit",
            dayKey,
          },
        }),
      };
    }
    reservation.extraCreditDecremented = true;
    reservation.extraCreditsAfter = credit.extraCredits;
  }

  return {
    allowed: true,
    reservation,
    usage: usageAfter,
  };
}

async function reserveTargetUsage({ root, prepared, config, requestId, dayKey }) {
  const targetRef = root.child(
    `connectionNotificationTargetUsage/${prepared.sender}/${prepared.peer}/${dayKey}`,
  );
  let denied = null;
  let reservation = null;
  let usageAfter = null;
  const result = await targetRef.transaction(
    (current) => {
      const usage = normalizeTargetUsage(current);
      if (usage.count >= config.perTargetDailyLimit) {
        denied = {
          reasonCode: "perTargetLimitExceeded",
          usage,
        };
        return undefined;
      }
      const updated = {
        ...usage,
        count: usage.count + 1,
        updatedAt: prepared.now,
        lastRequestId: requestId,
      };
      reservation = { count: 1 };
      usageAfter = { ...updated };
      return updated;
    },
    undefined,
    false,
  );

  if (denied) {
    return {
      allowed: false,
      response: denyPrepared(prepared, denied.reasonCode, {
        quota: {
          dayKey,
          perTargetUsed: denied.usage.count,
          perTargetDailyLimit: config.perTargetDailyLimit,
        },
        diagnostics: {
          quotaDeniedAt: "target",
          dayKey,
        },
      }),
    };
  }

  if (!result || result.committed !== true || !reservation) {
    return {
      allowed: false,
      response: denyPrepared(prepared, "backendUnavailable", {
        requestId,
        diagnostics: { quotaTargetCommitted: false, dayKey },
      }),
    };
  }

  return {
    allowed: true,
    reservation,
    usage: usageAfter,
  };
}

async function decrementExtraCredit(root, username) {
  let extraCredits = 0;
  const result = await root
    .child(`connectionNotificationEntitlements/${username}`)
    .transaction(
      (current) => {
        const entitlement = current && typeof current === "object" ? current : {};
        const currentCredits = Math.max(
          0,
          positiveIntegerOrDefault(entitlement.extraCredits, 0),
        );
        if (currentCredits <= 0) {
          extraCredits = 0;
          return undefined;
        }
        extraCredits = currentCredits - 1;
        return {
          ...entitlement,
          extraCredits,
        };
      },
      undefined,
      false,
    );
  return {
    allowed: result && result.committed === true,
    extraCredits,
  };
}

async function releaseQuotaReservation(root, requestId) {
  const reservationPath = `connectionNotificationReservations/${requestId}`;
  const reservation = await readValue(root, reservationPath);
  if (!reservation || reservation.status !== "reserved") {
    return;
  }
  await rollbackTargetUsage(
    root,
    reservation.sender,
    reservation.peer,
    reservation.dayKey,
    reservation.target,
  );
  await rollbackDailyUsage(
    root,
    reservation.sender,
    reservation.dayKey,
    reservation.daily,
  );
  await root.child(reservationPath).transaction(
    (current) => {
      if (current && current.status === "reserved") {
        return null;
      }
      return undefined;
    },
    undefined,
    false,
  );
}

async function rollbackDailyUsage(root, sender, dayKey, reservation) {
  if (!reservation) {
    return;
  }
  await root.child(`connectionNotificationUsage/${sender}/${dayKey}`).transaction(
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
      usage.recentRequestTimes = removeOneTimestamp(
        usage.recentRequestTimes,
        reservation.timestamp,
      );
      return usage;
    },
    undefined,
    false,
  );
  if (
    reservation.usedExtraCredit &&
    reservation.extraCreditDecremented === true &&
    reservation.extraCreditRestored !== true
  ) {
    await restoreExtraCredit(root, sender);
    reservation.extraCreditRestored = true;
  }
}

async function rollbackTargetUsage(root, sender, peer, dayKey, reservation) {
  if (!reservation) {
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

async function restoreExtraCredit(root, username) {
  await root.child(`connectionNotificationEntitlements/${username}`).transaction(
    (current) => {
      const entitlement = current && typeof current === "object" ? current : {};
      return {
        ...entitlement,
        extraCredits:
          Math.max(0, positiveIntegerOrDefault(entitlement.extraCredits, 0)) + 1,
      };
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
    cooldownUntil: Number.isFinite(Number(source.cooldownUntil))
      ? Number(source.cooldownUntil)
      : null,
    recentRequestTimes: Array.isArray(source.recentRequestTimes)
      ? source.recentRequestTimes
          .map((timestamp) => Number(timestamp))
          .filter(Number.isFinite)
          .slice(-20)
      : [],
    updatedAt: Number.isFinite(Number(source.updatedAt))
      ? Number(source.updatedAt)
      : null,
    lastRequestId:
      typeof source.lastRequestId === "string" ? source.lastRequestId : null,
    lastPeer: typeof source.lastPeer === "string" ? source.lastPeer : null,
  };
}

function normalizeTargetUsage(value) {
  const source = value && typeof value === "object" ? value : {};
  return {
    count: Math.max(0, positiveIntegerOrDefault(source.count, 0)),
    updatedAt: Number.isFinite(Number(source.updatedAt))
      ? Number(source.updatedAt)
      : null,
    lastRequestId:
      typeof source.lastRequestId === "string" ? source.lastRequestId : null,
  };
}

function removeOneTimestamp(timestamps, timestamp) {
  if (!Number.isFinite(Number(timestamp))) {
    return timestamps;
  }
  const target = Number(timestamp);
  const next = [...timestamps];
  const index = next.lastIndexOf(target);
  if (index >= 0) {
    next.splice(index, 1);
  }
  return next;
}

function quotaSummary({
  config,
  entitlement,
  usage,
  targetUsage,
  dayKey,
  reservation = null,
  now = Date.now(),
}) {
  const normalizedUsage = normalizeUsage(usage);
  const normalizedTarget =
    targetUsage === null ? null : normalizeTargetUsage(targetUsage);
  const unlimitedActive =
    Number.isFinite(entitlement.unlimitedUntil) &&
    entitlement.unlimitedUntil > now;
  return {
    dayKey,
    dailyFreeLimit: config.dailyFreeLimit,
    freeUsed: normalizedUsage.freeUsed,
    freeRemaining: Math.max(
      0,
      config.dailyFreeLimit - normalizedUsage.freeUsed,
    ),
    extraCreditsRemaining: Math.max(
      0,
      positiveIntegerOrDefault(entitlement.extraCredits, 0),
    ),
    extraUsed: normalizedUsage.extraUsed,
    unlimitedActive,
    unlimitedUntil: entitlement.unlimitedUntil,
    unlimitedUsed: normalizedUsage.unlimitedUsed,
    perTargetDailyLimit: config.perTargetDailyLimit,
    perTargetUsed: normalizedTarget ? normalizedTarget.count : null,
    cooldownUntil: normalizedUsage.cooldownUntil,
    reservation: reservation
      ? {
          requestId: reservation.requestId,
          usedFreeDaily: reservation.daily.usedFreeDaily === true,
          usedExtraCredit: reservation.daily.usedExtraCredit === true,
          unlimited: reservation.daily.unlimited === true,
        }
      : null,
  };
}

function buildConnectionRequestPayload({
  data,
  prepared,
  requestId,
  expiresAt,
  receiverPresence,
  quota,
}) {
  const common = {
    requestId,
    pairKey: prepared.pairKey,
    from: prepared.sender,
    to: prepared.peer,
    status: "pending",
    reason: "manualConnect",
    senderDevice: guardrails.senderDeviceFromData(data),
    createdAt: prepared.now,
    updatedAt: prepared.now,
    expiresAt,
    receiverPresenceAt: receiverPresence.lastHeartbeat,
    quota: quota || null,
  };
  return {
    inbox: {
      ...common,
      seenAt: null,
    },
    outbox: {
      ...common,
      lastReasonCode: null,
    },
  };
}

async function rollbackPairLock(root, pairKey, requestId) {
  const lockRef = root.child(`connectionRequestPairLocks/${pairKey}`);
  await lockRef.transaction(
    (current) => {
      if (current && current.requestId === requestId) {
        return null;
      }
      return undefined;
    },
    undefined,
    false,
  );
}

async function readValue(root, path) {
  const snapshot = await root.child(path).get();
  return snapshot.exists() ? snapshot.val() : null;
}

async function exists(root, path) {
  const snapshot = await root.child(path).get();
  return snapshot.exists();
}

function createRequestId(prepared, deps) {
  if (deps && typeof deps.requestIdFactory === "function") {
    return guardrails.validateRequestId(
      deps.requestIdFactory({
        action: prepared.action,
        now: prepared.now,
        sender: prepared.sender,
        peer: prepared.peer,
        pairKey: prepared.pairKey,
      }),
    );
  }
  const randomSuffix = Math.random().toString(36).slice(2, 10);
  return guardrails.validateRequestId(`cr_${prepared.now}_${randomSuffix}`);
}

function positiveNumberOrDefault(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? number : fallback;
}

function positiveIntegerOrDefault(value, fallback) {
  const number = Number(value);
  return Number.isInteger(number) && number >= 0 ? number : fallback;
}

function denyResult(prepared, reasonCode, options = {}) {
  return {
    allowed: false,
    response: denyPrepared(prepared, reasonCode, options),
  };
}

function denyPrepared(prepared, reasonCode, options = {}) {
  return guardrails.denied(reasonCode, {
    requestId: options.requestId,
    peerLabel: prepared.peer,
    status: options.status,
    retryAfterMs: options.retryAfterMs,
    quota: options.quota,
    diagnostics: preparedDiagnostics(prepared, options.diagnostics || {}),
  });
}

function preparedDiagnostics(prepared, extra = {}) {
  return {
    action: prepared.action,
    serverNow: prepared.now,
    sender: prepared.sender,
    peer: prepared.peer,
    pairKey: prepared.pairKey,
    ...extra,
  };
}

function attachDiagnostics(response, diagnostics) {
  return {
    ...response,
    diagnostics: {
      ...(response.diagnostics || {}),
      ...diagnostics,
    },
  };
}

function callable(coreHandler) {
  return onCall(callableOptions, async (request) => {
    return coreHandler(request.data, request);
  });
}

module.exports = {
  createConnectionRequest: callable(createConnectionRequestCore),
  cancelConnectionRequest: callable(cancelConnectionRequestCore),
  acceptConnectionRequest: callable(acceptConnectionRequestCore),
  rejectConnectionRequest: callable(rejectConnectionRequestCore),
  markConnectionRequestSeen: callable(markConnectionRequestSeenCore),
  muteConnectionRequestsFromPeer: callable(muteConnectionRequestsFromPeerCore),
  unmuteConnectionRequestsFromPeer: callable(
    unmuteConnectionRequestsFromPeerCore,
  ),
  getConnectionRequestQuotaSummary: callable(
    getConnectionRequestQuotaSummaryCore,
  ),
  __test: {
    actionTypes,
    acceptConnectionRequestCore,
    cancelConnectionRequestCore,
    createConnectionRequestCore,
    getConnectionRequestQuotaSummaryCore,
    markConnectionRequestSeenCore,
    muteConnectionRequestsFromPeerCore,
    rejectConnectionRequestCore,
    unmuteConnectionRequestsFromPeerCore,
  },
};
