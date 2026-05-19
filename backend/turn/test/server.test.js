const assert = require("node:assert/strict");
const http = require("node:http");
const test = require("node:test");
const { bearerToken, createHandler, createRateLimiter } = require("../src/server");

test("extracts bearer token", () => {
  assert.equal(bearerToken("Bearer abc.def"), "abc.def");
  assert.equal(bearerToken("bearer token"), "token");
  assert.equal(bearerToken("Basic token"), "");
});

test("broker rejects missing auth with 401", async () => {
  const response = await callHandler(createHandler({
    verifyToken: async () => ({ uid: "unused" }),
  }));

  assert.equal(response.statusCode, 401);
  assert.deepEqual(response.body, { error: "missing_auth" });
});

test("broker returns compatible ICE server payload for valid auth", async () => {
  const response = await callHandler(createHandler({
    verifyToken: async (token) => ({ uid: `uid-${token}` }),
    nowMs: () => 1779120000000,
    env: {
      RAIN_TURN_HOSTNAME: "rain-p2p-turn.duckdns.org",
      TURN_STATIC_AUTH_SECRET: "test-secret",
      RAIN_TURN_TTL_SECONDS: "1200",
    },
  }), "Bearer ok");

  assert.equal(response.statusCode, 200);
  assert.equal(response.body.provider, "coturn-hmac");
  assert.equal(response.body.ttlSeconds, 1200);
  assert.equal(response.body.expiresAt, 1779121200000);
  assert.ok(Array.isArray(response.body.iceServers));
  assert.ok(response.body.iceServers.some((server) => {
    return Array.isArray(server.urls) &&
      server.urls.some((url) => url.startsWith("turn:")) &&
      server.username &&
      server.credential;
  }));
});

test("default Firebase verifier checks token revocation", () => {
  const serverSource = require("node:fs")
    .readFileSync(require.resolve("../src/server"), "utf8");

  assert.ok(serverSource.includes("verifyIdToken(token, true)"));
});

test("rate limiter returns retry-after for repeated UID requests", () => {
  let now = 1000;
  const limiter = createRateLimiter({
    limit: 2,
    windowMs: 60 * 60 * 1000,
    nowMs: () => now,
  });

  assert.equal(limiter.check("uid-1").allowed, true);
  assert.equal(limiter.check("uid-1").allowed, true);
  const limited = limiter.check("uid-1");
  assert.equal(limited.allowed, false);
  assert.equal(limited.retryAfterSeconds, 3600);
  assert.equal(limiter.check("uid-2").allowed, true);

  now += 60 * 60 * 1000 + 1;
  assert.equal(limiter.check("uid-1").allowed, true);
});

test("broker applies per-UID rate limiting", async () => {
  let now = 1779120000000;
  const handler = createHandler({
    verifyToken: async (token) => ({ uid: token }),
    nowMs: () => now,
    rateLimiter: createRateLimiter({
      limit: 2,
      windowMs: 60 * 60 * 1000,
      nowMs: () => now,
    }),
    env: {
      RAIN_TURN_HOSTNAME: "rain-p2p-turn.duckdns.org",
      TURN_STATIC_AUTH_SECRET: "test-secret",
      RAIN_TURN_TTL_SECONDS: "1200",
    },
  });

  assert.equal((await callHandler(handler, "Bearer same-user")).statusCode, 200);
  assert.equal((await callHandler(handler, "Bearer same-user")).statusCode, 200);
  const limited = await callHandler(handler, "Bearer same-user");
  assert.equal(limited.statusCode, 429);
  assert.equal(limited.body.error, "rate_limited");
  assert.equal(limited.retryAfter, "3600");
  assert.equal((await callHandler(handler, "Bearer other-user")).statusCode, 200);

  now += 60 * 60 * 1000 + 1;
  assert.equal((await callHandler(handler, "Bearer same-user")).statusCode, 200);
});

function callHandler(handler, authorization) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(handler);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      const request = http.request({
        hostname: "127.0.0.1",
        port: address.port,
        path: "/rainTurnCredentials",
        method: "POST",
        headers: authorization ? { authorization } : {},
      }, (response) => {
        let data = "";
        response.setEncoding("utf8");
        response.on("data", (chunk) => {
          data += chunk;
        });
        response.on("end", () => {
          server.close(() => {
            resolve({
              statusCode: response.statusCode,
              retryAfter: response.headers["retry-after"],
              body: JSON.parse(data),
            });
          });
        });
      });
      request.on("error", (error) => {
        server.close(() => reject(error));
      });
      request.end("{}");
    });
  });
}
