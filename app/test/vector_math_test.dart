import 'dart:typed_data';

import 'package:ragchat/rag/vector_math.dart';
import 'package:test/test.dart';

/// ADR-0016：向量工具是标定与检索的唯一真相源，先钉死它的边界行为。
void main() {
  test('dot 与 cosineSimilarity：同向为 1，反向为 -1，正交为 0', () {
    final a = Float32List.fromList([1, 0, 0]);
    final b = Float32List.fromList([1, 0, 0]);
    final neg = Float32List.fromList([-1, 0, 0]);
    final orth = Float32List.fromList([0, 2, 0]);
    expect(dot(a, b), 1);
    expect(cosineSimilarity(a, b), closeTo(1, 1e-9));
    expect(cosineSimilarity(a, neg), closeTo(-1, 1e-9));
    expect(cosineSimilarity(a, orth), closeTo(0, 1e-9));
  });

  test('余弦与向量长度无关（未归一化的输入也能算对）', () {
    final a = Float32List.fromList([3, 4]);
    final b = Float32List.fromList([6, 8]);
    expect(cosineSimilarity(a, b), closeTo(1, 1e-9));
    expect(l2Norm(a), closeTo(5, 1e-6));
  });

  test('维度不一致直接抛错，绝不静默返回 0', () {
    expect(
      () => cosineSimilarity(
        Float32List.fromList([1, 2]),
        Float32List.fromList([1, 2, 3]),
      ),
      throwsArgumentError,
    );
  });

  test('零向量不出 NaN', () {
    final zero = Float32List(4);
    final other = Float32List.fromList([1, 0, 0, 0]);
    expect(l2Norm(zero), 0);
    expect(cosineSimilarity(zero, other), 0);
    expect(normalized(zero), [0, 0, 0, 0]);
  });

  test('normalized 返回新列表，不改入参', () {
    final v = Float32List.fromList([3, 4]);
    final n = normalized(v);
    expect(v[0], 3);
    expect(v[1], 4);
    expect(l2Norm(n), closeTo(1, 1e-6));
    expect(n[0], closeTo(0.6, 1e-6));
  });

  test('encodeVector 小端 float32，与 decodeVector 往返一致', () {
    final v = Float32List.fromList([1.0, -0.5, 3.25]);
    final bytes = encodeVector(v);
    expect(bytes.length, 12);
    // 1.0f 的小端字节是 00 00 80 3F
    expect(bytes.sublist(0, 4), [0x00, 0x00, 0x80, 0x3F]);
    final back = decodeVector(bytes);
    expect(back.length, 3);
    expect(back[0], 1.0);
    expect(back[1], -0.5);
    expect(back[2], 3.25);
  });

  test('decodeVector 能吃非 4 字节对齐的 BLOB（真机 SQLite 会这样）', () {
    final v = Float32List.fromList([0.125, 7.5]);
    final padded = Uint8List(10);
    padded.setRange(1, 9, encodeVector(v));
    final view = Uint8List.view(padded.buffer, 1, 8);
    final back = decodeVector(view);
    expect(back[0], closeTo(0.125, 1e-7));
    expect(back[1], closeTo(7.5, 1e-6));
  });

  test('BLOB 长度不是 4 的倍数要报错', () {
    expect(() => decodeVector(Uint8List(7)), throwsArgumentError);
  });
}
