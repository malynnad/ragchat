/// 存储占用显示：单位自适应（十进制），避免小库显示成 0.0 MB。
String formatBytes(int bytes) {
  if (bytes < 1000) return '$bytes B';
  final kb = bytes / 1e3;
  if (kb < 999.5) return '${kb.toStringAsFixed(0)} KB';
  final mb = bytes / 1e6;
  if (mb < 999.5) return '${mb.toStringAsFixed(2)} MB';
  return '${(bytes / 1e9).toStringAsFixed(2)} GB';
}

/// 时段词：小模型分不清早晚，给它一个明确的中文时段比给 24 小时制有用。
String daytimeOf(int hour) {
  if (hour < 5) return '深夜';
  if (hour < 8) return '早上';
  if (hour < 11) return '上午';
  if (hour < 13) return '中午';
  if (hour < 17) return '下午';
  if (hour < 19) return '傍晚';
  if (hour < 23) return '晚上';
  return '深夜';
}

/// 「2026年11月28日 周六 晚上 9:47」——喂给模型的当前时间。
String nowLabel(DateTime now) {
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  final w = weekdays[now.weekday - 1];
  final period = daytimeOf(now.hour);
  final h12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
  final mm = now.minute.toString().padLeft(2, '0');
  return '${now.year}年${now.month}月${now.day}日 $w $period $h12:$mm';
}
