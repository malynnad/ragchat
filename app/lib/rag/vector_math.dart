/// 向量基础工具（ADR-0016）。
///
/// 只放纯函数：归一化、相似度、BLOB 编解码。标定（embedding_calibration）
/// 与检索（下一步）共用同一套定义——不然「标定算一种余弦、检索算另一种」
/// 会成为最难查的一类错。
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// 点积。调用方保证长度一致（[cosineSimilarity] 已做检查）。
double dot(Float32List a, Float32List b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}

/// L2 范数。
double l2Norm(Float32List v) {
  var sum = 0.0;
  for (final x in v) {
    sum += x * x;
  }
  return math.sqrt(sum);
}

/// 返回归一化后的新列表；零向量原样返回（不制造 NaN）。
///
/// 不能就地改：嵌入结果可能被调用方复用，标定要同时看原始范数。
Float32List normalized(Float32List v) {
  final n = l2Norm(v);
  if (n == 0) return Float32List.fromList(v);
  final out = Float32List(v.length);
  for (var i = 0; i < v.length; i++) {
    out[i] = v[i] / n;
  }
  return out;
}

/// 余弦相似度。内部各自归一化，调用方不必预处理。
/// 维度不一致直接抛错：静默返回 0 会把「模型换了」伪装成「不相关」。
double cosineSimilarity(Float32List a, Float32List b) {
  if (a.length != b.length) {
    throw ArgumentError('向量维度不一致：${a.length} vs ${b.length}');
  }
  final na = l2Norm(a);
  final nb = l2Norm(b);
  if (na == 0 || nb == 0) return 0;
  return dot(a, b) / (na * nb);
}

/// 向量 → SQLite BLOB：小端 float32 紧排，与 [decodeVector] 对称。
Uint8List encodeVector(Float32List v) {
  final bytes = Uint8List(v.length * 4);
  final bd = ByteData.sublistView(bytes);
  for (var i = 0; i < v.length; i++) {
    bd.setFloat32(i * 4, v[i], Endian.little);
  }
  return bytes;
}

/// BLOB → 向量。走 [ByteData.sublistView] 而不是 Float32List.view：
/// 后者要求 4 字节对齐，SQLite 返回的 BLOB 偏移不保证，真机上会炸。
Float32List decodeVector(Uint8List bytes) {
  if (bytes.length % 4 != 0) {
    throw ArgumentError('向量 BLOB 长度不是 4 的倍数：${bytes.length}');
  }
  final bd = ByteData.sublistView(bytes);
  final out = Float32List(bytes.length ~/ 4);
  for (var i = 0; i < out.length; i++) {
    out[i] = bd.getFloat32(i * 4, Endian.little);
  }
  return out;
}
