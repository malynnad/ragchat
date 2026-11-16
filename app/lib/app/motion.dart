/// macOS 风格动效核心（改造阶段 1）。
///
/// 设计原则（apple-design）：
/// - 弹簧而非固定时长 Tween：用 [SpringSimulation]，自然减速、可中断。
/// - 手势继承速度：释放时的 velocity 直接作为弹簧初速度。
/// - 可中断：[springTo] 从 controller 当前值 + 当前速度重新驱动，
///   反向操作不会跳变。
/// - 降级：系统「减少动态效果」(MediaQuery.disableAnimations) 时直接跳变，
///   由调用方配合 crossfade；触觉反馈在不支持的设备上静默忽略。
library;

import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 弹簧参数：周期 [period]（秒）+ 阻尼比 [dampingRatio] → SpringDescription。
///
/// 物理换算（质量 m=1）：刚度 k=(2π/T)²，阻尼 c=2ζ√k。
/// ζ=1 临界阻尼（无过冲，稳妥）；ζ<1 轻微过冲（活泼）。
SpringDescription macSpring({double period = 0.35, double dampingRatio = 1.0}) {
  final k = math.pow(2 * math.pi / period, 2).toDouble();
  final c = 2 * dampingRatio * math.sqrt(k);
  return SpringDescription(mass: 1, stiffness: k, damping: c);
}

/// 默认 UI 弹簧：临界阻尼、0.35s 周期——面板/抽屉开合。
SpringDescription macDefaultSpring() => macSpring();

/// 手势弹簧：ζ0.8 / T0.3——拖拽释放，轻微过冲更有「弹性」。
SpringDescription macGestureSpring() =>
    macSpring(period: 0.3, dampingRatio: 0.8);

/// 可中断弹簧驱动：把 [controller] 从当前值（继承当前速度或传入 [velocity]）
/// 弹簧驱动到 [target]。系统减少动态效果时直接赋值（调用方做 crossfade）。
///
/// 反复调用安全：每次从当前状态重新起算，反向/中途改目标都平滑。
void springTo(
  AnimationController controller,
  double target, {
  required BuildContext context,
  SpringDescription? spring,
  double? velocity,
}) {
  final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  if (reduceMotion) {
    controller.value = target;
    return;
  }
  final simulation = SpringSimulation(
    spring ?? macDefaultSpring(),
    controller.value,
    target,
    velocity ?? controller.velocity,
  );
  // 方向必须与目标一致：animateWith 恒置 forward，仿真结束一律报 completed，
  // 即便值已降到 0。向下（关闭）动画须用 animateBackWith 才会报 dismissed，
  // 否则依赖 dismissed 状态的收尾回调（如弹层 pop）永不触发 → 灰屏障残留。
  if (target < controller.value) {
    controller.animateBackWith(simulation);
  } else {
    controller.animateWith(simulation);
  }
}

/// 抽屉/弹层释放判定：速度优先（快甩直接决定方向），否则看位置过半。
/// [fraction] 0=全合 1=全开；[velocity] 像素/秒（正=向开方向）。
bool shouldSettleOpen(double fraction, double velocity) {
  if (velocity > 400) return true;
  if (velocity < -400) return false;
  return fraction >= 0.5;
}

/// 触觉反馈类型（macOS 语义 → Android HapticFeedback 映射）。
enum MacHaptic { selection, light, medium, heavy }

/// 触觉反馈（带降级）：不支持的平台/设备静默忽略，绝不抛错打断交互。
void macHaptic([MacHaptic kind = MacHaptic.selection]) {
  Future<void> future;
  switch (kind) {
    case MacHaptic.selection:
      future = HapticFeedback.selectionClick();
    case MacHaptic.light:
      future = HapticFeedback.lightImpact();
    case MacHaptic.medium:
      future = HapticFeedback.mediumImpact();
    case MacHaptic.heavy:
      future = HapticFeedback.heavyImpact();
  }
  // 异步错误（部分设备无振动器）吞掉，避免未捕获异常。
  future.catchError((Object _) {});
}
