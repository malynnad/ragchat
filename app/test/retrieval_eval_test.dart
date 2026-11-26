import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ragchat/app/persona.dart';
import 'package:ragchat/chat/app_db.dart';
import 'package:ragchat/chat/chat_service.dart';
import 'package:ragchat/rag/memory_retrieval.dart';
import 'package:ragchat/rag/retrieval_eval.dart';
import 'package:test/test.dart';

/// 构造「与查询余弦恰好为 [cosine]」的 2 维向量：查询固定 [1,0]。
Float32List _vec(double cosine) {
  final theta = math.acos(cosine.clamp(-1.0, 1.0));
  return Float32List.fromList([math.cos(theta), math.sin(theta)]);
}

final _query = Float32List.fromList([1, 0]);

/// 人设故意短一点，好让预算计算可预期。
const _persona = PersonaCard(
  id: 'test',
  name: '阿鱼',
  personality: '话少，爱吃白饭',
);

MemoryVector _idx(String id, double cosine, int importance) => MemoryVector(
  id: id,
  content: id,
  importance: importance,
  vector: _vec(cosine),
);

void main() {
  test('fitMemoriesWithinBudget：贪心装入，装不下即停（不跳过硬塞）', () {
    final memories = [
      MemoryEntry(id: 'a', content: '一二三四五'),
      MemoryEntry(id: 'b', content: '一二三四五'),
      MemoryEntry(id: 'c', content: '一二三四五'),
    ];
    final head = _persona.render();
    final base = head.length + '\n关于用户的长期记忆：'.length;
    // 每条 '- 一二三四五' 是 1 个换行+连字符+空格+5 字 ≈ 8 token。
    final fitsTwo = base + 8 * 2;
    expect(
      ChatService.fitMemoriesWithinBudget(
        _persona,
        memories,
        budget: fitsTwo,
      ).map((m) => m.id),
      ['a', 'b'],
    );
    expect(
      ChatService.fitMemoriesWithinBudget(_persona, memories, budget: base),
      isEmpty,
    );
  });

  test('压力预算下：重要度序把相关的挤出去，检索序把它捞回来', () async {
    // 重要度序：两条高重要度的无关记忆排在前，相关的（重要度 1）垫底——
    // 这正是「纯重要度」在预算紧张时会犯的错。
    final memories = [
      MemoryEntry(id: '无关-儿子', content: '用户有一个20岁的大二儿子'),
      MemoryEntry(id: '无关-上班', content: '用户需要上班'),
      MemoryEntry(id: '相关-名字', content: '用户名字叫Danny'),
    ];
    final index = [
      _idx('无关-儿子', 0.30, 3),
      _idx('无关-上班', 0.32, 3),
      _idx('相关-名字', 0.72, 1),
    ];

    final eval = await evaluateRetrieval(
      memories: memories,
      index: index,
      persona: _persona,
      embedQuery: (_) async => _query,
    );

    final row = eval.rows.first;
    expect(row.hit, isTrue);
    expect(row.bestCosine, closeTo(0.72, 1e-6));
    // 真实预算 800 装得下全部 → 排序不影响结果（诚实记录「没差别」）。
    expect(row.pressureDiffers || row.baselineIncluded.length == 3, isTrue);
    expect(row.baselineIncluded, hasLength(3));
    // 压力预算正好装两条：重要度序丢掉了相关的那条，检索序保住了。
    expect(eval.pressureFit, 2);
    expect(row.pressureBaseline, ['用户有一个20岁的大二儿子', '用户需要上班']);
    expect(row.pressureRetrieval, ['用户名字叫Danny']);
    expect(row.pressureDiffers, isTrue);
    expect(eval.changedCount, greaterThan(0));
  });

  test('全部无关时不自作聪明：命中 0，两种排序一致', () async {
    final memories = [
      MemoryEntry(id: 'a', content: '用户需要上班'),
      MemoryEntry(id: 'b', content: '用户半夜会饿到睡不着'),
    ];
    final eval = await evaluateRetrieval(
      memories: memories,
      index: [_idx('a', 0.30, 3), _idx('b', 0.32, 2)],
      persona: _persona,
      embedQuery: (_) async => _query,
    );
    final row = eval.rows.first;
    expect(row.hit, isFalse);
    expect(row.pressureDiffers, isFalse);
    expect(eval.hitCount, 0);
    expect(eval.changedCount, 0);
  });

  test('查询编码失败时退化成重要度序，不崩', () async {
    final memories = [MemoryEntry(id: 'a', content: '用户需要上班')];
    final eval = await evaluateRetrieval(
      memories: memories,
      index: [_idx('a', 0.9, 3)],
      persona: _persona,
      embedQuery: (_) async => null,
    );
    expect(eval.rows.first.hit, isFalse);
    expect(eval.rows.first.bestCosine, 0);
    expect(eval.changedCount, 0);
  });

  test('markdown 报告含结论、逐题明细与阈值', () async {
    final memories = [MemoryEntry(id: '相关', content: '用户名字叫Danny')];
    final eval = await evaluateRetrieval(
      memories: memories,
      index: [_idx('相关', 0.72, 1)],
      persona: _persona,
      embedQuery: (_) async => _query,
      questions: const ['我叫什么名字'],
    );
    final md = eval.toMarkdown();
    expect(md, contains('## 检索自检'));
    expect(md, contains('「我叫什么名字」'));
    expect(md, contains('0.720'));
    expect(md, contains(memorySimilarityThreshold.toStringAsFixed(2)));
  });
}
