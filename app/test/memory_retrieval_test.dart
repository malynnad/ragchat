import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ragchat/chat/app_db.dart';
import 'package:ragchat/rag/memory_retrieval.dart';
import 'package:test/test.dart';

/// 构造与查询向量「余弦恰好等于 [cosine]」的 2 维向量：
/// 查询固定 [1,0]，向量取 [cosθ, sinθ] 即可，不用凑 1024 维也能验规则。
Float32List _vec(double cosine) {
  final theta = math.acos(cosine.clamp(-1.0, 1.0));
  return Float32List.fromList([math.cos(theta), math.sin(theta)]);
}

final _query = Float32List.fromList([1, 0]);

MemoryVector _mem(String id, double cosine, {int importance = 3}) =>
    MemoryVector(
      id: id,
      content: '内容-$id',
      importance: importance,
      vector: _vec(cosine),
    );

void main() {
  test('硬阈值：低于 0.50 的噪音一律不进候选（真机地板 0.385）', () {
    final hits = rankMemoryHits(
      query: _query,
      index: [_mem('noise', 0.3848), _mem('edge', 0.50), _mem('real', 0.62)],
    );
    expect(hits.map((h) => h.memory.id), ['real', 'edge']);
  });

  test('阈值可覆盖：关掉阈值看全量（诊断用）', () {
    final hits = rankMemoryHits(
      query: _query,
      index: [_mem('a', 0.2), _mem('b', 0.9)],
      threshold: 0,
    );
    expect(hits, hasLength(2));
  });

  test('0.15 的重要性权重不会反转排序（0.7/0.3 会）', () {
    // 相关但重要度 1 vs 无关但重要度 5：真机数值 0.62 / 0.385。
    final relevant = _mem('rel', 0.6207, importance: 1);
    final irrelevant = _mem('imp', 0.3848, importance: 5);
    final hits = rankMemoryHits(
      query: _query,
      index: [irrelevant, relevant],
      threshold: 0,
    );
    expect(hits.first.memory.id, 'rel');
    // 顺手把「0.7/0.3 会反转」算出来钉在测试里：文档与代码别跑偏。
    double score(MemoryVector m, double w) =>
        w * (m.id == 'rel' ? 0.6207 : 0.3848) + (1 - w) * (m.importance / 5);
    expect(score(relevant, 0.7), lessThan(score(irrelevant, 0.7)));
    expect(score(relevant, 0.85), greaterThan(score(irrelevant, 0.85)));
  });

  test('同相似度时重要度高的在前', () {
    final hits = rankMemoryHits(
      query: _query,
      index: [
        _mem('low', 0.70, importance: 1),
        _mem('high', 0.70, importance: 5),
      ],
    );
    expect(hits.map((h) => h.memory.id), ['high', 'low']);
    expect(
      hits.first.score,
      closeTo(0.85 * hits.first.cosine + 0.15, 1e-9),
    );
  });

  test('top-k 截断，按分数从高到低', () {
    final index = [
      for (var i = 0; i < 8; i++) _mem('m$i', 0.55 + i * 0.05),
    ];
    final hits = rankMemoryHits(query: _query, index: index, topK: 3);
    expect(hits.map((h) => h.memory.id), ['m7', 'm6', 'm5']);
  });

  test('维度不一致的向量跳过（换模型残留）', () {
    final wrongDim = MemoryVector(
      id: 'stale',
      content: '旧模型算的',
      importance: 5,
      vector: Float32List.fromList([1, 0, 0, 0]),
    );
    final hits = rankMemoryHits(
      query: _query,
      index: [wrongDim, _mem('ok', 0.8)],
    );
    expect(hits.map((h) => h.memory.id), ['ok']);
  });

  test('保留原始余弦，便于排查为什么没进上下文', () {
    final hits = rankMemoryHits(query: _query, index: [_mem('a', 0.7777)]);
    // float32 存储带来的 1e-8 级误差，别用 1e-9 卡自己
    expect(hits.single.cosine, closeTo(0.7777, 1e-6));
  });

  test('注入顺序：命中在前，其余按原序兜底并去重', () {
    final all = [
      MemoryEntry(id: 'a', content: 'A'),
      MemoryEntry(id: 'b', content: 'B'),
      MemoryEntry(id: 'c', content: 'C'),
    ];
    final hits = rankMemoryHits(
      query: _query,
      index: [_mem('c', 0.9), _mem('a', 0.8)],
    );
    final ordered = orderMemoryPrompt(all: all, hits: hits);
    expect(ordered.map((e) => e.id), ['c', 'a', 'b']);
    expect(ordered.map((e) => e.id).toSet().length, 3);
  });

  test('命中里已删除/停用的条目丢弃，不影响其余顺序', () {
    final all = [MemoryEntry(id: 'a', content: 'A')];
    final hits = rankMemoryHits(
      query: _query,
      index: [_mem('gone', 0.9), _mem('a', 0.8)],
    );
    final ordered = orderMemoryPrompt(all: all, hits: hits);
    expect(ordered.map((e) => e.id), ['a']);
  });

  test('没有命中时就是原序（等价于纯重要度路径）', () {
    final all = [
      MemoryEntry(id: 'a', content: 'A'),
      MemoryEntry(id: 'b', content: 'B'),
    ];
    final hits = rankMemoryHits(
      query: _query,
      index: [_mem('a', 0.1), _mem('b', 0.2)],
    );
    expect(hits, isEmpty);
    expect(orderMemoryPrompt(all: all, hits: hits).map((e) => e.id), ['a', 'b']);
  });
}
