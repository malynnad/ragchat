import 'package:ragchat/rag/models.dart';
import 'package:ragchat/rag/token_budget.dart';
import 'package:test/test.dart';

/// ADR-0006 容量预算纯函数。
void main() {
  test('estimateTokens 按字符数保守计（中文 1 字 = 1）', () {
    expect(estimateTokens('长城有多长'), 5);
    expect(estimateTokens(''), 0);
    expect(estimateTokens('abcd'), 4);
  });

  test('historyTokens 累加各轮问题与答案', () {
    const history = [
      SessionTurn(question: '一二三', answer: '四五六七'),
      SessionTurn(question: '八', answer: '九'),
    ];
    expect(historyTokens(history), 3 + 4 + 1 + 1);
    expect(historyTokens(const []), 0);
  });

  test('sessionUsageEstimate：新对话为 0，随历史增长，上限 1', () {
    expect(sessionUsageEstimate(const []), 0);
    final short = sessionUsageEstimate(const [
      SessionTurn(question: '问', answer: '答'),
    ]);
    expect(short, greaterThan(0));
    expect(short, lessThan(1));
    // 超长历史钳制到 1
    final long = List.generate(
      500,
      (_) => const SessionTurn(question: '问问问问问问问问问问', answer: '答答答答答答答答答答'),
    );
    expect(sessionUsageEstimate(long), 1);
  });

  test('projectedUsage 包含 system/历史/问题/答案预留', () {
    final n = projectedUsage(
      systemPrompt: '助手甲乙',
      history: const [SessionTurn(question: '问', answer: '答')],
      question: '问题',
    );
    expect(
      n,
      4 + // system
          2 + // 历史
          2 + // 问题
          answerHeadroomTokens,
    );
  });

  test('默认 8K 预算下典型会话可容纳数轮', () {
    // 每轮约 100 字 Q/A，预算 8192×0.9 − 3900 ≈ 3473 字 → 30+ 轮
    final turns = List.generate(
      10,
      (_) => SessionTurn(question: '问' * 20, answer: '答' * 80),
    );
    final usage = sessionUsageEstimate(turns);
    expect(usage, greaterThan(0));
    expect(usage, lessThan(1), reason: '10 轮百字问答不应触顶');
  });
}
