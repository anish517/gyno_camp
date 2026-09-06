import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyno_camp/core/theme/app_theme.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/repositories/camp_repository.dart';
import 'package:gyno_camp/viewmodels/camp_viewmodel.dart';
import 'package:gyno_camp/views/admin/camp_management_view.dart';

class FakeCampRepository implements ICampRepository {
  List<CampModel> camps = [
    CampModel(
      id: 'c1',
      campCode: 'KTM01',
      name: 'Kathmandu Central Camp',
      district: 'Kathmandu',
      municipality: 'Budhanilkantha',
      ward: '2',
      venue: 'Health Post',
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 5),
      status: CampStatus.open,
      createdAt: DateTime.now(),
      totalPatientsRegistered: 45,
    ),
    CampModel(
      id: 'c2',
      campCode: 'DHN02',
      name: 'Dhading Rural Camp',
      district: 'Dhading',
      municipality: 'Nilkantha',
      ward: '4',
      venue: 'Primary Care Center',
      startDate: DateTime(2026, 9, 15),
      endDate: DateTime(2026, 9, 18),
      status: CampStatus.scheduled,
      createdAt: DateTime.now(),
      totalPatientsRegistered: 0,
    ),
  ];

  @override
  Future<List<CampModel>> getAllCamps() async => camps;

  @override
  Future<CampModel?> getActiveCamp() async {
    try {
      return camps.firstWhere((c) => c.status == CampStatus.open);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<CampModel?> getCampById(String id) async {
    try {
      return camps.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<CampModel> createCamp(CampModel camp, {required String createdByUserId, required String deviceId}) async {
    camps.add(camp);
    return camp;
  }

  @override
  Future<bool> openCamp(String campId, {required String adminUserId, required String deviceId}) async {
    for (int i = 0; i < camps.length; i++) {
      if (camps[i].id == campId) {
        camps[i] = camps[i].copyWith(status: CampStatus.open);
      } else if (camps[i].status == CampStatus.open) {
        camps[i] = camps[i].copyWith(status: CampStatus.closed);
      }
    }
    return true;
  }

  @override
  Future<bool> closeCamp(String campId, {required String adminUserId, required String deviceId}) async {
    final idx = camps.indexWhere((c) => c.id == campId);
    if (idx != -1) {
      camps[idx] = camps[idx].copyWith(status: CampStatus.closed);
      return true;
    }
    return false;
  }

  @override
  Future<bool> archiveCamp(String campId, {required String adminUserId, required String deviceId}) async {
    final idx = camps.indexWhere((c) => c.id == campId);
    if (idx != -1) {
      camps[idx] = camps[idx].copyWith(status: CampStatus.archived);
      return true;
    }
    return false;
  }

  @override
  Future<CampModel> updateCamp(CampModel camp, {required String adminUserId, required String deviceId}) async {
    final idx = camps.indexWhere((c) => c.id == camp.id);
    if (idx != -1) camps[idx] = camp;
    return camp;
  }

  @override
  Future<bool> deleteCamp(String campId, {required String adminUserId, required String deviceId}) async {
    camps.removeWhere((c) => c.id == campId);
    return true;
  }

  @override
  Future<bool> assignStaff(String campId, List<String> staffIds, {required String adminUserId, required String deviceId}) async {
    final idx = camps.indexWhere((c) => c.id == campId);
    if (idx != -1) {
      camps[idx] = camps[idx].copyWith(assignedStaffIds: staffIds);
      return true;
    }
    return false;
  }
}

void main() {
  Widget createTestWidget(ICampRepository repo) {
    return ProviderScope(
      overrides: [
        campRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const CampManagementView(),
      ),
    );
  }

  testWidgets('CampManagementView renders Camp Roster tab with camp cards', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeCampRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    expect(find.text('Camp Lifecycle & Calendar'), findsOneWidget);
    expect(find.text('Camp Roster'), findsOneWidget);
    expect(find.text('Interactive Calendar'), findsOneWidget);

    expect(find.text('Kathmandu Central Camp'), findsOneWidget);
    expect(find.text('Dhading Rural Camp'), findsOneWidget);
    expect(find.text('45 Intakes'), findsOneWidget);
  });

  testWidgets('CampManagementView switches to Interactive Calendar tab', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeCampRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Interactive Calendar'));
    await tester.pumpAndSettle();

    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('Mon'), findsOneWidget);
    expect(find.text('Sun'), findsOneWidget);
  });
}
