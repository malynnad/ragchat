import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:ragchat/rag/cloud_gateway.dart';
import 'package:ragchat/rag/models.dart';

/// 用本地假服务器跑一遍真请求/真流式，验证 SSE 解析与请求格式。
void main() {
  late HttpServer server;
  late String? seenAuth;
  late Map<String, dynamic> seenBody;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      seenAuth = req.headers.value('authorization');
      final body = await utf8.decoder.bind(req).join();
      seenBody = jsonDecode(body) as Map<String, dynamic>;
      req.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      for (final chunk in ['你', '好']) {
        req.response.add(
          utf8.encode(
            'data: ${jsonEncode({
              'choices': [
                {
                  'delta': {'content': chunk},
                },
              ],
            })}\n\n',
          ),
        );
        await req.response.flush();
      }
      req.response.add(utf8.encode('data: [DONE]\n\n'));
      await req.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('流式返回按增量吐出，请求带 key 与模型名', () async {
    final gateway = CloudGateway(
      baseUrl: 'http://127.0.0.1:${server.port}',
      apiKey: 'test-key',
      model: 'deepseek-chat',
      temperature: 0.5,
    );
    final tokens = await gateway
        .generate(const [
          ChatMessage(role: ChatRole.system, content: '你是小暖。'),
          ChatMessage(role: ChatRole.user, content: '你好'),
        ])
        .toList();

    expect(tokens, ['你', '好']);
    expect(seenAuth, 'Bearer test-key');
    expect(seenBody['model'], 'deepseek-chat');
    expect(seenBody['stream'], isTrue);
    expect(seenBody['temperature'], 0.5);
    final messages = seenBody['messages'] as List<dynamic>;
    expect((messages.first as Map)['role'], 'system');
    await gateway.dispose();
  });

  test('401 给出可读错误', () async {
    await server.close(force: true);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      req.response.statusCode = 401;
      req.response.write('{"error":"bad key"}');
      await req.response.close();
    });
    final gateway = CloudGateway(
      baseUrl: 'http://127.0.0.1:${server.port}',
      apiKey: 'bad',
    );

    expect(
      () => gateway.generate(const [
        ChatMessage(role: ChatRole.user, content: 'hi'),
      ]).toList(),
      throwsA(
        isA<CloudApiException>().having(
          (e) => e.message,
          'message',
          contains('API key'),
        ),
      ),
    );
  });
}
