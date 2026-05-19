const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const test = require("node:test");
const {
  buildCoturnPayload,
  boundedTtlSeconds,
  defaultTurnUrls,
  sanitizeUserId,
} = require("../src/credentials");

test("builds Coturn REST credentials with HMAC-SHA1", () => {
  const payload = buildCoturnPayload({
    hostname: "rain-p2p-turn.duckdns.org",
    secret: "test-secret",
    userId: "user:bad/path",
    ttlSeconds: 1200,
    nowMs: 1779120000000,
  });
  const turnServer = payload.iceServers.find((server) => server.credential);
  const expectedUsername = "1779121200:user_bad_path";
  const expectedCredential = crypto
    .createHmac("sha1", "test-secret")
    .update(expectedUsername)
    .digest("base64");

  assert.equal(payload.provider, "coturn-hmac");
  assert.equal(payload.ttlSeconds, 1200);
  assert.equal(payload.expiresAt, 1779121200000);
  assert.equal(turnServer.username, expectedUsername);
  assert.equal(turnServer.credential, expectedCredential);
});

test("uses Google and Cloudflare STUN plus UDP TCP and TLS TURN defaults", () => {
  const payload = buildCoturnPayload({
    hostname: "rain-p2p-turn.duckdns.org",
    secret: "test-secret",
    userId: "rain",
    nowMs: 1779120000000,
  });
  const urls = payload.iceServers.flatMap((server) => server.urls);

  assert.ok(urls.includes("stun:stun.l.google.com:19302"));
  assert.ok(urls.includes("stun:stun.cloudflare.com:3478"));
  assert.deepEqual(
    defaultTurnUrls("rain-p2p-turn.duckdns.org"),
    [
      "turn:rain-p2p-turn.duckdns.org:3478?transport=udp",
      "turn:rain-p2p-turn.duckdns.org:3478?transport=tcp",
      "turns:rain-p2p-turn.duckdns.org:5349?transport=tcp",
    ],
  );
  assert.ok(urls.includes("turn:rain-p2p-turn.duckdns.org:3478?transport=udp"));
  assert.ok(urls.includes("turn:rain-p2p-turn.duckdns.org:3478?transport=tcp"));
  assert.ok(urls.includes("turns:rain-p2p-turn.duckdns.org:5349?transport=tcp"));
});

test("bounds TTL and sanitizes user ids", () => {
  assert.equal(boundedTtlSeconds("10"), 300);
  assert.equal(boundedTtlSeconds("999999"), 3600);
  assert.equal(boundedTtlSeconds("bad"), 1200);
  assert.equal(sanitizeUserId("a/b:c d"), "a_b_c_d");
  assert.equal(sanitizeUserId(""), "rain");
});
