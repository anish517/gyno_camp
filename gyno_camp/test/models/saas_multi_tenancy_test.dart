import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/models/sync_payload_model.dart';
import 'package:gyno_camp/models/user_model.dart';

void main() {
  group('SaaS Multi-Tenancy Architecture Tests', () {
    test('UserModel serializes and deserializes tenantId and tenantName properly', () {
      const user = UserModel(
        id: 'usr-nurse-10',
        name: 'Gita Adhikari',
        email: 'gita@fpan.org',
        phone: '9841999888',
        role: UserRole.dataTaker,
        tenantId: 'tenant_fpan_nepal',
        tenantName: 'Family Planning Association of Nepal (FPAN)',
        assignedCampIds: ['camp-fpan-01', 'camp-fpan-02'],
      );

      final map = user.toMap();
      expect(map['tenant_id'], 'tenant_fpan_nepal');
      expect(map['tenant_name'], 'Family Planning Association of Nepal (FPAN)');

      final reconstituted = UserModel.fromMap(map);
      expect(reconstituted.tenantId, 'tenant_fpan_nepal');
      expect(reconstituted.tenantName, 'Family Planning Association of Nepal (FPAN)');
      expect(reconstituted.assignedCampIds, ['camp-fpan-01', 'camp-fpan-02']);
    });

    test('CampModel serializes and deserializes tenantId and organizationName properly', () {
      final camp = CampModel(
        id: 'camp-fpan-01',
        campCode: 'FPAN01',
        name: 'FPAN Sindhupalchok Mobile Camp',
        district: 'Sindhupalchok',
        municipality: 'Chautara Sangachokgadhi',
        ward: '04',
        venue: 'District Health Center',
        startDate: DateTime(2026, 9, 15),
        endDate: DateTime(2026, 9, 18),
        tenantId: 'tenant_fpan_nepal',
        organizationName: 'Family Planning Association of Nepal',
        createdAt: DateTime(2026, 9, 1),
      );

      final map = camp.toMap();
      expect(map['tenant_id'], 'tenant_fpan_nepal');
      expect(map['organization_name'], 'Family Planning Association of Nepal');

      final reconstituted = CampModel.fromMap(map);
      expect(reconstituted.tenantId, 'tenant_fpan_nepal');
      expect(reconstituted.organizationName, 'Family Planning Association of Nepal');
    });

    test('PatientModel and ClinicalVisitModel stamp tenantId correctly in payloads', () {
      final patient = PatientModel(
        id: 'pat-100',
        patientId: 'GC-FPAN01-2026-00001',
        campId: 'camp-fpan-01',
        campCode: 'FPAN01',
        intakeDate: DateTime(2026, 9, 15),
        firstName: 'Maya',
        surname: 'Gurung',
        age: 39,
        mobile: '9801234567',
        ward: '04',
        createdAt: DateTime(2026, 9, 15),
        createdByUserId: 'usr-nurse-10',
        createdByDeviceId: 'dev-tab-02',
        tenantId: 'tenant_fpan_nepal',
      );

      final visit = ClinicalVisitModel(
        id: 'vis-100',
        patientId: 'GC-FPAN01-2026-00001',
        campId: 'camp-fpan-01',
        visitDate: DateTime(2026, 9, 15),
        createdAt: DateTime(2026, 9, 15),
        createdByUserId: 'usr-nurse-10',
        tenantId: 'tenant_fpan_nepal',
      );

      final pMap = patient.toMap();
      final vMap = visit.toMap();

      expect(pMap['tenant_id'], 'tenant_fpan_nepal');
      expect(vMap['tenant_id'], 'tenant_fpan_nepal');

      final pushPayload = SyncPushPayload(
        deviceId: 'dev-tab-02',
        generatedAt: DateTime.now(),
        tenantId: 'tenant_fpan_nepal',
        patients: [patient],
        clinicalVisits: [visit],
      );

      final payloadMap = pushPayload.toMap();
      expect(payloadMap['tenant_id'], 'tenant_fpan_nepal');
      expect((payloadMap['patients'] as List).first['tenant_id'], 'tenant_fpan_nepal');
      expect((payloadMap['clinical_visits'] as List).first['tenant_id'], 'tenant_fpan_nepal');
    });
  });
}
