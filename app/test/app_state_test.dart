import 'dart:async';
import 'dart:io';

import 'package:ragchat/app/app_state.dart';
import 'package:ragchat/app/persona.dart';
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

  test('人设：单卡编辑即落盘，system 用新正文，可恢复默认', () async {
    final dir = await Directory.systemTemp.createTemp('ragchat-persona');
    addTearDown(() => dir.delete(recursive: true));
    final state = AppState();
    state.debugSupportDir = dir.path;

    final base = state.activePersonaCard();
    expect(base.name, '小助', reason: '默认内置第一张');

    await state.savePersona(
      base.copyWith(name: '阿鱼', text: '你是阿鱼，话少。'),
    );
    expect(state.activePersonaCard().name, '阿鱼');
    expect(state.systemPrompt(), contains('你是阿鱼，话少。'));

    // 落盘只有一张，正文就是刚写的那段。
    final reloaded = await AppSettings.load(dir.path);
    expect(reloaded.personas().length, 1);
    expect(reloaded.personas().single.name, '阿鱼');
    expect(reloaded.personas().single.text, '你是阿鱼，话少。');
    expect(reloaded.activePersonaId, base.id);

    await state.resetPersona();
    expect(state.activePersonaCard().text, builtinPersonas.first.text);
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
