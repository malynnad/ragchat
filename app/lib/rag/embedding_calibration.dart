import 'dart:typed_data';

import 'vector_math.dart';

/// 嵌入标定（ADR-0016 第 0 步）。
///
/// 目的：在把向量接进检索之前，先量清楚三个事实——
/// 维度对不对、向量归不归一化、相似度阈值该定在哪。
/// 不量就写死阈值，等于闭着眼睛调参。
///
/// 只依赖注入的 [EmbedFn]，不碰 nobodywho，因此可单测、可换模型复用。
typedef EmbedFn = Future<Float32List> Function(String text);
typedef EmbedBatchFn = Future<List<Float32List>> Function(List<String> texts);

/// 探针对的期望档位。只用来判「模型给出的分布像不像人话」，
/// 不是验收标准：真机数值回填 ADR 后才成为阈值。
enum ProbeExpect { high, mid, low, cross }

class ProbePair {
  const ProbePair(this.label, this.a, this.b, this.expect);

  final String label;
  final String a;
  final String b;
  final ProbeExpect expect;
}

class PairScore {
  const PairScore({required this.pair, required this.cosine});

  final ProbePair pair;
  final double cosine;

  /// 明显不符合预期：高相似对拉不开、无关对被拉近。
  bool get suspicious => switch (pair.expect) {
    ProbeExpect.high => cosine < 0.60,
    ProbeExpect.low => cosine > 0.55,
    // 「中」的问题是塌成无关，不是太高。
    ProbeExpect.mid => cosine < 0.25,
    // 跨语言没有先验，只看不判。
    ProbeExpect.cross => false,
  };
}

/// 标定结果。字段全部来自实测，没跑到的留 null（报告里显示「未测」）。
class CalibrationReport {
  const CalibrationReport({
    required this.modelLabel,
    required this.dim,
    required this.expectedDim,
    required this.warmupMs,
    required this.singleAvgMs,
    required this.singleCount,
    required this.batchMs,
    required this.rawNorm,
    required this.selfSim,
    required this.batchDrift,
    required this.pairs,
    required this.instructionTop,
    required this.plainTop,
    required this.querySimPlain,
    required this.querySimInstruct,
    required this.warnings,
    required this.notes,
  });

  final String modelLabel;
  final int dim;

  /// 期望维度（Qwen3-Embedding-0.6B = 1024，GGUF 元数据实证）。
  final int expectedDim;

  /// 首次调用耗时（含模型加载），只作观察。
  final int warmupMs;
  final int singleAvgMs;
  final int singleCount;
  final int? batchMs;
  final double rawNorm;
  final double selfSim;
  final double? batchDrift;
  final List<PairScore> pairs;
  final String? plainTop;
  final String? instructionTop;
  final double? querySimPlain;
  final double? querySimInstruct;
  final List<String> warnings;
  final List<String> notes;

  bool get dimOk => dim == expectedDim;

  /// 可用于方框回填：全部警告清空才算标定通过。
  bool get ok => warnings.isEmpty;

  String toMarkdown() {
    final b = StringBuffer()
      ..writeln('## 嵌入标定报告')
      ..writeln()
      ..writeln('- 模型：$modelLabel')
      ..writeln('- 维度：$dim（期望 $expectedDim）${dimOk ? "✓" : "✗ 模型不对，先换模型"}')
      ..writeln('- 首次调用（含加载）：$warmupMs ms')
      ..writeln('- 单条平均：$singleAvgMs ms（$singleCount 条，已排除首次）')
      ..writeln('- 批量：${batchMs == null ? "未测" : "$batchMs ms"}')
      ..writeln('- 原始范数：${rawNorm.toStringAsFixed(4)}')
      ..writeln('- 同句一致性：${selfSim.toStringAsFixed(6)}')
      ..writeln(
        '- 批量/单条最大偏差：'
        '${batchDrift == null ? "未测" : batchDrift!.toStringAsFixed(6)}',
      )
      ..writeln()
      ..writeln('| 探针 | 档位 | 余弦 | 判定 |')
      ..writeln('|---|---|---|---|')
      ..writeln(
        [
          for (final s in pairs)
            '| ${s.pair.label} | ${s.pair.expect.name} | '
                '${s.cosine.toStringAsFixed(4)} | ${s.suspicious ? "⚠" : "ok"} |',
        ].join('\n'),
      )
      ..writeln()
      ..writeln('### 指令前缀（Qwen3 推荐 query 加 Instruct）')
      ..writeln('- 无前缀 top1：${plainTop ?? "未测"}')
      ..writeln('- 有前缀 top1：${instructionTop ?? "未测"}')
      ..writeln(
        '- 查询对「我住在杭州。」：'
        '${querySimPlain?.toStringAsFixed(4) ?? "-"} → '
        '${querySimInstruct?.toStringAsFixed(4) ?? "-"}',
      );
    if (notes.isNotEmpty) {
      b
        ..writeln()
        ..writeln('### 观察');
      for (final n in notes) {
        b.writeln('- $n');
      }
    }
    b
      ..writeln()
      ..writeln('### 警告');
    if (warnings.isEmpty) {
      b.writeln('- 无');
    } else {
      for (final w in warnings) {
        b.writeln('- $w');
      }
    }
    return b.toString();
  }
}

/// 跑一次标定。任何一个嵌入调用抛错都会原样抛出——
/// 加载失败不该被包装成「报告里的 0 分」。
class EmbeddingCalibration {
  EmbeddingCalibration({
    required this.embed,
    this.embedBatch,
    this.modelLabel = '',
    this.expectedDim = defaultDim,
  });

  /// Qwen3-Embedding-0.6B 的 hidden size；换模型必须同步改（ADR-0016）。
  static const int defaultDim = 1024;

  /// 【实测】Qwen3-Embedding 官方建议 query 加指令、passage 不加。
  /// 这里只用来量它到底有没有影响，不当作默认行为。
  static const String instruction = 'Instruct: 从记忆条目里找出与用户问题最相关的事实\nQuery: ';

  /// 固定探针：中文短事实 + 一句跨语言 + 一句无关。
  /// 改动这里要同步 ADR 的标定记录，否则历史和现在没法比。
  static const List<ProbePair> probes = [
    ProbePair('改写同义', '我住在杭州。', '我家在杭州。', ProbeExpect.high),
    ProbePair('同义加词', '我住在杭州。', '我平时都住在杭州。', ProbeExpect.high),
    ProbePair('地点相关不同', '我住在杭州。', '杭州的西湖很有名。', ProbeExpect.mid),
    ProbePair('同城不同事', '我住在杭州。', '我在上海上班。', ProbeExpect.mid),
    ProbePair('完全无关', '我住在杭州。', '今天天气不错。', ProbeExpect.low),
    ProbePair('跨语言同义', '我住在杭州。', 'I live in Hangzhou.', ProbeExpect.cross),
    ProbePair('同类不同事', '今天天气不错。', '明天要下雨，记得带伞。', ProbeExpect.mid),
  ];

  /// 探针用到的全部句子（去重，保证缓存生效）。
  static List<String> get probeTexts => {
    for (final p in probes) ...[p.a, p.b],
  }.toList();

  static const String _query = '我住在哪';

  final EmbedFn embed;
  final EmbedBatchFn? embedBatch;
  final String modelLabel;
  final int expectedDim;

  Future<CalibrationReport> run() async {
    final warnings = <String>[];
    final notes = <String>[];

    // 首次调用含模型加载（真机数秒级），单独计时，别污染单条平均值。
    final warm = Stopwatch()..start();
    final first = await embed(probes.first.a);
    warm.stop();
    final warmupMs = warm.elapsedMilliseconds;
    final dim = first.length;
    final rawNorm = l2Norm(first);
    if (dim != expectedDim) {
      warnings.add('维度 $dim 与期望 $expectedDim 不符：模型文件选错了，先换模型再谈阈值');
    }
    // 只比「离 1 多远」：模型自己归一化过就 ≈1，没归一化会明显偏大或偏小。
    if ((rawNorm - 1).abs() > 0.01) {
      notes.add('原始向量未归一化（范数 ${rawNorm.toStringAsFixed(4)}）：检索侧自行归一化，不影响余弦');
    }

    final again = await embed(probes.first.a);
    final selfSim = cosineSimilarity(first, again);
    if (selfSim < 0.999) {
      warnings.add('同句两次结果不一致（${selfSim.toStringAsFixed(4)}）：推理存在随机性，检索不可复现');
    }

    final texts = probeTexts;
    final singles = <String, Float32List>{};
    var totalMs = 0;
    for (final t in texts) {
      final sw = Stopwatch()..start();
      singles[t] = await embed(t);
      sw.stop();
      totalMs += sw.elapsedMilliseconds;
    }
    final singleAvgMs = texts.isEmpty ? 0 : (totalMs / texts.length).round();

    int? batchMs;
    double? batchDrift;
    if (embedBatch != null) {
      final sw = Stopwatch()..start();
      final batched = await embedBatch!(texts);
      sw.stop();
      batchMs = sw.elapsedMilliseconds;
      if (batched.length != texts.length) {
        warnings.add('批量返回 ${batched.length} 条，输入 ${texts.length} 条：批量接口错位');
      } else {
        var worst = 0.0;
        for (var i = 0; i < texts.length; i++) {
          final single = singles[texts[i]]!;
          if (batched[i].length != single.length) {
            warnings.add(
              '批量第 $i 条维度 ${batched[i].length} 与单条 ${single.length} 不同',
            );
            continue;
          }
          final drift = 1 - cosineSimilarity(batched[i], single);
          if (drift.abs() > worst.abs()) worst = drift;
        }
        batchDrift = worst;
        if (worst.abs() > 1e-3) {
          warnings.add('批量与单条结果偏差 ${worst.toStringAsFixed(6)}：批量实现和单条不等价');
        }
      }
    }

    final pairs = <PairScore>[
      for (final p in probes)
        PairScore(
          pair: p,
          cosine: cosineSimilarity(singles[p.a]!, singles[p.b]!),
        ),
    ];
    for (final s in pairs) {
      if (s.suspicious) {
        warnings.add(
          '探针「${s.pair.label}」${s.cosine.toStringAsFixed(3)} 不符合 ${s.pair.expect.name} 预期',
        );
      }
    }

    final plain = await embed(_query);
    final instructed = await embed('$instruction$_query');
    final plainTop = _topMatch(plain, singles);
    final instructionTop = _topMatch(instructed, singles);
    final fixed = probes.first.a;

    if (singleAvgMs > 200) {
      warnings.add('单条平均 $singleAvgMs ms 太慢：检索必须异步，不能挡在出字前');
    }

    return CalibrationReport(
      modelLabel: modelLabel.isEmpty ? '未命名模型' : modelLabel,
      dim: dim,
      expectedDim: expectedDim,
      warmupMs: warmupMs,
      singleAvgMs: singleAvgMs,
      singleCount: texts.length,
      batchMs: batchMs,
      rawNorm: rawNorm,
      selfSim: selfSim,
      batchDrift: batchDrift,
      pairs: pairs,
      plainTop: plainTop,
      instructionTop: instructionTop,
      querySimPlain: cosineSimilarity(plain, singles[fixed]!),
      querySimInstruct: cosineSimilarity(instructed, singles[fixed]!),
      warnings: warnings,
      notes: notes,
    );
  }

  /// 在探针句子里找最像查询的一条，返回「句子（分数）」。
  String? _topMatch(Float32List query, Map<String, Float32List> singles) {
    String? best;
    var bestScore = -2.0;
    for (final e in singles.entries) {
      final s = cosineSimilarity(query, e.value);
      if (s > bestScore) {
        bestScore = s;
        best = e.key;
      }
    }
    if (best == null) return null;
    return '$best（${bestScore.toStringAsFixed(4)}）';
  }
}
