# Comprehensive Fix for 13 Field & Sync Defects Across Web, Android, RBAC, and Analytics

This implementation plan addresses the 13 concrete defects identified during real-world testing of the GynoCamp project on Chrome Web and Android tablet.

---

## User Review Required

> [!IMPORTANT]
> **Super Admin Camp Assignment Exemption (Issue 10)**:
> Super Admin accounts are now categorically exempt from camp assignment validation gates. Super Administrators govern tenants and configure camps; requiring an active assigned camp before login caused a critical lockout if all camps were deleted.
> 
> **Central Cloud Deletion Propagation (Issues 2, 6A, 3)**:
> Previously, deleting an entity (camp, staff user, medicine lookup) on Web only deleted it in the central PostgreSQL database. Android's local SQLite database was never informed of the deletion, keeping stale records and re-syncing them back to Web. We introduce explicit deletion propagation via `deleted_camp_ids`, `deleted_user_ids`, and `deleted_lookup_ids` in `/api/sync/pull` and an explicit `DELETE /api/lookups` endpoint.

---

## Proposed Changes

### 1. Authentication, RBAC & Super Admin Gate (Issues 9 & 10)

#### [MODIFY] [user_model.dart](file:///f:/gyno_camp/gyno_camp/lib/models/user_model.dart)
- Expand `UserRole.fromString` to recognize `'ADMIN'`, `'SUPERADMIN'`, `'SUPER_ADMIN'`, `'SUPER ADMINISTRATOR'`, and `'ROOT'`.
- Enhance `UserModel.isSuperAdmin` to verify role, well-known root ID (`'usr-superadmin-01'`), root email (`'admin@gynocamp.org'`), or name containing `'super admin'/'super administrator'`.

#### [MODIFY] [auth_viewmodel.dart](file:///f:/gyno_camp/gyno_camp/lib/viewmodels/auth_viewmodel.dart)
- Update login, session restore, and `loginAsRole` camp assignment gates:
  ```dart
  if (!user.isSuperAdmin && user.role != UserRole.superAdmin) { ... }
  ```
  Ensures Super Admin is never locked out even if all camps are deleted or unassigned.

#### [MODIFY] [auth_repository.dart](file:///f:/gyno_camp/gyno_camp/lib/repositories/auth_repository.dart)
- Support superadmin aliases (`'superadmin'`, `'admin'`).
- Preserve local password/PIN hashes during sync and cloud pulls so user credentials are not overwritten by null values.

---

### 2. Staff Registration & Security Management (Issues 6B, 7, 9)

#### [MODIFY] [user_management_view.dart](file:///f:/gyno_camp/gyno_camp/lib/views/admin/user_management_view.dart)
- **Issue 6B**: Remove the unstable `LayoutBuilder` inside `_showAddStaffDialog` that destroyed and recreated `TextField` instances when the virtual keyboard or error snackbars appeared. Use a stable responsive layout with fixed keys so password and PIN text fields remain fully editable.
- **Issue 7**: In `_showAddStaffDialog`, pre-fill Organization Name by reading from `SessionService.current?.getOrganizationName()`, active tenant metadata, or current user's organization name.
- **Issue 9**: In `_showSecurityDialog`, hash new password/PIN, persist locally in SQLite, update audit log, and broadcast the update to Central Cloud.

---

### 3. Central Server Deletion Propagation & Sync (Issues 2, 3, 6A, 8, 9)

#### [MODIFY] [server.dart](file:///f:/gyno_camp/gyno_camp/bin/server.dart)
- Create `deleted_entities` table in PostgreSQL (`id TEXT, entity_type TEXT, deleted_at TIMESTAMPTZ`) to track deleted camps, users, and lookup items.
- In `_handleDeleteCamp`: record deleted camp ID into `deleted_entities`.
- In `_handleDeleteUser`: record deleted user ID into `deleted_entities`.
- Add `DELETE /api/lookups` route and handler to delete medicines/diagnoses from PostgreSQL and track in `deleted_entities`.
- In `_handleSyncPull`:
  - Return `deleted_camp_ids`, `deleted_user_ids`, `deleted_lookup_ids`.
  - Filter `lookup_items` with `WHERE is_deleted = 0`.
  - Include `doctor_names` column in camp schema and queries.
  - Fix user password/pin update handling so credentials are not wiped on pull.

#### [MODIFY] [sync_repository.dart](file:///f:/gyno_camp/gyno_camp/lib/repositories/sync_repository.dart)
- In `pullDelta()`:
  - Delete local SQLite camps matching `deleted_camp_ids`.
  - Delete local SQLite users matching `deleted_user_ids`.
  - Delete local SQLite lookups matching `deleted_lookup_ids`.
  - When upserting users from central cloud, preserve existing local `password_hash` and `pin_hash` if remote fields are null.

#### [MODIFY] [camp_repository.dart](file:///f:/gyno_camp/gyno_camp/lib/repositories/camp_repository.dart)
- **Issue 8 Speed Optimization**: Remove the redundant call to `SyncRepository().pullDelta()` from inside `getAllCamps()`. Serve local SQLite camps immediately and reconcile with central cloud asynchronously.
- Cascade-prune orphaned patients and clinical visits when camps are deleted:
  ```sql
  DELETE FROM patients WHERE camp_id NOT IN (SELECT id FROM camps);
  DELETE FROM clinical_visits WHERE camp_id NOT IN (SELECT id FROM camps);
  ```

---

### 4. Master Data & Formulary (Issues 3 & 4)

#### [MODIFY] [lookup_repository.dart](file:///f:/gyno_camp/gyno_camp/lib/repositories/lookup_repository.dart)
- In `deleteItem`: call `HttpCentralApiService().deleteCentralLookup(id)` so deletions are permanent on both local and central cloud.
- Guard `ensureDefaultsSeeded()` so that it never re-seeds default medicines or diagnoses if the tenant has already seeded once, even if items were subsequently deleted by the user.

#### [MODIFY] [master_lookup_viewmodel.dart](file:///f:/gyno_camp/gyno_camp/lib/viewmodels/master_lookup_viewmodel.dart)
- Decouple `masterLookupProvider` from full `currentUser` state watching so minor auth/device events do not trigger a full data re-fetch and UI refresh loop.

#### [MODIFY] [sync_viewmodel.dart](file:///f:/gyno_camp/gyno_camp/lib/viewmodels/sync_viewmodel.dart)
- Only reload master lookup data if `response.lookupItems.isNotEmpty`.

---

### 5. Camp Management, Doctor Names & Staff Assignment Count (Issues 1 & 5)

#### [MODIFY] [camp_management_view.dart](file:///f:/gyno_camp/gyno_camp/lib/views/admin/camp_management_view.dart)
- **Issue 1**: Dynamically compute staff assigned count by checking both `camp.assignedStaffIds` AND any staff in `allUsers` where `user.assignedCampIds.contains(camp.id)`. This guarantees camp cards reflect assignments made from both Camp Management and User Management / RBAC screens.
- **Issue 5**:
  - Add robust doctor name sanitizer regex: `raw.replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim()`.
  - When editing camp, pre-fill doctor names without `'Dr. '` prefix so saving does not accumulate multiple prefixes.
  - Properly persist `doctor_names` list and primary `doctor_name`.

---

### 6. Clinical Data Workstation & Executive Reports (Issues 11, 12, 13)

#### [MODIFY] [patient_list_viewmodel.dart](file:///f:/gyno_camp/gyno_camp/lib/viewmodels/patient_list_viewmodel.dart)
- Add `doctorName` filter criteria to `PatientFilterCriteria` and apply to patient filtering.
- Reset state cleanly during camp switches so stale counts do not flash before new data is fetched.

#### [MODIFY] [reporting_repository.dart](file:///f:/gyno_camp/gyno_camp/lib/repositories/reporting_repository.dart)
- In `getCampSummary`:
  - When `campId == null || campId == 'all'`, filter `WHERE camp_id IN (SELECT id FROM camps)` to exclude orphaned records from deleted camps.
  - Add optional `doctorFilter` parameter to filter visits and patients by attending doctor across all metrics.

#### [MODIFY] [reporting_viewmodel.dart](file:///f:/gyno_camp/gyno_camp/lib/viewmodels/reporting_viewmodel.dart)
- Support `doctorFilter` parameter in `loadSummary`.

#### [MODIFY] [home_gateway_view.dart](file:///f:/gyno_camp/gyno_camp/lib/views/dashboard/home_gateway_view.dart)
- **Issue 11**: Clear stale patient counts immediately when switching camps; show clean progress indicators.
- **Issue 12**:
  - Replace hardcoded chief complaints switch in `_DataAnalystWorkstation` with dynamic lookups from `activeChiefComplaintsProvider`.
  - Expand Doctor filter to check `visit.primaryDoctorName`, `visit.attendingDoctorNames`, and camp doctors.
  - Test and verify all filters (POP stage, chief complaint, surgery, age bracket, intake status, doctor).

#### [MODIFY] [camp_report_view.dart](file:///f:/gyno_camp/gyno_camp/lib/views/reports/camp_report_view.dart)
- **Issue 13**:
  - Add Doctor filter dropdown affecting all 5 sub-tabs (Demographics, POP Staging, Diagnosis, Treatment, Patient Registry).
  - Fix `_onCampChanged` to pass `null` (all patients) when "All camp records" is chosen instead of defaulting to active camp.
  - Make the screen modern and professional with card elevations, polished typography, and clean stats grids.

---

## Verification Plan

### Automated Tests
- Run `flutter analyze --no-pub` to ensure zero compilation or lint errors.
- Run existing unit test suite:
  ```bash
  flutter test test/views/home_gateway_view_responsive_test.dart
  ```
- Add unit tests for:
  - Super Admin camp assignment bypass in `AuthViewModel`.
  - Doctor name sanitizer (no duplicate "Dr. Dr.").
  - Deletion propagation in `SyncRepository`.
  - Staff assigned counter calculation (union of `assignedCampIds` and `assignedStaffIds`).

### Manual Verification
- Test Super Admin login when 0 camps exist in the system.
- Test Camp deletion on Web and verify deletion propagates to Android after sync.
- Test Medicine deletion (e.g. 19 to 10) and verify count remains 10 after background sync.
- Test Add Staff modal: verify organization name pre-fills, enter 4-char password, observe validation message, and verify text field remains editable.
- Test Camp edit: add doctor, save, verify single "Dr." prefix and persistence across reloads.
- Test Executive Reports: select "All camp records" when 0 patients exist, verify 0 is shown (no 22/14/8 flash).
- Test Doctor filter in Executive Reports and Clinical Workstation.
