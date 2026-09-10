import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gyno_camp/core/services/session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SessionService Tests', () {
    test('User session lifecycle: save, read, clear', () async {
      final session = await SessionService.getInstance();
      expect(session.hasActiveSession(), isFalse);
      expect(session.getSavedUserId(), isNull);

      await session.saveUserSession(
        userId: 'usr-nurse-01',
        email: 'nurse@gynocamp.org',
        role: 'DATA_TAKER',
      );

      expect(session.hasActiveSession(), isTrue);
      expect(session.getSavedUserId(), 'usr-nurse-01');
      expect(session.getSavedUserEmail(), 'nurse@gynocamp.org');
      expect(session.getSavedUserRole(), 'DATA_TAKER');

      await session.clearSession();
      expect(session.hasActiveSession(), isFalse);
      expect(session.getSavedUserId(), isNull);
    });

    test('Active Camp ID lifecycle: save, read, clear', () async {
      final session = await SessionService.getInstance();
      expect(session.getSavedActiveCampId(), isNull);

      await session.saveActiveCampId('camp-ktm-01');
      expect(session.getSavedActiveCampId(), 'camp-ktm-01');

      await session.clearActiveCampId();
      expect(session.getSavedActiveCampId(), isNull);
    });

    test('PostgreSQL config default and update persistence', () async {
      final session = await SessionService.getInstance();
      final defaultConfig = session.getPostgresConfig();

      expect(defaultConfig.host, 'localhost');
      expect(defaultConfig.port, 5432);
      expect(defaultConfig.database, 'gynocamp_db');
      expect(defaultConfig.username, 'postgres');
      expect(defaultConfig.useSsl, isFalse);
      expect(defaultConfig.isDirectModeEnabled, isFalse);

      const customConfig = PostgresConfig(
        host: '192.168.1.150',
        port: 5433,
        database: 'camp_production_db',
        username: 'gyno_admin',
        password: 'securePassword456',
        useSsl: true,
        isDirectModeEnabled: true,
      );

      await session.savePostgresConfig(customConfig);
      final retrieved = session.getPostgresConfig();

      expect(retrieved.host, '192.168.1.150');
      expect(retrieved.port, 5433);
      expect(retrieved.database, 'camp_production_db');
      expect(retrieved.username, 'gyno_admin');
      expect(retrieved.password, 'securePassword456');
      expect(retrieved.useSsl, isTrue);
      expect(retrieved.isDirectModeEnabled, isTrue);
    });
  });
}
