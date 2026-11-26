import 'dart:async';
import 'dart:typed_data';

import '../chat/app_db.dart';
import 'model_gateway.dart';
import 'vector_math.dart';

/// 记忆嵌入服务（ADR-0016 第 2 步）。
///
/// 只做三件事：后台补齐待补向量、给出检索投影、编码查询。
///
/// 铁律：任何失败都只降级，绝不把异常抛给聊天主路径（ADR-0016 决策 6）。
/// 嵌入是「锦上添花」，模型坏了最多退回纯重要度排序，不能连聊天一起挂。
class EmbeddingService {
  EmbeddingService({
    required this.db,
    required this.gateway,
    required this.modelId,
    this.batchSize = 16,
    this.log,
  });

  final AppDb db;

  /// 惰性取网关：没装嵌入模型时返回 null，而不是让调用方先判断。
  final Future<EmbedGateway?> Function() gateway;

  /// 向量归属（生产为嵌入模型文件路径），换模型后旧向量会自动作废。
  final String modelId;

  final int batchSize;
  final void Function(String)? log;

  Future<int>? _inFlight;

  /// 补齐待补向量，返回本次写入条数。
  ///
  /// 并发调用复用同一个 Future：切页面、导入、提取同时触发也只跑一轮。
  Future<int> backfill() {
    return _inFlight ??= _runBackfill().whenComplete(() => _inFlight = null);
  }

  Future<int> _runBackfill() async {
    var written = 0;
    final attempted = <String>{};
    try {
      while (true) {
        final pending = await db.memoriesNeedingEmbedding(
          modelId,
          limit: batchSize,
        );
        if (pending.isEmpty) break;
        // 没有进展就收手，避免「写不进去又一直查得到」的死循环。
        if (pending.every((m) => attempted.contains(m.id))) {
          log?.call('补算无进展，停止本轮（已写 $written 条）');
          break;
        }
        attempted.addAll(pending.map((m) => m.id));

        // 只在真有待补时才加载编码器：没有待补就不该付 787 ms 的加载成本。
        final gw = await gateway();
        if (gw == null) {
          log?.call('嵌入网关不可用，本轮补算跳过');
          break;
        }

        final vectors = await gw.embedBatch([
          for (final m in pending) m.content,
        ]);
        if (vectors.length != pending.length) {
          // 标定量的就是这个等价性；错位时整批作废，绝不写错位向量。
          log?.call(
            '批量返回 ${vectors.length} 条 / 输入 ${pending.length} 条：本轮作废',
          );
          break;
        }
        for (var i = 0; i < pending.length; i++) {
          await db.setMemoryEmbedding(
            pending[i].id,
            vectors[i],
            modelId: modelId,
          );
          written++;
        }
        if (pending.length < batchSize) break;
      }
    } catch (e) {
      // 加载失败、OOM、原生异常全在这里落地：日志留痕，向上无声。
      log?.call('补算中止：$e');
    }
    if (written > 0) log?.call('向量补算完成：$written 条（$modelId）');
    return written;
  }

  /// 检索投影：当前模型的 active 向量（已归一化）。读失败返回空表。
  Future<List<MemoryVector>> loadIndex() async {
    try {
      return await db.memoryVectors(modelId);
    } catch (e) {
      log?.call('读取向量失败：$e');
      return const [];
    }
  }

  /// 编码查询串，返回归一化向量；不可用/失败返回 null（调用方回退）。
  Future<Float32List?> embedQuery(String question) async {
    final text = question.trim();
    if (text.isEmpty) return null;
    try {
      final gw = await gateway();
      if (gw == null) return null;
      return normalized(await gw.embed(text));
    } catch (e) {
      log?.call('查询编码失败：$e');
      return null;
    }
  }
}
