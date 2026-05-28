"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const guardrails = require("../connectionRequestGuardrails");
const connectionRequestCleanup = require("../connectionRequestCleanup");
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
  const root = fakeRoot();
  const response = await connectionRequests.__test.createConnectionRequestCore(
    { peer: "../bob" },
    authRequest(),
    { root },
  );

  assertResponseShape(response);
  assert.equal(response.allowed, false);
  assert.equal(response.reasonCode, "invalidPeer");
  assert.match(response.userMessage, /valid peer/);
  assert.equal(root.updates.length, 0);
});

test("self request is rejected with peer-specific diagnostics", async () => {
  const response = await connectionRequests.__test.createConnectionRequestCore(
    { peer: "Alice" },
    authRequest(),
    {
      root: fakeRoot(),
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
    authRequest(),
    { root: fakeRoot() },
  );

  assertResponseShape(response);
  assert.equal(response.allowed, false);
  assert.equal(response.reasonCode, "malformedRequest");
  assert.match(response.userMessage, /malformed/);
});

test("backend lookup failure returns backendUnavailable", async () => {
  const response = await connectionRequests.__test.createConnectionRequestCore(
    { peer: "bob" },
    authRequest(),
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

test("create writes server-owned request and outbox payloads", async () => {
  const root = fakeRoot();
  const response = await connectionRequests.__test.createConnectionRequestCore(
    { peer: "bob", createdAt: 1, updatedAt: 1, senderDevice: "Android" },
    authRequest(),
    {
      root,
      clock: () => 4242,
      requestIdFactory: () => "request-01",
    },
  );

  assertResponseShape(response);
  assert.equal(response.allowed, true);
  assert.equal(response.reasonCode, null);
  assert.equal(response.requestId, "request-01");
  assert.equal(response.status, "pending");
  assert.equal(response.diagnostics.serverNow, 4242);
  assert.equal(response.diagnostics.pairKey, "alice:bob");
  assert.equal(response.diagnostics.pairLockClaimed, true);

  const inbox = getPath(root.state, "connectionRequests/bob/request-01");
  const outbox = getPath(root.state, "connectionRequestOutboxes/alice/request-01");
  const lock = getPath(root.state, "connectionRequestPairLocks/alice:bob");
  assert.equal(inbox.createdAt, 4242);
  assert.equal(inbox.updatedAt, 4242);
  assert.equal(inbox.expiresAt, 49242);
  assert.equal(inbox.senderDevice, "android");
  assert.equal(outbox.from, "alice");
  assert.equal(outbox.to, "bob");
  assert.equal(lock.requestId, "request-01");
});

test("all action shells return the standard response shape", async () => {
  const deps = {
    root: fakeRoot(),
    clock: () => 5000,
    requestIdFactory: () => "request-shell",
  };
  const request = authRequest();
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

test("duplicate live pair lock returns existing open request", async () => {
  for (const status of ["pending", "seen"]) {
    let quotaCalls = 0;
    const root = fakeRoot({
      state: {
        connectionRequestPairLocks: {
          "alice:bob": {
            requestId: `existing-${status}`,
            from: "alice",
            to: "bob",
            status,
            expiresAt: 20_000,
          },
        },
      },
    });

    const response = await connectionRequests.__test.createConnectionRequestCore(
      { peer: "bob" },
      authRequest(),
      {
        root,
        clock: () => 10_000,
        requestIdFactory: () => `new-${status}`,
        reserveSenderQuota: async () => {
          quotaCalls += 1;
          return { allowed: true };
        },
      },
    );

    assertResponseShape(response);
    assert.equal(response.allowed, false);
    assert.equal(response.reasonCode, "duplicatePendingRequest");
    assert.equal(response.requestId, `existing-${status}`);
    assert.equal(quotaCalls, 0);
    assert.equal(getPath(root.state, `connectionRequests/bob/new-${status}`), undefined);
  }
});

test("expired and terminal pair locks can be replaced", async () => {
  for (const [status, expiresAt] of [
    ["pending", 9_999],
    ["accepted", 30_000],
  ]) {
    const root = fakeRoot({
      state: {
        connectionRequestPairLocks: {
          "alice:bob": {
            requestId: `old-${status}`,
            from: "alice",
            to: "bob",
            status,
            expiresAt,
          },
        },
      },
    });

    const response = await connectionRequests.__test.createConnectionRequestCore(
      { peer: "bob" },
      authRequest(),
      {
        root,
        clock: () => 10_000,
        requestIdFactory: () => `new-${status}`,
      },
    );

    assertResponseShape(response);
    assert.equal(response.allowed, true);
    assert.equal(response.requestId, `new-${status}`);
    assert.equal(
      getPath(root.state, "connectionRequestPairLocks/alice:bob/requestId"),
      `new-${status}`,
    );
  }
});

test("receiver protection denials do not write inbox or consume quota", async () => {
  const cases = [
    {
      name: "muted receiver",
      state: {
        connectionNotificationMutes: { bob: { alice: { muted: true } } },
      },
      reasonCode: "mutedByReceiver",
    },
    {
      name: "blocked peer",
      state: { blocks: { bob: { alice: { createdAt: 1 } } } },
      reasonCode: "blocked",
    },
    {
      name: "offline peer",
      state: { presence: { bob: { online: false, lastHeartbeat: 10_000 } } },
      reasonCode: "peerOffline",
    },
    {
      name: "missing accepted friendship",
      state: { friendships: { alice: { bob: null }, bob: { alice: null } } },
      reasonCode: "notAcceptedFriend",
    },
  ];

  for (const testCase of cases) {
    let quotaCalls = 0;
    const root = fakeRoot({ state: testCase.state });
    const response = await connectionRequests.__test.createConnectionRequestCore(
      { peer: "bob" },
      authRequest(),
      {
        root,
        clock: () => 10_000,
        requestIdFactory: () => `request-${testCase.name.replaceAll(" ", "-")}`,
        reserveSenderQuota: async () => {
          quotaCalls += 1;
          return { allowed: true };
        },
      },
    );

    assertResponseShape(response);
    assert.equal(response.allowed, false, testCase.name);
    assert.equal(response.reasonCode, testCase.reasonCode, testCase.name);
    assert.equal(quotaCalls, 0, testCase.name);
    assert.equal(getPath(root.state, "connectionRequests/bob"), undefined);
    assert.equal(getPath(root.state, "connectionRequestOutboxes/alice"), undefined);
    assert.equal(getPath(root.state, "connectionRequestPairLocks/alice:bob"), undefined);
  }
});

test("receiver inbox full rolls back pair lock before quota spend", async () => {
  let quotaCalls = 0;
  const root = fakeRoot({
    state: {
      connectionNotificationConfig: {
        global: { enabled: true, maxPendingInboundPerUser: 1 },
      },
      connectionRequests: {
        bob: {
          pending_existing: {
            requestId: "pending_existing",
            status: "pending",
            expiresAt: 20_000,
          },
        },
      },
    },
  });

  const response = await connectionRequests.__test.createConnectionRequestCore(
    { peer: "bob" },
    authRequest(),
    {
      root,
      clock: () => 10_000,
      requestIdFactory: () => "inbox-full-request",
      reserveSenderQuota: async () => {
        quotaCalls += 1;
        return { allowed: true };
      },
    },
  );

  assertResponseShape(response);
  assert.equal(response.allowed, false);
  assert.equal(response.reasonCode, "receiverInboxFull");
  assert.equal(quotaCalls, 0);
  assert.equal(getPath(root.state, "connectionRequests/bob/inbox-full-request"), undefined);
  assert.equal(getPath(root.state, "connectionRequestPairLocks/alice:bob"), undefined);
});

test("quota reservation failure rolls back pair lock and writes no rows", async () => {
  const root = fakeRoot();
  const response = await connectionRequests.__test.createConnectionRequestCore(
    { peer: "bob" },
    authRequest(),
    {
      root,
      clock: () => 10_000,
      requestIdFactory: () => "quota-denied",
      reserveSenderQuota: async () => ({
        allowed: false,
        reasonCode: "rateLimited",
        retryAfterMs: 30_000,
        quota: { remaining: 0 },
      }),
    },
  );

  assertResponseShape(response);
  assert.equal(response.allowed, false);
  assert.equal(response.reasonCode, "rateLimited");
  assert.equal(response.retryAfterMs, 30_000);
  assert.deepEqual(response.quota, { remaining: 0 });
  assert.equal(getPath(root.state, "connectionRequests/bob/quota-denied"), undefined);
  assert.equal(getPath(root.state, "connectionRequestOutboxes/alice/quota-denied"), undefined);
  assert.equal(getPath(root.state, "connectionRequestPairLocks/alice:bob"), undefined);
});

test("global kill switch and sender disable stop before pair lock claim", async () => {
  const cases = [
    {
      state: { connectionNotificationConfig: { global: { enabled: false } } },
      reasonCode: "notificationsDisabledByAdmin",
    },
    {
      state: { connectionNotificationEntitlements: { alice: { disabled: true } } },
      reasonCode: "permissionDenied",
    },
  ];

  for (const testCase of cases) {
    const root = fakeRoot({ state: testCase.state });
    const response = await connectionRequests.__test.createConnectionRequestCore(
      { peer: "bob" },
      authRequest(),
      {
        root,
        clock: () => 10_000,
        requestIdFactory: () => "disabled-request",
      },
    );

    assertResponseShape(response);
    assert.equal(response.allowed, false);
    assert.equal(response.reasonCode, testCase.reasonCode);
    assert.equal(getPath(root.state, "connectionRequestPairLocks/alice:bob"), undefined);
  }
});

test("daily limit denies after configured free allowance", async () => {
  const root = fakeRoot({
    state: {
      connectionNotificationConfig: {
        global: { dailyFreeLimit: 1 },
      },
      connectionNotificationUsage: {
        alice: {
          19700101: { freeUsed: 1, totalReserved: 1 },
        },
      },
    },
  });

  const response = await connectionRequests.__test.createConnectionRequestCore(
    { peer: "bob" },
    authRequest(),
    {
      root,
      clock: () => 10_000,
      requestIdFactory: () => "daily-limit",
    },
  );

  assertResponseShape(response);
  assert.equal(response.allowed, false);
  assert.equal(response.reasonCode, "dailyLimitExceeded");
  assert.equal(getPath(root.state, "connectionRequests/bob/daily-limit"), undefined);
  assert.equal(getPath(root.state, "connectionRequestPairLocks/alice:bob"), undefined);
});

test("extra credits allow after free limit and cannot go negative", async () => {
  const root = fakeRoot({
    state: {
      friendships: {
        alice: {
          bob: { acceptedAt: 1 },
          cara: { acceptedAt: 1 },
        },
        bob: { alice: { acceptedAt: 1 } },
        cara: { alice: { acceptedAt: 1 } },
      },
      connectionNotificationConfig: {
        global: { dailyFreeLimit: 0, perTargetDailyLimit: 2 },
      },
      connectionNotificationEntitlements: {
        alice: { extraCredits: 1 },
      },
    },
  });

  const first = await connectionRequests.__test.createConnectionRequestCore(
    { peer: "bob" },
    authRequest(),
    {
      root,
      clock: () => 10_000,
      requestIdFactory: () => "credit-ok",
    },
  );

  assertResponseShape(first);
  assert.equal(first.allowed, true);
  assert.equal(first.quota.extraCreditsRemaining, 0);
  assert.equal(
    getPath(root.state, "connectionNotificationEntitlements/alice/extraCredits"),
    0,
  );
  assert.equal(
    getPath(root.state, "connectionNotificationUsage/alice/19700101/extraUsed"),
    1,
  );
  assert.equal(
    getPath(root.state, "connectionNotificationReservations/credit-ok/status"),
    "spent",
  );

  const second = await connectionRequests.__test.createConnectionRequestCore(
    { peer: "cara" },
    authRequest(),
    {
      root,
      clock: () => 11_000,
      requestIdFactory: () => "credit-denied",
    },
  );

  assertResponseShape(second);
  assert.equal(second.allowed, false);
  assert.equal(second.reasonCode, "dailyLimitExceeded");
  assert.equal(
    getPath(root.state, "connectionNotificationEntitlements/alice/extraCredits"),
    0,
  );
});

test("per-target daily limit denies while global quota is rolled back", async () => {
  const root = fakeRoot({
    state: {
      connectionNotificationConfig: {
        global: { dailyFreeLimit: 10, perTargetDailyLimit: 1 },
      },
      connectionNotificationTargetUsage: {
        alice: {
          bob: {
            19700101: { count: 1 },
          },
        },
      },
    },
  });

  const response = await connectionRequests.__test.createConnectionRequestCore(
    { peer: "bob" },
    authRequest(),
    {
      root,
      clock: () => 10_000,
      requestIdFactory: () => "target-limit",
    },
  );

  assertResponseShape(response);
  assert.equal(response.allowed, false);
  assert.equal(response.reasonCode, "perTargetLimitExceeded");
  assert.equal(
    getPath(root.state, "connectionNotificationUsage/alice/19700101/freeUsed"),
    0,
  );
  assert.equal(getPath(root.state, "connectionRequestPairLocks/alice:bob"), undefined);
});

test("cooldown and burst limits deny with retry guidance", async () => {
  const cooldownRoot = fakeRoot({
    state: {
      connectionNotificationUsage: {
        alice: {
          19700101: { cooldownUntil: 20_000 },
        },
      },
    },
  });

  const cooldown = await connectionRequests.__test.createConnectionRequestCore(
    { peer: "bob" },
    authRequest(),
    {
      root: cooldownRoot,
      clock: () => 10_000,
      requestIdFactory: () => "cooldown-denied",
    },
  );

  assertResponseShape(cooldown);
  assert.equal(cooldown.allowed, false);
  assert.equal(cooldown.reasonCode, "rateLimited");
  assert.equal(cooldown.retryAfterMs, 10_000);

  const burstRoot = fakeRoot({
    state: {
      connectionNotificationConfig: {
        global: { burstLimit: 1, burstWindowMs: 60_000, cooldownMs: 15_000 },
      },
      connectionNotificationUsage: {
        alice: {
          19700101: { recentRequestTimes: [9_900] },
        },
      },
    },
  });

  const burst = await connectionRequests.__test.createConnectionRequestCore(
    { peer: "bob" },
    authRequest(),
    {
      root: burstRoot,
      clock: () => 10_000,
      requestIdFactory: () => "burst-denied",
    },
  );

  assertResponseShape(burst);
  assert.equal(burst.allowed, false);
  assert.equal(burst.reasonCode, "rateLimited");
  assert.equal(burst.retryAfterMs, 15_000);
  assert.equal(
    getPath(
      burstRoot.state,
      "connectionNotificationUsage/alice/19700101/cooldownUntil",
    ),
    25_000,
  );
  assert.equal(
    getPath(burstRoot.state, "connectionNotificationUsage/alice/19700101/freeUsed"),
    0,
  );
});

test("expired entitlement is ignored instead of blocking or granting credits", async () => {
  const root = fakeRoot({
    state: {
      connectionNotificationConfig: {
        global: { dailyFreeLimit: 1 },
      },
      connectionNotificationEntitlements: {
        alice: {
          disabled: true,
          extraCredits: 99,
          expiresAt: 9_999,
        },
      },
    },
  });

  const response = await connectionRequests.__test.createConnectionRequestCore(
    { peer: "bob" },
    authRequest(),
    {
      root,
      clock: () => 10_000,
      requestIdFactory: () => "expired-entitlement",
    },
  );

  assertResponseShape(response);
  assert.equal(response.allowed, true);
  assert.equal(response.quota.extraCreditsRemaining, 0);
  assert.equal(response.diagnostics.quotaFinalized, true);
});

test("unlimited entitlement bypasses daily free count but records usage", async () => {
  const root = fakeRoot({
    state: {
      connectionNotificationConfig: {
        global: { dailyFreeLimit: 0 },
      },
      connectionNotificationEntitlements: {
        alice: { unlimitedUntil: 20_000 },
      },
    },
  });

  const response = await connectionRequests.__test.createConnectionRequestCore(
    { peer: "bob" },
    authRequest(),
    {
      root,
      clock: () => 10_000,
      requestIdFactory: () => "unlimited-ok",
    },
  );

  assertResponseShape(response);
  assert.equal(response.allowed, true);
  assert.equal(
    getPath(root.state, "connectionNotificationUsage/alice/19700101/freeUsed"),
    0,
  );
  assert.equal(
    getPath(root.state, "connectionNotificationUsage/alice/19700101/unlimitedUsed"),
    1,
  );
});

test("write failure rolls back quota reservation and pair lock", async () => {
  const root = fakeRoot({ throwOnUpdate: true });
  const response = await connectionRequests.__test.createConnectionRequestCore(
    { peer: "bob" },
    authRequest(),
    {
      root,
      clock: () => 10_000,
      requestIdFactory: () => "write-fails",
    },
  );

  assertResponseShape(response);
  assert.equal(response.allowed, false);
  assert.equal(response.reasonCode, "backendUnavailable");
  assert.equal(getPath(root.state, "connectionRequestPairLocks/alice:bob"), undefined);
  assert.equal(
    getPath(root.state, "connectionNotificationReservations/write-fails"),
    undefined,
  );
  assert.equal(
    getPath(root.state, "connectionNotificationUsage/alice/19700101/freeUsed"),
    0,
  );
  assert.equal(
    getPath(
      root.state,
      "connectionNotificationTargetUsage/alice/bob/19700101/count",
    ),
    0,
  );
});

test("accept vs cancel first terminal transition wins", async () => {
  const root = fakeRoot();
  seedConnectionRequest(root, { requestId: "race-request" });

  const accepted = await connectionRequests.__test.acceptConnectionRequestCore(
    { requestId: "race-request" },
    authRequest("uid-bob"),
    { root, clock: () => 10_000 },
  );

  assertResponseShape(accepted);
  assert.equal(accepted.allowed, true);
  assert.equal(accepted.status, "accepted");
  assert.equal(
    getPath(root.state, "connectionRequests/bob/race-request/status"),
    "accepted",
  );
  assert.equal(
    getPath(root.state, "connectionRequestOutboxes/alice/race-request/status"),
    "accepted",
  );
  assert.equal(getPath(root.state, "connectionRequestPairLocks/alice:bob"), undefined);

  const canceled = await connectionRequests.__test.cancelConnectionRequestCore(
    { requestId: "race-request" },
    authRequest("uid-alice"),
    { root, clock: () => 10_001 },
  );

  assertResponseShape(canceled);
  assert.equal(canceled.allowed, false);
  assert.equal(canceled.reasonCode, "terminalRaceLost");
  assert.equal(canceled.status, "accepted");
});

test("cancel and reject update mirrors and clear pair lock", async () => {
  const cases = [
    {
      action: connectionRequests.__test.cancelConnectionRequestCore,
      uid: "uid-alice",
      requestId: "cancel-ok",
      status: "canceled",
    },
    {
      action: connectionRequests.__test.rejectConnectionRequestCore,
      uid: "uid-bob",
      requestId: "reject-ok",
      status: "rejected",
    },
  ];

  for (const testCase of cases) {
    const root = fakeRoot();
    seedConnectionRequest(root, { requestId: testCase.requestId });

    const response = await testCase.action(
      { requestId: testCase.requestId },
      authRequest(testCase.uid),
      { root, clock: () => 10_000 },
    );

    assertResponseShape(response);
    assert.equal(response.allowed, true);
    assert.equal(response.status, testCase.status);
    assert.equal(
      getPath(root.state, `connectionRequests/bob/${testCase.requestId}/status`),
      testCase.status,
    );
    assert.equal(
      getPath(
        root.state,
        `connectionRequestOutboxes/alice/${testCase.requestId}/status`,
      ),
      testCase.status,
    );
    assert.equal(getPath(root.state, "connectionRequestPairLocks/alice:bob"), undefined);
  }
});

test("accept after expiry returns stale message and expires mirrors", async () => {
  const root = fakeRoot();
  seedConnectionRequest(root, {
    requestId: "expired-accept",
    expiresAt: 9_999,
  });

  const response = await connectionRequests.__test.acceptConnectionRequestCore(
    { requestId: "expired-accept" },
    authRequest("uid-bob"),
    { root, clock: () => 10_000 },
  );

  assertResponseShape(response);
  assert.equal(response.allowed, false);
  assert.equal(response.reasonCode, "expired");
  assert.equal(response.status, "expired");
  assert.equal(getPath(root.state, "connectionRequests/bob/expired-accept"), undefined);
  assert.equal(
    getPath(root.state, "connectionRequestOutboxes/alice/expired-accept/status"),
    "expired",
  );
  assert.equal(getPath(root.state, "connectionRequestPairLocks/alice:bob"), undefined);
});

test("mark seen is idempotent and mirrors status", async () => {
  const root = fakeRoot();
  seedConnectionRequest(root, { requestId: "seen-request" });

  const first = await connectionRequests.__test.markConnectionRequestSeenCore(
    { requestId: "seen-request" },
    authRequest("uid-bob"),
    { root, clock: () => 10_000 },
  );
  const second = await connectionRequests.__test.markConnectionRequestSeenCore(
    { requestId: "seen-request" },
    authRequest("uid-bob"),
    { root, clock: () => 10_001 },
  );

  assertResponseShape(first);
  assertResponseShape(second);
  assert.equal(first.allowed, true);
  assert.equal(second.allowed, true);
  assert.equal(first.status, "seen");
  assert.equal(second.status, "seen");
  assert.equal(
    getPath(root.state, "connectionRequests/bob/seen-request/status"),
    "seen",
  );
  assert.equal(
    getPath(root.state, "connectionRequestOutboxes/alice/seen-request/status"),
    "seen",
  );
  assert.equal(
    getPath(root.state, "connectionRequestPairLocks/alice:bob/status"),
    "seen",
  );
});

test("retry after client timeout returns existing pending request", async () => {
  const root = fakeRoot();
  seedConnectionRequest(root, { requestId: "timeout-existing" });

  const response = await connectionRequests.__test.createConnectionRequestCore(
    { peer: "bob" },
    authRequest("uid-alice"),
    {
      root,
      clock: () => 10_000,
      requestIdFactory: () => "timeout-new",
    },
  );

  assertResponseShape(response);
  assert.equal(response.allowed, false);
  assert.equal(response.reasonCode, "duplicatePendingRequest");
  assert.equal(response.requestId, "timeout-existing");
  assert.equal(getPath(root.state, "connectionRequests/bob/timeout-new"), undefined);
});

test("cleanup removes stale pair lock and preserves newer lock", async () => {
  const root = fakeRoot({
    state: {
      connectionRequestPairLocks: {
        "alice:bob": {
          requestId: "old-lock",
          from: "alice",
          to: "bob",
          status: "pending",
          expiresAt: 9_999,
        },
        "alice:cara": {
          requestId: "new-lock",
          from: "alice",
          to: "cara",
          status: "pending",
          expiresAt: 20_000,
        },
      },
    },
  });

  const stats = await connectionRequestCleanup.__test.cleanupConnectionRequestsCore({
    root,
    clock: () => 10_000,
  });

  assert.equal(stats.expiredPairLocks, 1);
  assert.equal(getPath(root.state, "connectionRequestPairLocks/alice:bob"), undefined);
  assert.equal(
    getPath(root.state, "connectionRequestPairLocks/alice:cara/requestId"),
    "new-lock",
  );
});

test("cleanup expires requests and clears only matching pair lock", async () => {
  const root = fakeRoot();
  seedConnectionRequest(root, {
    requestId: "cleanup-expired",
    expiresAt: 9_999,
  });
  setPath(root.state, "connectionRequestPairLocks/alice:bob", {
    requestId: "newer-request",
    from: "alice",
    to: "bob",
    status: "pending",
    expiresAt: 20_000,
  });

  const stats = await connectionRequestCleanup.__test.cleanupConnectionRequestsCore({
    root,
    clock: () => 10_000,
  });

  assert.equal(stats.expiredRequests, 1);
  assert.equal(getPath(root.state, "connectionRequests/bob/cleanup-expired"), undefined);
  assert.equal(
    getPath(
      root.state,
      "connectionRequestOutboxes/alice/cleanup-expired/status",
    ),
    "expired",
  );
  assert.equal(
    getPath(root.state, "connectionRequestPairLocks/alice:bob/requestId"),
    "newer-request",
  );
});

test("cleanup removes corrupt request rows without crashing", async () => {
  const root = fakeRoot({
    state: {
      connectionRequests: {
        bob: {
          corrupt_request: {
            requestId: "corrupt_request",
            from: "alice",
            to: "bob",
            status: "pending",
            createdAt: "bad",
            updatedAt: 1,
            expiresAt: 20_000,
          },
        },
      },
      connectionRequestOutboxes: {
        alice: {
          corrupt_request: {
            requestId: "corrupt_request",
            from: "alice",
          },
        },
      },
    },
  });

  const stats = await connectionRequestCleanup.__test.cleanupConnectionRequestsCore({
    root,
    clock: () => 10_000,
  });

  assert.equal(stats.corruptRequests, 1);
  assert.equal(getPath(root.state, "connectionRequests/bob/corrupt_request"), undefined);
  assert.equal(
    getPath(root.state, "connectionRequestOutboxes/alice/corrupt_request"),
    undefined,
  );
  assert.ok(getPath(root.state, "connectionNotificationAudit/19700101"));
});

test("cleanup rolls back stale reservations and expired entitlements", async () => {
  const root = fakeRoot({
    state: {
      connectionNotificationEntitlements: {
        alice: { extraCredits: 5, expiresAt: 9_999 },
      },
      connectionNotificationUsage: {
        alice: {
          19700101: { freeUsed: 1, totalReserved: 1 },
        },
      },
      connectionNotificationTargetUsage: {
        alice: {
          bob: {
            19700101: { count: 1 },
          },
        },
      },
      connectionNotificationReservations: {
        stale_reservation: {
          requestId: "stale_reservation",
          sender: "alice",
          peer: "bob",
          pairKey: "alice:bob",
          status: "reserved",
          createdAt: 1,
          updatedAt: 1,
          dayKey: "19700101",
          daily: {
            usedFreeDaily: true,
            usedExtraCredit: false,
            unlimited: false,
          },
          target: { count: 1 },
        },
      },
    },
  });

  const stats = await connectionRequestCleanup.__test.cleanupConnectionRequestsCore({
    root,
    clock: () => 10_000,
    staleReservationMs: 1_000,
  });

  assert.equal(stats.staleReservations, 1);
  assert.equal(stats.expiredEntitlements, 1);
  assert.equal(
    getPath(root.state, "connectionNotificationReservations/stale_reservation"),
    undefined,
  );
  assert.equal(
    getPath(root.state, "connectionNotificationUsage/alice/19700101/freeUsed"),
    0,
  );
  assert.equal(
    getPath(
      root.state,
      "connectionNotificationTargetUsage/alice/bob/19700101/count",
    ),
    0,
  );
  assert.equal(getPath(root.state, "connectionNotificationEntitlements/alice"), undefined);
});

function assertResponseShape(response) {
  assert.deepEqual(Object.keys(response), responseKeys);
  assert.equal(typeof response.allowed, "boolean");
  assert.equal(typeof response.userMessage, "string");
  assert.equal(typeof response.diagnostics, "object");
}

function authRequest(uid = "uid-alice") {
  return { auth: { uid } };
}

function seedConnectionRequest(root, options = {}) {
  const requestId = options.requestId || "seed-request";
  const from = options.from || "alice";
  const to = options.to || "bob";
  const pairKey = `${from}:${to}`;
  const createdAt = options.createdAt ?? 9_000;
  const updatedAt = options.updatedAt ?? createdAt;
  const expiresAt = options.expiresAt ?? 20_000;
  const status = options.status || "pending";
  const payload = {
    requestId,
    pairKey,
    from,
    to,
    status,
    reason: "manualConnect",
    senderDevice: "unknown",
    createdAt,
    updatedAt,
    expiresAt,
    receiverPresenceAt: createdAt,
    quota: null,
  };
  setPath(root.state, `connectionRequests/${to}/${requestId}`, {
    ...payload,
    seenAt: null,
  });
  setPath(root.state, `connectionRequestOutboxes/${from}/${requestId}`, {
    ...payload,
    lastReasonCode: null,
  });
  setPath(root.state, `connectionRequestPairLocks/${pairKey}`, {
    requestId,
    pairKey,
    from,
    to,
    status,
    createdAt,
    updatedAt,
    expiresAt,
  });
  return payload;
}

function fakeRoot(options = {}) {
  const state = deepMerge(defaultState(), options.state || {});
  const root = {
    state,
    throwOnGet: options.throwOnGet === true,
    throwOnUpdate: options.throwOnUpdate === true,
    updates: [],
    transactions: [],
    child(pathName) {
      return fakeRef(root, pathName);
    },
    async update(updates) {
      if (root.throwOnUpdate) {
        throw new Error("simulated update failure");
      }
      root.updates.push(deepClone(updates));
      for (const [pathName, value] of Object.entries(updates)) {
        setPath(root.state, pathName, value);
      }
    },
  };
  return root;
}

function defaultState() {
  return {
    users: {
      alice: { uid: "uid-alice" },
      bob: { uid: "uid-bob" },
      cara: { uid: "uid-cara" },
    },
    friendships: {
      alice: { bob: { acceptedAt: 1 } },
      bob: { alice: { acceptedAt: 1 } },
      cara: {},
    },
    blocks: {},
    presence: {
      bob: { online: true, lastHeartbeat: 10_000 },
      cara: { online: true, lastHeartbeat: 10_000 },
    },
    connectionNotificationConfig: {
      global: {
        enabled: true,
        requestTtlMs: 45_000,
        maxPendingInboundPerUser: 25,
      },
    },
  };
}

function fakeRef(root, pathName) {
  return {
    child(childPath) {
      return fakeRef(root, joinPath(pathName, childPath));
    },
    async get() {
      if (root.throwOnGet) {
        throw new Error("simulated backend failure");
      }
      return fakeSnapshotFromValue(getPath(root.state, pathName));
    },
    async update(updates) {
      const absoluteUpdates = {};
      for (const [childPath, value] of Object.entries(updates)) {
        absoluteUpdates[joinPath(pathName, childPath)] = value;
      }
      await root.update(absoluteUpdates);
    },
    async transaction(updateFn) {
      const current = deepClone(getPath(root.state, pathName));
      const next = updateFn(current);
      if (next === undefined) {
        return {
          committed: false,
          snapshot: fakeSnapshotFromValue(current),
        };
      }
      setPath(root.state, pathName, next);
      root.transactions.push({
        path: pathName,
        current,
        next: deepClone(next),
      });
      return {
        committed: true,
        snapshot: fakeSnapshotFromValue(next),
      };
    },
    orderByChild(field) {
      return fakeQuery(root, pathName, { orderByChild: field });
    },
  };
}

function fakeQuery(root, pathName, spec) {
  const query = {
    spec: { ...spec },
    orderByChild(field) {
      query.spec.orderByChild = field;
      return query;
    },
    equalTo(value) {
      query.spec.equalTo = value;
      return query;
    },
    limitToFirst(limit) {
      query.spec.limitToFirst = limit;
      return query;
    },
    async get() {
      if (root.throwOnGet) {
        throw new Error("simulated backend failure");
      }
      const value = getPath(root.state, pathName);
      const entries = [];
      if (value && typeof value === "object") {
        for (const [key, childValue] of Object.entries(value)) {
          if (
            Object.prototype.hasOwnProperty.call(query.spec, "equalTo") &&
            (!childValue ||
              typeof childValue !== "object" ||
              childValue[query.spec.orderByChild] !== query.spec.equalTo)
          ) {
            continue;
          }
          entries.push([key, childValue]);
          if (
            Number.isInteger(query.spec.limitToFirst) &&
            entries.length >= query.spec.limitToFirst
          ) {
            break;
          }
        }
      }
      return fakeSnapshotFromEntries(entries);
    },
  };
  return query;
}

function fakeSnapshotFromValue(value) {
  const snapshotValue = deepClone(value);
  return {
    exists() {
      return snapshotValue !== undefined && snapshotValue !== null;
    },
    val() {
      return deepClone(snapshotValue);
    },
    forEach(callback) {
      if (!snapshotValue || typeof snapshotValue !== "object") {
        return false;
      }
      for (const [key, value] of Object.entries(snapshotValue)) {
        if (callback({ key, val: () => deepClone(value) }) === true) {
          return true;
        }
      }
      return false;
    },
  };
}

function fakeSnapshotFromEntries(entries) {
  return {
    exists() {
      return entries.length > 0;
    },
    val() {
      return Object.fromEntries(entries.map(([key, value]) => [key, deepClone(value)]));
    },
    forEach(callback) {
      for (const [key, value] of entries) {
        if (callback({ key, val: () => deepClone(value) }) === true) {
          return true;
        }
      }
      return false;
    },
  };
}

function deepClone(value) {
  if (value === undefined) {
    return undefined;
  }
  return JSON.parse(JSON.stringify(value));
}

function deepMerge(base, override) {
  const result = deepClone(base);
  for (const [key, value] of Object.entries(override || {})) {
    if (
      value &&
      typeof value === "object" &&
      !Array.isArray(value) &&
      result[key] &&
      typeof result[key] === "object" &&
      !Array.isArray(result[key])
    ) {
      result[key] = deepMerge(result[key], value);
    } else {
      result[key] = deepClone(value);
    }
  }
  return result;
}

function getPath(root, pathName) {
  const parts = splitPath(pathName);
  let cursor = root;
  for (const part of parts) {
    if (!cursor || typeof cursor !== "object") {
      return undefined;
    }
    cursor = cursor[part];
  }
  return cursor;
}

function setPath(root, pathName, value) {
  const parts = splitPath(pathName);
  if (parts.length === 0) {
    throw new Error("cannot set root");
  }
  let cursor = root;
  for (let i = 0; i < parts.length - 1; i += 1) {
    const part = parts[i];
    if (!cursor[part] || typeof cursor[part] !== "object") {
      cursor[part] = {};
    }
    cursor = cursor[part];
  }
  if (value === null) {
    delete cursor[parts[parts.length - 1]];
  } else {
    cursor[parts[parts.length - 1]] = deepClone(value);
  }
}

function splitPath(pathName) {
  return String(pathName || "")
    .split("/")
    .filter((part) => part.length > 0);
}

function joinPath(first, second) {
  const left = splitPath(first).join("/");
  const right = splitPath(second).join("/");
  if (!left) {
    return right;
  }
  if (!right) {
    return left;
  }
  return `${left}/${right}`;
}
