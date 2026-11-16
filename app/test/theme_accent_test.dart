import 'dart:convert';
import 'dart:io';

// ignore: deprecated_member_use
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

/// v2 主题色设置：色板单点 / 持久化兼容 / builder 注入 / 设置页点色块即时换色。
void main() {
  group('色板 kAccents', () {
    test('六档 Nord 色，id 唯一，默认霜蓝在首', () {
      expect(kAccents.length, 6);
      expect(kAccents.map((a) => a.id).toSet().length, 6);
      expect(kAccents.first.id, kDefaultAccentId);
      expect(kDefaultAccentId, 'blue');
    });

    test('每档标签非空；六档色值=用户指定色号（亮/暗同色）', () {
      const spec = {
        'blue': 0xFF81A1C1,
        'slate': 0xFF4C566A,
        'gray': 0xFFD8DEE9,
        'teal': 0xFF8FBCBB,
        'purple': 0xFFB48EAD,
        'orange': 0xFFD08770,
      };
      for (final a in kAccents) {
        expect(a.label.isNotEmpty, true, reason: a.id);
        expect(a.light, Color(spec[a.id]!), reason: a.id);
        expect(a.dark, Color(spec[a.id]!), reason: a.id);
      }
    });

    test('accentById 命中与未知回退', () {
      expect(accentById('purple').id, 'purple');
      expect(accentById('teal').light, kIosAccentLight);
      expect(accentById('nope').id, kDefaultAccentId);
    });
  });

  group('theme builder 注入 accent', () {
    test('Cupertino 亮/暗默认=Nord 霜蓝，可覆盖', () {
      expect(buildCupertinoLightTheme().primaryColor, kDefaultAccentLight);
      expect(buildCupertinoDarkTheme().primaryColor, kDefaultAccentDark);
      expect(
        buildCupertinoLightTheme(kIosAccentLight).primaryColor,
        kIosAccentLight,
      );
      expect(
        buildCupertinoDarkTheme(kIosAccentDark).primaryColor,
        kIosAccentDark,
      );
    });
  });

  group('settings.accentId 持久化', () {
    test('默认蓝；save/load 往返保留；旧 json 无字段回退蓝', () async {
      final dir = Directory.systemTemp.createTempSync('accent_cfg');
      addTearDown(() => dir.deleteSync(recursive: true));

      expect(AppSettings().accentId, 'blue');

      final s = AppSettings(accentId: 'purple');
      await s.save(dir.path);
      final loaded = await AppSettings.load(dir.path);
      expect(loaded.accentId, 'purple');

      // 旧版本 settings.json 不含 accentId → 回退默认蓝（向后兼容）。
      await File('${dir.path}/settings.json')
          .writeAsString(jsonEncode({'topK': 5}));
      final old = await AppSettings.load(dir.path);
      expect(old.accentId, 'blue');
    });

    test('updateAccent 换色并落盘（真实异步）', () async {
      final dir = Directory.systemTemp.createTempSync('accent_upd');
      addTearDown(() => dir.deleteSync(recursive: true));
      final state = AppState();
      state.debugSupportDir = dir.path;
      await state.updateAccent('orange');
      expect(state.settings.accentId, 'orange');
      expect(state.accent.id, 'orange');
      final j = jsonDecode(
        File('${dir.path}/settings.json').readAsStringSync(),
      );
      expect(j['accentId'], 'orange');
    });
  });

  group('设置页主题颜色分组', () {
    Future<AppState> buildState(Directory dir) async {
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
      state.modelsDirPath = '/tmp/models';
      return state;
    }

    // 镜像 main.dart：AnimatedBuilder 监听 state，notify 后重建 MaterialApp
    // 并把 state.accent 注入 theme，验证「点色块全 App 即时换色」。
    Widget wrap(AppState state) => AppStateScope(
      state: state,
      child: AnimatedBuilder(
        animation: state,
        builder: (_, _) => MaterialApp(
          theme: buildLightTheme(state.accent.light),
          localizationsDelegates: const [
            DefaultCupertinoLocalizations.delegate,
          ],
          builder: (c, child) => iosAppBuilder(
            c,
            child,
            theme: buildCupertinoLightTheme(state.accent.light),
          ),
          home: const SettingsPage(),
        ),
      ),
    );

    testWidgets('渲染六档色块，默认霜蓝选中', (tester) async {
      final dir = Directory.systemTemp.createTempSync('accent_ui');
      addTearDown(() => dir.deleteSync(recursive: true));
      final state = await buildState(dir);
      await tester.pumpWidget(wrap(state));
      await tester.pumpAndSettle();
      // 主题色已移到列表底部（清空知识库下），需先滚动到可见再断言。
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('accent-blue')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      for (final a in kAccents) {
        expect(find.byKey(ValueKey('accent-${a.id}')), findsOneWidget);
      }
      expect(state.settings.accentId, 'blue');
      expect(tester.takeException(), isNull);
    });

    testWidgets('点紫色色块：换色+落盘+主题即时跟随', (tester) async {
      final dir = Directory.systemTemp.createTempSync('accent_ui2');
      addTearDown(() => dir.deleteSync(recursive: true));
      final state = await buildState(dir);
      await tester.pumpWidget(wrap(state));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('accent-purple')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('accent-purple')));
      await tester.pumpAndSettle();

      expect(state.settings.accentId, 'purple');
      expect(state.accent.id, 'purple');
      // 主题即时跟随（CupertinoTheme primaryColor 变为紫亮色）。
      // 落盘持久化由下方真实异步 pure test 覆盖（fake-async 内异步 IO 不完成）。
      final cup = tester.widget<CupertinoTheme>(
        find.byType(CupertinoTheme).first,
      );
      expect(cup.data.primaryColor, accentById('purple').light);
      expect(tester.takeException(), isNull);
    });
  });
}
