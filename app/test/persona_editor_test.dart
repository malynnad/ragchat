// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ragchat/app/app_state.dart';
import 'package:ragchat/app/ios_dialogs.dart';
import 'package:ragchat/app/settings.dart';
import 'package:ragchat/app/persona.dart';
import 'package:ragchat/app/persona_editor.dart';
import 'package:ragchat/app/theme.dart';

/// 人设编辑器：短字段能存、字数有上限、预算表跟着变、空名字拦下、预设可填。
void main() {
  const base = PersonaCard(
    id: 'x',
    name: '小暖',
    personality: '温和',
    style: '短句',
    catchphrase: '嗯，我在',
  );

  /// 编辑器比默认 800×600 的测试屏长：撑高视口，免得下方分组没被构建。
  void tallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

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

  testWidgets('改口癖后保存，渲染出「常说」那句', (tester) async {
    tallScreen(tester);
    PersonaCard? saved;
    await tester.pumpWidget(
      host(
        (ctx) async => saved = await showPersonaEditor(ctx, initial: base),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('persona-field-3')),
      '那你慢慢说',
    );
    await tester.pump();
    // 预览实时跟着走。
    expect(find.textContaining('常说：「那你慢慢说」'), findsWidgets);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.id, 'x');
    expect(saved!.catchphrase, '那你慢慢说');
    expect(saved!.render(), contains('常说：「那你慢慢说」'));
  });

  testWidgets('字数有上限：性格最多 60 字', (tester) async {
    tallScreen(tester);
    PersonaCard? saved;
    await tester.pumpWidget(
      host(
        (ctx) async => saved = await showPersonaEditor(ctx, initial: base),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('persona-field-1')),
      'a' * 100,
    );
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(saved!.personality.length, 60);
  });

  testWidgets('名字清空不能保存', (tester) async {
    tallScreen(tester);
    PersonaCard? saved;
    var popped = false;
    await tester.pumpWidget(
      host(
        (ctx) async {
          saved = await showPersonaEditor(ctx, initial: base);
          popped = true;
        },
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('persona-field-0')), '');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(saved, isNull);
    expect(popped, isFalse);
    expect(find.text('先给它起个名字'), findsOneWidget);
  });

  testWidgets('长人设走整段文本编辑', (tester) async {
    tallScreen(tester);
    PersonaCard? saved;
    final long = cloudPersonaDefault;
    await tester.pumpWidget(
      host(
        (ctx) async => saved = await showPersonaEditor(ctx, initial: long),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final raw = find.byKey(const ValueKey('persona-raw'));
    expect(raw, findsOneWidget, reason: '长人设应显示整段编辑框');
    expect(find.byKey(const ValueKey('persona-field-1')), findsNothing);

    await tester.enterText(raw, '${long.text}\n\n额外一句：只在云端用。');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(saved!.id, 'cloud');
    expect(saved!.text, contains('额外一句'));
    expect(saved!.render(), contains('额外一句'));
  });

  testWidgets('云端人设的 system 预算显示 6000，不再是 800', (tester) async {
    tallScreen(tester);
    final state = AppState();
    state.settings = AppSettings(backend: 'cloud');
    PersonaCard? saved;
    await tester.pumpWidget(
      AppStateScope(
        state: state,
        child: host(
          (ctx) async => saved = await showPersonaEditor(
            ctx,
            initial: cloudPersonaDefault,
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.textContaining('云端 system 一共 6000 token'), findsOneWidget);
    expect(find.textContaining('800 token'), findsNothing);
    expect(saved, isNull);
  });

  testWidgets('取消不返回任何卡', (tester) async {
    tallScreen(tester);
    var popped = false;
    PersonaCard? saved;
    await tester.pumpWidget(
      host(
        (ctx) async {
          saved = await showPersonaEditor(ctx, initial: base);
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
