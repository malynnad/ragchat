// ignore: deprecated_member_use
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ragchat/app/app_state.dart';
import 'package:ragchat/app/ios_dialogs.dart';
import 'package:ragchat/app/ios_widgets.dart';
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

  testWidgets('设置页在手机宽度（411dp）下不溢出', (tester) async {
    // 真机 1264×2780 @3x ≈ 411×927 dp。测试默认 800dp 宽，比手机宽一倍，
    // 卡片里多塞两个按钮根本测不出来——所以这条用例必须自己压窄视口。
    tester.view.physicalSize = const Size(1264, 2780);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    // 系统字号放大时 Flutter 会等比放大所有文本——真机溢出就是这么来的，
    // 测试里默认 1.0 永远测不出，必须显式压一个放大档。
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final state = await buildState();
    await tester.pumpWidget(wrap(state));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '窄屏下不该有 RenderFlex 溢出');
    expect(find.byKey(const ValueKey('calibrate-embed')), findsOneWidget);
    expect(find.byKey(const ValueKey('retrieval-eval')), findsOneWidget);

    // 光看「没报溢出」不够：真机上 Row 超宽时 Flutter 会把内容画到卡片外面，
    // release 下既不报错也不打条纹，只能靠量边界。这里逐行核到底。
    final card = find
        .ancestor(
          of: find.byKey(const ValueKey('calibrate-embed')),
          matching: find.byType(IosSection),
        )
        .first;
    final cardRect = tester.getRect(card);
    for (final key in const [
      'calibrate-embed',
      'retrieval-eval',
    ]) {
      final r = tester.getRect(find.byKey(ValueKey(key)));
      expect(
        r.right,
        lessThanOrEqualTo(cardRect.right),
        reason: '$key 超出卡片右边界',
      );
      expect(r.left, greaterThanOrEqualTo(cardRect.left), reason: '$key 超出左边界');
    }
  });

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

  testWidgets('存储区有导出/导入备份入口', (tester) async {
    final state = await buildState();
    await tester.pumpWidget(wrap(state));
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('export-backup')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('export-backup')), findsOneWidget);
    expect(find.byKey(const ValueKey('import-backup')), findsOneWidget);
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
