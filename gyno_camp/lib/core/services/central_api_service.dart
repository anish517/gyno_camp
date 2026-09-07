import '../../models/camp_model.dart';
import '../../models/clinical_visit_model.dart';
import '../../models/lookup_item_model.dart';
import '../../models/patient_model.dart';
import '../../models/sync_payload_model.dart';
import '../../models/user_model.dart';

abstract class ICentralApiService {
  Future<bool> pingServer();
  Future<SyncPushResponse> pushDelta(SyncPushPayload payload);
  Future<SyncPullResponse> pullDelta({DateTime? since, required String deviceId});
  void setMockServerCamps(List<CampModel> camps);
  void setMockServerLookupItems(List<LookupItemModel> items);
  List<PatientModel> get serverStoredPatients;
  List<ClinicalVisitModel> get serverStoredVisits;
}

class CentralApiService implements ICentralApiService {
  final List<PatientModel> _serverPatients = [];
  final List<ClinicalVisitModel> _serverVisits = [];
  final List<CampModel> _serverCamps = [];
  final List<LookupItemModel> _serverLookupItems = [];
  final List<UserModel> _serverUsers = [];

  bool simulateNetworkFailure = false;

  CentralApiService() {
    _seedDefaultServerData();
  }

  void _seedDefaultServerData() {
    _serverCamps.add(
      CampModel(
        id: 'camp-ktm-01',
        campCode: 'KTM01',
        name: 'Community Gyno Health Camp',
        district: 'Kathmandu',
        municipality: 'Budhanilkantha Municipality',
        ward: '03',
        venue: 'Primary Health Care Center',
        startDate: DateTime.now().subtract(const Duration(days: 1)),
        endDate: DateTime.now().add(const Duration(days: 3)),
        status: CampStatus.open,
        assignedStaffIds: const ['usr-datataker-01', 'usr-superadmin-01'],
        totalPatientsRegistered: 0,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        tenantId: 'tenant_default',
        organizationName: 'Community Health Outreach Mission',
      ),
    );

    _serverUsers.addAll([
      const UserModel(
        id: 'usr-superadmin-01',
        name: 'Super Administrator',
        email: 'admin@gynocamp.org',
        phone: '9851000001',
        role: UserRole.superAdmin,
        tenantId: 'tenant_default',
        tenantName: 'Community Health Outreach Mission',
      ),
      const UserModel(
        id: 'usr-datataker-01',
        name: 'Field Nurse',
        email: 'nurse@gynocamp.org',
        phone: '9841000002',
        role: UserRole.dataTaker,
        tenantId: 'tenant_default',
        tenantName: 'Community Health Outreach Mission',
      ),
      const UserModel(
        id: 'usr-dataanalyst-01',
        name: 'Data Analyst',
        email: 'analyst@gynocamp.org',
        phone: '9860123456',
        role: UserRole.dataAnalyst,
        tenantId: 'tenant_default',
        tenantName: 'Community Health Outreach Mission',
      ),
    ]);
  }

  @override
  List<PatientModel> get serverStoredPatients => List.unmodifiable(_serverPatients);

  @override
  List<ClinicalVisitModel> get serverStoredVisits => List.unmodifiable(_serverVisits);

  @override
  void setMockServerCamps(List<CampModel> camps) {
    _serverCamps.clear();
    _serverCamps.addAll(camps);
  }

  @override
  void setMockServerLookupItems(List<LookupItemModel> items) {
    _serverLookupItems.clear();
    _serverLookupItems.addAll(items);
  }

  @override
  Future<bool> pingServer() async {
    if (simulateNetworkFailure) return false;
    return true;
  }

  @override
  Future<SyncPushResponse> pushDelta(SyncPushPayload payload) async {
    if (simulateNetworkFailure) {
      throw Exception('Network timeout: Could not connect to central Gynocamp server.');
    }

    final serverTime = DateTime.now();
    final syncedPatientIds = <String>[];
    final syncedVisitIds = <String>[];
    final syncedAuditLogIds = <String>[];
    final conflictIds = <String>[];

    // Process Patients
    for (final patient in payload.patients) {
      final existingIndex = _serverPatients.indexWhere((p) => p.id == patient.id);
      if (existingIndex >= 0) {
        final existing = _serverPatients[existingIndex];
        // Last-Write-Wins (LWW) check
        final existingTime = existing.updatedAt ?? existing.createdAt;
        final incomingTime = patient.updatedAt ?? patient.createdAt;
        if (incomingTime.isBefore(existingTime)) {
          conflictIds.add(patient.id);
          continue;
        }
        _serverPatients[existingIndex] = patient.copyWith(isSynced: true, syncedAt: serverTime);
      } else {
        _serverPatients.add(patient.copyWith(isSynced: true, syncedAt: serverTime));
      }
      syncedPatientIds.add(patient.id);
    }

    // Process Clinical Visits
    for (final visit in payload.clinicalVisits) {
      final existingIndex = _serverVisits.indexWhere((v) => v.id == visit.id);
      if (existingIndex >= 0) {
        final existing = _serverVisits[existingIndex];
        final existingTime = existing.updatedAt ?? existing.createdAt;
        final incomingTime = visit.updatedAt ?? visit.createdAt;
        if (incomingTime.isBefore(existingTime)) {
          conflictIds.add(visit.id);
          continue;
        }
        _serverVisits[existingIndex] = visit;
      } else {
        _serverVisits.add(visit);
      }
      syncedVisitIds.add(visit.id);
    }

    // Process Audit Logs
    for (final log in payload.auditLogs) {
      syncedAuditLogIds.add(log.id);
    }

    return SyncPushResponse(
      success: true,
      serverTimestamp: serverTime,
      syncedPatientIds: syncedPatientIds,
      syncedVisitIds: syncedVisitIds,
      syncedAuditLogIds: syncedAuditLogIds,
      conflictEntityIds: conflictIds,
      message: 'Successfully processed ${syncedPatientIds.length} patients and ${syncedVisitIds.length} visits.',
    );
  }

  @override
  Future<SyncPullResponse> pullDelta({DateTime? since, required String deviceId}) async {
    if (simulateNetworkFailure) {
      throw Exception('Network timeout: Could not connect to central Gynocamp server.');
    }

    final serverTime = DateTime.now();

    final deltaCamps = since == null
        ? _serverCamps
        : _serverCamps.where((c) {
            final t = c.updatedAt ?? c.createdAt;
            return t.isAfter(since);
          }).toList();

    final deltaLookup = since == null
        ? _serverLookupItems
        : _serverLookupItems.where((l) {
            return true;
          }).toList();

    final deltaUsers = since == null
        ? _serverUsers
        : _serverUsers.where((u) {
            return u.lastLoginAt != null ? u.lastLoginAt!.isAfter(since) : true;
          }).toList();

    return SyncPullResponse(
      success: true,
      serverTimestamp: serverTime,
      camps: deltaCamps,
      lookupItems: deltaLookup,
      users: deltaUsers,
      message: 'Pulled ${deltaCamps.length} camps, ${deltaUsers.length} users.',
    );
  }
}
