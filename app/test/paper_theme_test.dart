// ignore: deprecated_member_use
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ragchat/app/ios_dialogs.dart';
import 'package:ragchat/app/paper.dart';
import 'package:ragchat/app/theme.dart';

/// 纸页与档案：只用一套纸墨色，层级靠明度，不提供多色主题。
void main() {
  test('纸墨令牌 = 规范色号', () {
    expect(PaperPalette.light.bg, const Color(0xFFF4F3EF));
    expect(PaperPalette.light.surface, const Color(0xFFFDFCFA));
    expect(PaperPalette.light.milk, const Color(0xFFFEFDF8));
    expect(PaperPalette.light.hairline, const Color(0xFFD8DBD5));
    expect(PaperPalette.light.ink, const Color(0xFF181818));
    expect(PaperPalette.light.muted, const Color(0xFF646B62));
    expect(PaperPalette.dark.bg, const Color(0xFF191919));
    expect(PaperPalette.dark.surface, const Color(0xFF242424));
    expect(PaperPalette.dark.ink, const Color(0xFFF2F2F2));
  });

  test('主题映射纸色：强调色就是墨色，不再有彩色档位', () {
    final light = buildCupertinoLightTheme();
    expect(light.primaryColor, PaperPalette.light.ink);
    expect(light.scaffoldBackgroundColor, PaperPalette.light.bg);

    final dark = buildCupertinoDarkTheme();
    expect(dark.primaryColor, PaperPalette.dark.ink);
    expect(dark.scaffoldBackgroundColor, PaperPalette.dark.bg);
  });

  test('字阶取自规范档位', () {
    expect(kFontCode, 9);
    expect(kFontDock, 11);
    expect(kFontCaption, 12);
    expect(kFontBody, 13);
    expect(kFontControl, 14);
    expect(kFontTitle, 18);
  });

  testWidgets('纸卡：圆角 4、纸面色、发丝描边', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (c, child) =>
            iosAppBuilder(c, child, theme: buildCupertinoLightTheme()),
        home: const Center(child: ContentPanel(child: Text('内容'))),
      ),
    );
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(ContentPanel),
            matching: find.byType(Container),
          )
          .first,
    );
    final deco = container.decoration! as BoxDecoration;
    expect(deco.color, PaperPalette.light.surface);
    expect(
      deco.borderRadius,
      BorderRadius.circular(4),
      reason: '纸面板圆角 ≤4',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('区块：档案码 + 标题 + 内容三层', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (c, child) =>
            iosAppBuilder(c, child, theme: buildCupertinoLightTheme()),
        home: const Scaffold(
          body: ArchiveSection(
            code: '01 / SYNOPSIS',
            title: '最近阅读',
            subtitle: '按最近顺序',
            child: Text('内容'),
          ),
        ),
      ),
    );
    expect(find.text('01 / SYNOPSIS'), findsOneWidget);
    expect(find.text('最近阅读'), findsOneWidget);
    expect(find.text('按最近顺序'), findsOneWidget);
    final title = tester.widget<Text>(find.text('最近阅读'));
    expect(title.style!.fontSize, 18);
    expect(title.style!.fontWeight, FontWeight.w700);
  });
}
