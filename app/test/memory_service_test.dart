import 'package:ragchat/chat/app_db.dart';
import 'package:ragchat/chat/memory_service.dart';
import 'package:ragchat/rag/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'fakes/fake_gateway.dart';

/// US-20 记忆提取：入库 / 去重 / 停用 / 坏 JSON 丢弃 / prompt 结构。
void main() {
  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
  });

  late AppDb db;
  late FakeGateway gateway;
  late MemoryService service;

  setUp(() async {
    final raw = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
    );
    db = await AppDb.fromDatabase(raw);
    gateway = FakeGateway();
    service = MemoryService(db, gateway);
  });
  tearDown(() => db.close());

  SessionTurn turn(String q, String a) => SessionTurn(question: q, answer: a);

  test('add：解析 JSON 入库，kind/importance/source 正确', () async {
    gateway.nextResponse =
        '{"add":[{"content":"用户叫Danny","kind":"fact","importance":5}]}';
    final n = await service.extractFromTurns([
      turn('我叫什么名字？', '你叫Danny。'),
    ], sessionId: 's-1');

    expect(n, 1);
    final mem = (await db.activeMemories()).single;
    expect(mem.content, '用户叫Danny');
    expect(mem.kind, MemoryKind.fact);
    expect(mem.importance, 5);
    expect(mem.source, 's-1');
  });

  test('prompt：含已有记忆、对话与格式规则', () async {
    await db.upsertMemory(MemoryEntry(id: 'm1', content: '用户在用Mac'));
    gateway.nextResponse = '{"add":[]}';
    await service.extractFromTurns([turn('我用什么电脑？', 'Mac。')]);

    final prompt = gateway.lastMessages!.single.content;
    expect(prompt, contains('[m1] 用户在用Mac'), reason: '已有条目进 prompt 防重复');
    expect(prompt, contains('用户：我用什么电脑？'));
    expect(prompt, contains('"add"'));
    expect(prompt, contains('fact/preference/event/relation'));
  });

  test('去重：与已有条目 bigram 相似度过阈值 → update 而非 add', () async {
    await db.upsertMemory(
      MemoryEntry(id: 'old', content: '用户住在上海', importance: 3),
    );
    gateway.nextResponse =
        '{"add":[{"content":"用户现在住在上海","kind":"fact","importance":4}]}';
    final n = await service.extractFromTurns([turn('我住哪？', '上海。')]);

    expect(n, 1, reason: '去重后走 update，只写一条');
    final mem = await db.memory('old');
    expect(mem!.content, '用户现在住在上海');
    expect(mem.importance, 4);
    expect(await db.memoryCount(), 1, reason: '不新增堆积');
  });

  test('deactivate：矛盾事实显式停用，旧条目保留可追溯', () async {
    await db.upsertMemory(MemoryEntry(id: 'm1', content: '用户喜欢猫'));
    gateway.nextResponse =
        '{"add":[{"content":"用户对猫过敏，不喜欢猫了"}],"deactivate":["m1"]}';
    await service.extractFromTurns([turn('我现在对猫过敏', '明白了。')]);

    final old = await db.memory('m1');
    expect(old!.active, isFalse, reason: '被取代置 active=0 不物理删除');
    expect((await db.activeMemories()).single.content, '用户对猫过敏，不喜欢猫了');
  });

  test('update：按 id 改写，未知/已停用 id 忽略', () async {
    await db.upsertMemory(MemoryEntry(id: 'm1', content: '用户用1.7B模型'));
    await db.upsertMemory(
      MemoryEntry(id: 'dead', content: '已停用', active: false),
    );
    gateway.nextResponse = '{"update":[{"id":"m1","content":"用户换用4B模型"},{"id":"ghost","content":"不存在"},{"id":"dead","content":"停用条目"}]}';
    await service.extractFromTurns([turn('', '')]);

    expect((await db.memory('m1'))!.content, '用户换用4B模型');
    expect((await db.memory('dead'))!.content, '已停用', reason: '停用条目不改');
    expect(await db.memory('ghost'), isNull);
  });

  test('update 只给 importance 时保留原内容与 kind', () async {
    await db.upsertMemory(
      MemoryEntry(
        id: 'm1',
        content: '用户喜欢茶',
        kind: MemoryKind.preference,
        importance: 3,
      ),
    );
    gateway.nextResponse = '{"update":[{"id":"m1","importance":5}]}';

    final n = await service.extractFromTurns([turn('我更喜欢茶', '记住了。')]);

    final mem = await db.memory('m1');
    expect(n, 1);
    expect(mem!.content, '用户喜欢茶');
    expect(mem.kind, MemoryKind.preference);
    expect(mem.importance, 5);
  });

  group('容错：坏输出静默丢弃，绝不写脏数据', () {
    for (final (name, reply) in [
      ('纯文本', '我觉得用户挺喜欢聊天的。'),
      ('缺字段 JSON', '{"新增":[{"content":"x"}]}'),
      ('截断 JSON', '{"add":[{"content":"用'),
      ('空列表', '{"add":[],"update":[],"deactivate":[]}'),
    ]) {
      test(name, () async {
        gateway.nextResponse = reply;
        final n = await service.extractFromTurns([turn('聊点别的', '好的。')]);
        expect(n, 0);
        expect(await db.allMemories(), isEmpty);
      });
    }
  });

  test('围栏 JSON（```json 包裹）可解析', () async {
    gateway.nextResponse =
        '好的，我提取如下：\n```json\n{"add":[{"content":"用户会写Dart"}]}\n```';
    final n = await service.extractFromTurns([turn('我会Dart', '真棒。')]);
    expect(n, 1);
    expect((await db.activeMemories()).single.content, '用户会写Dart');
  });

  test('空轮次不发起调用', () async {
    final n = await service.extractFromTurns([]);
    expect(n, 0);
    expect(gateway.lastMessages, isNull, reason: '未触发模型');
  });

  test('超长对话只取尾部 maxTurnsPerRun 轮', () async {
    gateway.nextResponse = '{"add":[]}';
    final turns = [for (var i = 0; i < 10; i++) turn('问题$i', '答案$i')];
    await service.extractFromTurns(turns);

    final prompt = gateway.lastMessages!.single.content;
    expect(prompt, contains('问题9'), reason: '取最新轮');
    expect(prompt, isNot(contains('问题0')), reason: '早期轮被截断');
  });
}
