# 04 — PHASE 03: Security Foundation (Key Store + Encrypted DB)

**Master ref:** `01_IMPLEMENTATION_MASTER_PLAN.md` · **Backlog:** `02_ENGINEERING_BACKLOG.md` (TASK-015, TASK-002)
**Goal:** Build the OS-backed secret store + per-user identity keypair (TASK-015), then encrypt the local Drift DB at rest with SQLCipher (TASK-002).
**Why now:** This is the **keystone phase** — TASK-001 (per-pair E2E) and TASK-002 both need a safe key home. Do NOT start P4 crypto until this merges.
**Estimated effort:** 2 weeks (TASK-015 ~8d, TASK-002 ~6d). **Risk:** MEDIUM (irreversible migration — mitigate by copy-to-new-file).
**Prerequisites:** P1 + P2 complete. `flutter_secure_storage` NOT yet a dependency (confirmed).
**Exit criteria:** P3 DoD (§10). **Deliverables:** encrypted DB on disk; secure key round-trip on Android + Windows.

---

## TASK-015 — Secure Key Store + Identity KeyPair  (KEYSTONE)

### Overview
- **Objective:** Add `flutter_secure_storage`; create `KeyStoreService` (Keystore/Keychain/encrypted-file) and `IdentityKeyRepository` (X25519 keypair); add keypair columns to `Identity`; publish public key via `users/$username`.
- **Business value:** Hardware/OS-backed secret home; unblocks TASK-001 + TASK-002.
- **Technical value:** Removes DEBT-010 (no secret store, no keypair).
- **Dependencies:** none. **Risk:** MEDIUM (Windows `flutter_secure_storage` is file-backed, not TPM — document).

### Current State
- `apps/rain/pubspec.yaml`: no `flutter_secure_storage`.
- `packages/rain_core/lib/identity/identity.dart:15-18`: `Identity` = `username`, `displayName`, `gender` only — **no key material**.
- `packages/rain_core/lib/database/rain_database.dart:106-115`: `IdentityTable` columns `id/username/displayName/createdAt/gender`.
- `app_environment.dart`: signaling key is a `dart-define` singleton — not a per-user secret.

### Target State
- `KeyStoreService` round-trips a `String` secret per key id on Android (Keystore) + Windows (`flutter_secure_storage` encrypted file — documented as non-TPM).
- `IdentityKeyRepository` generates an X25519 keypair on first run; private key bytes wrapped (base64) and stored via `KeyStoreService` under `identity_signing_private`; public key stored in `IdentityTable.signingPublicKey` and published to `users/$username/signingPublicKey` (auth-uid owned).
- `SignalingCipher` (P4) will later call `IdentityKeyRepository` for per-pair derivation.

### Implementation Breakdown
**Task 15.1 — Add dependency + platform check** (0.5d)
- MODIFY `apps/rain/pubspec.yaml`, `packages/rain_core/pubspec.yaml` (add `flutter_secure_storage: ^9.0.0`). `dart pub get`.
- Validation: `flutter pub deps` resolves; `dart analyze`.

**Task 15.2 — `KeyStoreService`** (1.5d)
- CREATE `apps/rain/lib/infrastructure/security/key_store_service.dart`.
- API: `Future<String?> read(String keyId)`, `Future<void> write(String keyId, String value)`, `Future<void> delete(String keyId)`.
- Use `FlutterSecureStorage` with `androidOptions: AndroidOptions(encryptedSharedPreferences: true)` (Android Keystore-backed) and default (Windows encrypted-file).
- Validation: unit test with a fake on Windows path; real round-trip test on Android emulator (`integration_test`).

**Task 15.3 — `Identity` keypair migration** (1d)
- MODIFY `packages/rain_core/lib/database/rain_database.dart`:
  - `IdentityTable` add `TextColumn get signingPublicKey => text().nullable()();` (`:115`).
  - `schemaVersion` 6 → **7** (`:139`).
  - `onUpgrade`: `if (from < 7) { await m.addColumn(identityTable, identityTable.signingPublicKey); }` — additive, mirrors existing `if (from < N)` pattern.
- Validation: `dart analyze`; migration test (v6→v7 adds column).

**Task 15.4 — `IdentityKeyRepository`** (2d)
- CREATE `packages/rain_core/lib/identity/identity_key_repository.dart`.
- Uses `package:cryptography` `KeyPair` (`X25519`) — generate once, persist public key to Drift, private key (base64) via `KeyStoreService`.
- Methods: `Future<SimplePublicKey> ensureKeyPair()`, `Future<SimplePublicKey> getPublicKey()`, `Future<String> getPrivateKeyWrapped()` (reads store).
- Validation: unit test on a temp DB + fake `KeyStoreService` proves generate-once + round-trip.

**Task 15.5 — Publish public key to RTDB** (1.5d)
- MODIFY `packages/protocol_brain/lib/adapters/firebase_adapter.dart` (or identity adapter): on login/register success, write `users/$username/signingPublicKey` under auth-uid ownership (rules already enforce uid match per prior tombstone work).
- Validation: emulator test asserts write succeeds with own auth, denied with other auth.

**Task 15.6 — `app_environment` wiring + tests** (1.5d)
- MODIFY `app_environment.dart`: add `identityKeyRepositoryProvider` / `keyStoreServiceProvider` (Riverpod). Keep `signalingEncryptionKey` for P4 fallback.
- Validation: `flutter test` provider wiring.

### File-Level Changes
- CREATE `apps/rain/lib/infrastructure/security/key_store_service.dart`
- CREATE `packages/rain_core/lib/identity/identity_key_repository.dart`
- MODIFY `packages/rain_core/lib/database/rain_database.dart` (schema 6→7, new column, migration)
- MODIFY `packages/rain_core/lib/identity/identity.dart` (optional helper)
- MODIFY `apps/rain/pubspec.yaml`, `packages/rain_core/pubspec.yaml` (dep)
- MODIFY `packages/protocol_brain/lib/adapters/firebase_adapter.dart` (publish pubkey)
- MODIFY `apps/rain/lib/core/config/app_environment.dart` (DI)

### Code-Level Changes
- Classes: `KeyStoreService`, `IdentityKeyRepository` (new).
- Models: `IdentityTable.signingPublicKey` (new column).
- Enums/Constants: `schemaVersion = 7`.
- DI: Riverpod providers for key services.
- Error handling: `KeyStoreService.write` throws typed `KeyStoreException` on platform failure.
- Testing hooks: constructor-injectable `KeyStoreService` (fake in tests).

### Testing Plan
- Unit: `KeyStoreService` (fake), `IdentityKeyRepository` (temp DB + fake store), migration v6→v7.
- Integration: Android emulator real Keystore round-trip.
- Edge: key missing (generate-once), key read failure (graceful), concurrent first-run.
- Regression: existing `rain_database_test.dart` green.

### Validation Checklist
□ `flutter_secure_storage` resolved □ `KeyStoreService` round-trips (Android+Windows) □ `IdentityTable.signingPublicKey` migrated □ pubkey published under uid ownership □ Analyze + test green

### Rollback
- Revert schema to 6 + remove column add (additive migration → safe revert; old v6 DB unaffected since new column is nullable).
- Remove dep if needed.

---

## TASK-002 — SQLCipher Encryption-at-Rest  (H-2)

### Overview
- **Objective:** Open the Drift DB with SQLCipher; derive the key from `KeyStoreService` (TASK-015). One-time migration copies plaintext → encrypted file.
- **Business value:** Clears the cleartext-DB privacy FAIL (`07_PRODUCTION_READINESS_CHECKLIST.md`).
- **Technical value:** Removes DEBT-002.
- **Dependencies:** TASK-015 (must merge first). **Risk:** MEDIUM (irreversible — mitigate by copy-to-new-file).

### Current State
- `packages/rain_core/lib/database/rain_database.dart:303-316`: `driftDatabase(name:'rain', native: DriftNativeOptions(shareAcrossIsolates:true, setup: configureRainSqliteConnection))` — **no SQLCipher, no key**.
- `configureRainSqliteConnection` sets `busy_timeout/WAL/synchronous/foreign_keys` only.

### Target State
- `drift` + `sqlcipher_flutter_libs` open via `NativeDatabase.open(..., setup: (db) => db.execute('PRAGMA key = "$key";'))`.
- Key = `KeyStoreService.read('rain_db_key')` (generated once, 32 bytes base64). On first encrypted launch: open plaintext `rain.sqlite`, open new SQLCipher `rain.sqlite.cipher`, `INSERT INTO cipher SELECT * FROM plaintext`, verify row counts, then delete plaintext + `-wal`/`-shm`.
- `beforeOpen` (from TASK-008) validates key + `foreign_key_check`.

### Implementation Breakdown
**Task 2.1 — Add SQLCipher dep + open path** (1.5d)
- MODIFY `packages/rain_core/pubspec.yaml` (`sqlcipher_flutter_libs: ^0.6.0`, `drift` already present).
- MODIFY `rain_database.dart:303`: `NativeDatabase.open(dbFile, setup: (db) { db.execute('PRAGMA key = "$key";'); configureRainSqliteConnection(db); })`.
- Validation: `dart analyze`; build on Windows + Android.

**Task 2.2 — Key bootstrap** (1d)
- In `RainDatabase` factory: read `rain_db_key` from `KeyStoreService`; if absent, generate + store. Pass key to open.
- Validation: unit test with fake store proves generate-once.

**Task 2.3 — One-time plaintext→cipher migration** (2d)
- CREATE `packages/rain_core/lib/database/database_encryption_migrator.dart`.
- Logic: if `rain.sqlite` exists and `rain.sqlite.cipher` does not → copy; verify `SELECT COUNT(*)` matches per table; delete plaintext.
- Validation: test with a seeded plaintext DB → assert cipher file non-plaintext-readable + row parity + plaintext deleted.

**Task 2.4 — Wire `beforeOpen` + tests** (1.5d)
- Extend TASK-008 `beforeOpen` to also assert the DB opens with the key (throws on wrong key).
- Validation: `rain_database_test.dart` asserts `rain.sqlite` is NOT plaintext (grep for a known cleartext string fails); wrong-key open throws.

### File-Level Changes
- CREATE `packages/rain_core/lib/database/database_encryption_migrator.dart`
- MODIFY `packages/rain_core/lib/database/rain_database.dart` (open path, key bootstrap, beforeOpen)
- MODIFY `packages/rain_core/pubspec.yaml` (dep)
- MODIFY `packages/rain_core/lib/database/rain_database.g.dart` (regenerated by `drift_dev`)

### Code-Level Changes
- Functions: `NativeDatabase.open` with `PRAGMA key`; `DatabaseEncryptionMigrator.migrate()`.
- Constants: `rain_db_key` store id.
- Error handling: `WrongDatabaseKeyException` on open failure.
- Caching: key read once at open, not per-query.

### Testing Plan
- Unit: key generate-once; migrator row parity; wrong-key throws.
- Integration: real encrypted open on Android + Windows.
- Edge: plaintext file missing (fresh install → just open cipher); cipher already exists (skip migration); migration partial failure (keep plaintext, don't delete).
- Regression: all `rain_core` DB tests green.

### Validation Checklist
□ DB file non-plaintext-readable □ row parity after migration □ plaintext deleted □ wrong key throws □ Android+Windows open OK □ Analyze+test green

### Rollback
- Migration writes to **new** `rain.sqlite.cipher`; original `rain.sqlite` untouched until verified copy. Revert = delete cipher file (original intact). SQLCipher dep can be dropped without schema change.

---

## 10. Phase 3 Exit / DoD
- [ ] TASK-015 merged: `KeyStoreService` round-trips on Android+Windows; `Identity.signingPublicKey` migrated; pubkey published under uid.
- [ ] TASK-002 merged: DB file non-plaintext; one-time migration verified; wrong key throws.
- [ ] `dart run melos run analyze` + `test` green.
- [ ] CONTINUITY + vault (ADR-010 Option B in-progress→done) updated; `check_obsidian_vault.ps1` green.

## 11. Phase Summary
- **Completed:** Keystone security foundation. Per-pair E2E (P4 TASK-001) and encrypted DB (TASK-002) now have a safe key home.
- **Remaining:** TASK-001 (per-pair crypto) still pending — now unblocked.
- **Known issues:** Windows `flutter_secure_storage` is file-backed (documented as non-TPM; acceptable for v1).
- **Metrics:** DB plaintext-readable (target NO); key round-trip success (target 100%).
- **Go/No-Go:** **GO** if DoD met + Android/Windows key round-trip proven. No-Go if migration deletes plaintext before parity verified.

## 12. Decisions Log (P3)
- Schema 6→7 (additive) for keypair; SQLCipher is a separate open-path change, not a schema bump.
- Windows secure storage = encrypted file (not TPM) — accepted for v1, documented.
- Migration copies to NEW file; original preserved until parity check → safe revert.
