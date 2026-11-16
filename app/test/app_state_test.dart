import 'dart:async';

import 'package:ragchat/app/app_state.dart';
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
