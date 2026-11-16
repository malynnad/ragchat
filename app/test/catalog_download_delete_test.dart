import 'dart:io';

// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ragchat/app/app_state.dart';
import 'package:ragchat/app/ios_dialogs.dart';
import 'package:ragchat/app/settings.dart';
import 'package:ragchat/app/settings_page.dart';
import 'package:ragchat/app/theme.dart';
import 'package:ragchat/chat/chat_service.dart';
import 'package:ragchat/rag/model_catalog.dart';

import 'fakes/fake_gateway.dart';
import 'helpers.dart';

/// v2 下载圆环进度 + 删除已下载模型：安全闸 / 成功删文件 / 行内圆环 / 垃圾桶。
void main() {
  group('deleteModel 安全闸与成功路径', () {
    test('活跃生成模型拒删', () async {
      final dir = Directory.systemTemp.createTempSync('del_chat');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File(p.join(dir.path, 'a.gguf'))..writeAsStringSync('x');
      final state = AppState();
      state.settings = AppSettings(chatModelPath: f.path);
      final err = await state.deleteModel(f.path);
      expect(err, contains('正在使用'));
      expect(f.existsSync(), true);
    });

    test('活跃嵌入模型拒删', () async {
      final dir = Directory.systemTemp.createTempSync('del_embed');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File(p.join(dir.path, 'b.gguf'))..writeAsStringSync('x');
      final state = AppState();
      state.settings = AppSettings(embedModelPath: f.path);
      final err = await state.deleteModel(f.path);
      expect(err, contains('正在使用'));
      expect(f.existsSync(), true);
    });

    test('下载进行中拒删', () async {
      final dir = Directory.systemTemp.createTempSync('del_busy');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File(p.join(dir.path, 'c.gguf'))..writeAsStringSync('x');
      final state = AppState();
      state.downloadingUrl = 'https://example/x.gguf';
      final err = await state.deleteModel(f.path);
      expect(err, contains('下载进行中'));
      expect(f.existsSync(), true);
    });

    test('文件不存在返回原因', () async {
      final state = AppState();
      final err = await state.deleteModel('/nonexistent/zz.gguf');
      expect(err, contains('文件不存在'));
    });

    test('非活跃模型删除成功：文件移除+modelFiles 移除', () async {
      final dir = Directory.systemTemp.createTempSync('del_ok');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File(p.join(dir.path, 'd.gguf'))..writeAsStringSync('x');
      final state = AppState();
      state.modelFiles.add(ModelFile(f.path, 1));
      final err = await state.deleteModel(f.path);
      expect(err, isNull);
      expect(f.existsSync(), false);
      expect(state.modelFiles, isEmpty);
    });
  });

  group('设置页目录圆环进度与垃圾桶', () {
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
      state.modelsDirPath = dir.path;
      return state;
    }

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

    testWidgets('下载行显示圆环+百分比，已下载行显示垃圾桶', (tester) async {
      final dir = Directory.systemTemp.createTempSync('ring_ui');
      addTearDown(() => dir.deleteSync(recursive: true));
      final state = await buildState(dir);
      final embed4 = modelCatalog.firstWhere(
        (m) => !m.isChat && m.label.contains('4B'),
      );
      final embed06 = modelCatalog.firstWhere(
        (m) => !m.isChat && m.label.contains('0.6B'),
      );
      // 已下载：0.6B 文件名匹配 → ✓+垃圾桶。
      state.modelFiles.add(
        ModelFile(p.join(dir.path, p.basename(embed06.url)), 1),
      );
      // 正在下载：4B → 圆环 40%。
      state.downloadingUrl = embed4.url;
      state.downloadProgress = 0.4;

      await tester.pumpWidget(wrap(state));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('国内镜像；下载即切换，不支持断点续传'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('国内镜像；下载即切换，不支持断点续传'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(CircularProgressIndicator));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.trash), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
