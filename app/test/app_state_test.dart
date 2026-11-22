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

  test('没有模型也能「稍后配置」进主界面', () async {
    final dir = await Directory.systemTemp.createTemp('ragchat-skip');
    addTearDown(() => dir.delete(recursive: true));
    final state = AppState();
    state.debugSupportDir = dir.path;

    expect(state.entered, isFalse);
    await state.skipModelSetup();
    expect(state.entered, isTrue);
    expect(state.settings.skipModelSetup, isTrue);

    // 之后配好模型再确认，跳过标记会被清掉。
    final model = File('${dir.path}/fake.gguf')..writeAsStringSync('x');
    state.settings.chatModelPath = model.path;
    await state.confirmModels();
    expect(state.settings.skipModelSetup, isFalse);
    expect(state.entered, isTrue);
  });

  test('本地历史只带最近 N 轮且在 token 预算内', () async {
    final state = AppState();
    for (var i = 1; i <= 15; i++) {
      state.sessionTurns.add(
        SessionTurn(
          question: '第$i轮问题',
          answer: '第$i轮回答' * 20,
        ),
      );
    }
    final r = state.promptHistory(maxTokens: 300, maxTurns: 10);
    expect(r.length, lessThanOrEqualTo(10));
    expect(r.isNotEmpty, isTrue);
    expect(r.last.question, '第15轮问题');
    // 预算小：只应带最后一两轮。
    expect(r.length, lessThan(15));
  });

  test('云端用量记账：今日/累计随记录增长，清空聊天一起清', () async {
    final db = await openTestDb(inIsolate: false);
    final state = AppState();
    state.debugDb = db;
    addTearDown(db.close);

    await state.recordUsage(
      'deepseek-flash',
      const TokenUsage(promptTokens: 1500, completionTokens: 300),
    );
    expect(state.totalUsage.count, 1);
    expect(state.totalUsage.promptTokens, 1500);
    expect(state.totalUsage.completionTokens, 300);
    expect(state.totalUsage.cost, closeTo(0.0027, 1e-9));
    expect(state.todayUsage.count, 1);

    await state.recordUsage(
      'deepseek-v4-pro',
      const TokenUsage(promptTokens: 1000, completionTokens: 100),
    );
    expect(state.totalUsage.count, 2);
    expect(state.totalUsage.cost, closeTo(0.0027 + 0.00585, 1e-6));

    await state.clearAllData();
    expect(state.totalUsage.count, 0);
    expect(state.todayUsage.count, 0);
  });

  test('本地 system 不带口癖原文，云端才带（9B 会照抄开头）', () async {
    final dir = await Directory.systemTemp.createTemp('ragchat-catch');
    addTearDown(() => dir.delete(recursive: true));
    final state = AppState();
    state.debugSupportDir = dir.path;
    await state.normalizePersonaSlots();

    final localPrompt = state.systemPrompt();
    expect(localPrompt, isNot(contains(state.activePersonaCard().catchphrase)));

    await state.setBackend('cloud');
    expect(state.systemPrompt(), contains(state.activePersonaCard().catchphrase));
  });

  test('两个槽位：切后端用各自的卡，改过的名字两边都留得住', () async {
    final dir = await Directory.systemTemp.createTemp('ragchat-slots');
    addTearDown(() => dir.delete(recursive: true));
    final state = AppState();
    state.debugSupportDir = dir.path;
    await state.normalizePersonaSlots();

    expect(state.activePersonaCard().name, '大肥鱼', reason: '本地默认');

    // 改云端那张的名字与正文：切走再切回，改动不能丢。
    await state.setBackend('cloud');
    expect(state.activePersonaCard().name, '大肥鱼');
    await state.savePersona(
      state.activePersonaCard().copyWith(name: '我的傲娇鱼'),
    );

    await state.setBackend('local');
    expect(state.activePersonaCard().name, '大肥鱼');
    await state.savePersona(
      state.activePersonaCard().copyWith(name: '我的小暖'),
    );

    await state.setBackend('cloud');
    expect(state.activePersonaCard().name, '我的傲娇鱼');
    await state.setBackend('local');
    expect(state.activePersonaCard().name, '我的小暖');

    // 恢复默认只影响当前槽位。
    await state.resetPersona();
    expect(state.activePersonaCard().name, '大肥鱼');
    await state.setBackend('cloud');
    expect(state.activePersonaCard().name, '我的傲娇鱼');
  });

  test('人设：单卡编辑即落盘，system 用新正文，可恢复默认', () async {
    final dir = await Directory.systemTemp.createTemp('ragchat-persona');
    addTearDown(() => dir.delete(recursive: true));
    final state = AppState();
    state.debugSupportDir = dir.path;

    final base = state.activePersonaCard();
    expect(base.name, '大肥鱼', reason: '本地默认短人设');

    await state.savePersona(
      base.copyWith(name: '阿鱼', personality: '话少，爱吃白饭'),
    );
    expect(state.activePersonaCard().name, '阿鱼');
    expect(state.systemPrompt(), contains('你是阿鱼'));
    expect(state.systemPrompt(), contains('性格：话少，爱吃白饭'));

    // 落盘两张槽位，改的是本地那张；云端那张保留默认。
    final reloaded = await AppSettings.load(dir.path);
    expect(reloaded.personas().length, 2);
    final local = reloaded.personas().firstWhere((c) => c.id == 'local');
    expect(local.name, '阿鱼');
    expect(local.personality, '话少，爱吃白饭');
    expect(reloaded.activePersonaId, 'local');

    await state.resetPersona();
    expect(state.activePersonaCard().name, '大肥鱼');
    expect(state.activePersonaCard().catchphrase, contains('才不是'));
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
