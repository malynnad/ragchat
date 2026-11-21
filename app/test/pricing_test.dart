import 'package:ragchat/rag/models.dart';
import 'package:ragchat/rag/pricing.dart';
import 'package:test/test.dart';

void main() {
  const usage = TokenUsage(promptTokens: 1500, completionTokens: 300);

  test('flash 按 1 / 4 元每百万估算', () {
    final cost = estimateCost('deepseek-flash', usage);
    // 1500/1e6*1 + 300/1e6*4 = 0.0027
    expect(cost, closeTo(0.0027, 1e-9));
  });

  test('pro 按 4.5 / 13.5 元每百万估算', () {
    final cost = estimateCost('deepseek-v4-pro', usage);
    // 1500/1e6*4.5 + 300/1e6*13.5 = 0.0108
    expect(cost, closeTo(0.0108, 1e-9));
  });

  test('认不出的模型不编价格', () {
    expect(estimateCost('gpt-4o', usage), isNull);
    expect(formatCost(null), '');
  });

  test('token 数量与费用格式化', () {
    expect(formatTokens(999), '999');
    expect(formatTokens(1234), '1.2k');
    expect(formatTokens(12345), '12k');
    expect(formatCost(0.0027), '¥0.0027');
    expect(formatCost(0.00001), '<¥0.0001');
  });
}
