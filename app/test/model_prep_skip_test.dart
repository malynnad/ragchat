// ignore: deprecated_member_use
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ragchat/app/app_state.dart';
import 'package:ragchat/app/ios_dialogs.dart';
import 'package:ragchat/app/model_prep_page.dart';
import 'package:ragchat/app/settings.dart';
import 'package:ragchat/app/theme.dart';

/// 首次启动不强制下载模型：点「稍后配置」也能进主界面。
void main() {
  testWidgets('没有模型时点「稍后配置」进入主界面', (tester) async {
    final dir = Directory.systemTemp.createTempSync('prep-skip');
    addTearDown(() => dir.deleteSync(recursive: true));
    final state = AppState();
    state.settings = AppSettings();
    state.debugSupportDir = dir.path;
    state.modelsDirPath = dir.path;

    await tester.pumpWidget(
      AppStateScope(
        state: state,
        child: AnimatedBuilder(
          animation: state,
          builder: (_, _) => MaterialApp(
            theme: buildLightTheme(),
            localizationsDelegates: const [
              DefaultCupertinoLocalizations.delegate,
            ],
            builder: (c, child) =>
                iosAppBuilder(c, child, theme: buildCupertinoLightTheme()),
            home: const ModelPrepPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(state.entered, isFalse);
    final skip = find.byKey(const ValueKey('skip-model-setup'));
    await tester.ensureVisible(skip);
    await tester.pumpAndSettle();
    await tester.tap(skip);
    await tester.pumpAndSettle();

    expect(state.entered, isTrue);
    expect(state.settings.skipModelSetup, isTrue);
    expect(tester.takeException(), isNull);
  });
}
