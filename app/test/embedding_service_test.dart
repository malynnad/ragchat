import 'dart:typed_data';

import 'package:ragchat/chat/app_db.dart';
import 'package:ragchat/rag/embedding_service.dart';
import 'package:ragchat/rag/model_gateway.dart';
import 'package:ragchat/rag/vector_math.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// 可编程的假网关：能装坏、能错位、能计次，用来验证「降级」而不是「模型质量」。
class _FakeGateway implements EmbedGateway {
  _FakeGateway({
    this.dim = 4,
    this.fail = false,
    this.shortenBatch = false,
    this.delay = Duration.zero,
  });

  final int dim;
  final bool fail;

  /// 批量少返回一条：模拟错位（标定量过 encode/encodeBatch 等价性）。
  final bool shortenBatch;
  final Duration delay;

  int embedCalls = 0;
  int batchCalls = 0;

  @override
  String get embedModelId => 'fake';

  Float32List _vec(String text) {
    final v = Float32List(dim);
    for (final r in text.runes) {
      v[r % dim] += 3; // 故意不归一化：服务/pipeline 必须自己归一化
    }
    v[0] += 1;
    return v;
  }

  @override
  Future<Float32List> embed(String text) async {
    embedCalls++;
    if (fail) throw StateError('boom');
    return _vec(text);
  }

  @override
  Future<List<Float32List>> embedBatch(List<String> texts) async {
    batchCalls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (fail) throw StateError('boom');
    final out = [for (final t in texts) _vec(t)];
    if (shortenBatch && out.length > 1) return out.sublist(0, out.length - 1);
    return out;
  }
}

void main() {
  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppDb> openStore() async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
    );
    return AppDb.fromDatabase(db);
  }

  Future<void> seed(AppDb store, int n) async {
    for (var i = 1; i <= n; i++) {
      await store.upsertMemory(
        MemoryEntry(id: 'm$i', content: '事实$i', importance: i),
      );
    }
  }

  EmbeddingService service(
    AppDb store, {
    required Future<EmbedGateway?> Function() gateway,
    String modelId = 'model-a',
    int batchSize = 16,
  }) => EmbeddingService(
    db: store,
    gateway: gateway,
    modelId: modelId,
    batchSize: batchSize,
  );

  test('补齐全部待补向量，再跑一次就是 0（幂等）', () async {
    final store = await openStore();
    addTearDown(store.close);
    await seed(store, 3);
    final gw = _FakeGateway();
    final svc = service(store, gateway: () async => gw);

    expect(await svc.backfill(), 3);
    expect(await store.pendingEmbeddingCount('model-a'), 0);
    expect(await svc.backfill(), 0);
    expect(gw.batchCalls, 1, reason: '第二轮没有待补，不该再调批量编码');

    final index = await svc.loadIndex();
    expect(index, hasLength(3));
    expect(l2Norm(index.first.vector), closeTo(1, 1e-6));
  });

  test('没有待补就不加载编码器（省钱也省 787 ms）', () async {
    final store = await openStore();
    addTearDown(store.close);
    var gatewayAsked = 0;
    final svc = service(
      store,
      gateway: () async {
        gatewayAsked++;
        return _FakeGateway();
      },
    );
    expect(await svc.backfill(), 0);
    expect(gatewayAsked, 0);
  });

  test('网关不可用（没装嵌入模型）→ 0 条，不抛错', () async {
    final store = await openStore();
    addTearDown(store.close);
    await seed(store, 2);
    final svc = service(store, gateway: () async => null);
    expect(await svc.backfill(), 0);
    expect(await store.pendingEmbeddingCount('model-a'), 2);
  });

  test('编码抛错 → 静默降级，条目仍待补（不写脏数据）', () async {
    final store = await openStore();
    addTearDown(store.close);
    await seed(store, 2);
    final svc = service(store, gateway: () async => _FakeGateway(fail: true));
    expect(await svc.backfill(), 0);
    expect(await store.pendingEmbeddingCount('model-a'), 2);
    expect(await svc.loadIndex(), isEmpty);
  });

  test('批量条数错位 → 整批作废，绝不写错位向量', () async {
    final store = await openStore();
    addTearDown(store.close);
    await seed(store, 4);
    final svc = service(
      store,
      gateway: () async => _FakeGateway(shortenBatch: true),
      batchSize: 4,
    );
    expect(await svc.backfill(), 0);
    expect(await store.pendingEmbeddingCount('model-a'), 4);
  });

  test('换模型（modelId 不同）→ 全量重算', () async {
    final store = await openStore();
    addTearDown(store.close);
    await seed(store, 2);
    expect(
      await service(store, gateway: () async => _FakeGateway()).backfill(),
      2,
    );
    final other = service(
      store,
      gateway: () async => _FakeGateway(),
      modelId: 'model-b',
    );
    expect(await other.backfill(), 2);
    expect(await store.pendingEmbeddingCount('model-b'), 0);
    // 一条记忆只有一个向量列：换模型是原地覆盖，不是并存两套。
    // 所以对旧模型而言这些条目重新变成「待补」，而不是留着旧向量蒙混。
    expect(await store.memoryVectors('model-a'), isEmpty);
    expect(await store.pendingEmbeddingCount('model-a'), 2);
  });

  test('分批补齐：batchSize=2 时多轮跑完', () async {
    final store = await openStore();
    addTearDown(store.close);
    await seed(store, 5);
    final gw = _FakeGateway();
    final svc = service(store, gateway: () async => gw, batchSize: 2);
    expect(await svc.backfill(), 5);
    expect(gw.batchCalls, 3, reason: '2+2+1');
  });

  test('并发触发只跑一轮', () async {
    final store = await openStore();
    addTearDown(store.close);
    await seed(store, 2);
    final gw = _FakeGateway(delay: const Duration(milliseconds: 20));
    final svc = service(store, gateway: () async => gw);
    final results = await Future.wait([svc.backfill(), svc.backfill()]);
    expect(results, [2, 2]);
    expect(gw.batchCalls, 1);
  });

  test('embedQuery：归一化、空串 null、异常 null', () async {
    final store = await openStore();
    addTearDown(store.close);
    final ok = service(store, gateway: () async => _FakeGateway());
    final q = await ok.embedQuery('我住在哪');
    expect(q, isNotNull);
    expect(l2Norm(q!), closeTo(1, 1e-6));
    expect(await ok.embedQuery('   '), isNull);

    final broken = service(store, gateway: () async => _FakeGateway(fail: true));
    expect(await broken.embedQuery('我住在哪'), isNull);
  });
}
