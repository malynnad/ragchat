/// 记忆检索（ADR-0016 第 3 步）：纯函数，不碰数据库、不碰网关，可单测。
///
/// 规则来自真机标定（ADR-0016「标定」）：
/// - 先过硬阈值：中文短句的「无关」地板实测最高 0.385，低于 0.50 的一律当噪音；
/// - 再混合排序：0.85 × cosine + 0.15 × importance。importance 只能微调次序，
///   不能把无关但重要的条目顶到相关条目前面（0.7/0.3 会反转，见 ADR）。
library;

import 'dart:typed_data';

import '../chat/app_db.dart';
import 'vector_math.dart';

/// 相似度硬阈值。低于它连候选都不进，谈不上排序。
const double memorySimilarityThreshold = 0.50;

/// 每轮最多注入几条命中：记忆预算只有 800 token，宁少勿滥。
const int memoryTopK = 5;

const double memoryHitWeight = 0.85;
const double memoryImportanceWeight = 0.15;

/// 一条命中：保留原始余弦，方便排查「为什么这条没进来」。
class MemoryHit {
  const MemoryHit({
    required this.memory,
    required this.cosine,
    required this.score,
  });

  final MemoryVector memory;
  final double cosine;
  final double score;
}

/// 检索并按混合分排序，返回 top-k。
///
/// [query] 与 index 里的向量都应已归一化；这里仍走 [cosineSimilarity]，
/// 万一上游忘了归一化也不会算错（1024 维多算一次范数，代价可忽略）。
List<MemoryHit> rankMemoryHits({
  required Float32List query,
  required List<MemoryVector> index,
  double threshold = memorySimilarityThreshold,
  int topK = memoryTopK,
}) {
  final hits = <MemoryHit>[];
  for (final m in index) {
    // 维度不一致说明是换模型残留的向量：跳过，不猜。
    if (m.vector.length != query.length) continue;
    final cosine = cosineSimilarity(query, m.vector);
    if (cosine < threshold) continue;
    hits.add(
      MemoryHit(
        memory: m,
        cosine: cosine,
        score:
            memoryHitWeight * cosine +
            memoryImportanceWeight * (m.importance / 5),
      ),
    );
  }
  hits.sort((a, b) => b.score.compareTo(a.score));
  return hits.length <= topK ? hits : hits.sublist(0, topK);
}

/// 生成注入顺序：命中按分数在前，剩下的按原顺序（调用方给的是重要度序）兜底。
///
/// 为什么不是「只注入命中」：检索可能漏、向量可能还没补完，把其余条目按重要度
/// 排在后面，能保证「预算够时装得下」，也让降级路径和正常路径同一套代码。
List<MemoryEntry> orderMemoryPrompt({
  required List<MemoryEntry> all,
  required List<MemoryHit> hits,
}) {
  final byId = {for (final m in all) m.id: m};
  final out = <MemoryEntry>[];
  final seen = <String>{};
  for (final h in hits) {
    final m = byId[h.memory.id];
    if (m == null) continue; // 命中但已停用/删除：丢弃
    if (!seen.add(m.id)) continue;
    out.add(m);
  }
  for (final m in all) {
    if (seen.contains(m.id)) continue;
    out.add(m);
  }
  return out;
}
