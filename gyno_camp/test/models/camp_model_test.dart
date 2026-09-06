import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/models/camp_model.dart';

void main() {
  group('CampModel & CampStatus Tests', () {
    test('CampStatus enum parsing and lifecycle checks', () {
      expect(CampStatus.fromString('OPEN'), CampStatus.open);
      expect(CampStatus.fromString('CLOSED'), CampStatus.closed);
      expect(CampStatus.fromString('DRAFT'), CampStatus.draft);
      expect(CampStatus.fromString('SCHEDULED'), CampStatus.scheduled);
      expect(CampStatus.open.isOpenForDataEntry, isTrue);
      expect(CampStatus.closed.isOpenForDataEntry, isFalse);
    });

    test('CampModel serialization and staff assignment verification', () {
      final now = DateTime(2026, 9, 6);
      final camp = CampModel(
        id: 'camp-01',
        campCode: 'KTM01',
        name: 'Kathmandu Health Camp',
        district: 'Kathmandu',
        municipality: 'Budhanilkantha',
        ward: '03',
        venue: 'Health Post',
        startDate: now,
        endDate: now.add(const Duration(days: 2)),
        status: CampStatus.open,
        assignedStaffIds: const ['staff-1', 'staff-2'],
        totalPatientsRegistered: 25,
        createdAt: now,
      );

      expect(camp.isOpen, isTrue);
      expect(camp.isStaffAssigned('staff-1'), isTrue);
      expect(camp.isStaffAssigned('staff-99'), isFalse);

      final map = camp.toMap();
      final fromMap = CampModel.fromMap(map);

      expect(fromMap.id, camp.id);
      expect(fromMap.campCode, 'KTM01');
      expect(fromMap.totalPatientsRegistered, 25);
      expect(fromMap.assignedStaffIds, ['staff-1', 'staff-2']);
    });
  });
}
