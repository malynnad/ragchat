import 'dart:io';
import 'dart:typed_data';

import 'package:ragchat/chat/app_db.dart';
import 'package:ragchat/rag/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// ADR-0009 schema v3：memories/sessions/turns CRUD + v2→v3 迁移。
/// 迁移测试沿用 store_migration_test 的独立真相源模式：手写 v2 schema 与数据。
void main() {
  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppDb> openMem() async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
    );
    return AppDb.fromDatabase(db);
  }

  group('memories CRUD', () {
    test('upsert 覆盖同 id，activeMemories 按 importance 降序、同分按更新时间', () async {
      final store = await openMem();
      addTearDown(store.close);

      final old = DateTime(2026, 1, 1);
      await store.upsertMemory(
        MemoryEntry(id: 'a', content: '低重要度', importance: 1, updatedAt: old),
      );
      await store.upsertMemory(
        MemoryEntry(id: 'b', content: '高重要度', importance: 5, updatedAt: old),
      );
      await store.upsertMemory(
        MemoryEntry(
          id: 'c',
          content: '中重要度-更新',
          importance: 3,
          updatedAt: DateTime(2026, 11, 16),
        ),
      );
      await store.upsertMemory(
        MemoryEntry(id: 'd', content: '中重要度-更旧', importance: 3, updatedAt: old),
      );
      await store.upsertMemory(
        MemoryEntry(id: 'e', content: '停用条目', importance: 5, active: false),
      );

      final active = await store.activeMemories();
      expect(active.map((m) => m.id).toList(), [
        'b',
        'c',
        'd',
        'a',
      ], reason: '停用的 e 不出现；同分时新更新在前');
      expect(await store.memoryCount(), 4);

      await store.upsertMemory(
        MemoryEntry(id: 'b', content: '高重要度-改写', importance: 5),
      );
      expect(
        (await store.activeMemories()).first.content,
        '高重要度-改写',
        reason: '同 id 再 upsert 为覆盖',
      );
      expect(await store.memoryCount(), 4, reason: '覆盖不新增');
    });

    test('kind 往返、停用后 allMemories 可见、删除', () async {
      final store = await openMem();
      addTearDown(store.close);
      await store.upsertMemory(
        MemoryEntry(
          id: 'm1',
          content: '用户对猫过敏',
          kind: MemoryKind.preference,
          importance: 4,
          source: 'sess-1',
        ),
      );
      await store.upsertMemory(
        MemoryEntry(id: 'm2', content: '用户养了狗', kind: MemoryKind.relation),
      );

      var m1 = await store.memory('m1');
      expect(m1!.kind, MemoryKind.preference);
      expect(m1.source, 'sess-1');
      expect(m1.active, isTrue);

      await store.deactivateMemory('m1');
      expect(await store.memoryCount(), 1);
      m1 = await store.memory('m1');
      expect(m1!.active, isFalse, reason: '停用是标记不是删除');
      expect((await store.allMemories()).length, 2, reason: '记忆页含停用条目');

      await store.deleteMemory('m1');
      expect(await store.memory('m1'), isNull);
    });
  });

  group('sessions/turns', () {
    test('追加轮次自动编号升序，latestSession 取最近活跃', () async {
      final store = await openMem();
      addTearDown(store.close);

      final s1 = await store.createSession();
      await store.appendTurn(s1.id, _turn('我叫Danny', '你好Danny！'));
      await store.appendTurn(s1.id, _turn('我在用Mac', '了解了'));

      final s2 = await store.createSession();
      expect((await store.latestSession())!.id, s2.id, reason: '新建会话成为最近会话');

      await store.appendTurn(s2.id, _turn('新话题', '好的'));
      expect((await store.latestSession())!.id, s2.id);

      final turns = await store.sessionTurns(s1.id);
      expect(turns.map((t) => t.question).toList(), [
        '我叫Danny',
        '我在用Mac',
      ], reason: '按 turn_index 升序恢复');

      await store.deleteAllSessions();
      expect(await store.latestSession(), isNull);
      expect(await store.sessionTurns(s1.id), isEmpty, reason: '清会话不影响记忆');
    });
  });

  group('v2→v3 迁移（RAG 版覆盖安装）', () {
    test('旧 RAG 数据完好，新表就位可写', () async {
      final dir = await Directory.systemTemp.createTemp('chat_migration');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/rag.db';

      // 手写 v2 schema 作独立真相源（与被测建表语句无关）。
      final v2 = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE documents(
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                format TEXT NOT NULL,
                chunk_count INTEGER NOT NULL,
                ingested_at INTEGER NOT NULL,
                content BLOB,
                category TEXT NOT NULL DEFAULT '未分类'
              )''');
            await db.execute('''
              CREATE TABLE chunks(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                doc_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
                chunk_index INTEGER NOT NULL,
                text TEXT NOT NULL,
                vector BLOB NOT NULL
              )''');
            await db.execute('CREATE INDEX idx_chunks_doc ON chunks(doc_id)');
            await db.execute(
              'CREATE TABLE categories(name TEXT PRIMARY KEY, created_at INTEGER NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
            );
          },
        ),
      );
      final vec = Float32List.fromList([1, 0, 0, 0]);
      await v2.insert('documents', {
        'id': 'doc-1',
        'name': '旧知识源.txt',
        'format': 'txt',
        'chunk_count': 1,
        'ingested_at': 1700000000000,
        'category': '历史',
      });
      await v2.insert('chunks', {
        'doc_id': 'doc-1',
        'chunk_index': 0,
        'text': '旧分块',
        'vector': vec.buffer.asUint8List(),
      });
      await v2.insert('meta', {'key': 'vector_dim', 'value': '256'});
      await v2.close();

      final db = await AppDb.openFile(path);

      // 新表可写。
      await db.upsertMemory(
        MemoryEntry(id: 'mem-1', content: '用户从 RAG 版迁移过来', importance: 4),
      );
      expect(await db.memoryCount(), 1);
      final s = await db.createSession();
      await db.appendTurn(s.id, _turn('你好', '你好！'));
      expect((await db.sessionTurns(s.id)).single.question, '你好');
      await db.close();

      // 旧表数据不动（ADR-0009：代码删、数据留）。
      final check = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      final docs = await check.query('documents');
      expect(docs.single['name'], '旧知识源.txt');
      expect(docs.single['category'], '历史');
      expect((await check.query('chunks')).single['text'], '旧分块');
      expect((await check.query('meta')).single['value'], '256');
      await check.close();
    });

    test('v3 schema 幂等：重复构造不报错、不丢数据', () async {
      final raw = await databaseFactoryFfiNoIsolate.openDatabase(
        inMemoryDatabasePath,
      );
      final db = await AppDb.fromDatabase(raw);
      await db.upsertMemory(MemoryEntry(id: 'x', content: '幂等'));
      final again = await AppDb.fromDatabase(raw); // 第二次全量建表路径
      expect(await again.memoryCount(), 1, reason: '重复建表不丢数据');
      await again.close();
    });
  });
}

SessionTurn _turn(String q, String a) => SessionTurn(question: q, answer: a);
