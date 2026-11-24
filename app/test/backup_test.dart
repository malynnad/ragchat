import 'dart:convert';
import 'dart:typed_data';

import 'package:ragchat/app/backup.dart';
import 'package:ragchat/app/settings.dart';
import 'package:ragchat/chat/app_db.dart';
import 'package:ragchat/rag/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
  });

  test('导出再导入：会话、轮次、记忆、设置都能回来', () async {
    final src = await openTestDb(inIsolate: false);
    addTearDown(src.close);
    final session = await src.createSession();
    await src.appendTurn(session.id, const SessionTurn(question: '在吗', answer: '在呢'));
    await src.appendTurn(session.id, const SessionTurn(question: '吃了吗', answer: '吃了'));
    await src.upsertMemory(
      MemoryEntry(id: 'm1', content: '用户叫 Danny', importance: 5),
    );

    final settings = AppSettings(
      temperature: 0.4,
      ttsRate: 0.65,
      backend: 'cloud',
      cloudModel: 'deepseek-flash',
      personasJson: '[]',
    );

    final bytes = await buildBackup(
      db: src,
      settings: settings,
      appVersion: '1.3.0',
    );
    final preview = inspectBackup(bytes);
    expect(preview.sessions, 1);
    expect(preview.turns, 2);
    expect(preview.memories, 1);

    final dst = await openTestDb(inIsolate: false);
    addTearDown(dst.close);
    final dstSettings = AppSettings();
    final applied = await applyBackup(
      bytes: bytes,
      db: dst,
      settings: dstSettings,
    );

    expect(applied.turns, 2);
    final sessions = await dst.dumpSessions();
    expect(sessions.length, 1);
    expect((sessions.first['turns'] as List).length, 2);
    final memories = await dst.allMemories();
    expect(memories.single.content, '用户叫 Danny');
    expect(memories.single.importance, 5);

    expect(dstSettings.temperature, 0.4);
    expect(dstSettings.ttsRate, 0.65);
    expect(dstSettings.backend, 'cloud');
    expect(dstSettings.cloudModel, 'deepseek-flash');
  });

  test('导入会覆盖已有数据，不是追加', () async {
    // 同一个内存库：先导出「新」，再往库里塞「旧」，导入后应只剩备份里的「新」。
    final db = await openTestDb(inIsolate: false);
    addTearDown(db.close);
    final s = await db.createSession();
    await db.appendTurn(s.id, const SessionTurn(question: '新', answer: '新'));
    final bytes = await buildBackup(
      db: db,
      settings: AppSettings(),
      appVersion: '1.3.0',
    );

    final old = await db.createSession();
    await db.appendTurn(old.id, const SessionTurn(question: '旧', answer: '旧'));
    expect((await db.dumpSessions()).length, 2);

    await applyBackup(bytes: bytes, db: db, settings: AppSettings());
    final sessions = await db.dumpSessions();
    expect(sessions.length, 1);
    final turns = sessions.first['turns'] as List;
    expect((turns.first as Map)['question'], '新');
  });

  test('备份里不含 API key', () async {
    final db = await openTestDb(inIsolate: false);
    addTearDown(db.close);
    final settings = AppSettings()..cloudBaseUrl = 'https://api.deepseek.com';
    final bytes = await buildBackup(
      db: db,
      settings: settings,
      appVersion: '1.3.0',
    );
    final text = utf8.decode(bytes, allowMalformed: true);
    expect(text.contains('apiKey'), isFalse);
    expect(text.contains('API key'), isFalse);
  });

  test('坏文件与陌生格式会被拒绝', () async {
    expect(
      () => inspectBackup(Uint8List.fromList(utf8.encode('not a zip'))),
      throwsA(isA<FormatException>()),
    );
  });
}
