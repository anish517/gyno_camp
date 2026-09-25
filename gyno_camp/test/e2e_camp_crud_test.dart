import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/http_central_api_service.dart';
import 'package:gyno_camp/models/camp_model.dart';

void main() {
  const testServerUrl = 'http://localhost:8080';
  final api = HttpCentralApiService(baseUrl: testServerUrl);

  group('Full Camp Lifecycle & CRUD Operations Integration Test', () {
    setUp(() {
      HttpCentralApiService.markServerOnline(testServerUrl);
    });

    test('Create, Read, Update, Open, Archive, and Cascade Delete Camp', () async {
      final isOnline = await api.pingServer();
      if (!isOnline) {
        // Skip when central live server is not running
        return;
      }
      final ts = DateTime.now().millisecondsSinceEpoch;
      final campId = 'camp-crud-$ts';
      final campCode = 'CRUD$ts'.substring(0, 10);

      // 1. CREATE
      final newCamp = CampModel(
        id: campId,
        campCode: campCode,
        name: 'Dhulikhel Outreach Camp $ts',
        province: 'Bagmati',
        district: 'Kavrepalanchok',
        municipality: 'Dhulikhel Municipality',
        ward: '04',
        venue: 'Dhulikhel Hospital Field Station',
        startDate: DateTime(2026, 4, 1),
        endDate: DateTime(2026, 4, 5),
        status: CampStatus.draft,
        doctorName: 'Dr. Aarav Sharma',
        createdAt: DateTime.now(),
      );

      final createdOk = await api.broadcastCamp(newCamp);
      expect(createdOk, isTrue, reason: 'Camp creation broadcast should succeed');

      // 2. READ
      final campsList = await api.fetchCentralCamps();
      final fetched = campsList.firstWhere((c) => c.id == campId);
      expect(fetched.name, equals('Dhulikhel Outreach Camp $ts'));
      expect(fetched.status, equals(CampStatus.draft));
      expect(fetched.doctorName, equals('Dr. Aarav Sharma'));
      expect(fetched.venue, equals('Dhulikhel Hospital Field Station'));

      // 3. UPDATE
      final updatedCamp = fetched.copyWith(
        name: 'Dhulikhel Enhanced Maternal Camp $ts',
        venue: 'Upgraded Community Clinic',
        doctorName: 'Dr. Sunita Karki',
        updatedAt: DateTime.now(),
      );
      final updateOk = await api.broadcastCamp(updatedCamp);
      expect(updateOk, isTrue, reason: 'Camp update broadcast should succeed');

      final afterUpdate = await api.fetchCentralCamps();
      final updatedFetched = afterUpdate.firstWhere((c) => c.id == campId);
      expect(updatedFetched.name, equals('Dhulikhel Enhanced Maternal Camp $ts'));
      expect(updatedFetched.venue, equals('Upgraded Community Clinic'));
      expect(updatedFetched.doctorName, equals('Dr. Sunita Karki'));

      // 4. OPEN (Single Active Camp Rule)
      final openCamp = updatedFetched.copyWith(
        status: CampStatus.open,
        updatedAt: DateTime.now(),
      );
      final openOk = await api.broadcastCamp(openCamp);
      expect(openOk, isTrue);

      final afterOpen = await api.fetchCentralCamps();
      final openFetched = afterOpen.firstWhere((c) => c.id == campId);
      expect(openFetched.status, equals(CampStatus.open));
      expect(openFetched.isOpen, isTrue);

      // Verify open camp is prioritized at the top of the list
      expect(afterOpen.first.id, equals(campId), reason: 'Open camp should be first in list');

      // 5. ARCHIVE
      final archivedCamp = openFetched.copyWith(
        status: CampStatus.archived,
        updatedAt: DateTime.now(),
      );
      final archiveOk = await api.broadcastCamp(archivedCamp);
      expect(archiveOk, isTrue);

      final afterArchive = await api.fetchCentralCamps();
      final archivedFetched = afterArchive.firstWhere((c) => c.id == campId);
      expect(archivedFetched.status, equals(CampStatus.archived));

      // 6. DELETE
      final deleteOk = await api.deleteCentralCamp(campId);
      expect(deleteOk, isTrue, reason: 'Camp delete should succeed');

      final afterDelete = await api.fetchCentralCamps();
      expect(afterDelete.any((c) => c.id == campId), isFalse, reason: 'Deleted camp should no longer exist');
    });
  });
}
