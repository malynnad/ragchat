// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ragchat/app/ios_dialogs.dart';
import 'package:ragchat/app/theme.dart';

/// 回归：弹层（纯 Cupertino 子树）里的 plain Text 必须继承干净默认样式。
/// 根因回顾：MaterialApp 应用级 DefaultTextStyle 是「错误提示样式」
/// （monospace + w900 + 黄色双下划线）；主页面有 Material/Scaffold 盖掉它，
/// 而 showIosSheet 路由没有 Material → 曾出现黄双下划线+粗体。
/// iosAppBuilder 在根 Navigator 之上补 DefaultTextStyle 后应消失。
void main() {
  testWidgets('弹层 plain Text 无黄双下划线/非 monospace 粗体', (tester) async {
    TextStyle? probed;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [DefaultCupertinoLocalizations.delegate],
        builder: (c, child) =>
            iosAppBuilder(c, child, theme: buildCupertinoLightTheme()),
        home: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => showIosSheet(
              context: context,
              builder: (_) => Builder(
                builder: (ctx) {
                  probed = DefaultTextStyle.of(ctx).style;
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('探针'),
                  );
                },
              ),
            ),
            child: const Text('开弹层'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('开弹层'));
    await tester.pumpAndSettle();

    expect(probed, isNotNull);
    expect(probed!.decoration, isNull);
    expect(probed!.decorationStyle, isNot(TextDecorationStyle.double));
    expect(probed!.fontFamily, isNot('monospace'));
    expect(probed!.fontWeight, isNot(FontWeight.w900));
    expect(probed!.fontSize, kFontBody);
    expect(tester.takeException(), isNull);
  });
}
