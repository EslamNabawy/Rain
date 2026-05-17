const admin = require("firebase-admin");
const crypto = require("crypto");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onRequest } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");

admin.initializeApp();

const HEARTBEAT_STALE_MS = 7 * 60 * 1000;
const DEFAULT_TURN_TTL_SECONDS = 20 * 60;

exports.rainTurnCredentials = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.set("Allow", "POST");
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  try {
    await verifyBearer(req);
    const provider = (process.env.RAIN_TURN_PROVIDER || "").trim();
    const ttlSeconds = boundedTtlSeconds(
      process.env.RAIN_TURN_TTL_SECONDS,
    );
    const payload = await buildTurnCredentialPayload(provider, ttlSeconds);
    res.status(200).json(payload);
  } catch (error) {
    const status = error.status || 500;
    const code = error.code || "turn_credentials_unavailable";
    if (status >= 500) {
      logger.error("TURN credential broker failed.", { code, error });
    }
    res.status(status).json({ error: code });
  }
});

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

async function verifyBearer(req) {
  const authorization = req.get("authorization") || "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    throw httpError(401, "missing_auth");
  }
  try {
    await admin.auth().verifyIdToken(match[1]);
  } catch (error) {
    throw httpError(401, "invalid_auth");
  }
}

async function buildTurnCredentialPayload(provider, ttlSeconds) {
  switch (provider) {
    case "twilio":
      return twilioCredentials(ttlSeconds);
    case "coturn-hmac":
      return coturnHmacCredentials(ttlSeconds);
    case "static":
      return staticCredentials(ttlSeconds);
    default:
      throw httpError(503, "turn_provider_not_configured");
  }
}

async function twilioCredentials(ttlSeconds) {
  const accountSid = requiredEnv("TWILIO_ACCOUNT_SID");
  const authToken = requiredEnv("TWILIO_AUTH_TOKEN");
  const response = await fetch(
    `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Tokens.json`,
    {
      method: "POST",
      headers: {
        authorization:
          "Basic " +
          Buffer.from(`${accountSid}:${authToken}`).toString("base64"),
        "content-type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({ Ttl: String(ttlSeconds) }),
    },
  );
  if (!response.ok) {
    throw httpError(502, "twilio_turn_token_failed");
  }
  const data = await response.json();
  return turnPayload({
    provider: "twilio",
    ttlSeconds,
    iceServers: normalizeIceServers(data.ice_servers),
  });
}

function coturnHmacCredentials(ttlSeconds) {
  const secret = requiredEnv("TURN_STATIC_AUTH_SECRET");
  const urls = requiredCsv("RAIN_TURN_URLS");
  const stunUrls = csv(process.env.RAIN_STUN_URLS);
  const expiresAtSeconds = Math.floor(Date.now() / 1000) + ttlSeconds;
  const userKey = "rain";
  const username = `${expiresAtSeconds}:${userKey}`;
  const credential = crypto
    .createHmac("sha1", secret)
    .update(username)
    .digest("base64");
  return turnPayload({
    provider: "coturn-hmac",
    ttlSeconds,
    iceServers: [
      ...stunUrls.map((url) => ({ urls: url })),
      { urls, username, credential },
    ],
  });
}

function staticCredentials(ttlSeconds) {
  const raw = requiredEnv("RAIN_TURN_ICE_SERVERS_JSON");
  let iceServers;
  try {
    iceServers = JSON.parse(raw);
  } catch (error) {
    throw httpError(500, "invalid_static_turn_json");
  }
  return turnPayload({
    provider: "static",
    ttlSeconds,
    iceServers: normalizeIceServers(iceServers),
  });
}

function turnPayload({ provider, ttlSeconds, iceServers }) {
  const normalized = normalizeIceServers(iceServers);
  if (!normalized.some(hasTurnUrl)) {
    throw httpError(500, "turn_urls_missing");
  }
  return {
    provider,
    ttlSeconds,
    expiresAt: Date.now() + ttlSeconds * 1000,
    iceServers: normalized,
  };
}

function normalizeIceServers(value) {
  if (!Array.isArray(value)) {
    throw httpError(500, "invalid_ice_servers");
  }
  return value
    .filter((server) => server && typeof server === "object")
    .map((server) => ({
      ...server,
      urls: normalizeUrls(server.urls),
    }))
    .filter((server) => server.urls.length > 0);
}

function normalizeUrls(value) {
  const urls = Array.isArray(value) ? value : [value];
  return urls
    .filter((url) => typeof url === "string")
    .map((url) => url.trim())
    .filter(Boolean);
}

function hasTurnUrl(server) {
  return normalizeUrls(server.urls).some((url) => {
    const normalized = url.toLowerCase();
    return normalized.startsWith("turn:") || normalized.startsWith("turns:");
  });
}

function requiredEnv(name) {
  const value = (process.env[name] || "").trim();
  if (!value) {
    throw httpError(500, `${name.toLowerCase()}_missing`);
  }
  return value;
}

function requiredCsv(name) {
  const values = csv(process.env[name]);
  if (values.length === 0) {
    throw httpError(500, `${name.toLowerCase()}_missing`);
  }
  return values;
}

function csv(value) {
  return (value || "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function boundedTtlSeconds(value) {
  const parsed = Number.parseInt(value || "", 10);
  if (!Number.isFinite(parsed)) {
    return DEFAULT_TURN_TTL_SECONDS;
  }
  return Math.min(Math.max(parsed, 300), 3600);
}

function httpError(status, code) {
  const error = new Error(code);
  error.status = status;
  error.code = code;
  return error;
}
