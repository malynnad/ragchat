// 云端对话网关：DeepSeek（或任何 OpenAI 兼容 /chat/completions）走 SSE 流式。
//
// 与本地 nobodywho 网关实现同一个 ChatGateway 接缝，ChatService 不需要知道
// 对面是 CPU 上的 GGUF 还是云上的模型。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'model_gateway.dart';
import 'models.dart';

/// 云端调用失败：message 直接给用户看，别丢原始 JSON。
class CloudApiException implements Exception {
  CloudApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 消息表 → OpenAI 兼容格式（纯函数，方便单测）。
List<Map<String, String>> toApiMessages(List<ChatMessage> messages) => [
  for (final m in messages)
    {
      'role': switch (m.role) {
        ChatRole.system => 'system',
        ChatRole.user => 'user',
        ChatRole.assistant => 'assistant',
      },
      'content': m.content,
    },
];

/// 解析一行 SSE：`data: {"choices":[{"delta":{"content":"..."}}]}`。
/// 不是数据行、空增量、`[DONE]` 都返回 null。
String? parseSseLine(String line) {
  if (!line.startsWith('data:')) return null;
  final payload = line.substring(5).trim();
  if (payload.isEmpty || payload == '[DONE]') return null;
  try {
    final json = jsonDecode(payload) as Map<String, dynamic>;
    final choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return null;
    final delta = (choices.first as Map<String, dynamic>)['delta'];
    if (delta is! Map<String, dynamic>) return null;
    final content = delta['content'];
    return content is String && content.isNotEmpty ? content : null;
  } catch (_) {
    return null;
  }
}

class CloudGateway implements ChatGateway {
  CloudGateway({
    required this.baseUrl,
    required this.apiKey,
    this.model = 'deepseek-chat',
    this.temperature = 0.6,
    this.timeout = const Duration(seconds: 60),
    HttpClient Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  final String baseUrl;
  final String apiKey;
  final String model;
  final double temperature;
  final Duration timeout;
  final HttpClient Function() _clientFactory;

  HttpClient? _client;
  bool _stopped = false;

  Uri get _endpoint {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$base/chat/completions');
  }

  @override
  Stream<String> generate(List<ChatMessage> messages) async* {
    _stopped = false;
    final client = _client ??= (_clientFactory()
      ..connectionTimeout = const Duration(seconds: 20));
    try {
      final req = await client.postUrl(_endpoint);
      req.headers.contentType = ContentType.json;
      req.headers.set('Authorization', 'Bearer $apiKey');
      req.headers.set('Accept', 'text/event-stream');
      req.write(
        jsonEncode({
          'model': model,
          'messages': toApiMessages(messages),
          'stream': true,
          'temperature': temperature,
        }),
      );
      final resp = await req.close().timeout(timeout);
      if (resp.statusCode != 200) {
        final body = await resp
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 10));
        throw CloudApiException(_friendlyError(resp.statusCode, body));
      }

      final lines = resp
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (_stopped) return;
        final text = parseSseLine(line);
        if (text != null) yield text;
      }
    } on CloudApiException {
      rethrow;
    } on TimeoutException {
      if (!_stopped) {
        throw CloudApiException('连接超时：检查网络，或把 baseURL 换成可用的中转');
      }
    } on SocketException {
      if (!_stopped) {
        throw CloudApiException('连不上服务器：检查网络与 baseURL');
      }
    } on HttpException {
      if (!_stopped) throw CloudApiException('请求中断：换一个 baseURL 再试');
    } finally {
      client.close(force: true);
      _client = null;
    }
  }

  String _friendlyError(int status, String body) {
    if (status == 401 || status == 403) {
      return 'API key 无效或没有权限（HTTP $status）';
    }
    if (status == 402) return '账户余额不足（HTTP 402）';
    if (status == 429) return '请求太频繁，被限流了（HTTP 429）';
    final trimmed = body.length > 200 ? '${body.substring(0, 200)}…' : body;
    return '请求失败（HTTP $status）：$trimmed';
  }

  /// 连通性自检：GET /models，不发对话、不消耗 token。
  Future<List<String>> ping() async {
    final client = _clientFactory()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final base = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final req = await client.getUrl(Uri.parse('$base/models'));
      req.headers.set('Authorization', 'Bearer $apiKey');
      final resp = await req.close().timeout(timeout);
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 200) {
        throw CloudApiException(_friendlyError(resp.statusCode, body));
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      final data = json['data'] as List<dynamic>? ?? const [];
      return [
        for (final m in data)
          if (m is Map<String, dynamic> && m['id'] is String) m['id'] as String,
      ];
    } on CloudApiException {
      rethrow;
    } on TimeoutException {
      throw CloudApiException('连接超时：检查网络或 baseURL');
    } on SocketException {
      throw CloudApiException('连不上服务器：检查网络或 baseURL');
    } catch (e) {
      throw CloudApiException('返回格式不对：$e');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> resetSession() async {
    // 云侧无状态，上下文由客户端消息表决定。
  }

  @override
  void stopGeneration() {
    _stopped = true;
    // 直接掐 socket：读循环会以 SocketException 结束，generate 里已吞掉。
    _client?.close(force: true);
    _client = null;
  }

  @override
  Future<void> dispose() async {
    stopGeneration();
  }
}
