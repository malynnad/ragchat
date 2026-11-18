// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ragchat/app/app_state.dart';
import 'package:ragchat/app/ios_dialogs.dart';
import 'package:ragchat/app/qa_page.dart';
import 'package:ragchat/app/settings.dart';
import 'package:ragchat/app/theme.dart';
import 'package:ragchat/chat/chat_service.dart';
import 'package:ragchat/rag/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes/fake_gateway.dart';
import 'helpers.dart';

void main() {
  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
  });

  Future<(AppState, FakeGateway)> buildState() async {
    final db = await openTestDb(inIsolate: false);
    final gateway = FakeGateway();
    final service = ChatService(gateway: gateway);
    addTearDown(() async {
      await service.dispose();
      await db.close();
    });
    final state = AppState();
    state.settings = AppSettings(
      confirmed: true,
      chatModelPath: '/tmp/fake-model.gguf',
    );
    state.debugServiceFactory = () async => service;
    state.debugDb = db;
    return (state, gateway);
  }

  Widget wrap(AppState state) => MaterialApp(
    theme: buildLightTheme(),
    localizationsDelegates: const [DefaultCupertinoLocalizations.delegate],
    builder: (c, child) =>
        iosAppBuilder(c, child, theme: buildCupertinoLightTheme()),
    home: AppStateScope(state: state, child: const QaPage()),
  );

  Future<void> pumpUntilIdle(WidgetTester tester) async {
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(CupertinoActivityIndicator).evaluate().isEmpty) return;
    }
    fail('生成未在预期帧数内结束');
  }

  testWidgets('启动时恢复最近会话的问答气泡', (tester) async {
    final (state, _) = await buildState();
    state.sessionTurns.add(
      const SessionTurn(question: '我叫什么？', answer: '你叫Danny。'),
    );

    await tester.pumpWidget(wrap(state));
    await tester.pump();

    expect(find.text('我叫什么？'), findsOneWidget);
    expect(find.text('你叫Danny。'), findsOneWidget);
  });

  testWidgets('发送后清空输入框，完成轮次写入当前会话', (tester) async {
    final (state, gateway) = await buildState();
    gateway.nextResponse = '我记住了。';
    await tester.pumpWidget(wrap(state));

    await tester.enterText(find.byType(CupertinoTextField), '记住我喜欢喝茶');
    await tester.tap(find.byIcon(CupertinoIcons.arrow_up));
    await tester.pump();
    await pumpUntilIdle(tester);
    await tester.pumpAndSettle();

    expect(find.text('记住我喜欢喝茶'), findsOneWidget);
    expect(find.text('我记住了。'), findsOneWidget);
    expect(state.sessionTurns.single.question, '记住我喜欢喝茶');
    expect(state.sessionTurns.single.answer, '我记住了。');
    expect(state.currentSessionId, isNotNull);
  });

  testWidgets('新对话清空气泡并从旧会话提取记忆', (tester) async {
    final (state, gateway) = await buildState();
    gateway.scriptedResponses.addAll([
      '你好，Danny。',
      '{"add":[{"content":"用户叫Danny","kind":"fact","importance":5}]}',
    ]);
    await tester.pumpWidget(wrap(state));

    await tester.enterText(find.byType(CupertinoTextField), '我叫Danny');
    await tester.tap(find.byIcon(CupertinoIcons.arrow_up));
    await tester.pump();
    await pumpUntilIdle(tester);

    await tester.tap(find.text('new'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新对话'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 200 && state.memories.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.text('我叫Danny'), findsNothing);
    expect(state.sessionTurns, isEmpty);
    expect(state.memories.single.content, '用户叫Danny');
  });
}
