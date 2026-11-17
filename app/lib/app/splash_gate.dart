// 开机动画：图标落在屏幕中央（120%），停 0.5s，然后急速放大冲出画面并淡出。
// 一次性落定，不循环；开启「减少动态效果」时直接跳过。
// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';

import 'paper.dart';

class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child});

  /// 动画结束后要显示的内容（主界面或模型准备页）。
  final Widget child;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  /// 0–55%（约 0.5s）停留，55–100% 冲出画面并淡出。
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _done = true);
      }
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return widget.child;
    }

    // 登场：120ms 内从 0.9 微弹到 1.2，然后停住。
    final scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.9, end: 1.2).chain(
          CurveTween(curve: Curves.easeOutCubic),
        ),
        weight: 14,
      ),
      TweenSequenceItem(tween: ConstantTween(1.2), weight: 42),
      // 冲出画面：168 × 1.2 → 168 × 18，盖满 2780px 高的屏幕。
      TweenSequenceItem(
        tween: Tween(begin: 1.2, end: 18.0).chain(
          CurveTween(curve: Curves.easeInCubic),
        ),
        weight: 44,
      ),
    ]).animate(_c);

    final opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0).chain(
          CurveTween(curve: Curves.easeOut),
        ),
        weight: 10,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 48),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0).chain(
          CurveTween(curve: Curves.easeIn),
        ),
        weight: 42,
      ),
    ]).animate(_c);

    return Atmosphere(
      child: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Opacity(
            opacity: opacity.value,
            child: Transform.scale(
              scale: scale.value,
              child: Image.asset(
                'assets/branding/whale-splash.png',
                width: 168,
                height: 168,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
