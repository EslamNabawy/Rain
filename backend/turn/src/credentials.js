const crypto = require("crypto");

const DEFAULT_TTL_SECONDS = 20 * 60;
const MIN_TTL_SECONDS = 300;
const MAX_TTL_SECONDS = 3600;
const DEFAULT_STUN_URLS = [
  "stun:stun.l.google.com:19302",
  "stun:stun1.l.google.com:19302",
  "stun:stun.cloudflare.com:3478",
];

function buildCoturnPayload({
  hostname,
  secret,
  userId,
  ttlSeconds,
  nowMs = Date.now(),
  stunUrls,
  turnUrls,
}) {
  const cleanHostname = requiredString(hostname, "RAIN_TURN_HOSTNAME");
  const cleanSecret = requiredString(secret, "TURN_STATIC_AUTH_SECRET");
  const cleanUserId = sanitizeUserId(userId);
  const boundedTtl = boundedTtlSeconds(ttlSeconds);
  const expiresAtSeconds = Math.floor(nowMs / 1000) + boundedTtl;
  const username = `${expiresAtSeconds}:${cleanUserId}`;
  const credential = crypto
    .createHmac("sha1", cleanSecret)
    .update(username)
    .digest("base64");

  const resolvedStunUrls = normalizeCsv(stunUrls);
  const resolvedTurnUrls = normalizeCsv(turnUrls);
  const iceServers = [
    ...(resolvedStunUrls.length === 0 ? DEFAULT_STUN_URLS : resolvedStunUrls)
      .map((url) => ({ urls: url })),
    {
      urls: resolvedTurnUrls.length === 0
        ? defaultTurnUrls(cleanHostname)
        : resolvedTurnUrls,
      username,
      credential,
    },
  ];

  return {
    provider: "coturn-hmac",
    ttlSeconds: boundedTtl,
    expiresAt: nowMs + boundedTtl * 1000,
    iceServers,
  };
}

function defaultTurnUrls(hostname) {
  return [
    `turn:${hostname}:3478?transport=udp`,
    `turn:${hostname}:3478?transport=tcp`,
    `turns:${hostname}:5349?transport=tcp`,
  ];
}

function boundedTtlSeconds(value) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed)) {
    return DEFAULT_TTL_SECONDS;
  }
  return Math.min(Math.max(parsed, MIN_TTL_SECONDS), MAX_TTL_SECONDS);
}

function sanitizeUserId(value) {
  const normalized = String(value || "rain")
    .trim()
    .replace(/[^A-Za-z0-9._-]/g, "_")
    .slice(0, 80);
  return normalized.length === 0 ? "rain" : normalized;
}

function requiredString(value, name) {
  const normalized = String(value || "").trim();
  if (!normalized) {
    throw new Error(`${name} is required`);
  }
  return normalized;
}

function normalizeCsv(value) {
  if (Array.isArray(value)) {
    return value.map((item) => String(item).trim()).filter(Boolean);
  }
  return String(value || "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

module.exports = {
  DEFAULT_STUN_URLS,
  buildCoturnPayload,
  boundedTtlSeconds,
  defaultTurnUrls,
  sanitizeUserId,
};
