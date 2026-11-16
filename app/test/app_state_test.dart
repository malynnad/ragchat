import 'dart:async';
import 'dart:io';

import 'package:ragchat/app/app_state.dart';
import 'package:ragchat/app/settings.dart';
import 'package:ragchat/chat/chat_service.dart';
import 'package:ragchat/rag/model_gateway.dart';
import 'package:ragchat/rag/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
  });

  test('新对话的记忆提取失败不会留下未处理异步异常', () async {
    final db = await openTestDb();
    addTearDown(db.close);
    final state = AppState();
    state.debugDb = db;
    state.debugServiceFactory = () async =>
        ChatService(gateway: _ThrowingGateway());
    state.sessionTurns.add(
      const SessionTurn(question: '我叫Danny', answer: '你好，Danny。'),
    );

    final errors = <Object>[];
    await runZonedGuarded(() async {
      await state.startNewConversation();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }, (error, stack) => errors.add(error));

    expect(errors, isEmpty);
    expect(state.sessionTurns, isEmpty);
    expect(state.currentSessionId, isNotNull);
  });

  test('恢复最新会话及其完整轮次', () async {
    final db = await openTestDb();
    addTearDown(db.close);
    final oldSession = await db.createSession();
    await db.appendTurn(
      oldSession.id,
      const SessionTurn(question: '旧问题', answer: '旧答案'),
    );
    final latest = await db.createSession();
    await db.appendTurn(
      latest.id,
      const SessionTurn(question: '新问题', answer: '新答案'),
    );

    final state = AppState();
    state.debugDb = db;
    await state.restoreLatestSession();

    expect(state.currentSessionId, latest.id);
    expect(state.sessionTurns.single.question, '新问题');
    expect(state.sessionTurns.single.answer, '新答案');
  });

  test('人设：新建→编辑→落盘→删除，且至少保留一张', () async {
    final dir = await Directory.systemTemp.createTemp('ragchat-persona');
    addTearDown(() => dir.delete(recursive: true));
    final state = AppState();
    state.debugSupportDir = dir.path;
    expect(state.settings.personas().length, 3, reason: '默认三张内置预设');

    final created = await state.createPersona();
    expect(state.activePersonaCard().id, created.id);
    expect(state.settings.personas().length, 4);

    await state.upsertPersona(created.copyWith(name: '阿鱼', personality: '话少'));
    expect(state.activePersonaCard().name, '阿鱼');
    expect(state.systemPrompt(), contains('你是阿鱼'));

    // 落盘：重新读 settings.json 拿到改过的卡与激活 id。
    final reloaded = await AppSettings.load(dir.path);
    final saved = reloaded.personas().firstWhere((c) => c.id == created.id);
    expect(saved.name, '阿鱼');
    expect(saved.personality, '话少');
    expect(reloaded.activePersonaId, created.id);

    // 删掉激活卡 → 回退第一张。
    expect(await state.deletePersona(created.id), isNull);
    expect(state.settings.personas().length, 3);
    expect(state.activePersonaCard().id, state.settings.personas().first.id);

    // 删到只剩一张：拒绝再删。
    for (final c in state.settings.personas().skip(1).toList()) {
      await state.deletePersona(c.id);
    }
    expect(state.settings.personas().length, 1);
    expect(
      await state.deletePersona(state.settings.personas().single.id),
      '至少保留一张人设',
    );
  });
}

class _ThrowingGateway implements ChatGateway {
  @override
  Stream<String> generate(List<ChatMessage> messages) async* {
    throw StateError('model failed');
  }

  @override
  Future<void> resetSession() async {}

  @override
  void stopGeneration() {}

  @override
  Future<void> dispose() async {}
}
