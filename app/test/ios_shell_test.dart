// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ragchat/app/app_state.dart';
import 'package:ragchat/app/home_page.dart';
import 'package:ragchat/app/ios_dialogs.dart';
import 'package:ragchat/app/settings.dart';
import 'package:ragchat/app/theme.dart';
import 'package:ragchat/chat/chat_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes/fake_gateway.dart';
import 'helpers.dart';

void main() {
  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppState> buildState() async {
    final db = await openTestDb(inIsolate: false);
    final service = ChatService(gateway: FakeGateway());
    addTearDown(() async {
      await service.dispose();
      await db.close();
    });
    final state = AppState();
    state.settings = AppSettings(confirmed: true);
    state.debugServiceFactory = () async => service;
    state.debugDb = db;
    state.modelsDirPath = '/tmp/models';
    return state;
  }

  Widget wrap(AppState state) => MaterialApp(
    theme: buildLightTheme(),
    localizationsDelegates: const [DefaultCupertinoLocalizations.delegate],
    builder: (c, child) =>
        iosAppBuilder(c, child, theme: buildCupertinoLightTheme()),
    home: AppStateScope(state: state, child: const HomePage()),
  );

  testWidgets('底部标签栏为聊天、记忆、设置，默认聊天页', (tester) async {
    final state = await buildState();
    await tester.pumpWidget(wrap(state));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoTabBar), findsOneWidget);
    expect(find.text('聊天'), findsWidgets);
    expect(find.text('记忆'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.textContaining('随便聊聊吧'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点「记忆」切到记忆页空态', (tester) async {
    final state = await buildState();
    await tester.pumpWidget(wrap(state));
    await tester.pumpAndSettle();

    await tester.tap(find.text('记忆'));
    await tester.pumpAndSettle();

    expect(find.textContaining('还没有记忆'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切页后聊天输入内容不丢', (tester) async {
    final state = await buildState();
    await tester.pumpWidget(wrap(state));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(CupertinoTextField), '保留测试');
    await tester.tap(find.text('记忆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('聊天').last);
    await tester.pumpAndSettle();

    final field = tester.widget<CupertinoTextField>(
      find.byType(CupertinoTextField),
    );
    expect(field.controller!.text, '保留测试');
    expect(tester.takeException(), isNull);
  });
}
