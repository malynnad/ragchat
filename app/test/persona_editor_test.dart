// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ragchat/app/ios_dialogs.dart';
import 'package:ragchat/app/persona.dart';
import 'package:ragchat/app/persona_editor.dart';
import 'package:ragchat/app/theme.dart';

/// 人设编辑器：自由正文能存、预算表跟着字数走、空名字拦下、预设可一键填入。
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

  testWidgets('改正文后保存，返回的卡正文变了、名字和 id 不变', (tester) async {
    PersonaCard? saved;
    await tester.pumpWidget(
      host(
        (ctx) async => saved = await showPersonaEditor(
          ctx,
          initial: const PersonaCard(id: 'x', name: '小暖', text: '旧的'),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('persona-text')),
      '你是阿鱼，话少，爱吃白饭。',
    );
    await tester.pump();
    expect(find.textContaining('人设 ≈ 13 token'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.id, 'x');
    expect(saved!.name, '小暖');
    expect(saved!.render(), '你是阿鱼，话少，爱吃白饭。');
  });

  testWidgets('名字清空不能保存', (tester) async {
    PersonaCard? saved;
    var popped = false;
    await tester.pumpWidget(
      host(
        (ctx) async {
          saved = await showPersonaEditor(
            ctx,
            initial: const PersonaCard(id: 'x', name: '小暖', text: '旧'),
          );
          popped = true;
        },
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('persona-name')), '');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(saved, isNull);
    expect(popped, isFalse);
    expect(find.text('先给它起个名字'), findsOneWidget);
  });

  testWidgets('点预设把人设换成内置那段的正文', (tester) async {
    PersonaCard? saved;
    await tester.pumpWidget(
      host(
        (ctx) async => saved = await showPersonaEditor(
          ctx,
          initial: const PersonaCard(id: 'x', name: '小暖', text: '旧'),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('persona-preset-tutor')));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(saved!.name, '阿博');
    expect(saved!.render(), builtinPersonas.last.text);
  });

  testWidgets('取消不返回任何卡', (tester) async {
    PersonaCard? saved;
    var popped = false;
    await tester.pumpWidget(
      host(
        (ctx) async {
          saved = await showPersonaEditor(
            ctx,
            initial: const PersonaCard(id: 'x', name: '小暖', text: '旧'),
          );
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
