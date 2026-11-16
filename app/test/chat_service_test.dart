import 'package:ragchat/app/persona.dart';
import 'package:ragchat/chat/app_db.dart';
import 'package:ragchat/chat/chat_service.dart';
import 'package:ragchat/rag/models.dart';
import 'package:test/test.dart';

import 'fakes/fake_gateway.dart';

void main() {
  group('system prompt', () {
    test('人设已占满预算时不硬塞第一条长期记忆', () {
      const persona = PersonaCard(id: 'p', name: 'A');
      final memories = [
        MemoryEntry(id: 'm1', content: '用户叫Danny', importance: 5),
      ];

      final prompt = ChatService.buildSystemPromptWithinBudget(
        persona,
        memories,
        budget: 5,
      );

      expect(prompt, persona.render());
      expect(prompt, isNot(contains('用户叫Danny')));
    });
  });

  group('chat messages', () {
    test('按 system、历史 Q/A、当前问题组装，且不夹带检索资料', () {
      final gateway = FakeGateway();
      final service = ChatService(gateway: gateway);
      const history = [SessionTurn(question: '我叫什么？', answer: '你叫Danny。')];

      final messages = service.buildMessages(
        question: '我今天在做什么？',
        systemPrompt: '你是小助。',
        history: history,
      );

      expect(messages.map((m) => m.role), [
        ChatRole.system,
        ChatRole.user,
        ChatRole.assistant,
        ChatRole.user,
      ]);
      expect(messages.map((m) => m.content), [
        '你是小助。',
        '我叫什么？',
        '你叫Danny。',
        '我今天在做什么？',
      ]);
    });
  });
}
