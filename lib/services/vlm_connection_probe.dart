import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// What went wrong (or right) when probing an OpenAI-compatible VLM service.
///
/// Each value maps to a different user action, so they must not be merged
/// into one generic "connection error".
enum VlmProbeKind {
  ok,

  /// Nothing listens on host:port (Windows errno 1225 / 10061, Linux 111).
  connectionRefused,

  /// Host name could not be resolved.
  dnsFailure,

  /// Connected, but no answer in time.
  timeout,

  /// HTTP 401 / 403.
  unauthorized,

  /// `/models` or `/chat/completions` returned 404: wrong base URL / path.
  endpointNotFound,

  /// The server lists models and the configured id is not among them.
  modelNotListed,

  /// The server answered the chat request with 4xx about the model
  /// (not loaded, wrong id, unsupported input).
  modelRejected,

  /// HTTP 400 / 422 not obviously about the model: request format problem.
  badRequest,

  /// HTTP 5xx.
  serverError,

  /// The URL is not a valid http(s) URL.
  invalidUrl,

  /// The body was not the expected JSON.
  invalidResponse,

  /// Any other transport failure.
  networkError,
}

class VlmProbeResult {
  const VlmProbeResult({
    required this.kind,
    required this.message,
    this.models = const [],
    this.statusCode,
    this.latency,
  });

  final VlmProbeKind kind;
  final String message;

  /// Model ids reported by `GET <base>/models`. Empty when unknown.
  final List<String> models;
  final int? statusCode;
  final Duration? latency;

  bool get isOk => kind == VlmProbeKind.ok;

  @override
  String toString() => 'VlmProbeResult($kind, $message, models=$models)';
}

/// Probes an OpenAI-compatible service (LM Studio, Ollama, DashScope, ...).
///
/// Flow: `GET <base>/models` (reachability, auth, model list), then
/// `POST <base>/chat/completions` with the same tiny "ping" body the app
/// always used. The chat request format is intentionally unchanged so Ollama
/// keeps working.
class VlmConnectionProbe {
  VlmConnectionProbe({http.Client? client}) : _client = client;

  final http.Client? _client;

  static const Duration modelsTimeout = Duration(seconds: 5);
  static const Duration chatTimeout = Duration(seconds: 20);

  /// Windows: WSAECONNREFUSED 10061, ERROR_CONNECTION_REFUSED 1225.
  /// Linux/macOS: ECONNREFUSED 111 / 61.
  static const Set<int> _refusedErrnos = {1225, 10061, 111, 61};

  /// Windows: WSAHOST_NOT_FOUND 11001, WSATRY_AGAIN 11002; getaddrinfo -2/-3.
  static const Set<int> _dnsErrnos = {11001, 11002, -2, -3, -5};

  static Uri? _endpoint(String baseUrl, String tail) {
    final trimmed = baseUrl.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    final base = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    return Uri.parse('$base/$tail');
  }

  /// Fetches the model ids only.
  Future<VlmProbeResult> listModels({
    required String baseUrl,
    String apiKey = '',
    bool isLmStudio = false,
  }) async {
    final uri = _endpoint(baseUrl, 'models');
    if (uri == null) {
      return const VlmProbeResult(
        kind: VlmProbeKind.invalidUrl,
        message: 'API 地址无效，应为 http://host:port/v1 的形式。',
      );
    }
    final client = _client ?? http.Client();
    final stopwatch = Stopwatch()..start();
    try {
      final res = await client
          .get(uri, headers: _headers(apiKey))
          .timeout(modelsTimeout);
      stopwatch.stop();
      return _interpretModels(
        res,
        latency: stopwatch.elapsed,
        isLmStudio: isLmStudio,
      );
    } catch (e) {
      return _classifyTransportError(e, uri, isLmStudio: isLmStudio);
    } finally {
      if (_client == null) client.close();
    }
  }

  /// Full probe: model list, then a minimal chat request.
  Future<VlmProbeResult> probe({
    required String baseUrl,
    required String model,
    String apiKey = '',
    bool isLmStudio = false,
  }) async {
    final listed = await listModels(
      baseUrl: baseUrl,
      apiKey: apiKey,
      isLmStudio: isLmStudio,
    );

    // Hard failures that make a chat request pointless.
    switch (listed.kind) {
      case VlmProbeKind.connectionRefused:
      case VlmProbeKind.dnsFailure:
      case VlmProbeKind.timeout:
      case VlmProbeKind.invalidUrl:
      case VlmProbeKind.unauthorized:
      case VlmProbeKind.networkError:
        return listed;
      case VlmProbeKind.ok:
      case VlmProbeKind.endpointNotFound:
      case VlmProbeKind.badRequest:
      case VlmProbeKind.serverError:
      case VlmProbeKind.invalidResponse:
      case VlmProbeKind.modelNotListed:
      case VlmProbeKind.modelRejected:
        break;
    }

    final models = listed.models;
    // Only LM Studio enforces the listed ids. Ollama and the built-in
    // llama-server accept names that /models does not echo back, so for them
    // the list is informational and the chat request decides.
    if (isLmStudio &&
        listed.isOk &&
        models.isNotEmpty &&
        !models.contains(model)) {
      return VlmProbeResult(
        kind: VlmProbeKind.modelNotListed,
        message:
            '服务可达，但模型 "$model" 不在服务返回的模型列表中。\n'
            '请从下方列表选择实际可用的模型 ID。\n'
            '(LM Studio 需在 Developer 页加载该模型，或开启 JIT 自动加载。)',
        models: models,
        latency: listed.latency,
      );
    }
    if (listed.isOk && models.isEmpty && isLmStudio) {
      return const VlmProbeResult(
        kind: VlmProbeKind.modelNotListed,
        message: '服务可达，但没有返回任何模型。请在 LM Studio 中下载并加载一个支持图像输入的模型 (VLM)。',
      );
    }

    final chatUri = _endpoint(baseUrl, 'chat/completions')!;
    final client = _client ?? http.Client();
    final stopwatch = Stopwatch()..start();
    try {
      final res = await client
          .post(
            chatUri,
            headers: _headers(apiKey, json: true),
            body: jsonEncode({
              'model': model,
              'messages': [
                {'role': 'user', 'content': 'ping'},
              ],
              'max_tokens': 5,
            }),
          )
          .timeout(chatTimeout);
      stopwatch.stop();
      final result = _interpretChat(
        res,
        model: model,
        latency: stopwatch.elapsed,
        isLmStudio: isLmStudio,
      );
      return VlmProbeResult(
        kind: result.kind,
        message: result.message,
        models: models,
        statusCode: result.statusCode,
        latency: result.latency,
      );
    } catch (e) {
      final r = _classifyTransportError(e, chatUri, isLmStudio: isLmStudio);
      return VlmProbeResult(kind: r.kind, message: r.message, models: models);
    } finally {
      if (_client == null) client.close();
    }
  }

  Map<String, String> _headers(String apiKey, {bool json = false}) {
    final h = <String, String>{};
    if (json) h['Content-Type'] = 'application/json';
    if (apiKey.trim().isNotEmpty)
      h['Authorization'] = 'Bearer ${apiKey.trim()}';
    return h;
  }

  VlmProbeResult _interpretModels(
    http.Response res, {
    required Duration latency,
    required bool isLmStudio,
  }) {
    final code = res.statusCode;
    if (code == 401 || code == 403) {
      return VlmProbeResult(
        kind: VlmProbeKind.unauthorized,
        message:
            '服务拒绝了认证 (HTTP $code)。请检查 API Key；'
            '${isLmStudio ? 'LM Studio 若在服务设置中启用了 Token 认证，需要在这里填入对应 Token。' : ''}',
        statusCode: code,
      );
    }
    if (code == 404) {
      return VlmProbeResult(
        kind: VlmProbeKind.endpointNotFound,
        message:
            '服务可达，但 /models 返回 404。请确认 API 地址以 /v1 结尾，例如 http://localhost:1234/v1。',
        statusCode: code,
      );
    }
    if (code >= 500) {
      return VlmProbeResult(
        kind: VlmProbeKind.serverError,
        message: '服务内部错误 (HTTP $code)：${_snippet(res)}',
        statusCode: code,
      );
    }
    if (code < 200 || code >= 300) {
      return VlmProbeResult(
        kind: VlmProbeKind.badRequest,
        message: '获取模型列表失败 (HTTP $code)：${_snippet(res)}',
        statusCode: code,
      );
    }
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      final data = decoded is Map ? decoded['data'] : null;
      if (data is! List) {
        return VlmProbeResult(
          kind: VlmProbeKind.invalidResponse,
          message: '/models 返回的不是 OpenAI 兼容格式 (缺少 data 数组)。',
          statusCode: code,
        );
      }
      final ids = <String>[
        for (final m in data)
          if (m is Map && m['id'] is String) m['id'] as String,
      ];
      return VlmProbeResult(
        kind: VlmProbeKind.ok,
        message: '服务可达，共 ${ids.length} 个模型。',
        models: ids,
        statusCode: code,
        latency: latency,
      );
    } catch (_) {
      return VlmProbeResult(
        kind: VlmProbeKind.invalidResponse,
        message: '/models 返回内容无法解析为 JSON。该地址可能不是 OpenAI 兼容服务。',
        statusCode: code,
      );
    }
  }

  VlmProbeResult _interpretChat(
    http.Response res, {
    required String model,
    required Duration latency,
    required bool isLmStudio,
  }) {
    final code = res.statusCode;
    if (code >= 200 && code < 300) {
      return VlmProbeResult(
        kind: VlmProbeKind.ok,
        message: '连接成功，模型 "$model" 可用，耗时 ${latency.inMilliseconds}ms',
        statusCode: code,
        latency: latency,
      );
    }
    final snippet = _snippet(res);
    final lower = snippet.toLowerCase();
    final aboutModel =
        lower.contains('model') &&
        (lower.contains('not found') ||
            lower.contains('not loaded') ||
            lower.contains('failed to load') ||
            lower.contains('no model') ||
            lower.contains('does not exist') ||
            lower.contains('unknown') ||
            lower.contains('not support'));
    if (code == 401 || code == 403) {
      return VlmProbeResult(
        kind: VlmProbeKind.unauthorized,
        message: '服务拒绝了认证 (HTTP $code)：$snippet',
        statusCode: code,
      );
    }
    if (code == 404 && !aboutModel) {
      return VlmProbeResult(
        kind: VlmProbeKind.endpointNotFound,
        message: '/chat/completions 返回 404。请确认 API 地址以 /v1 结尾。服务回复：$snippet',
        statusCode: code,
      );
    }
    if (aboutModel) {
      return VlmProbeResult(
        kind: VlmProbeKind.modelRejected,
        message:
            '服务拒绝了模型 "$model" (HTTP $code)：$snippet\n'
            '${isLmStudio ? '请在 LM Studio 的 Developer 页确认该模型已加载，且为支持图像输入的 VLM。' : '请确认模型名称与服务端一致。'}',
        statusCode: code,
      );
    }
    if (code >= 500) {
      return VlmProbeResult(
        kind: VlmProbeKind.serverError,
        message: '服务内部错误 (HTTP $code)：$snippet',
        statusCode: code,
      );
    }
    return VlmProbeResult(
      kind: VlmProbeKind.badRequest,
      message: '请求被服务拒绝 (HTTP $code)：$snippet',
      statusCode: code,
    );
  }

  VlmProbeResult _classifyTransportError(
    Object e,
    Uri uri, {
    required bool isLmStudio,
  }) {
    final hostPort =
        '${uri.host}:${uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80)}';
    if (e is TimeoutException) {
      return VlmProbeResult(
        kind: VlmProbeKind.timeout,
        message: '连接 $hostPort 超时。服务可能正在加载模型或被防火墙/代理拦截。',
      );
    }
    SocketException? sock;
    if (e is SocketException) {
      sock = e;
    } else if (e is http.ClientException) {
      final m = e.message;
      final match = RegExp(r'errno\s*=\s*(\d+)').firstMatch(m);
      if (match != null) {
        sock = SocketException(
          m,
          osError: OSError(m, int.tryParse(match.group(1)!) ?? 0),
        );
      }
    }
    if (sock != null) {
      final errno = sock.osError?.errorCode;
      if (errno != null && _refusedErrnos.contains(errno)) {
        return VlmProbeResult(
          kind: VlmProbeKind.connectionRefused,
          message: isLmStudio
              ? '无法连接 $hostPort：连接被拒绝 (errno $errno)，说明该端口没有程序在监听。\n'
                    '请打开 LM Studio → Developer 页：\n'
                    '1. 确认 "Start server" 开关已打开 (Status: Running)；\n'
                    '2. 确认页面显示的端口与此处一致 (默认 1234)；\n'
                    '3. 若在 LM Studio 中改过端口，请同步修改上方 API 地址。\n'
                    '本程序不会自动启动 LM Studio，也不会修改代理或防火墙。'
              : '无法连接 $hostPort：连接被拒绝 (errno $errno)，该端口没有服务在监听。'
                    '请确认服务已启动且端口正确。',
        );
      }
      final msg = sock.message.toLowerCase();
      if ((errno != null && _dnsErrnos.contains(errno)) ||
          msg.contains('failed host lookup') ||
          msg.contains('no address associated')) {
        return VlmProbeResult(
          kind: VlmProbeKind.dnsFailure,
          message: '无法解析主机名 "${uri.host}"。请检查地址拼写与网络/DNS。',
        );
      }
      return VlmProbeResult(
        kind: VlmProbeKind.networkError,
        message:
            '网络错误 ($hostPort)：${sock.message}${errno != null ? ' (errno $errno)' : ''}',
      );
    }
    return VlmProbeResult(
      kind: VlmProbeKind.networkError,
      message: '请求失败 ($hostPort)：$e',
    );
  }

  static String _snippet(http.Response res) {
    final text = utf8.decode(res.bodyBytes, allowMalformed: true).trim();
    if (text.length <= 200) return text;
    return '${text.substring(0, 200)}...';
  }
}
