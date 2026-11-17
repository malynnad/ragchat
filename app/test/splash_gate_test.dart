// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ragchat/app/ios_dialogs.dart';
import 'package:ragchat/app/splash_gate.dart';
import 'package:ragchat/app/theme.dart';

/// 开机动画：先停住（0.5s），再冲出画面淡出，最后交给主界面；
/// 减少动态时直接进主界面。
void main() {
  Widget host(Widget child, {bool reduce = false}) => MaterialApp(
    localizationsDelegates: const [DefaultCupertinoLocalizations.delegate],
    builder: (c, inner) {
      final app = iosAppBuilder(
        c,
        inner,
        theme: buildCupertinoLightTheme(),
      );
      if (!reduce) return app;
      return MediaQuery(
        data: MediaQuery.of(c).copyWith(disableAnimations: true),
        child: app,
      );
    },
    home: SplashGate(child: child),
  );

  testWidgets('0.5s 内停在中间，之后放大淡出并进主页', (tester) async {
    await tester.pumpWidget(host(const Text('主页')));
    await tester.pump(const Duration(milliseconds: 80));

    // 停留阶段：图标在，主页还不在。
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('主页'), findsNothing);

    final start = tester.widget<Transform>(
      find.descendant(of: find.byType(Opacity), matching: find.byType(Transform)),
    );
    final startScale = start.transform.getMaxScaleOnAxis();

    await tester.pump(const Duration(milliseconds: 380));
    expect(find.text('主页'), findsNothing, reason: '0.46s 还在停留');

    await tester.pump(const Duration(milliseconds: 200));
    final mid = tester.widget<Transform>(
      find.descendant(of: find.byType(Opacity), matching: find.byType(Transform)),
    );
    expect(
      mid.transform.getMaxScaleOnAxis(),
      greaterThan(startScale),
      reason: '停留结束后开始放大',
    );

    await tester.pumpAndSettle();
    expect(find.text('主页'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('减少动态：直接进主页', (tester) async {
    await tester.pumpWidget(host(const Text('主页'), reduce: true));
    await tester.pump();
    expect(find.text('主页'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
