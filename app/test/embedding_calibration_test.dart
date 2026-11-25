import 'dart:typed_data';

import 'package:ragchat/rag/embedding_calibration.dart';
import 'package:test/test.dart';

/// 假的词袋嵌入：确定性、未归一化，用来验证标定的算术与判定，
/// 不验证模型质量（那要在真机上跑）。
Float32List _bagOfChars(String text, {int dim = 16, double scale = 3}) {
  final v = Float32List(dim);
  for (final r in text.runes) {
    v[r % dim] += 1;
  }
  for (var i = 0; i < dim; i++) {
    v[i] *= scale;
  }
  return v;
}

EmbeddingCalibration _harness({
  int dim = 16,
  int? expectedDim,
  EmbedBatchFn? batch,
  void Function(String)? onText,
}) {
  return EmbeddingCalibration(
    embed: (t) async {
      onText?.call(t);
      return _bagOfChars(t, dim: dim);
    },
    embedBatch: batch,
    modelLabel: 'fake.gguf',
    expectedDim: expectedDim ?? dim,
  );
}

void main() {
  test('跑通全部探针：维度、范数、一致性、批量偏差都量到', () async {
    final report = await _harness().run();

    expect(report.dim, 16);
    expect(report.dimOk, isTrue);
    expect(report.modelLabel, 'fake.gguf');
    // 假向量被 ×3 放大过，所以原始范数应明显大于 1
    expect(report.rawNorm, greaterThan(1));
    expect(report.selfSim, closeTo(1, 1e-6));
    expect(report.batchDrift, isNull, reason: '没给批量实现就不该有偏差值');
    expect(report.pairs.length, EmbeddingCalibration.probes.length);
    expect(report.plainTop, isNotNull);
    expect(report.instructionTop, isNotNull);
    expect(report.querySimPlain, isNotNull);
    expect(report.notes.any((n) => n.contains('未归一化')), isTrue);
  });

  test('维度不符 → 报警告并判 ok=false', () async {
    final report = await _harness(expectedDim: 1024).run();
    expect(report.dimOk, isFalse);
    expect(report.ok, isFalse);
    expect(report.warnings.any((w) => w.contains('维度')), isTrue);
  });

  test('批量与单条不等价 → 报偏差', () async {
    final report = await _harness(
      batch: (texts) async => [
        for (final t in texts) _bagOfChars(t, dim: 16, scale: 3),
      ],
    ).run();
    // 同一套算法 → 偏差应接近 0，不报警
    expect(report.batchDrift, closeTo(0, 1e-6));
    expect(report.warnings.any((w) => w.contains('批量')), isFalse);

    final broken = await _harness(
      batch: (texts) async => [for (final _ in texts) Float32List(16)],
    ).run();
    expect(broken.batchDrift, closeTo(1, 1e-6));
    expect(broken.warnings.any((w) => w.contains('批量')), isTrue);
  });

  test('批量条数对不上 → 直接判错位，不用长度不一的列表硬算', () async {
    final report = await _harness(
      batch: (texts) async => [_bagOfChars(texts.first)],
    ).run();
    expect(report.warnings.any((w) => w.contains('错位')), isTrue);
    expect(report.batchDrift, isNull);
  });

  test('嵌入抛错要原样抛出，不能包装成 0 分', () async {
    final harness = EmbeddingCalibration(
      embed: (t) async => throw StateError('未安装嵌入模型'),
      expectedDim: 16,
    );
    expect(harness.run(), throwsStateError);
  });

  test('探针句子去重后再嵌入：除同句一致性探针外每句只算一次', () async {
    final seen = <String>[];
    await _harness(onText: seen.add).run();
    final probe = seen.where(EmbeddingCalibration.probeTexts.contains).toList();
    // 首句被刻意嵌入三次：预热、复算一致性、批量对照。
    expect(probe.toSet().length, EmbeddingCalibration.probeTexts.length);
    expect(probe.length - probe.toSet().length, 2, reason: '只有「我住在杭州。」该重复出现');
  });

  test('markdown 报告含结论与探针表，空警告写「无」', () async {
    final md = (await _harness().run()).toMarkdown();
    expect(md, contains('## 嵌入标定报告'));
    expect(md, contains('维度：16（期望 16）'));
    expect(md, contains('| 探针 | 档位 | 余弦 | 判定 |'));
    expect(md, contains('### 指令前缀'));
    expect(md, contains('### 警告'));
  });
}
