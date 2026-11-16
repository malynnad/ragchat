// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ragchat/app/ios_dialogs.dart';
import 'package:ragchat/app/persona.dart';
import 'package:ragchat/app/persona_editor.dart';
import 'package:ragchat/app/theme.dart';

/// 人设编辑器：改字段能保存、预览跟着输入走、空名字拦下。
void main() {
  Widget host(void Function(BuildContext) onOpen) => MaterialApp(
    localizationsDelegates: const [DefaultCupertinoLocalizations.delegate],
    builder: (c, child) =>
        iosAppBuilder(c, child, theme: buildCupertinoLightTheme()),
    home: Builder(
      builder: (ctx) => Center(
        child: CupertinoButton(
          onPressed: () => onOpen(ctx),
          child: const Text('打开'),
        ),
      ),
    ),
  );

  testWidgets('改性格/风格后保存，返回改好的卡且 id 不变', (tester) async {
    PersonaCard? saved;
    await tester.pumpWidget(
      host(
        (ctx) async => saved = await showPersonaEditor(
          ctx,
          initial: const PersonaCard(id: 'x', name: '小暖'),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('编辑人设'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('persona-field-1')), '温柔耐心');
    await tester.enterText(
      find.byKey(const ValueKey('persona-field-2')),
      '口语化，短句',
    );
    await tester.pump();
    // 预览实时跟着变。
    expect(find.textContaining('性格：温柔耐心'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.id, 'x');
    expect(saved!.name, '小暖');
    expect(saved!.personality, '温柔耐心');
    expect(saved!.render(), contains('说话风格：口语化，短句'));
  });

  testWidgets('新建：空名字不保存，填了名字才返回新卡', (tester) async {
    PersonaCard? saved;
    await tester.pumpWidget(
      host((ctx) async => saved = await showPersonaEditor(ctx)),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('新建人设'), findsOneWidget);

    // 默认名被清空后再保存 → 拦下。
    await tester.enterText(find.byKey(const ValueKey('persona-field-0')), '');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(find.text('先给它起个名字'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('persona-field-0')), '阿鱼');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.name, '阿鱼');
  });

  testWidgets('取消不返回任何卡', (tester) async {
    PersonaCard? saved;
    var popped = false;
    await tester.pumpWidget(
      host(
        (ctx) async {
          saved = await showPersonaEditor(ctx);
          popped = true;
        },
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(popped, isTrue);
    expect(saved, isNull);
  });
}
