// ignore: deprecated_member_use
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ragchat/app/app_state.dart';
import 'package:ragchat/app/ios_dialogs.dart';
import 'package:ragchat/app/settings.dart';
import 'package:ragchat/app/settings_page.dart';
import 'package:ragchat/app/theme.dart';
import 'package:ragchat/chat/chat_service.dart';

import 'fakes/fake_gateway.dart';
import 'helpers.dart';

/// 设置页新增控件：采样温度三档、思考开关、长按数据库弹删除。
void main() {
  late Directory dir;

  // 注意：widget 测试跑在 FakeAsync 里，异步文件 IO 会一直挂住；
  // 临时目录必须同步创建（catalog 测试同样的坑）。
  setUp(() {
    dir = Directory.systemTemp.createTempSync('settings_controls');
  });

  tearDown(() => dir.deleteSync(recursive: true));

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
    state.debugSupportDir = dir.path;
    state.modelsDirPath = dir.path;
    return state;
  }

  Widget wrap(AppState state) => AppStateScope(
    state: state,
    child: AnimatedBuilder(
      animation: state,
      builder: (_, _) => MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: const [DefaultCupertinoLocalizations.delegate],
        builder: (c, child) =>
            iosAppBuilder(c, child, theme: buildCupertinoLightTheme()),
        home: const SettingsPage(),
      ),
    ),
  );

  testWidgets('温度三档：点「稳定」写进设置并落盘', (tester) async {
    final state = await buildState();
    await tester.pumpWidget(wrap(state));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('稳定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('稳定'));
    await tester.pumpAndSettle();

    expect(state.settings.temperature, 0.4);
    expect(find.text('当前 0.4'), findsOneWidget);
  });

  testWidgets('按住删除按钮填满才弹确认；点一下不弹', (tester) async {
    final state = await buildState();
    await tester.pumpWidget(wrap(state));
    await tester.pumpAndSettle();

    final btn = find.byKey(const ValueKey('delete-db'));
    await tester.ensureVisible(btn);
    await tester.pumpAndSettle();

    // 轻点一下：不弹窗。
    await tester.tap(btn);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('删除全部聊天数据'), findsNothing);

    // 按住 1.1s：填满后弹确认，标题只有一个（按钮文案已换成弹窗标题，先松开）。
    final g = await tester.startGesture(tester.getCenter(btn));
    await tester.pump(const Duration(milliseconds: 150)); // 让 onTapDown 落下
    await tester.pump(const Duration(milliseconds: 1000)); // 填满一格
    await g.up();
    await tester.pumpAndSettle();

    expect(find.text('删除全部聊天数据'), findsOneWidget);
    expect(find.textContaining('不可恢复'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('删除全部聊天数据'), findsNothing);
    expect(state.settings.temperature, 0.6, reason: '没有误清数据');
    expect(tester.takeException(), isNull);
  });
}
