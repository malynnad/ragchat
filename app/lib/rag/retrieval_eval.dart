/// 检索自检（ADR-0016 第 4 步）：用真实记忆和真实向量，比较两种排序
/// 在「同一份预算」下的差别——纯重要度 vs 检索命中优先。
///
/// 为什么要有它：A/B 的结论不能靠感觉。预算宽时两种排序装下的条目一模一样，
/// 只有把预算压到「正好装两条」才看得出差别；这个文件负责把这件事算清楚。
library;

import 'dart:typed_data';

import '../app/persona.dart';
import '../chat/app_db.dart';
import '../chat/chat_service.dart';
import 'memory_retrieval.dart';
import 'token_budget.dart';

/// 固定问题集：都是「个人助理会问到的」短句，不针对某一台机器的记忆定制。
/// 命中与否由真实余弦决定，命中率低不丢人，掩盖才丢人。
const List<String> kEvalQuestions = [
  '我叫什么名字',
  '我有孩子吗',
  '我几点睡觉',
  '我在哪上班',
  '我最近在忙什么',
  '我住在哪',
  '我多大年纪',
  '我周末做什么',
  '我今天累不累',
  '我最喜欢吃什么',
  '我需要早起吗',
  '我心情不好怎么办',
];

/// 单题结果。
class EvalRow {
  const EvalRow({
    required this.question,
    required this.bestCosine,
    required this.bestContent,
    required this.hit,
    required this.baselineIncluded,
    required this.retrievalIncluded,
    required this.pressureBaseline,
    required this.pressureRetrieval,
  });

  final String question;

  /// 全库最高分（可能低于阈值）：用来判断「是没命中还是没跑」。
  final double bestCosine;
  final String? bestContent;
  final bool hit;

  /// 真实预算下，两种排序各自装进 system 的记忆。
  final List<String> baselineIncluded;
  final List<String> retrievalIncluded;

  /// 压力预算（正好装 [RetrievalEval.pressureFit] 条）下的两种排序。
  final List<String> pressureBaseline;
  final List<String> pressureRetrieval;

  /// 压力预算下排序真的改变了结果：这才是检索起作用的证据。
  bool get pressureDiffers =>
      pressureBaseline.join('|') != pressureRetrieval.join('|');
}

class RetrievalEval {
  const RetrievalEval({
    required this.rows,
    required this.budget,
    required this.pressureBudget,
    required this.pressureFit,
    required this.indexSize,
    required this.threshold,
  });

  final List<EvalRow> rows;
  final int budget;
  final int pressureBudget;
  final int pressureFit;
  final int indexSize;
  final double threshold;

  int get hitCount => rows.where((r) => r.hit).length;
  int get changedCount => rows.where((r) => r.pressureDiffers).length;

  String toMarkdown() {
    final b = StringBuffer()
      ..writeln('## 检索自检')
      ..writeln()
      ..writeln('- 问题 ${rows.length} 题，记忆索引 $indexSize 条')
      ..writeln('- 真实预算 $budget token；压力预算 $pressureBudget token（正好装 $pressureFit 条）')
      ..writeln('- 命中（cos ≥ ${threshold.toStringAsFixed(2)}）：$hitCount / ${rows.length}')
      ..writeln('- 压力预算下排序被改写：$changedCount / ${rows.length}');
    for (final r in rows) {
      b
        ..writeln()
        ..writeln('### 「${r.question}」')
        ..writeln(
          '- 最高分 ${r.bestCosine.toStringAsFixed(3)}'
          '${r.hit ? " ✓" : " ✗（低于阈值）"}'
          '${r.bestContent == null ? "" : " · ${r.bestContent}"}',
        )
        ..writeln('- 真实预算 重要度 ${_fmt(r.baselineIncluded)} / 检索 ${_fmt(r.retrievalIncluded)}');
      b.writeln(
        '- 压力预算 重要度 ${_fmt(r.pressureBaseline)} / 检索 ${_fmt(r.pressureRetrieval)}'
        '${r.pressureDiffers ? "  ← 有差异" : ""}',
      );
    }
    return b.toString();
  }

  static String _fmt(List<String> xs) =>
      xs.isEmpty ? '（空）' : xs.map((e) => '「$e」').join(' + ');
}

/// 跑一次自检。[memories] 必须是重要度序（`activeMemories()` 的输出）。
Future<RetrievalEval> evaluateRetrieval({
  required List<MemoryEntry> memories,
  required List<MemoryVector> index,
  required PersonaCard persona,
  required Future<Float32List?> Function(String question) embedQuery,
  List<String> questions = kEvalQuestions,
  int budget = systemBudgetTokens,
  int pressureFit = 2,
  double threshold = memorySimilarityThreshold,
}) async {
  // 压力预算按真实数据算：人设 + 记忆表头 + 前 pressureFit 条，正好卡住。
  final head = persona.render();
  var pressure =
      estimateTokens(head) +
      estimateTokens('\n关于用户的长期记忆：') +
      estimateTokens(ChatService.memoryGuard);
  for (var i = 0; i < memories.length && i < pressureFit; i++) {
    pressure += estimateTokens('\n- ${memories[i].content}');
  }

  final rows = <EvalRow>[];
  for (final q in questions) {
    final query = await embedQuery(q);
    final hits = query == null
        ? const <MemoryHit>[]
        : rankMemoryHits(query: query, index: index, threshold: threshold);
    final scored = query == null
        ? const <MemoryHit>[]
        : rankMemoryHits(query: query, index: index, threshold: 0, topK: 1);
    final retrievalOrder = orderMemoryPrompt(all: memories, hits: hits);

    List<String> pick(List<MemoryEntry> order, int b) => [
      for (final m in ChatService.fitMemoriesWithinBudget(
        persona,
        order,
        budget: b,
      ))
        m.content,
    ];

    rows.add(
      EvalRow(
        question: q,
        bestCosine: scored.isEmpty ? 0 : scored.first.cosine,
        bestContent: scored.isEmpty ? null : scored.first.memory.content,
        hit: hits.isNotEmpty,
        baselineIncluded: pick(memories, budget),
        retrievalIncluded: pick(retrievalOrder, budget),
        pressureBaseline: pick(memories, pressure),
        pressureRetrieval: pick(retrievalOrder, pressure),
      ),
    );
  }

  return RetrievalEval(
    rows: rows,
    budget: budget,
    pressureBudget: pressure,
    pressureFit: pressureFit,
    indexSize: index.length,
    threshold: threshold,
  );
}
