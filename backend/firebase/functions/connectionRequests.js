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

    const quota = await reserveSenderQuota(prepared, requestId, deps);
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
  return foundationNotReady(prepared);
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

  const entitlement = await readValue(
    root,
    `connectionNotificationEntitlements/${prepared.sender}`,
  );
  if (entitlement && entitlement.disabled === true) {
    return denyResult(prepared, "permissionDenied", {
      diagnostics: { entitlementDisabled: true },
    });
  }

  return {
    allowed: true,
    config,
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

async function reserveSenderQuota(prepared, requestId, deps) {
  if (typeof deps.reserveSenderQuota !== "function") {
    return { allowed: true, quota: null };
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
