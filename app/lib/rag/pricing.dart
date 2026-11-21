import 'models.dart';

/// 每百万 token 的单价（人民币）。
class TokenPrice {
  const TokenPrice({required this.inputPerM, required this.outputPerM});
  final double inputPerM;
  final double outputPerM;
}

/// 官方闲时价（高峰翻倍）。DeepSeek 2026-11 文档：
/// flash 输入 1 元 / 输出 4 元；pro 输入 4.5 元 / 输出 13.5 元（每百万 token）。
const _prices = <String, TokenPrice>{
  'flash': TokenPrice(inputPerM: 1, outputPerM: 4),
  'pro': TokenPrice(inputPerM: 4.5, outputPerM: 13.5),
};

/// 按模型名猜价格档位；认不出就返回 null（只显示 token，不编价格）。
TokenPrice? priceFor(String model) {
  final m = model.toLowerCase();
  if (m.contains('flash')) return _prices['flash'];
  if (m.contains('pro')) return _prices['pro'];
  return null;
}

/// 估算这一轮的费用；不知道价格返回 null。
double? estimateCost(String model, TokenUsage usage) {
  final p = priceFor(model);
  if (p == null) return null;
  return usage.promptTokens / 1e6 * p.inputPerM +
      usage.completionTokens / 1e6 * p.outputPerM;
}

/// 1234 → 1.2k；999 → 999。
String formatTokens(int n) {
  if (n < 1000) return '$n';
  final k = n / 1000;
  return '${k.toStringAsFixed(k < 10 ? 1 : 0)}k';
}

/// 费用展示：小额多给几位，避免全显示成 ¥0.00。
String formatCost(double? cost) {
  if (cost == null) return '';
  if (cost <= 0) return '¥0';
  if (cost < 0.0001) return '<¥0.0001';
  if (cost < 0.01) return '¥${cost.toStringAsFixed(4)}';
  return '¥${cost.toStringAsFixed(3)}';
}
