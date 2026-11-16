// 开机动画：图标放大 + 透明度归零，然后交给主界面。
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
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
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
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) return widget.child;
    // 0 → .55：放大到 1.18；.55 → 1：透明度归零。
    final scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.86, end: 1.18).chain(
          CurveTween(curve: Curves.easeOutCubic),
        ),
        weight: 55,
      ),
      TweenSequenceItem(tween: ConstantTween(1.18), weight: 45),
    ]).animate(_c);
    final opacity = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 55),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0).chain(
          CurveTween(curve: Curves.easeInCubic),
        ),
        weight: 45,
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
                'assets/branding/whale-512.png',
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
