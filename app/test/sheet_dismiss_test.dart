// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ragchat/app/ios_dialogs.dart';
import 'package:ragchat/app/theme.dart';

/// 弹层关闭回归（真机 bug 修复）：
/// 1) 抓手拖到底后必须真正 pop（曾残留灰屏障：value=0 时 status 已 dismissed，
///    弹簧回 0 无 status 变化 → 监听器不触发）。
/// 2) 弹层不抢焦点（requestFocus=false）：开关前后焦点不变，
///    退出时不会因 setFirstFocus 自动聚焦输入框而带起键盘。
void main() {
  Widget app(Widget home) => MaterialApp(
    localizationsDelegates: const [DefaultCupertinoLocalizations.delegate],
    builder: (c, child) =>
        iosAppBuilder(c, child, theme: buildCupertinoLightTheme()),
    home: home,
  );

  testWidgets('抓手拖到底 → 弹层 pop，无残留', (tester) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => showIosSheet(
              context: context,
              builder: (_) => const Padding(
                padding: EdgeInsets.all(16),
                child: Text('弹层内容'),
              ),
            ),
            child: const Text('开弹层'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('开弹层'));
    await tester.pumpAndSettle();
    expect(find.text('弹层内容'), findsOneWidget);

    final handle = find.byWidgetPredicate(
      (w) => w is GestureDetector && w.onVerticalDragUpdate != null,
    );
    expect(handle, findsOneWidget);
    final center = tester.getCenter(handle);
    final gesture = await tester.startGesture(center);
    // 分步拖到屏幕底（超过弹层高度），模拟用户「拖到底」。
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('弹层内容'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('内容到顶再下滑 → 关闭弹层', (tester) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => showIosSheet(
              context: context,
              builder: (_) => const Padding(
                padding: EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [Text('弹层内容'), SizedBox(height: 40)],
                  ),
                ),
              ),
            ),
            child: const Text('开弹层'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('开弹层'));
    await tester.pumpAndSettle();
    expect(find.text('弹层内容'), findsOneWidget);

    // 慢拖过半（位移按全屏高归一，需 >300px 才过 0.5 阈值）→ 释放关闭。
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('弹层内容'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('内容到顶快速下滑（fling）→ 关闭弹层', (tester) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => showIosSheet(
              context: context,
              builder: (_) => const Padding(
                padding: EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [Text('弹层内容'), SizedBox(height: 40)],
                  ),
                ),
              ),
            ),
            child: const Text('开弹层'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('开弹层'));
    await tester.pumpAndSettle();
    expect(find.text('弹层内容'), findsOneWidget);

    // 真机手感：短距离快甩，速度优先判定（<-400px/s → 关闭）。
    await tester.fling(
      find.byType(SingleChildScrollView),
      const Offset(0, 150),
      1200,
    );
    await tester.pumpAndSettle();
    expect(find.text('弹层内容'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('关闭无长尾：下滑释放后 ~300ms 内弹层消失', (tester) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => showIosSheet(
              context: context,
              builder: (_) => const Padding(
                padding: EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [Text('弹层内容'), SizedBox(height: 40)],
                  ),
                ),
              ),
            ),
            child: const Text('开弹层'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('开弹层'));
    await tester.pumpAndSettle();

    await tester.fling(
      find.byType(SingleChildScrollView),
      const Offset(0, 150),
      1200,
    );
    // 不用 pumpAndSettle：限定 300ms 内必须已退出（曾等弹簧停稳 0.5–1s）。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('弹层内容'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('内容未到顶时上滑=正常滚动，不关弹层', (tester) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => showIosSheet(
              context: context,
              builder: (_) => const Padding(
                padding: EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: SizedBox(height: 2000, child: Text('弹层内容')),
                ),
              ),
            ),
            child: const Text('开弹层'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('开弹层'));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(find.text('弹层内容'), findsOneWidget, reason: '上滑应滚动而非关闭');
    final pos = tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(pos.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('弹层不抢焦点：开关前后焦点不变（键盘状态不被扰动）', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Column(
            children: [
              CupertinoTextField(focusNode: node),
              CupertinoButton(
                onPressed: () => showIosSheet(
                  context: context,
                  builder: (ctx) => CupertinoButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('关闭弹层'),
                  ),
                ),
                child: const Text('开弹层'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 真机流程：用户手点输入框聚焦（非 autofocus）。
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue);

    await tester.tap(find.text('开弹层'));
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue, reason: '开弹层不抢焦点（requestFocus=false）');

    await tester.tap(find.text('关闭弹层'));
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue, reason: 'pop 恢复原焦点，无 hide→show 键盘扰动');
    expect(tester.takeException(), isNull);
  });
}
