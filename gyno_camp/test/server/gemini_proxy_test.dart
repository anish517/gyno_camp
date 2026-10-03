import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../bin/gemini_proxy.dart';

http.Response _geminiOk(String text) => http.Response(
      jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': text},
              ],
            },
          },
        ],
      }),
      200,
    );

GeminiProxy _proxy(
  http.Client client, {
  String? key = 'SERVER_SIDE_KEY',
  List<String>? models,
}) =>
    GeminiProxy(
      client: client,
      apiKeyProvider: () => key,
      models: models ?? const ['model-a', 'model-b'],
      retryDelay: (_) => Duration.zero,
    );

void main() {
  group('OcrRateLimiter', () {
    test('blocks after the per-window limit and reports Retry-After', () {
      final limiter = OcrRateLimiter(maxPerWindow: 3, window: const Duration(minutes: 10), maxPerDay: 100);
      final t0 = DateTime(2026, 1, 1, 10);

      expect(limiter.tryAcquire('dev:1', now: t0), isNull);
      expect(limiter.tryAcquire('dev:1', now: t0.add(const Duration(seconds: 1))), isNull);
      expect(limiter.tryAcquire('dev:1', now: t0.add(const Duration(seconds: 2))), isNull);

      final wait = limiter.tryAcquire('dev:1', now: t0.add(const Duration(minutes: 1)));
      expect(wait, isNotNull);
      expect(wait!.inMinutes, inInclusiveRange(8, 9));

      // A different device is unaffected.
      expect(limiter.tryAcquire('dev:2', now: t0), isNull);
      // Once the window passes the device may proceed again.
      expect(limiter.tryAcquire('dev:1', now: t0.add(const Duration(minutes: 11))), isNull);
    });

    test('enforces the daily cap', () {
      final limiter = OcrRateLimiter(maxPerWindow: 1000, window: const Duration(minutes: 10), maxPerDay: 5);
      final t0 = DateTime(2026, 1, 1, 0);
      for (var i = 0; i < 5; i++) {
        expect(limiter.tryAcquire('dev:1', now: t0.add(Duration(hours: i))), isNull);
      }
      final wait = limiter.tryAcquire('dev:1', now: t0.add(const Duration(hours: 6)));
      expect(wait, isNotNull);
      expect(limiter.tryAcquire('dev:1', now: t0.add(const Duration(hours: 25))), isNull);
    });

    test('check does not record, record does', () {
      final limiter = OcrRateLimiter(maxPerWindow: 1, window: const Duration(minutes: 10), maxPerDay: 10);
      final t0 = DateTime(2026, 1, 1);
      expect(limiter.check('ip:1', now: t0), isNull);
      expect(limiter.check('ip:1', now: t0), isNull);
      limiter.record('ip:1', now: t0);
      expect(limiter.check('ip:1', now: t0.add(const Duration(seconds: 1))), isNotNull);
    });
  });

  group('GeminiProxy', () {
    test('reports not configured and refuses to call upstream without a key', () async {
      var called = false;
      final proxy = _proxy(MockClient((_) async {
        called = true;
        return _geminiOk('{}');
      }), key: '   ');

      expect(proxy.isConfigured, false);
      await expectLater(
        proxy.extractText(imageBase64: 'AAAA', mimeType: 'image/jpeg', pageNumber: 1),
        throwsA(isA<GeminiProxyException>()
            .having((e) => e.statusCode, 'status', 503)
            .having((e) => e.code, 'code', 'OCR_NOT_CONFIGURED')),
      );
      expect(called, false);
    });

    test('sends the server-held key and server-owned prompt upstream, returns model text', () async {
      late http.Request seen;
      final proxy = _proxy(MockClient((request) async {
        seen = request;
        return _geminiOk('{"pageNumber":2}');
      }));

      final text = await proxy.extractText(imageBase64: 'AAAA', mimeType: 'image/png', pageNumber: 2);

      expect(text, '{"pageNumber":2}');
      expect(seen.url.host, 'generativelanguage.googleapis.com');
      expect(seen.url.path, contains('model-a'));
      expect(seen.headers['x-goog-api-key'], 'SERVER_SIDE_KEY');
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      final parts = (body['contents'] as List).first['parts'] as List;
      expect(parts[0]['text'], contains('Target Page: Page 2'));
      expect(parts[1]['inline_data']['mime_type'], 'image/png');
      expect(parts[1]['inline_data']['data'], 'AAAA');
      expect(body['generationConfig']['response_mime_type'], 'application/json');
    });

    test('retries transient 503 then fails over to the next model', () async {
      final urls = <String>[];
      final proxy = _proxy(MockClient((request) async {
        urls.add(request.url.path);
        if (request.url.path.contains('model-a')) {
          return http.Response('overloaded', 503);
        }
        return _geminiOk('{"ok":true}');
      }));

      final text = await proxy.extractText(imageBase64: 'AAAA', mimeType: 'image/jpeg', pageNumber: 1);

      expect(text, '{"ok":true}');
      expect(urls.where((u) => u.contains('model-a')).length, 2); // 2 attempts
      expect(urls.where((u) => u.contains('model-b')).length, 1);
    });

    test('maps persistent 429 to a generic busy error', () async {
      final proxy = _proxy(MockClient((_) async => http.Response('quota exceeded', 429)));
      await expectLater(
        proxy.extractText(imageBase64: 'AAAA', mimeType: 'image/jpeg', pageNumber: 1),
        throwsA(isA<GeminiProxyException>()
            .having((e) => e.statusCode, 'status', 503)
            .having((e) => e.code, 'code', 'OCR_BUSY')),
      );
    });

    test('never leaks upstream error body or the API key to callers', () async {
      final proxy = _proxy(MockClient((_) async => http.Response(
            'SECRET_UPSTREAM_BODY key=SERVER_SIDE_KEY API key not valid',
            400,
          )));

      try {
        await proxy.extractText(imageBase64: 'AAAA', mimeType: 'image/jpeg', pageNumber: 1);
        fail('expected GeminiProxyException');
      } on GeminiProxyException catch (e) {
        expect(e.statusCode, 502);
        expect(e.message, isNot(contains('SECRET_UPSTREAM_BODY')));
        expect(e.message, isNot(contains('SERVER_SIDE_KEY')));
        expect(e.toString(), isNot(contains('SERVER_SIDE_KEY')));
      }
    });

    test('network failure becomes a generic 502', () async {
      final proxy = _proxy(MockClient((_) async => throw http.ClientException('socket down')));
      await expectLater(
        proxy.extractText(imageBase64: 'AAAA', mimeType: 'image/jpeg', pageNumber: 1),
        throwsA(isA<GeminiProxyException>().having((e) => e.code, 'code', 'OCR_NETWORK')),
      );
    });

    test('rejects invalid input before calling upstream', () async {
      var called = false;
      final proxy = _proxy(MockClient((_) async {
        called = true;
        return _geminiOk('{}');
      }));

      Future<void> expectCode(Future<String> f, int status) => expectLater(
            f,
            throwsA(isA<GeminiProxyException>().having((e) => e.statusCode, 'status', status)),
          );

      await expectCode(proxy.extractText(imageBase64: 'AAAA', mimeType: 'text/html', pageNumber: 1), 400);
      await expectCode(proxy.extractText(imageBase64: 'AAAA', mimeType: 'image/jpeg', pageNumber: 9), 400);
      await expectCode(proxy.extractText(imageBase64: 'AAAA', mimeType: 'image/jpeg', pageNumber: -1), 400);
      await expectCode(proxy.extractText(imageBase64: '', mimeType: 'image/jpeg', pageNumber: 1), 413);
      await expectCode(
        proxy.extractText(
          imageBase64: 'A' * (GeminiProxy.maxImageBase64Chars + 1),
          mimeType: 'image/jpeg',
          pageNumber: 1,
        ),
        413,
      );
      expect(called, false);
    });

    test('empty or malformed model output is a generic 502', () async {
      final proxy = _proxy(MockClient((_) async => http.Response(jsonEncode({'candidates': []}), 200)));
      await expectLater(
        proxy.extractText(imageBase64: 'AAAA', mimeType: 'image/jpeg', pageNumber: 1),
        throwsA(isA<GeminiProxyException>().having((e) => e.statusCode, 'status', 502)),
      );
    });

    test('prompt reflects auto-detect vs specific page', () {
      final proxy = _proxy(MockClient((_) async => _geminiOk('{}')));
      expect(proxy.buildPrompt(0), contains('Target Page: Auto-detect'));
      expect(proxy.buildPrompt(0), contains('"pageNumber": 1 or 2'));
      expect(proxy.buildPrompt(1), contains('Target Page: Page 1'));
      expect(proxy.buildPrompt(1), contains('"pageNumber": 1,'));
    });
  });
}
