import 'package:ragchat/app/format.dart';
import 'package:ragchat/chat/app_db.dart';
import 'package:ragchat/chat/chat_service.dart';
import 'package:ragchat/app/persona.dart';
import 'package:test/test.dart';

void main() {
  test('时段词覆盖一天：小模型最容易错的早晚两档要点名', () {
    expect(daytimeOf(3), '深夜');
    expect(daytimeOf(6), '早上');
    expect(daytimeOf(9), '上午');
    expect(daytimeOf(12), '中午');
    expect(daytimeOf(15), '下午');
    expect(daytimeOf(18), '傍晚');
    expect(daytimeOf(21), '晚上');
    expect(daytimeOf(23), '深夜');
  });

  test('nowLabel：日期 + 周几 + 时段 + 12 小时制', () {
    expect(
      nowLabel(DateTime(2026, 11, 28, 21, 7)),
      '2026年11月28日 周六 晚上 9:07',
    );
    // 0 点与 12 点不能写成 0:xx / 12 点却显示「上午」
    expect(nowLabel(DateTime(2026, 1, 5, 0, 5)), contains('深夜 12:05'));
    expect(nowLabel(DateTime(2026, 1, 5, 12, 30)), contains('中午 12:30'));
  });

  test('system 里带当前时间，且人设仍在最前面', () {
    const persona = PersonaCard(id: 'p', name: '大肥鱼', personality: '话少');
    final prompt = ChatService.buildSystemPromptWithinBudget(
      persona,
      const [],
      now: DateTime(2026, 11, 28, 21, 7),
    );
    expect(prompt, startsWith('你是大肥鱼'));
    expect(prompt, contains('现在是2026年11月28日 周六 晚上 9:07'));
    expect(prompt, contains('这是准确时间'));
    expect(prompt, contains('直接回答'));
  });

  test('时间行占用预算：塞满人设时不再硬塞记忆', () {
    // 预算刚好装下人设 + 时间行，不该再塞进一条记忆。
    final persona = PersonaCard(id: 'p', name: 'A', personality: '话少');
    final head = ChatService.promptHead(persona);
    final fitted = ChatService.fitMemoriesWithinBudget(
      persona,
      [MemoryEntry(id: 'm', content: '用户叫Danny', importance: 5)],
      budget: head.length,
      now: DateTime(2026, 11, 28, 21, 7),
    );
    expect(fitted, isEmpty);
  });
}
