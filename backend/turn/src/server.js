const http = require("http");
const { buildCoturnPayload } = require("./credentials");

function createHandler({
  verifyToken = defaultVerifyFirebaseToken,
  env = process.env,
  nowMs = Date.now,
  rateLimiter = createRateLimiter({
    limit: env.RAIN_TURN_RATE_LIMIT_PER_HOUR,
    windowMs: 60 * 60 * 1000,
    nowMs,
  }),
} = {}) {
  return async function rainTurnBrokerHandler(req, res) {
    if (req.url !== "/rainTurnCredentials") {
      sendJson(res, 404, { error: "not_found" });
      return;
    }
    if (req.method !== "POST") {
      res.setHeader("Allow", "POST");
      sendJson(res, 405, { error: "method_not_allowed" });
      return;
    }

    try {
      const token = bearerToken(req.headers.authorization || "");
      if (!token) {
        sendJson(res, 401, { error: "missing_auth" });
        return;
      }
      const decoded = await verifyToken(token);
      const rateLimit = rateLimiter.check(decoded.uid);
      if (!rateLimit.allowed) {
        res.setHeader("Retry-After", String(rateLimit.retryAfterSeconds));
        sendJson(res, 429, { error: "rate_limited" });
        console.warn("Rain TURN broker rate limited UID.", {
          uid: decoded.uid,
          retryAfterSeconds: rateLimit.retryAfterSeconds,
        });
        return;
      }
      await drainRequest(req);
      const payload = buildCoturnPayload({
        hostname: env.RAIN_TURN_HOSTNAME,
        secret: env.TURN_STATIC_AUTH_SECRET,
        userId: decoded.uid,
        ttlSeconds: env.RAIN_TURN_TTL_SECONDS,
        nowMs: nowMs(),
        stunUrls: env.RAIN_STUN_URLS,
        turnUrls: env.RAIN_TURN_URLS,
      });
      sendJson(res, 200, payload);
    } catch (error) {
      const status = error.statusCode || error.status || 500;
      const safeStatus = status >= 400 && status < 600 ? status : 500;
      sendJson(res, safeStatus, {
        error: safeStatus === 401
          ? "invalid_auth"
          : "turn_credentials_unavailable",
      });
    }
  };
}

function startServer({
  port = Number.parseInt(process.env.PORT || "8080", 10),
  host = process.env.HOST || "127.0.0.1",
} = {}) {
  const server = http.createServer(createHandler());
  server.listen(port, host, () => {
    console.log(`Rain TURN broker listening on http://${host}:${port}`);
  });
  return server;
}

async function defaultVerifyFirebaseToken(token) {
  const admin = require("firebase-admin");
  if (admin.apps.length === 0) {
    const rawServiceAccount = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
    if (rawServiceAccount && rawServiceAccount.trim()) {
      admin.initializeApp({
        credential: admin.credential.cert(JSON.parse(rawServiceAccount)),
        projectId: process.env.FIREBASE_PROJECT_ID || undefined,
      });
    } else {
      admin.initializeApp({
        projectId: process.env.FIREBASE_PROJECT_ID || undefined,
      });
    }
  }
  return admin.auth().verifyIdToken(token, true);
}

function createRateLimiter({
  limit = 10,
  windowMs = 60 * 60 * 1000,
  nowMs = Date.now,
} = {}) {
  const maxRequests = Math.max(Number.parseInt(limit, 10) || 10, 1);
  const buckets = new Map();
  return {
    check(uid) {
      const key = String(uid || "anonymous");
      const now = nowMs();
      const existing = buckets.get(key);
      const bucket = existing && existing.resetAt > now
        ? existing
        : { count: 0, resetAt: now + windowMs };
      if (bucket.count >= maxRequests) {
        buckets.set(key, bucket);
        return {
          allowed: false,
          retryAfterSeconds: Math.max(
            Math.ceil((bucket.resetAt - now) / 1000),
            1,
          ),
        };
      }
      bucket.count += 1;
      buckets.set(key, bucket);
      return { allowed: true, retryAfterSeconds: 0 };
    },
  };
}

function bearerToken(authorization) {
  const match = String(authorization).match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : "";
}

function sendJson(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
  });
  res.end(body);
}

function drainRequest(req) {
  return new Promise((resolve, reject) => {
    req.on("data", () => {});
    req.on("end", resolve);
    req.on("error", reject);
  });
}

if (require.main === module) {
  startServer();
}

module.exports = {
  bearerToken,
  createRateLimiter,
  createHandler,
  startServer,
};
