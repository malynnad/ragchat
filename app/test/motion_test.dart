import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ragchat/app/motion.dart';

/// 改造阶段 1：弹簧动效核心单测。
void main() {
  test('macSpring 物理换算 k=(2π/T)², c=2ζ√k, m=1', () {
    final s = macSpring(period: 0.35, dampingRatio: 1.0);
    final k = math.pow(2 * math.pi / 0.35, 2).toDouble();
    expect(s.mass, 1);
    expect(s.stiffness, closeTo(k, 1e-6));
    expect(s.damping, closeTo(2 * 1.0 * math.sqrt(k), 1e-6));
    final g = macGestureSpring();
    expect(g.damping, lessThan(2 * math.sqrt(g.stiffness))); // ζ0.8 欠阻尼
  });

  test('shouldSettleOpen：速度优先，否则位置过半', () {
    expect(shouldSettleOpen(0.2, 800), isTrue); // 快甩开
    expect(shouldSettleOpen(0.8, -800), isFalse); // 快甩合
    expect(shouldSettleOpen(0.6, 0), isTrue); // 慢放过半
    expect(shouldSettleOpen(0.4, 0), isFalse);
  });

  test('macHaptic 各类型不抛错（测试环境无振动器，降级静默）', () {
    for (final h in MacHaptic.values) {
      macHaptic(h);
    }
  });

  testWidgets('springTo 驱动到目标且可中断反向', (tester) async {
    final controller = AnimationController(vsync: const TestVSync(), value: 0);
    addTearDown(controller.dispose);
    late BuildContext ctx;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );

    springTo(controller, 1.0, context: ctx);
    await tester.pump(); // 启动 animateWith
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.value, greaterThan(0));
    expect(controller.value, lessThan(1));

    // 中途反向：从当前值平滑回 0，不跳变。
    final mid = controller.value;
    springTo(controller, 0.0, context: ctx);
    await tester.pump();
    expect((controller.value - mid).abs(), lessThan(0.2));
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if ((controller.value - 0.0).abs() < 0.001 &&
          controller.velocity.abs() < 0.01) {
        break;
      }
    }
    expect(controller.value, closeTo(0, 0.01));
  });

  testWidgets('springTo 向下驱动报 dismissed（弹层关闭收尾依赖此状态）', (tester) async {
    final controller = AnimationController(vsync: const TestVSync(), value: 1);
    addTearDown(controller.dispose);
    late BuildContext ctx;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );

    // animateWith 恒报 completed；向下必须 animateBackWith 才报 dismissed。
    springTo(controller, 0.0, context: ctx);
    await tester.pump();
    expect(controller.status, AnimationStatus.reverse);
    await tester.pumpAndSettle();
    expect(controller.value, closeTo(0, 0.001));
    expect(controller.status, AnimationStatus.dismissed);
  });

  testWidgets('减少动态效果时 springTo 直接跳变', (tester) async {
    final controller = AnimationController(vsync: const TestVSync(), value: 0);
    addTearDown(controller.dispose);
    late BuildContext ctx;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    springTo(controller, 1.0, context: ctx);
    expect(controller.value, 1.0); // 无动画过程
    expect(controller.isAnimating, isFalse);
  });
}
