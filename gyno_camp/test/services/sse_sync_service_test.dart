import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gyno_camp/core/services/http_central_api_service.dart';
import 'package:gyno_camp/core/services/sse_sync_service.dart';

void main() {
  group('SseSyncService Tests', () {
    test('connect establishes connection and triggers callback on sync_update', () async {
      final streamController = StreamController<List<int>>();
      final completer = Completer<Map<String, dynamic>>();

      final mockClient = MockClient.streaming((request, bodyStream) async {
        expect(request.url.path, '/api/events');
        expect(request.url.queryParameters['deviceId'], 'dev-test-1');
        expect(request.headers['Accept'], 'text/event-stream');

        return http.StreamedResponse(
          streamController.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final apiService = HttpCentralApiService(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );

      final sseService = SseSyncService(
        apiService: apiService,
        deviceId: 'dev-test-1',
        clientFactory: () => mockClient,
        onSyncEvent: (eventData) {
          if (!completer.isCompleted) {
            completer.complete(eventData);
          }
        },
      );

      await sseService.connect();
      expect(sseService.isConnected, isTrue);

      // Send a connected event
      streamController.add(utf8.encode('event: connected\ndata: {"status":"connected"}\n\n'));

      // Send a heartbeat event
      streamController.add(utf8.encode('event: heartbeat\ndata: {"time":"2026-09-23T00:00:00Z"}\n\n'));

      // Send a sync_update event
      streamController.add(utf8.encode('event: sync_update\ndata: {"action":"push","patients":1}\n\n'));

      final receivedData = await completer.future.timeout(const Duration(seconds: 3));
      expect(receivedData['action'], 'push');
      expect(receivedData['patients'], 1);

      sseService.dispose();
      await streamController.close();
      expect(sseService.isConnected, isFalse);
    });

    test('reconnect cleanly re-establishes stream without marking service disposed', () async {
      var connectionCount = 0;
      final controllers = <StreamController<List<int>>>[];

      http.Client buildClient() {
        return MockClient.streaming((request, bodyStream) async {
          connectionCount++;
          final sc = StreamController<List<int>>();
          controllers.add(sc);
          return http.StreamedResponse(sc.stream, 200);
        });
      }

      final apiService = HttpCentralApiService(baseUrl: 'http://localhost:8080');
      final sseService = SseSyncService(
        apiService: apiService,
        deviceId: 'dev-test-reconnect',
        clientFactory: buildClient,
      );

      await sseService.connect();
      expect(sseService.isConnected, isTrue);
      expect(connectionCount, 1);

      await sseService.reconnect();
      expect(sseService.isConnected, isTrue);
      expect(connectionCount, 2);

      sseService.dispose();
      for (final sc in controllers) {
        await sc.close();
      }
    });

    test('reconnect scheduled on non-200 server response', () async {
      final mockClient = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.value(utf8.encode('Internal Server Error')),
          500,
        );
      });

      final apiService = HttpCentralApiService(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );

      final sseService = SseSyncService(
        apiService: apiService,
        deviceId: 'dev-test-2',
        clientFactory: () => mockClient,
      );

      await sseService.connect();
      expect(sseService.isConnected, isFalse);

      sseService.dispose();
    });

    test('dispose cleans up timers and stream subscription', () async {
      final streamController = StreamController<List<int>>();

      final mockClient = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          streamController.stream,
          200,
        );
      });

      final apiService = HttpCentralApiService(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );

      final sseService = SseSyncService(
        apiService: apiService,
        deviceId: 'dev-test-3',
        clientFactory: () => mockClient,
      );

      await sseService.connect();
      expect(sseService.isConnected, isTrue);

      sseService.dispose();
      expect(sseService.isConnected, isFalse);
      await streamController.close();
    });
  });
}
