import 'models.dart';

/// 上下文容量预算（ADR-0006/0009）：纯函数，可单测。
/// 估算保守按字符数计（上界）：Qwen 分词中文约 1 字/token，
/// 英文实际更省，预算只会高估不会低估，安全。
int estimateTokens(String text) => text.runes.length;

/// 历史轮次（纯 Q/A）占用。
int historyTokens(List<SessionTurn> history) {
  var n = 0;
  for (final t in history) {
    n += estimateTokens(t.question) + estimateTokens(t.answer);
  }
  return n;
}

/// system 消息（人设卡 + 核心记忆清单）预算（ADR-0009 决策 8）。
/// 记忆条目多时超出此预算的条目不入 system（AppState 组装时截断）。
const int systemBudgetTokens = 800;

/// 答案生成预留（流式输出上限的保守估计）。
const int answerHeadroomTokens = 1200;

/// 安全系数：预计占用超过 contextSize×0.9 即拒绝发起生成。
const double contextSafetyFactor = 0.9;

/// 一轮提问的预计总占用：system（人设+记忆）+ 历史 + 问题 + 答案预留。
int projectedUsage({
  required String systemPrompt,
  required List<SessionTurn> history,
  required String question,
}) =>
    estimateTokens(systemPrompt) +
    historyTokens(history) +
    estimateTokens(question) +
    answerHeadroomTokens;

/// 会话预算占用率（UI 指示器用）：历史占用 / 可用历史预算。
/// 0 = 新对话，1 = 历史预算用尽（应开启新对话）。
double sessionUsageEstimate(
  List<SessionTurn> history, {
  int contextSize = 8192,
}) {
  final reserve = systemBudgetTokens + answerHeadroomTokens;
  final budget = contextSize * contextSafetyFactor - reserve;
  if (budget <= 0) return 1;
  return (historyTokens(history) / budget).clamp(0.0, 1.0).toDouble();
}
