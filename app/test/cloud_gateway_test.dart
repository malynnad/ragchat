import 'package:test/test.dart';
import 'package:ragchat/rag/cloud_gateway.dart';
import 'package:ragchat/rag/models.dart';

/// 云端网关的纯函数部分：消息映射与 SSE 解析（不触网）。
void main() {
  test('消息表映射成 OpenAI 兼容格式', () {
    final api = toApiMessages(const [
      ChatMessage(role: ChatRole.system, content: '你是小暖。'),
      ChatMessage(role: ChatRole.user, content: '你好'),
      ChatMessage(role: ChatRole.assistant, content: '嗯，我在'),
      ChatMessage(role: ChatRole.user, content: '在吗'),
    ]);
    expect(api.map((m) => m['role']), ['system', 'user', 'assistant', 'user']);
    expect(api[0]['content'], '你是小暖。');
  });

  test('SSE：正常增量、空增量、[DONE]、坏行', () {
    expect(
      parseSseLine(
        'data: {"choices":[{"delta":{"content":"你"}}]}',
      ),
      '你',
    );
    expect(
      parseSseLine('data: {"choices":[{"delta":{"role":"assistant"}}]}'),
      isNull,
      reason: '没有 content 的增量要跳过',
    );
    expect(parseSseLine('data: [DONE]'), isNull);
    expect(parseSseLine(': keep-alive'), isNull);
    expect(parseSseLine('data: 不是json'), isNull);
  });

  test('baseURL 末位斜杠会自动处理', () {
    final g = CloudGateway(
      baseUrl: 'https://api.deepseek.com/',
      apiKey: 'k',
    );
    expect(g.baseUrl.endsWith('/'), isTrue);
    // 不联网也能构造，ping/generate 才发请求。
    expect(g.model, 'deepseek-chat');
  });
}
