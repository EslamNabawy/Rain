"use strict";

const USERNAME_PATTERN = /^[a-z0-9_]{3,24}$/;
const REQUEST_ID_PATTERN = /^[A-Za-z0-9_-]{3,128}$/;
const TERMINAL_REQUEST_STATUSES = Object.freeze(
  new Set([
    "accepted",
    "rejected",
    "canceled",
    "cancelled",
    "expired",
    "failed",
  ]),
);
const VALID_SENDER_DEVICES = Object.freeze(
  new Set(["android", "windows", "unknown"]),
);

const reasonMessages = Object.freeze({
  authMissing: () => "Sign in before requesting a connection.",
  unknownUser: () => "Could not find your Rain account. Sign in again.",
  invalidPeer: () => "Choose a valid peer before requesting a connection.",
  selfRequest: () => "You cannot request a connection with yourself.",
  backendUnavailable: () =>
    "Connection request service is unavailable. Try again.",
  malformedRequest: () => "Connection request is malformed. Try again.",
  peerOffline: (peer) =>
    `${peer} is offline. Keep both apps open, then try again.`,
  presenceUnknown: (peer) => `Could not confirm ${peer} is online. Try again.`,
  notAcceptedFriend: () =>
    "You can only request a connection with accepted friends.",
  blocked: () => "This connection request cannot be sent.",
  mutedByReceiver: (peer) =>
    `${peer} is not receiving connection request notifications right now.`,
  manualDisconnectActive: (peer) =>
    `You disconnected ${peer}. Press Connect to open the peer lane again.`,
  activeCall: () => "Finish the call before requesting another connection.",
  activeTransfer: () =>
    "Finish the active file transfer before requesting a connection.",
  rateLimited: (_peer, retryAfterMs) =>
    `Too many connection requests. Try again ${retryAfterText(retryAfterMs)}.`,
  dailyLimitExceeded: () => "Daily connection request limit reached.",
  extraCreditsExhausted: () =>
    "No extra connection request credits are available.",
  perTargetLimitExceeded: (peer) =>
    `You have sent too many connection requests to ${peer} today.`,
  tooManyPendingRequests: () =>
    "You have too many pending connection requests.",
  receiverInboxFull: (peer) =>
    `${peer} has too many pending connection requests.`,
  duplicatePendingRequest: (peer) =>
    `A connection request to ${peer} is already pending.`,
  notificationsDisabledByAdmin: () =>
    "Connection request notifications are temporarily disabled.",
  notificationsTemporarilyDisabled: () =>
    "Connection request notifications are temporarily unavailable.",
  expired: () => "This connection request expired. Try again.",
  backendRejected: () => "Connection request could not be sent. Try again.",
  permissionDenied: () => "Connection request is not allowed for this account.",
  notificationUnavailable: () =>
    "Notification delivery is unavailable. Try again later.",
  staleRequest: () => "This connection request is no longer current.",
  terminalRaceLost: () => "This connection request was already handled.",
});

function normalizeUsername(value) {
  if (typeof value !== "string") {
    throw new ConnectionRequestInputError("invalidPeer");
  }
  const normalized = value.trim().toLowerCase();
  if (!USERNAME_PATTERN.test(normalized)) {
    throw new ConnectionRequestInputError("invalidPeer");
  }
  return normalized;
}

function validateRequestId(value) {
  if (typeof value !== "string") {
    throw new ConnectionRequestInputError("malformedRequest");
  }
  const normalized = value.trim();
  if (!REQUEST_ID_PATTERN.test(normalized)) {
    throw new ConnectionRequestInputError("malformedRequest");
  }
  return normalized;
}

function connectionRequestPairKey(from, to) {
  const normalizedFrom = normalizeUsername(from);
  const normalizedTo = normalizeUsername(to);
  if (normalizedFrom === normalizedTo) {
    throw new ConnectionRequestInputError("selfRequest");
  }
  return `${normalizedFrom}:${normalizedTo}`;
}

function serverNow(clock) {
  if (typeof clock === "function") {
    const value = clock();
    if (Number.isFinite(value)) {
      return Math.trunc(value);
    }
  }
  return Date.now();
}

function requireObjectData(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new ConnectionRequestInputError("malformedRequest");
  }
  return data;
}

function peerFromData(data) {
  const payload = requireObjectData(data);
  const rawPeer =
    payload.peer ?? payload.peerUsername ?? payload.to ?? payload.username;
  return normalizeUsername(rawPeer);
}

function requestIdFromData(data) {
  const payload = requireObjectData(data);
  return validateRequestId(payload.requestId);
}

function senderDeviceFromData(data) {
  const payload = requireObjectData(data);
  if (typeof payload.senderDevice !== "string") {
    return "unknown";
  }
  const normalized = payload.senderDevice.trim().toLowerCase();
  return VALID_SENDER_DEVICES.has(normalized) ? normalized : "unknown";
}

function isTerminalRequestStatus(status) {
  return TERMINAL_REQUEST_STATUSES.has(status);
}

async function resolveAuthUsername(root, request) {
  const uid = request && request.auth && request.auth.uid;
  if (!uid) {
    return {
      ok: false,
      response: denied("authMissing"),
    };
  }

  try {
    const snapshot = await root
      .child("users")
      .orderByChild("uid")
      .equalTo(uid)
      .limitToFirst(2)
      .get();

    if (!snapshot.exists()) {
      return {
        ok: false,
        response: denied("unknownUser", {
          diagnostics: { uid },
        }),
      };
    }

    const matches = [];
    snapshot.forEach((child) => {
      matches.push(child.key);
      return false;
    });

    if (matches.length !== 1) {
      return {
        ok: false,
        response: denied("backendUnavailable", {
          diagnostics: { uid, matchCount: matches.length },
        }),
      };
    }

    return {
      ok: true,
      username: normalizeUsername(matches[0]),
      uid,
    };
  } catch (error) {
    return {
      ok: false,
      response: denied("backendUnavailable", {
        diagnostics: {
          uid,
          error: sanitizeError(error),
        },
      }),
    };
  }
}

function standardResponse({
  allowed,
  requestId = null,
  status = null,
  reasonCode = null,
  userMessage = "",
  retryAfterMs = null,
  quota = null,
  diagnostics = {},
}) {
  return {
    allowed: allowed === true,
    requestId,
    status,
    reasonCode,
    userMessage,
    retryAfterMs,
    quota,
    diagnostics,
  };
}

function allowedResponse({
  requestId = null,
  status = null,
  userMessage = "",
  quota = null,
  diagnostics = {},
}) {
  return standardResponse({
    allowed: true,
    requestId,
    status,
    reasonCode: null,
    userMessage,
    retryAfterMs: null,
    quota,
    diagnostics,
  });
}

function denied(reasonCode, options = {}) {
  const peer = displayPeerLabel(options.peerLabel);
  const messageBuilder =
    reasonMessages[reasonCode] || reasonMessages.backendRejected;
  return standardResponse({
    allowed: false,
    requestId: options.requestId ?? null,
    status: options.status ?? null,
    reasonCode,
    userMessage: messageBuilder(peer, options.retryAfterMs),
    retryAfterMs: options.retryAfterMs ?? null,
    quota: options.quota ?? null,
    diagnostics: options.diagnostics ?? {},
  });
}

function messageForReason(reasonCode, peerLabel, retryAfterMs) {
  const messageBuilder =
    reasonMessages[reasonCode] || reasonMessages.backendRejected;
  return messageBuilder(displayPeerLabel(peerLabel), retryAfterMs);
}

function displayPeerLabel(peerLabel) {
  if (typeof peerLabel !== "string" || peerLabel.trim().length === 0) {
    return "Peer";
  }
  const trimmed = peerLabel.trim();
  return trimmed.startsWith("@") ? trimmed : `@${trimmed}`;
}

function retryAfterText(retryAfterMs) {
  if (!Number.isFinite(retryAfterMs) || retryAfterMs <= 0) {
    return "later";
  }
  const seconds = Math.max(1, Math.ceil(retryAfterMs / 1000));
  if (seconds < 60) {
    return `in ${seconds}s`;
  }
  return `in ${Math.ceil(seconds / 60)}m`;
}

function sanitizeError(error) {
  if (!error) {
    return "unknown";
  }
  if (typeof error.message === "string" && error.message.length > 0) {
    return error.message.slice(0, 240);
  }
  return String(error).slice(0, 240);
}

class ConnectionRequestInputError extends Error {
  constructor(reasonCode) {
    super(reasonCode);
    this.name = "ConnectionRequestInputError";
    this.reasonCode = reasonCode;
  }
}

module.exports = {
  USERNAME_PATTERN,
  REQUEST_ID_PATTERN,
  TERMINAL_REQUEST_STATUSES,
  ConnectionRequestInputError,
  allowedResponse,
  connectionRequestPairKey,
  denied,
  isTerminalRequestStatus,
  messageForReason,
  normalizeUsername,
  peerFromData,
  reasonMessages,
  requestIdFromData,
  resolveAuthUsername,
  sanitizeError,
  senderDeviceFromData,
  serverNow,
  standardResponse,
  validateRequestId,
};
