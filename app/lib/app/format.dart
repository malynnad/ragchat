/// 存储占用显示：单位自适应（十进制），避免小库显示成 0.0 MB。
String formatBytes(int bytes) {
  if (bytes < 1000) return '$bytes B';
  final kb = bytes / 1e3;
  if (kb < 999.5) return '${kb.toStringAsFixed(0)} KB';
  final mb = bytes / 1e6;
  if (mb < 999.5) return '${mb.toStringAsFixed(2)} MB';
  return '${(bytes / 1e9).toStringAsFixed(2)} GB';
}
