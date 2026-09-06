import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/network_connectivity_service.dart';

void main() {
  group('NetworkConnectivityService Tests', () {
    late NetworkConnectivityService connectivityService;

    setUp(() {
      connectivityService = NetworkConnectivityService(initialOnline: true);
    });

    tearDown(() {
      connectivityService.dispose();
    });

    test('initial state defaults to specified value', () async {
      expect(connectivityService.isOnline, isTrue);
      expect(await connectivityService.checkConnection(), isTrue);

      final offlineService = NetworkConnectivityService(initialOnline: false);
      expect(offlineService.isOnline, isFalse);
      expect(await offlineService.checkConnection(), isFalse);
      offlineService.dispose();
    });

    test('setOnline toggles online/offline state and emits on stream', () async {
      final emittedValues = <bool>[];
      final subscription = connectivityService.onConnectivityChanged.listen((status) {
        emittedValues.add(status);
      });

      // Switch to offline
      connectivityService.setOnline(false);
      expect(connectivityService.isOnline, isFalse);

      // Idempotent call should not re-emit
      connectivityService.setOnline(false);

      // Switch back to online
      connectivityService.setOnline(true);
      expect(connectivityService.isOnline, isTrue);

      await Future.delayed(const Duration(milliseconds: 20));
      expect(emittedValues, equals([false, true]));

      await subscription.cancel();
    });
  });
}
