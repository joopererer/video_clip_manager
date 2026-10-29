import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:video_clip_manager/services/vlm_connection_probe.dart';

http.Response _json(Object body, [int code = 200]) => http.Response(
  jsonEncode(body),
  code,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('VlmConnectionProbe against a real closed port', () {
    test('refused connection is classified, with LM Studio guidance', () async {
      // Bind to get a free port, then close it so nothing listens there.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();

      final result = await VlmConnectionProbe().probe(
        baseUrl: 'http://127.0.0.1:$port/v1',
        model: 'any',
        isLmStudio: true,
      );

      expect(result.kind, VlmProbeKind.connectionRefused);
      expect(result.message, contains('Developer'));
      expect(result.message, contains('$port'));
      expect(result.message, contains('不会自动启动'));
      expect(result.isOk, isFalse);
    });

    test(
      'refused connection for a non-LM-Studio service has no LM text',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final port = server.port;
        await server.close();

        final result = await VlmConnectionProbe().probe(
          baseUrl: 'http://127.0.0.1:$port/v1',
          model: 'any',
        );

        expect(result.kind, VlmProbeKind.connectionRefused);
        expect(result.message, isNot(contains('LM Studio')));
      },
    );
  });

  group('VlmConnectionProbe with a fake server', () {
    test('lists models and succeeds when the model is present', () async {
      final requests = <String>[];
      final client = MockClient((req) async {
        requests.add('${req.method} ${req.url.path}');
        if (req.url.path == '/v1/models') {
          return _json({
            'data': [
              {'id': 'qwen2-vl-2b'},
              {'id': 'other'},
            ],
          });
        }
        return _json({
          'choices': [
            {
              'message': {'content': 'pong'},
            },
          ],
        });
      });

      final r = await VlmConnectionProbe(client: client).probe(
        baseUrl: 'http://localhost:1234/v1',
        model: 'qwen2-vl-2b',
        isLmStudio: true,
      );

      expect(r.kind, VlmProbeKind.ok);
      expect(r.models, ['qwen2-vl-2b', 'other']);
      expect(requests, ['GET /v1/models', 'POST /v1/chat/completions']);
    });

    test('trailing slash in the base URL does not double the slash', () async {
      final paths = <String>[];
      final client = MockClient((req) async {
        paths.add(req.url.path);
        return req.url.path.endsWith('models')
            ? _json({'data': []})
            : _json({'choices': []});
      });
      await VlmConnectionProbe(
        client: client,
      ).probe(baseUrl: 'http://localhost:11434/v1/', model: 'm');
      expect(paths, ['/v1/models', '/v1/chat/completions']);
    });

    test('LM Studio: unlisted model id is reported before chat', () async {
      var chatCalled = false;
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/models')) {
          return _json({
            'data': [
              {'id': 'real-model'},
            ],
          });
        }
        chatCalled = true;
        return _json({});
      });

      final r = await VlmConnectionProbe(client: client).probe(
        baseUrl: 'http://localhost:1234/v1',
        model: 'qwen2-vl',
        isLmStudio: true,
      );

      expect(r.kind, VlmProbeKind.modelNotListed);
      expect(r.models, ['real-model']);
      expect(chatCalled, isFalse);
    });

    test('LM Studio: empty model list means no model is available', () async {
      final client = MockClient((req) async => _json({'data': []}));
      final r = await VlmConnectionProbe(client: client).probe(
        baseUrl: 'http://localhost:1234/v1',
        model: 'x',
        isLmStudio: true,
      );
      expect(r.kind, VlmProbeKind.modelNotListed);
      expect(r.models, isEmpty);
    });

    test('Ollama: a name missing from /models still goes to chat', () async {
      // Ollama accepts names such as "qwen2-vl:2b" that /models may not echo.
      var chatCalled = false;
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/models')) {
          return _json({
            'data': [
              {'id': 'something-else'},
            ],
          });
        }
        chatCalled = true;
        return _json({'choices': []});
      });

      final r = await VlmConnectionProbe(
        client: client,
      ).probe(baseUrl: 'http://localhost:11434/v1', model: 'qwen2-vl:2b');

      expect(chatCalled, isTrue);
      expect(r.kind, VlmProbeKind.ok);
    });

    test('Ollama chat request body keeps its original shape', () async {
      Map<String, dynamic>? body;
      Map<String, String>? headers;
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/models')) return _json({'data': []});
        body = jsonDecode(req.body) as Map<String, dynamic>;
        headers = req.headers;
        return _json({'choices': []});
      });

      await VlmConnectionProbe(client: client).probe(
        baseUrl: 'http://localhost:11434/v1',
        model: 'qwen2-vl:2b',
        apiKey: 'k',
      );

      expect(body, {
        'model': 'qwen2-vl:2b',
        'messages': [
          {'role': 'user', 'content': 'ping'},
        ],
        'max_tokens': 5,
      });
      expect(headers!['Authorization'], 'Bearer k');
      expect(headers!['Content-Type'], contains('application/json'));
    });

    test('401 on /models is an auth problem and stops the probe', () async {
      var chatCalled = false;
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/chat/completions')) chatCalled = true;
        return http.Response('unauthorized', 401);
      });
      final r = await VlmConnectionProbe(client: client).probe(
        baseUrl: 'http://localhost:1234/v1',
        model: 'm',
        isLmStudio: true,
      );
      expect(r.kind, VlmProbeKind.unauthorized);
      expect(r.message, contains('Token'));
      expect(chatCalled, isFalse);
    });

    test('404 on /models points at the /v1 base path', () async {
      final client = MockClient((req) async => http.Response('nope', 404));
      final r = await VlmConnectionProbe(
        client: client,
      ).listModels(baseUrl: 'http://localhost:1234');
      expect(r.kind, VlmProbeKind.endpointNotFound);
      expect(r.message, contains('/v1'));
    });

    test(
      'model rejected by chat endpoint is separated from bad request',
      () async {
        final client = MockClient((req) async {
          if (req.url.path.endsWith('/models')) {
            return _json({
              'data': [
                {'id': 'm'},
              ],
            });
          }
          return _json({
            'error': {'message': 'Failed to load model "m"'},
          }, 400);
        });
        final r = await VlmConnectionProbe(client: client).probe(
          baseUrl: 'http://localhost:1234/v1',
          model: 'm',
          isLmStudio: true,
        );
        expect(r.kind, VlmProbeKind.modelRejected);
        expect(r.message, contains('Developer'));
      },
    );

    test('400 unrelated to the model is a request-format problem', () async {
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/models')) return _json({'data': []});
        return http.Response('{"error":"messages is required"}', 400);
      });
      final r = await VlmConnectionProbe(
        client: client,
      ).probe(baseUrl: 'http://localhost:11434/v1', model: 'm');
      expect(r.kind, VlmProbeKind.badRequest);
    });

    test('5xx is reported as a server error', () async {
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/models')) return _json({'data': []});
        return http.Response('boom', 503);
      });
      final r = await VlmConnectionProbe(
        client: client,
      ).probe(baseUrl: 'http://localhost:11434/v1', model: 'm');
      expect(r.kind, VlmProbeKind.serverError);
    });

    test('non-OpenAI body on /models is an invalid response', () async {
      final client = MockClient((req) async => http.Response('<html>', 200));
      final r = await VlmConnectionProbe(
        client: client,
      ).listModels(baseUrl: 'http://localhost:1234/v1');
      expect(r.kind, VlmProbeKind.invalidResponse);
    });

    test('timeout is separated from refusal', () async {
      final client = MockClient((req) async {
        throw TimeoutException('slow');
      });
      final r = await VlmConnectionProbe(
        client: client,
      ).listModels(baseUrl: 'http://localhost:1234/v1');
      expect(r.kind, VlmProbeKind.timeout);
    });

    test('DNS failure is separated from refusal', () async {
      final client = MockClient((req) async {
        throw const SocketException(
          'Failed host lookup: no-such-host.invalid',
          osError: OSError('No such host is known', 11001),
        );
      });
      final r = await VlmConnectionProbe(
        client: client,
      ).listModels(baseUrl: 'http://no-such-host.invalid/v1');
      expect(r.kind, VlmProbeKind.dnsFailure);
    });

    test('Windows errno 1225 and 10061 both mean refused', () async {
      for (final code in [1225, 10061]) {
        final client = MockClient((req) async {
          throw SocketException(
            'Connection refused',
            osError: OSError('refused', code),
          );
        });
        final r = await VlmConnectionProbe(
          client: client,
        ).listModels(baseUrl: 'http://localhost:1234/v1', isLmStudio: true);
        expect(r.kind, VlmProbeKind.connectionRefused, reason: 'errno $code');
      }
    });

    test('invalid URL is rejected without a request', () async {
      var called = false;
      final client = MockClient((req) async {
        called = true;
        return http.Response('', 200);
      });
      for (final bad in ['', 'localhost:1234/v1', 'ftp://x/v1', 'http://']) {
        final r = await VlmConnectionProbe(
          client: client,
        ).listModels(baseUrl: bad);
        expect(r.kind, VlmProbeKind.invalidUrl, reason: bad);
      }
      expect(called, isFalse);
    });
  });
}
