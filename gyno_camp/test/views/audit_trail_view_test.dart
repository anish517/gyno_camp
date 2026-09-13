import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyno_camp/core/theme/app_theme.dart';
import 'package:gyno_camp/models/audit_log_model.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/viewmodels/audit_log_viewmodel.dart';
import 'package:gyno_camp/views/admin/audit_trail_view.dart';

import 'package:gyno_camp/core/security/security_service.dart';

class FakeAuditRepository implements IAuditRepository {
  static final _time1 = DateTime(2026, 9, 6, 10, 0);
  static final _hash1 = SecurityService.generateAuditHash(
    logId: 'log-1',
    userId: 'admin-01',
    action: 'CAMP_OPENED',
    timestamp: _time1.toIso8601String(),
    details: '{"campCode":"KTM01"}',
  );

  static final _time2 = DateTime(2026, 9, 6, 10, 15);
  static final _hash2 = SecurityService.generateAuditHash(
    logId: 'log-2',
    userId: 'usr-datataker-01',
    action: 'PATIENT_REGISTERED',
    timestamp: _time2.toIso8601String(),
    details: '{"patientId":"KTM01-0001"}',
    previousHash: _hash1,
  );

  List<AuditLogModel> logs = [
    AuditLogModel(
      id: 'log-1',
      userId: 'admin-01',
      userName: 'Dr. Aruna Shrestha',
      userRole: 'SUPER_ADMIN',
      action: 'CAMP_OPENED',
      entityType: 'Camp',
      entityId: 'camp-ktm-01',
      detailsJson: '{"campCode":"KTM01"}',
      deviceId: 'dev-01',
      timestamp: _time1,
      logHash: _hash1,
    ),
    AuditLogModel(
      id: 'log-2',
      userId: 'usr-datataker-01',
      userName: 'Sita Sharma',
      userRole: 'DATA_TAKER',
      action: 'PATIENT_REGISTERED',
      entityType: 'Patient',
      entityId: 'pat-001',
      detailsJson: '{"patientId":"KTM01-0001"}',
      deviceId: 'dev-01',
      timestamp: _time2,
      logHash: _hash2,
    ),
  ];

  @override
  Future<List<AuditLogModel>> getRecentLogs({int limit = 50}) async => logs.take(limit).toList();

  @override
  Future<List<AuditLogModel>> getAllLogs() async => logs;

  @override
  Future<List<AuditLogModel>> getLogsByUser(String userId, {int limit = 50}) async =>
      logs.where((l) => l.userId == userId).take(limit).toList();

  @override
  Future<void> logActivity({
    required String userId,
    required String userName,
    required String userRole,
    required String action,
    required String entityType,
    String? entityId,
    required String detailsJson,
    required String deviceId,
  }) async {
    final log = AuditLogModel(
      id: 'log-${logs.length + 1}',
      userId: userId,
      userName: userName,
      userRole: userRole,
      action: action,
      entityType: entityType,
      entityId: entityId,
      detailsJson: detailsJson,
      deviceId: deviceId,
      timestamp: DateTime.now(),
      logHash: 'hash-${logs.length + 1}',
    );
    logs.add(log);
  }
}

void main() {
  Widget createTestWidget(IAuditRepository repo) {
    return ProviderScope(
      overrides: [
        auditRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const AuditTrailView(),
      ),
    );
  }

  testWidgets('AuditTrailView renders banner and log items', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeAuditRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    expect(find.text('Tamper-Evident Audit Trail'), findsOneWidget);
    expect(find.text('Cryptographic Chain Intact (SHA-256)'), findsOneWidget);
    expect(find.text('CAMP_OPENED'), findsOneWidget);
    expect(find.text('PATIENT_REGISTERED'), findsOneWidget);
    expect(find.textContaining('Dr. Aruna Shrestha'), findsOneWidget);
  });

  testWidgets('Tapping audit log opens detail modal with JSON and full hash', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeAuditRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('CAMP_OPENED'));
    await tester.pumpAndSettle();

    expect(find.text('Details JSON Payload:'), findsOneWidget);
    expect(find.text('{"campCode":"KTM01"}'), findsOneWidget);
    expect(find.text('Chained SHA-256 Hash:'), findsOneWidget);
    expect(find.text('Copy Hash'), findsOneWidget);
  });
}
