"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const guardrails = require("../connectionRequestGuardrails");
const connectionRequests = require("../connectionRequests");

const responseKeys = [
  "allowed",
  "requestId",
  "status",
  "reasonCode",
  "userMessage",
  "retryAfterMs",
  "quota",
  "diagnostics",
];

test("exports every connection request callable", () => {
  for (const name of Object.values(connectionRequests.__test.actionTypes)) {
    assert.equal(typeof connectionRequests[name], "function", name);
  }
});

test("normalizes peers and derives directed pair keys", () => {
  assert.equal(guardrails.normalizeUsername(" Alice_01 "), "alice_01");
  assert.equal(
    guardrails.connectionRequestPairKey("Alice_01", "BOB_02"),
    "alice_01:bob_02",
  );
  assert.throws(
    () => guardrails.connectionRequestPairKey("alice", "Alice"),
    /selfRequest/,
  );
  assert.throws(() => guardrails.normalizeUsername("../alice"), /invalidPeer/);
});

test("auth missing has the standard response shape and message", async () => {
  const response = await connectionRequests.__test.createConnectionRequestCore(
    { peer: "bob" },
    {},
    { root: fakeRoot(), clock: () => 1234 },
  );

  assertResponseShape(response);
  assert.equal(response.allowed, false);
  assert.equal(response.reasonCode, "authMissing");
  assert.match(response.userMessage, /Sign in/);
  assert.equal(response.diagnostics.action, "createConnectionRequest");
  assert.equal(response.diagnostics.serverNow, 1234);
});

test("unknown user gets an exact denial response", async () => {
  const response = await connectionRequests.__test.createConnectionRequestCore(
    { peer: "bob" },
    { auth: { uid: "missing-uid" } },
    { root: fakeRoot(), clock: () => 2000 },
  );

  assertResponseShape(response);
  assert.equal(response.allowed, false);
  assert.equal(response.reasonCode, "unknownUser");
  assert.match(response.userMessage, /Could not find your Rain account/);
});

test("invalid peer is rejected before backend mutation", async () => {
  const response = await connectionRequests.__test.createConnectionRequestCore(
    { peer: "../bob" },
    { auth: { uid: "uid-alice" } },
    { root: fakeRoot({ usersByUid: { "uid-alice": "alice" } }) },
  );

  assertResponseShape(response);
  assert.equal(response.allowed, false);
  assert.equal(response.reasonCode, "invalidPeer");
  assert.match(response.userMessage, /valid peer/);
});

test("self request is rejected with peer-specific diagnostics", async () => {
  const response = await connectionRequests.__test.createConnectionRequestCore(
    { peer: "Alice" },
    { auth: { uid: "uid-alice" } },
    {
      root: fakeRoot({ usersByUid: { "uid-alice": "alice" } }),
      clock: () => 3000,
    },
  );

  assertResponseShape(response);
  assert.equal(response.allowed, false);
  assert.equal(response.reasonCode, "selfRequest");
  assert.equal(response.diagnostics.sender, "alice");
  assert.equal(response.diagnostics.peer, "alice");
});

test("malformed request data is rejected consistently", async () => {
  const response = await connectionRequests.__test.cancelConnectionRequestCore(
    null,
    { auth: { uid: "uid-alice" } },
    { root: fakeRoot({ usersByUid: { "uid-alice": "alice" } }) },
  );

  assertResponseShape(response);
  assert.equal(response.allowed, false);
  assert.equal(response.reasonCode, "malformedRequest");
  assert.match(response.userMessage, /malformed/);
});

test("backend lookup failure returns backendUnavailable", async () => {
  const response = await connectionRequests.__test.createConnectionRequestCore(
    { peer: "bob" },
    { auth: { uid: "uid-alice" } },
    {
      root: fakeRoot({ throwOnGet: true }),
      clock: () => 4000,
    },
  );

  assertResponseShape(response);
  assert.equal(response.allowed, false);
  assert.equal(response.reasonCode, "backendUnavailable");
  assert.match(response.userMessage, /unavailable/);
  assert.match(response.diagnostics.error, /simulated backend failure/);
});

test("valid create shell ignores client timestamps and returns not-ready denial", async () => {
  const response = await connectionRequests.__test.createConnectionRequestCore(
    { peer: "bob", createdAt: 1, updatedAt: 1 },
    { auth: { uid: "uid-alice" } },
    {
      root: fakeRoot({ usersByUid: { "uid-alice": "alice" } }),
      clock: () => 4242,
    },
  );

  assertResponseShape(response);
  assert.equal(response.allowed, false);
  assert.equal(response.reasonCode, "backendUnavailable");
  assert.equal(response.diagnostics.foundationReady, true);
  assert.equal(response.diagnostics.serverNow, 4242);
  assert.equal(response.diagnostics.pairKey, "alice:bob");
  assert.notEqual(response.diagnostics.serverNow, 1);
});

test("all action shells return the standard response shape", async () => {
  const deps = {
    root: fakeRoot({ usersByUid: { "uid-alice": "alice" } }),
    clock: () => 5000,
  };
  const request = { auth: { uid: "uid-alice" } };
  const cases = [
    connectionRequests.__test.createConnectionRequestCore(
      { peer: "bob" },
      request,
      deps,
    ),
    connectionRequests.__test.cancelConnectionRequestCore(
      { requestId: "request-01" },
      request,
      deps,
    ),
    connectionRequests.__test.acceptConnectionRequestCore(
      { requestId: "request-01" },
      request,
      deps,
    ),
    connectionRequests.__test.rejectConnectionRequestCore(
      { requestId: "request-01" },
      request,
      deps,
    ),
    connectionRequests.__test.markConnectionRequestSeenCore(
      { requestId: "request-01" },
      request,
      deps,
    ),
    connectionRequests.__test.muteConnectionRequestsFromPeerCore(
      { peer: "bob" },
      request,
      deps,
    ),
    connectionRequests.__test.unmuteConnectionRequestsFromPeerCore(
      { peer: "bob" },
      request,
      deps,
    ),
    connectionRequests.__test.getConnectionRequestQuotaSummaryCore(
      {},
      request,
      deps,
    ),
  ];

  for (const response of await Promise.all(cases)) {
    assertResponseShape(response);
    assert.equal(typeof response.userMessage, "string");
    assert.notEqual(response.userMessage.length, 0);
  }
});

function assertResponseShape(response) {
  assert.deepEqual(Object.keys(response), responseKeys);
  assert.equal(typeof response.allowed, "boolean");
  assert.equal(typeof response.userMessage, "string");
  assert.equal(typeof response.diagnostics, "object");
}

function fakeRoot(options = {}) {
  const usersByUid = options.usersByUid || {};
  return {
    child(pathName) {
      assert.equal(pathName, "users");
      return fakeUsersQuery(usersByUid, options);
    },
  };
}

function fakeUsersQuery(usersByUid, options) {
  const query = {
    uid: null,
    orderByChild(field) {
      assert.equal(field, "uid");
      return query;
    },
    equalTo(uid) {
      query.uid = uid;
      return query;
    },
    limitToFirst(limit) {
      assert.equal(limit, 2);
      return query;
    },
    async get() {
      if (options.throwOnGet) {
        throw new Error("simulated backend failure");
      }
      const username = usersByUid[query.uid];
      const entries = username ? [[username, { uid: query.uid }]] : [];
      return fakeSnapshot(entries);
    },
  };
  return query;
}

function fakeSnapshot(entries) {
  return {
    exists() {
      return entries.length > 0;
    },
    forEach(callback) {
      for (const [key, value] of entries) {
        callback({
          key,
          val: () => value,
        });
      }
      return false;
    },
  };
}
