# Central Sync Audit — Gynocamp Patient Registration System

**Symptom:** Data created via the web admin (camps, patients, lookup items) does not immediately appear on the Android app.

**Files audited:** `camp_repository.dart`, `patient_repository.dart`, `lookup_repository.dart`

---

## Root Cause

The sync architecture is **push-only from the device's point of view**, with pull-from-central happening as an undocumented side effect in exactly one place — buried inside `CampRepository._syncCentralCampsInBackground()`:

```dart
await SyncRepository().pullDelta(deviceId: 'dev-auto', userId: 'usr-auto');
```

`SyncPushPayload` / `pullDelta` already model multiple entity types (patients, clinicalVisits, lookupItems), so the pull endpoint is multi-entity — but **nothing calls it except this one accidental trigger**, and even that trigger:

- only fires as a side effect of `getAllCamps()`,
- is never awaited by its caller, so the screen renders before it completes,
- uses hardcoded `'dev-auto'` / `'usr-auto'` instead of the real device/user.

---

## Per-Repository Findings

| Repository | Pull exists? | Awaited before UI reads? | Severity |
|---|---|---|---|
| `CampRepository.getAllCamps()` | Yes (background) | ❌ No — races the local query | High |
| `PatientRepository.getPatientsByCamp()` | ❌ None at all | — | **Critical** |
| `LookupRepository.getAllItems()` / `getItemsByCategory()` | ❌ None at all | — | **Critical** |

**Patients and lookup items** (diagnoses, medicines, hospitals, visit reasons, chief complaints) only ever reach a given Android device if that device happens to open a camps screen first — which triggers the buried `pullDelta()` — and only if it finishes in time and isn't blocked by `isServerCooldownActive`. Going straight to a patient list or the lookup-management screen skips sync entirely.

### 1. `CampRepository.getAllCamps()`

```dart
// 1. Sync latest camps from Central Cloud in background without blocking local return
if (enableCentralSync && !HttpCentralApiService.isServerCooldownActive) {
  _syncCentralCampsInBackground(db);   // fire-and-forget, NOT awaited
}
// ...query runs immediately against local SQLite, before sync finishes
```

The background sync starts but the method returns local data before it completes. The new camp only appears the *next* time something calls `getAllCamps()` again, and only if the previous background sync had time to finish first.

### 2. `PatientRepository.getPatientsByCamp()`

No sync call anywhere in this method — it only ever reads local SQLite:

```dart
@override
Future<List<PatientModel>> getPatientsByCamp([String? campId]) async {
  final db = await _databaseService.database;
  // ...local query only, no pull
}
```

Patients created on the web only reach an Android device incidentally, via the camp-load side effect described above.

### 3. `LookupRepository.getAllItems()` / `getItemsByCategory()`

Same defect — push-only, no pull:

```dart
@override
Future<List<LookupItemModel>> getAllItems({String? tenantId}) async {
  final db = await _databaseService.database;
  // ...local query only, no pull
}
```

New diagnoses, medications, referral hospitals, visit reasons, or chief complaints added centrally never reach a device unless the incidental camp-load pull happens to carry them along.

---

## Additional Issues Found

### A. Patient ID collision risk (`PatientRepository.registerPatient`)

```dart
final countResult = Sqflite.firstIntValue(await db.rawQuery(
  'SELECT COUNT(*) FROM ${DatabaseTables.tablePatients} WHERE camp_id = ?',
  [patient.campId],
));
int nextSeq = (countResult ?? 0) + 1;
```

The sequence number is derived from a `COUNT(*)` on the **local** table only. Two devices registering patients for the same camp before either has pulled the other's data can generate identical human-readable `patientId`s. UUIDs (`id`) stay unique so rows won't overwrite each other, but two patients can end up sharing one visible Patient ID once both sync to central — breaking QR/barcode lookup, search, and the duplicate detector.

**Fix:** server-side uniqueness check/retry on push, or reserve ID ranges per device at camp-open time.

### B. Lookup delete: hard delete + tombstone, inconsistent with the soft-delete read model

```dart
// deleteItem — hard delete locally
await db.delete(DatabaseTables.tableLookupItems, where: 'id = ?', whereArgs: [id]);

// _pushLookupDeleteToServer — pushes a tombstone with the SAME id
final tombstone = LookupItemModel(
  id: id,
  category: 'deleted',
  code: 'deleted',
  labelEn: 'deleted',
  labelNe: 'deleted',
  isDeleted: true,
  isActive: false,
);
```

Every read query filters `is_deleted = 0`, implying soft-delete is the intended model, but the local delete is a hard delete (`db.delete`). If any pull path does a naive "insert if missing" (as `CampRepository`'s central sync does for camps), a stale central copy — or another device's un-pulled state — could reinsert the *original* row rather than respecting the tombstone, resurrecting a deleted lookup item.

**Fix:** switch local delete to `is_deleted = 1` (soft delete, consistent with reads) instead of `db.delete`, or confirm the pull-merge logic explicitly checks `is_deleted` before ever re-inserting a row.

### C. Silent error swallowing everywhere

Every sync call follows the same pattern, repeated near-identically in all three files:

```dart
try {
  // ...push or pull
} catch (_) {
  // Silently ignore
}
```

Failures are invisible — no logs, no retry queue, no "N items pending sync" indicator. Given camps often have unreliable connectivity (per the project's core use case), data can silently sit unsynced indefinitely with no signal to the user.

### D. Duplicated sync logic across repositories

`_pushPatientToServer`, `_pushVisitToServer`, `_pushLookupToServer`, `_pushLookupDeleteToServer` are near-identical copy-pasted fire-and-forget helpers spread across two files. Any future fix (retry logic, backoff, error surfacing) currently has to be applied in 4+ places.

---

## Fix Plan

### Step 1 — Make pull explicit and awaitable everywhere

```dart
// PatientRepository
Future<List<PatientModel>> getPatientsByCamp([String? campId], {bool forceSync = false}) async {
  final db = await _databaseService.database;
  if (forceSync) await _pullFromCentral();
  // ...existing query unchanged
}

// LookupRepository
Future<List<LookupItemModel>> getAllItems({String? tenantId, bool forceSync = false}) async {
  final db = await _databaseService.database;
  if (forceSync) await _pullFromCentral();
  // ...existing query unchanged
}
```

### Step 2 — Centralize the pull, don't bury it in `CampRepository`

Since `pullDelta()` already returns camps + patients + visits + lookups in one call, move it into a single coordinator that every repo/viewmodel can call:

```dart
class SyncCoordinator {
  Future<void> pullAll({required String deviceId, required String userId}) async {
    if (HttpCentralApiService.isServerCooldownActive) return;
    await SyncRepository().pullDelta(deviceId: deviceId, userId: userId);
  }
}
```

Use the **real** `deviceId` / `userId` — already threaded through every write method — instead of `'dev-auto'` / `'usr-auto'`.

### Step 3 — Trigger the pull at the right moments

- On app foreground/resume.
- Once when each list screen (camps, patient list, lookup manager) first loads.
- On explicit pull-to-refresh (`forceSync: true`, awaited, so the UI waits for fresh data before rendering).

### Step 4 — Surface sync state to the UI

A `lastSyncedAt` + `isSyncing` value in a Riverpod provider lets the UI show "Synced 2 min ago" or a spinner, so staff at a camp with unreliable internet aren't guessing whether what they see is current.

### Step 5 — Fix the collision and tombstone issues

- **Patient ID:** reject/renumber on collision during server-side push, or reserve ID blocks per device at camp-open time.
- **Lookup delete:** switch to soft delete locally, and verify the pull-merge logic respects `is_deleted` before re-inserting.

---

## Central Server Findings (`sync_server.dart`)

Findings from the standalone Dart HTTP server that bridges the web admin, Android app, and central PostgreSQL.

### S1. Sync push reports success even when the database write fails or never happens (Critical)

```dart
for (final p in patients) {
  final map = p as Map<String, dynamic>;
  final id = map['id']?.toString() ?? '';
  _memPatients[id] = map;
  syncedPatientIds.add(id);          // added unconditionally, BEFORE the DB write is attempted

  if (_isPgConnected && _connection != null) {
    try {
      await _connection!.execute(...);
    } catch (e) {
      print('Error inserting patient $id: $e');   // swallowed; id is already in syncedPatientIds
    }
  }
}
```

`id` is added to `syncedPatientIds` before the Postgres insert is attempted, and nothing removes it if the insert throws or Postgres isn't connected. The response always reports `success: true` with the id included. On the client:

```dart
if (response.success && response.syncedPatientIds.contains(patient.id)) {
  // mark is_synced = 1 locally — even though the central write may have failed
}
```

If Postgres drops for any stretch (redeploy, connection blip) and patients are registered during that window, they live only in the server's in-memory `_memPatients` map — gone on process restart — while the originating device believes they synced and never retries. This is silent, permanent data loss, and explains a "doesn't show up elsewhere" symptom better than a timing race does. Same pattern applies to `syncedVisitIds`.

### S2. Schema initialization order bug breaks fresh deployments (Critical)

```dart
await _connection!.execute('ALTER TABLE camps ADD COLUMN IF NOT EXISTS doctor_name TEXT DEFAULT \'\';');
await _connection!.execute('ALTER TABLE devices ADD COLUMN IF NOT EXISTS tenant_id TEXT DEFAULT \'tenant_default\';');  // devices doesn't exist yet

await _connection!.execute('''CREATE TABLE IF NOT EXISTS audit_logs (...)''');
await _connection!.execute('''CREATE TABLE IF NOT EXISTS devices (...)''');   // created AFTER the ALTER above
```

`ALTER TABLE devices` runs before `CREATE TABLE devices`. On any brand-new Postgres database this throws (`relation "devices" does not exist`), and since every statement runs inside one `try` block, that exception aborts everything after it — **`audit_logs` and `devices` never get created** on a fresh deploy. Every device-related endpoint then silently falls back to the in-memory maps (each handler's own `try/catch` swallows the "table doesn't exist" error), so device registration/approval appears to work but never persists, and is lost on every restart.

### S3. `/api/sync/pull` drops `province` and `doctor_name` from camps (High)

`ALTER TABLE camps ADD COLUMN province` / `doctor_name` append columns at positions 16–17, but `_handleSyncPull`'s `SELECT *` mapping only reads through index 15 — those two fields are never included. `_handleGetCamps()` maps them correctly, but `pullDelta()` (what the app actually calls for background sync) hits `/api/sync/pull`, not `/api/camps`, so every camp pulled via sync is missing `province` and `doctor_name` even though they exist server-side.

### S4. `/api/sync/pull` is a full table dump, not a delta (High)

No `since`/timestamp parameter, no tenant filtering, nothing scoped by device — every call returns every camp, user, patient, visit, and lookup item in the database. This matters directly for the fix plan above: pulling more often (on more screens, per Step 3) against a full unfiltered dump gets expensive fast as patient/visit counts grow, especially given the connectivity these camps likely have.

### S5. Password and PIN hashes are broadcast to every device (High / Security)

```dart
usersList.add({
  ...
  'password_hash': row[10],
  'pin_hash': row[11],
});
```

Both `/api/users` and `/api/sync/pull` include every user's `password_hash` and `pin_hash` in the response to any device that calls them, with no field filtering before serialization.

### S6. Audit trail is never persisted (Medium)

`_handleSyncPush` only does `_memAuditLogs.add(map)` for incoming audit logs — there is no `INSERT INTO audit_logs` anywhere in the file, despite the schema having `record_hash`/`previous_hash` columns implying a tamper-evident hash chain was intended. The audit trail currently lives only in RAM and is lost on every restart (independent of the S2 bug).

### S7. "Single active camp" enforced inconsistently in three places (Medium)

- Locally in `CampRepository.getAllCamps()` — closes stale OPEN rows in SQLite.
- Server-side in `_handlePostCamp` — closes other OPEN camps in both memory and Postgres.
- Server-side in `_handleGetCamps` — patches the *in-memory response object* to show only one OPEN camp, but never writes this back to Postgres, so it's cosmetic only.

None of these reconcile with each other, and the third looks like a fix but doesn't persist anything.

### S8. No server-side uniqueness constraint on `patient_id` (Medium)

Confirms the client-side collision risk noted in Additional Issue A — the `patients` table has `id` as primary key but no `UNIQUE` constraint on `patient_id`, so the server accepts two different patients sharing one human-readable ID.

---

## Central Server Fixes — Priority 1

### Fix for S1 — only mark patients/visits synced after a confirmed write

```dart
for (final p in patients) {
  final map = p as Map<String, dynamic>;
  final id = map['id']?.toString() ?? '';
  if (id.isEmpty) continue;
  _memPatients[id] = map;

  bool committed = false;
  if (_isPgConnected && _connection != null) {
    try {
      await _connection!.execute(
        Sql.named('''
          INSERT INTO patients (id, patient_id, camp_id, camp_code, intake_date, first_name, surname, age, spouse_or_father_name, relationship_type, mobile, district, municipality, ward, reasons_for_visit, created_at, created_by_user_id, created_by_device_id, tenant_id, is_synced, synced_at)
          VALUES (@id, @patient_id, @camp_id, @camp_code, @intake_date, @first_name, @surname, @age, @spouse_or_father_name, @relationship_type, @mobile, @district, @municipality, @ward, @reasons_for_visit, @created_at, @created_by_user_id, @created_by_device_id, @tenant_id, 1, NOW())
          ON CONFLICT (id) DO UPDATE SET
            first_name = EXCLUDED.first_name,
            surname = EXCLUDED.surname,
            age = EXCLUDED.age,
            mobile = EXCLUDED.mobile,
            ward = EXCLUDED.ward,
            updated_at = NOW(),
            synced_at = NOW();
        '''),
        parameters: {
          'id': id,
          'patient_id': map['patient_id'] ?? id,
          'camp_id': map['camp_id'] ?? '',
          'camp_code': map['camp_code'] ?? 'KTM01',
          'intake_date': map['intake_date'] ?? DateTime.now().toIso8601String(),
          'first_name': map['first_name'] ?? '',
          'surname': map['surname'] ?? '',
          'age': map['age'] ?? 30,
          'spouse_or_father_name': map['spouse_or_father_name'],
          'relationship_type': map['relationship_type'],
          'mobile': map['mobile'],
          'district': map['district'],
          'municipality': map['municipality'],
          'ward': map['ward'] ?? '01',
          'reasons_for_visit': map['reasons_for_visit'],
          'created_at': map['created_at'] ?? DateTime.now().toIso8601String(),
          'created_by_user_id': map['created_by_user_id'] ?? '',
          'created_by_device_id': map['created_by_device_id'] ?? '',
          'tenant_id': map['tenant_id'] ?? 'tenant_default',
        },
      );
      committed = true;
    } catch (e) {
      print('Error inserting patient $id: $e');
    }
  }

  if (committed) {
    syncedPatientIds.add(id);
  }
}
```

Apply the identical pattern to the clinical visits loop for `syncedVisitIds`.

**Behavior change to be aware of:** if Postgres is down, pushes will now correctly report those records as *not* synced instead of silently succeeding. Confirm the client's retry path (`is_synced = 0` stays until the next successful push) is driven by something recurring — a periodic background retry, not only the next manual sync — or unsynced records could still sit unpushed indefinitely.

### Fix for S2 — reorder schema initialization

Simplest fix: delete the stray line entirely — `CREATE TABLE devices` already declares `tenant_id TEXT DEFAULT 'tenant_default'` in its column list, so the ALTER is redundant on a fresh install:

```dart
// Remove this line from its current position (before CREATE TABLE devices):
// await _connection!.execute('ALTER TABLE devices ADD COLUMN IF NOT EXISTS tenant_id TEXT DEFAULT \'tenant_default\';');
```

If you'd rather keep the ALTER (e.g. to guard existing pre-migration databases), move it to *after* both `CREATE TABLE audit_logs` and `CREATE TABLE devices` instead of before them — `IF NOT EXISTS` makes it safe to run there for both fresh and existing databases.

### Quick fixes for S3–S8 (next priority)

- **S3:** extend the `/api/sync/pull` camp mapping to include `row[16]` (`province`) and `row[17]` (`doctor_name`), matching `_handleGetCamps`.
- **S4:** add a `since` query param and `WHERE updated_at > @since` (or `created_at` for immutable rows) filtering to `/api/sync/pull`, with the client passing its last-synced timestamp.
- **S5:** strip `password_hash` and `pin_hash` from `/api/users` and `/api/sync/pull` responses; only return them from an endpoint actually used for auth validation.
- **S6:** add a real `INSERT INTO audit_logs` execute() call, mirroring the patients/visits insert pattern, instead of only appending to `_memAuditLogs`.
- **S7:** keep the close-other-open-camps logic only in `_handlePostCamp` (it already persists to Postgres); have `_handleGetCamps` return what's actually in the database rather than patching a copy of the response.
- **S8:** add a `UNIQUE` constraint on `patients.patient_id` (or a partial unique index scoped by `tenant_id` if IDs can repeat across tenants), and handle the resulting conflict in the push handler by returning the id via `conflict_entity_ids` instead of relying on `ON CONFLICT (id)` alone.

---

## SyncRepository Findings (`sync_repository.dart`)

### R1. Pull can silently destroy unsynced local edits (Critical)

```dart
for (final patient in response.patients) {
  final patientMap = patient.toMap();
  patientMap['is_synced'] = 1;
  patientMap['synced_at'] = pullSyncIso;
  await txn.insert(
    DatabaseTables.tablePatients,
    patientMap,
    conflictAlgorithm: ConflictAlgorithm.replace,   // full row replace, no local-state check
  );
}
```

If a health worker edits a patient offline (local row now `is_synced = 0` with new data), and a pull happens before that edit is pushed, this does a full-row `replace` with the server's pre-edit copy and force-sets `is_synced = 1`. The local edit is gone, and because it's now falsely marked synced, nothing ever pushes it again. The same pattern applies to the clinical visits upsert immediately below it. This is silent, permanent data loss — not staleness — and it gets *more* likely, not less, if pull is triggered more aggressively (as recommended earlier in this audit) without this guard in place first.

### R2. Camps are pushed in full, unconditionally, every cycle (High)

```dart
// 3. Fetch all camps to ensure central server is up to date
final campRows = await db.query(DatabaseTables.tableCamps);
final camps = campRows.map((r) => CampModel.fromMap(r)).toList();
```

No `is_synced` filter — every local camp is sent on every push. Combined with the server's `ON CONFLICT (id) DO UPDATE` with no timestamp comparison (see S7), a device that hasn't pulled a recent web-admin camp edit will silently overwrite that fresher central edit with its own stale local copy on its next push.

### R3. Push runs before pull, compounding R2 (High)

```dart
// Step 1: Push local deltas
final pushRes = await pushDelta(deviceId: deviceId, userId: userId);
// Step 2: Pull remote deltas from central server
final pullRes = await pullDelta(deviceId: deviceId, userId: userId);
```

Given R2, this ordering guarantees the clobber scenario fires on the very next sync after any web-admin camp edit, since the device pushes its stale camp list before ever learning about the newer central state.

### R4. "No pending records" short-circuit is effectively dead code (Medium)

```dart
if (patients.isEmpty && visits.isEmpty && camps.isEmpty) {
  return SyncPushResponse(success: true, ..., message: 'No pending records to push...');
}
```

Since `camps` is unconditionally populated whenever any camp exists locally (R2), this branch can essentially never trigger in real use — every `pushDelta` call sends a full camp payload even when nothing changed, feeding both the R2/R3 clobber risk and unnecessary traffic on likely-poor camp connectivity.

### R5. Audit logs re-sent and duplicated on every sync cycle (Medium)

```dart
final logRows = await db.query(
  DatabaseTables.tableAuditLogs,
  limit: 50,
  orderBy: 'timestamp DESC',
);
```

No `is_synced`/dedup filter, so the 50 most recent logs are resent every cycle. Cross-referencing central server finding S6 (`_memAuditLogs.add(map)` with no id-based dedup on the receiving end), this doesn't just waste bandwidth — it actively grows duplicate audit entries server-side for as long as the process stays up.

### R6. `_history` and last-synced tracking don't survive being constructed fresh (Medium)

`CampRepository._syncCentralCampsInBackground()` calls `SyncRepository().pullDelta(...)` — a new instance each time. Since `_history` lives on the instance, that call gets an empty `_history` and never benefits from or contributes to it. More importantly, `_persistLastSyncedAt()` is only ever invoked from inside `executeFullSyncCycle` — so a pull triggered via that bypass path (the only pull that currently runs in production, per the client-repository findings above) never updates the persisted `last_sync_at`. The `since: lastSynced` delta window used for pulls can therefore stay stale indefinitely unless something always routes through `executeFullSyncCycle` on one shared instance.

---

## SyncRepository Fixes — Priority 1

### Fix for R1 — don't overwrite local rows that have unpushed edits

```dart
// Upsert patients from central cloud (marked as synced to prevent echo-push loops)
for (final patient in response.patients) {
  final existing = await txn.query(
    DatabaseTables.tablePatients,
    columns: ['id'],
    where: 'id = ? AND is_synced = 0',
    whereArgs: [patient.id],
    limit: 1,
  );
  if (existing.isNotEmpty) {
    // Local device has an unpushed edit — keep it, let the next push win.
    // Skipping here is safe: this record will be pushed on the next pushDelta call.
    continue;
  }
  final patientMap = patient.toMap();
  patientMap['is_synced'] = 1;
  patientMap['synced_at'] = pullSyncIso;
  await txn.insert(
    DatabaseTables.tablePatients,
    patientMap,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}
```

Apply the identical guard to the clinical visits upsert loop just below it. This is a conservative fix (local-unsynced-wins) appropriate for this data model, since a field worker's in-progress edit should never be silently discarded by a background pull; the record will reconcile correctly on the next successful push.

### Quick fixes for R2–R6 (next priority)

- **R2/R3:** filter the camp query in `pushDelta` to `WHERE is_synced = 0` (requires adding an `is_synced` column to camps, mirroring patients/visits, and setting it on local camp create/update), and swap the cycle order in `executeFullSyncCycle` to pull before push so the device has the latest camp state before it pushes anything.
- **R4:** once R2 adds real filtering, this short-circuit starts working as intended with no further change needed.
- **R5:** add an `is_synced` filter to the audit log query, and mark logs synced (mirroring patients/visits) once `pushRes.syncedAuditLogIds` confirms they landed — this also depends on fixing S6 server-side so logs are actually durable once acknowledged.
- **R6:** make `SyncRepository` a singleton (or inject one shared instance via your DI/provider setup) so `_history` and `_persistLastSyncedAt` are consistent across every caller, including `CampRepository`'s background trigger; alternatively, have `_syncCentralCampsInBackground()` go through `executeFullSyncCycle` on the shared instance instead of calling `pullDelta` directly.

---

## Summary Checklist

**Client (Flutter repositories)**
- [ ] Add `forceSync` param to `getPatientsByCamp`, `getAllItems`, `getItemsByCategory`
- [ ] Extract a single `SyncCoordinator.pullAll()` used by all repos
- [ ] Replace hardcoded `'dev-auto'` / `'usr-auto'` with real device/user IDs
- [ ] Trigger sync on app resume + first screen load + manual refresh (awaited)
- [ ] Add `lastSyncedAt` / `isSyncing` state visible in the UI
- [ ] Add server-side patient ID collision handling
- [ ] Switch lookup item delete to soft delete (`is_deleted = 1`) instead of hard delete
- [ ] Replace silent `catch (_) {}` blocks with logged errors + a pending-sync indicator

**Server (`sync_server.dart`)**
- [ ] Fix sync push to only mark patients/visits synced on confirmed DB write (S1)
- [ ] Fix schema init order — devices ALTER runs before CREATE TABLE devices (S2)
- [ ] Add `province`/`doctor_name` to `/api/sync/pull` camp mapping (S3)
- [ ] Add delta filtering (`since`/`updated_at`) to `/api/sync/pull` (S4)
- [ ] Strip `password_hash`/`pin_hash` from broadcasted user data (S5)
- [ ] Persist audit logs to Postgres instead of in-memory only (S6)
- [ ] Consolidate single-active-camp enforcement to one authoritative place (S7)
- [ ] Add `UNIQUE` constraint on `patients.patient_id` (S8)

**SyncRepository (`sync_repository.dart`)**
- [ ] Guard patient/visit pull-upsert against overwriting unsynced local edits (R1)
- [ ] Filter camp push to unsynced-only, add `is_synced` tracking to camps (R2)
- [ ] Pull before push in `executeFullSyncCycle` (R3)
- [ ] Filter and mark audit logs synced instead of resending all 50 every cycle (R5)
- [ ] Make `SyncRepository` a shared/singleton instance so history + last-synced tracking is consistent (R6)
