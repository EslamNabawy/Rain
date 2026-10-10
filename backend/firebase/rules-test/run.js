// Runs against the Realtime Database emulator:
//   npx firebase-tools emulators:exec --only database "node rules-test/run.js"
const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const { ref, get, set, update, query, orderByKey, startAt, endAt, limitToFirst } = require("firebase/database");

const rules = fs.readFileSync(path.join(__dirname, "..", "database.rules.json"), "utf8");
const [host, port] = (process.env.FIREBASE_DATABASE_EMULATOR_HOST || "127.0.0.1:9000").split(":");

const results = [];
async function check(name, fn) {
  try {
    await fn();
    results.push({ name, ok: true });
  } catch (error) {
    results.push({ name, ok: false, error });
  }
}

const userRow = (name, uid) => ({
  username: name,
  uid,
  displayName: name,
  registeredAt: 1,
  accountState: "active",
});
const envelope = (from, to) => ({
  v: 1,
  alg: "A256GCM-HKDF-SHA256",
  ts: 1,
  from,
  to,
  nonce: "n",
  ciphertext: "c",
  mac: "m",
});

async function main() {
  const env = await initializeTestEnvironment({
    projectId: "rain-rules-test",
    database: { rules, host, port: Number(port) },
  });
  const as = (uid, name) =>
    env.authenticatedContext(uid, { email: `${name}@rain.local` }).database();

  async function reset() {
    await env.clearDatabase();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.database();
      await set(ref(db, "users/alice"), userRow("alice", "ua"));
      await set(ref(db, "users/bob"), userRow("bob", "ub"));
    });
  }

  await reset();
  await check("unauthenticated users cannot read users", async () => {
    await assertFails(get(ref(env.unauthenticatedContext().database(), "users/alice")));
  });
  await check("signed-in user can read a users row", async () => {
    await assertSucceeds(get(ref(as("ub", "bob"), "users/alice")));
  });
  await check("a new account can create its own users row", async () => {
    await assertSucceeds(set(ref(as("uc", "carol"), "users/carol"), userRow("carol", "uc")));
  });
  await check("an account cannot create a row for another username", async () => {
    await assertFails(set(ref(as("um", "mallory"), "users/dave"), userRow("dave", "um")));
  });
  await check("an account cannot overwrite an existing users row", async () => {
    await assertFails(set(ref(as("um", "alice"), "users/alice"), userRow("alice", "um")));
  });
  await check("owner cannot change the uid of its row", async () => {
    await assertFails(set(ref(as("ua", "alice"), "users/alice/uid"), "other"));
  });
  await check("owner can update its display name", async () => {
    await assertSucceeds(set(ref(as("ua", "alice"), "users/alice/displayName"), "Alice A"));
  });
  await check("unknown users children are rejected", async () => {
    await assertFails(set(ref(as("ua", "alice"), "users/alice/extra"), "x"));
  });

  await check("userSearch entry can only be written by the owner", async () => {
    await assertSucceeds(set(ref(as("ua", "alice"), "userSearch/alice"), true));
    await assertFails(set(ref(as("ub", "bob"), "userSearch/alice"), true));
  });

  await check("userSearch allows only bounded ordered queries", async () => {
    const db = as("ub", "bob");
    await assertSucceeds(
      get(query(ref(db, "userSearch"), orderByKey(), startAt("al"), endAt("al"), limitToFirst(10))),
    );
    await assertFails(get(ref(db, "userSearch")));
    await assertFails(get(query(ref(db, "userSearch"), orderByKey(), limitToFirst(50))));
    await assertSucceeds(get(ref(db, "userSearch/alice")));
  });

  await check("presence cannot be written for another user", async () => {
    await assertFails(set(ref(as("ub", "bob"), "presence/alice/online"), true));
  });

  await reset();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await set(ref(ctx.database(), "rooms/alice:bob"), {
      userA: "alice",
      userB: "bob",
      attemptId: "alice:bob:1",
      createdAt: 1,
      updatedAt: 1,
      expiresAt: 999999999999999,
      offer: envelope("alice", "bob"),
    });
  });
  await check("room participants can read the room, outsiders cannot", async () => {
    await assertSucceeds(get(ref(as("ub", "bob"), "rooms/alice:bob")));
    await assertFails(get(ref(as("uc", "carol"), "rooms/alice:bob")));
  });
  await check("a third user cannot write into someone else's room", async () => {
    await assertFails(set(ref(as("uc", "carol"), "rooms/alice:bob/answer"), envelope("alice", "bob")));
    await assertFails(set(ref(as("uc", "carol"), "rooms/alice:bob/updatedAt"), 2));
  });
  await check("only the callee can write the answer", async () => {
    await assertFails(set(ref(as("ua", "alice"), "rooms/alice:bob/answer"), envelope("alice", "bob")));
    await assertSucceeds(set(ref(as("ub", "bob"), "rooms/alice:bob/answer"), envelope("bob", "alice")));
  });

  await check("room offers accept v=1 and v=2 (with salt) envelopes only", async () => {
    const offer = ref(as("ua", "alice"), "rooms/alice:bob/offer");
    const v2 = { ...envelope("alice", "bob"), v: 2, salt: "AAAAAAAAAAAAAAAAAAAAAA==" };
    await assertSucceeds(set(offer, v2));
    await assertSucceeds(set(offer, envelope("alice", "bob")));
    await assertFails(set(offer, { ...envelope("alice", "bob"), v: 2 }));
    await assertFails(set(offer, { ...envelope("alice", "bob"), v: 3, salt: "AAAA" }));
    await assertFails(set(offer, { ...v2, salt: "A".repeat(65) }));
  });

  await check("voice call offers accept v=1 and v=2 (with salt) envelopes only", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await set(ref(ctx.database(), "voiceCalls/c1"), {
        v: 1,
        pairId: "alice:bob",
        caller: "alice",
        callee: "bob",
        status: "accepted",
        createdAt: 1,
        updatedAt: 1,
        expiresAt: 999999999999999,
        mediaMode: "audio",
        muted: { alice: false, bob: false },
      });
    });
    const offer = ref(as("ua", "alice"), "voiceCalls/c1/offer");
    await assertSucceeds(set(offer, envelope("alice", "bob")));
    await assertSucceeds(set(offer, { ...envelope("alice", "bob"), v: 2, salt: "AAAAAAAAAAAAAAAAAAAAAA==" }));
    await assertFails(set(offer, { ...envelope("alice", "bob"), v: 2 }));
    await assertFails(set(offer, { ...envelope("alice", "bob"), v: 3, salt: "AAAA" }));
  });

  await check("clients cannot write connectionRequests directly", async () => {
    await assertFails(set(ref(as("ua", "alice"), "connectionRequests/bob/r1"), { from: "alice" }));
  });
  await check("clients cannot write the security block list", async () => {
    await assertFails(set(ref(as("ua", "alice"), "security/blockedUids/ub"), true));
  });

  // SEC-001: the app publishes its X25519 public key (32 bytes, base64 = 44 chars).
  await reset();
  const key = "A".repeat(43) + "=";
  await check("owner can publish and rotate signingPublicKey", async () => {
    await assertSucceeds(set(ref(as("ua", "alice"), "users/alice/signingPublicKey"), key));
    await assertSucceeds(set(ref(as("ua", "alice"), "users/alice/signingPublicKey"), "B".repeat(43) + "="));
  });
  await check("another user cannot write signingPublicKey", async () => {
    await assertFails(set(ref(as("ub", "bob"), "users/alice/signingPublicKey"), key));
  });
  await check("malformed signingPublicKey values are rejected", async () => {
    await assertFails(set(ref(as("ua", "alice"), "users/alice/signingPublicKey"), "short"));
    await assertFails(set(ref(as("ua", "alice"), "users/alice/signingPublicKey"), "!".repeat(43) + "="));
    await assertFails(set(ref(as("ua", "alice"), "users/alice/signingPublicKey"), 5));
  });

  await env.cleanup();
  let failed = 0;
  for (const r of results) {
    console.log(`${r.ok ? "PASS" : "FAIL"}  ${r.name}`);
    if (!r.ok) {
      failed += 1;
      console.log(`      ${String(r.error && r.error.message || r.error).split("\n")[0]}`);
    }
  }
  console.log(`${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
