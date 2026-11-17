// 纸页与档案（paper-archive-ui）：令牌 + 基础件。
//
// 五条硬约束的落点：
// 1. 纸在上、玻璃在下——页面底色是渐变纸，毛玻璃只给 dock / 图标按钮 / 弹层。
// 2. 前景永远清晰——文字不投影不发光，模糊只在身后。
// 3. 编号是结构——区块 `01 / SECTION`，记录 `WK-00012`。
// 4. 动效一次性落定——120ms 接触、420ms 落定，无循环。
// 5. 几何克制——纸面板圆角 4、控件胶囊、发丝线 0.5–0.7、触控 ≥48。
// ignore: deprecated_member_use
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';

import 'motion.dart';
import 'theme.dart';

/// 纸与墨的两套色（浅 / 深）。不新增彩色强调色，层级只靠明度。
class PaperPalette {
  const PaperPalette({
    required this.bg,
    required this.surface,
    required this.milk,
    required this.hairline,
    required this.ink,
    required this.muted,
    required this.raised,
    required this.raisedHigh,
  });

  final Color bg;
  final Color surface;
  final Color milk;
  final Color hairline;
  final Color ink;
  final Color muted;
  final Color raised;
  final Color raisedHigh;

  static const light = PaperPalette(
    bg: Color(0xFFF4F3EF),
    surface: Color(0xFFFDFCFA),
    milk: Color(0xFFFEFDF8),
    hairline: Color(0xFFD8DBD5),
    ink: Color(0xFF181818),
    muted: Color(0xFF646B62),
    raised: Color(0xFFFFFFFF),
    raisedHigh: Color(0xFFF2F1EC),
  );

  static const dark = PaperPalette(
    bg: Color(0xFF191919),
    surface: Color(0xFF242424),
    milk: Color(0xFFF6F6F6),
    hairline: Color(0xFF3C3C3C),
    ink: Color(0xFFF2F2F2),
    muted: Color(0xFFB7B7B7),
    raised: Color(0xFF2D2D2D),
    raisedHigh: Color(0xFF3A3A3A),
  );

  /// 开关打开、滑块已选、强调文字的推导色（明度插值，不引入新色号）。
  Color get active => Color.lerp(ink, surface, 0.48)!;
  Color get track => Color.lerp(surface, ink, 0.10)!;
}

PaperPalette paperOf(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? PaperPalette.dark
    : PaperPalette.light;

/// 键盘开合状态往外传：页面里的底部留白要据此让位给 dock 或键盘。
/// 外层 Scaffold 会把 viewInsets 从子树里移掉，页面自己读不到，只能由 shell 传。
class KeyboardDockScope extends InheritedWidget {
  const KeyboardDockScope({
    super.key,
    required this.keyboardOpen,
    required super.child,
  });

  final bool keyboardOpen;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<KeyboardDockScope>()
          ?.keyboardOpen ??
      false;

  @override
  bool updateShouldNotify(KeyboardDockScope old) =>
      old.keyboardOpen != keyboardOpen;
}

/// 版面常量。
const double kPageMargin = 24;
const double kToolbarHeight = 56;
const double kDockHeight = 54;
const double kDockItemWidth = 61.33;

/// 悬空 dock 占掉的高度（胶囊 + 安全区留白），底部有输入条的页面自己让位。
const double kDockReserve = 96;

/// 接触 / 落定（动效只允许这两个主时长）。
const Duration kContact = Duration(milliseconds: 120);
const Duration kSettle = Duration(milliseconds: 420);
const Curve kSettleCurve = Cubic(.2, 1.08, .34, 1);

/// 纸面：页面底色渐变 + 页头网格（只占页头 240，不铺满）。
class Atmosphere extends StatelessWidget {
  const Atmosphere({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = paperOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark ? [p.bg, p.surface] : [p.surface, p.bg],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _HeaderGridPainter(color: p.ink, dark: dark),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// 页头层：48px 网格 + 两块斜切薄膜 + 两枚定位十字（alpha .15）。
class _HeaderGridPainter extends CustomPainter {
  _HeaderGridPainter({required this.color, required this.dark});

  final Color color;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    const headerZone = 240.0;
    final zone = Size(size.width, headerZone);
    final line = Paint()
      ..color = color.withValues(alpha: 0.045)
      ..strokeWidth = 0.5;

    for (var y = 0.0; y < zone.height; y += 48) {
      canvas.drawLine(Offset(0, y), Offset(zone.width, y), line);
    }
    for (var x = kPageMargin; x < zone.width; x += 48) {
      canvas.drawLine(Offset(x, 0), Offset(x, zone.height), line);
    }

    // 斜切薄膜：两块，都只在页头。
    final film = Paint()
      ..color = (dark ? color : const Color(0xFFFFFFFF)).withValues(
        alpha: dark ? 0.012 : 0.42,
      );
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .42, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, 84)
        ..close(),
      film,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .60, 18)
        ..lineTo(size.width, 18)
        ..lineTo(size.width, 132)
        ..close(),
      Paint()
        ..color = (dark ? color : const Color(0xFFFFFFFF)).withValues(
          alpha: dark ? 0.018 : 0.28,
        ),
    );

    // 定位十字：两侧各一枚，臂长 3。
    final cross = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..strokeWidth = 0.7
      ..strokeCap = StrokeCap.round;
    for (final x in [kPageMargin, size.width - kPageMargin]) {
      const y = 60.0;
      canvas.drawLine(Offset(x - 3, y), Offset(x + 3, y), cross);
      canvas.drawLine(Offset(x, y - 3), Offset(x, y + 3), cross);
    }
  }

  @override
  bool shouldRepaint(_HeaderGridPainter old) =>
      old.color != color || old.dark != dark;
}

/// 档案码：等宽 9 / 500 / 1.05，属于印刷标记不参与字体缩放。
class ArchiveCode extends StatelessWidget {
  const ArchiveCode(this.text, {super.key, this.inverse = false});

  final String text;
  final bool inverse;

  @override
  Widget build(BuildContext context) {
    final p = paperOf(context);
    return Container(
      padding: inverse
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 3)
          : EdgeInsets.zero,
      color: inverse ? p.ink : null,
      child: Text(
        text,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: 9,
          height: 1.35,
          letterSpacing: 1.05,
          fontWeight: FontWeight.w500,
          fontFamily: 'monospace',
          color: inverse ? p.milk : p.muted,
        ),
      ),
    );
  }
}

/// 区块：`01 / SYNOPSIS` + 发丝线 + 墨点 → 标题 18/700 → 5 → 副标题 12。
class ArchiveSection extends StatelessWidget {
  const ArchiveSection({
    super.key,
    required this.title,
    this.code,
    this.subtitle,
    this.trailing,
    required this.child,
  });

  final String title;
  final String? code;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = paperOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kPageMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (code != null) ArchiveCode(code!),
              if (code != null) const SizedBox(width: 9),
              Expanded(
                child: Container(
                  height: 0.6,
                  color: p.ink.withValues(alpha: 0.18),
                ),
              ),
              const SizedBox(width: 9),
              Container(
                width: 3,
                height: 3,
                color: p.ink.withValues(alpha: .55),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
          const SizedBox(height: 7),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              height: 1.25,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: p.ink,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 5),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 12, height: 1.5, color: p.muted),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// 纸卡：圆角 4、0.7 描边、内边距 16、四角定位标。
class ContentPanel extends StatefulWidget {
  const ContentPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  State<ContentPanel> createState() => _ContentPanelState();
}

class _ContentPanelState extends State<ContentPanel> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = paperOf(context);
    final card = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: p.hairline, width: 0.7),
      ),
      padding: widget.padding,
      child: widget.child,
    );

    if (widget.onTap == null) return card;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
        setState(() => _down = true);
      },
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        macHaptic();
        widget.onTap!();
      },
      child: AnimatedScale(
        scale: _down ? .975 : 1,
        duration: _down ? kContact : kSettle,
        curve: kSettleCurve,
        child: card,
      ),
    );
  }
}

/// 玻璃基材：模糊 8 + 奶白 87%，亮边只在左上，投影只在轮廓外。
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.radius,
    this.padding = EdgeInsets.zero,
    this.width,
    this.height,
  });

  final Widget child;
  final double? radius;
  final EdgeInsets padding;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final p = paperOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final r = radius ?? 28;
    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: p.milk.withValues(alpha: 0.87),
            borderRadius: BorderRadius.circular(r),
            border: Border.all(
              color: dark
                  ? p.ink.withValues(alpha: 0.06)
                  : const Color(0xFFFFFFFF).withValues(alpha: 0.55),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 玻璃图标按钮：46×46，圆角 23，图标 21。
class GlassIconButton extends StatefulWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  State<GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<GlassIconButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = paperOf(context);
    final enabled = widget.onPressed != null;
    return Semantics(
      label: widget.label,
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled
            ? (_) {
                if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
                  return;
                }
                setState(() => _down = true);
              }
            : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: enabled
            ? () {
                macHaptic();
                widget.onPressed!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? .97 : 1,
          duration: _down ? kContact : kSettle,
          curve: kSettleCurve,
          child: LiquidGlass(
            radius: 23,
            width: 46,
            height: 46,
            child: Center(
              child: Icon(
                widget.icon,
                size: 21,
                color: p.ink.withValues(alpha: enabled ? 1 : .4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 玻璃文字按钮：最小 64×48，圆角 22，文字 14/500。
class GlassTextButton extends StatefulWidget {
  const GlassTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool selected;
  final bool destructive;

  @override
  State<GlassTextButton> createState() => _GlassTextButtonState();
}

class _GlassTextButtonState extends State<GlassTextButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = paperOf(context);
    final enabled = widget.onPressed != null;
    final color = !enabled
        ? p.ink.withValues(alpha: .45)
        : widget.destructive
        ? const Color(0xFFB3261E)
        : p.ink;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled
            ? (_) {
                if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
                  return;
                }
                setState(() => _down = true);
              }
            : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: enabled
            ? () {
                macHaptic();
                widget.onPressed!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? .97 : 1,
          duration: _down ? kContact : kSettle,
          curve: kSettleCurve,
          child: LiquidGlass(
            radius: 22,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 64, minHeight: 28),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: widget.selected
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 按住才会触发的危险按钮：按下去红色从左往右填满一格（默认 0.9s），
/// 填满才回调；中途松手立刻回退，不弹窗。
class HoldToConfirmButton extends StatefulWidget {
  const HoldToConfirmButton({
    super.key,
    required this.label,
    required this.onCompleted,
    this.hold = const Duration(milliseconds: 900),
  });

  final String label;
  final VoidCallback onCompleted;
  final Duration hold;

  @override
  State<HoldToConfirmButton> createState() => _HoldToConfirmButtonState();
}

class _HoldToConfirmButtonState extends State<HoldToConfirmButton>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.hold);
  bool _fired = false;

  static const _danger = Color(0xFFB3261E);

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && !_fired) {
        _fired = true;
        macHaptic(MacHaptic.medium);
        widget.onCompleted();
        // 复位，等下一次按住重新填。
        Future<void>.delayed(const Duration(milliseconds: 220), () {
          if (mounted) _c.value = 0;
        });
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _down(_) {
    _fired = false;
    _c.forward(from: 0);
  }

  void _up() {
    if (!_fired && _c.isAnimating) {
      _c.animateBack(0, duration: const Duration(milliseconds: 200));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = paperOf(context);
    return Semantics(
      button: true,
      label: widget.label,
      hint: '按住不放，进度填满后弹出确认',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _down,
        onTapUp: (_) => _up(),
        onTapCancel: _up,
        child: LayoutBuilder(
          builder: (context, constraints) => AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final v = _c.value;
              final textColor = Color.lerp(
                _danger,
                p.milk,
                (v * 1.6).clamp(0, 1),
              )!;
              return Container(
                height: 48,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _danger.withValues(alpha: .7),
                    width: 0.7,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: constraints.maxWidth * v,
                      child: const ColoredBox(color: _danger),
                    ),
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.trash,
                            size: 17,
                            color: textColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.label,
                            style: TextStyle(
                              fontSize: kFontControl,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 页头：56 工具栏 + 羽化；标题居中（14/700）+ 3px 档案码。
class ArchiveHeaderBar extends StatelessWidget {
  const ArchiveHeaderBar({
    super.key,
    required this.title,
    this.code,
    this.leading,
    this.actions,
  });

  final String title;
  final String? code;
  final Widget? leading;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final p = paperOf(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            p.surface.withValues(alpha: .94),
            p.surface.withValues(alpha: .72),
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kPageMargin),
            child: Row(
              children: [
                ?leading,
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: p.ink,
                        ),
                      ),
                      if (code != null) ...[
                        const SizedBox(height: 3),
                        ArchiveCode(code!),
                      ],
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: actions ?? const [],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 页面骨架：纸 + 页头 + 滚动体 + （可选）玻璃 dock。
class PaperScaffold extends StatelessWidget {
  const PaperScaffold({
    super.key,
    required this.title,
    this.code,
    this.leading,
    this.actions,
    required this.body,
    this.bottomBar,
    this.scrollable = true,
    this.padding,
  });

  final String title;
  final String? code;
  final Widget? leading;
  final List<Widget>? actions;
  final Widget body;
  final Widget? bottomBar;
  final bool scrollable;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final content = body;
    // 用 Scaffold 兜住 ScaffoldMessenger / SnackBar / 软键盘 inset；
    // 底色透明，纸面来自 Atmosphere。
    return Scaffold(
      backgroundColor: Colors.transparent,
      // 键盘 inset 由外层 shell 的 Scaffold 统一处理，内层再缩一次会重复让位。
      resizeToAvoidBottomInset: false,
      body: Atmosphere(
        child: Column(
          children: [
            ArchiveHeaderBar(
              title: title,
              code: code,
              leading: leading,
              actions: actions,
            ),
            Expanded(
              child: scrollable
                  ? ListView(
                      padding:
                          padding ?? const EdgeInsets.fromLTRB(0, 20, 0, 120),
                      children: [content],
                    )
                  : content,
            ),
            ?bottomBar,
          ],
        ),
      ),
    );
  }
}

/// 底部玻璃 dock：54 高胶囊，项宽 61.33，选中为 12×1.5 墨线。
class GlassDock extends StatelessWidget {
  const GlassDock({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<GlassDockItem> items;

  @override
  Widget build(BuildContext context) {
    final p = paperOf(context);
    final width = kDockItemWidth * items.length + 12;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: Center(
          child: LiquidGlass(
            radius: kDockHeight / 2,
            width: width,
            height: kDockHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < items.length; i++)
                  _DockItem(
                    item: items[i],
                    selected: i == selectedIndex,
                    ink: p.ink,
                    muted: p.muted,
                    onTap: () {
                      if (i == selectedIndex) return;
                      macHaptic();
                      onSelected(i);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GlassDockItem {
  const GlassDockItem(this.icon, this.label, {this.activeIcon});

  final IconData icon;
  final String label;
  final IconData? activeIcon;
}

class _DockItem extends StatefulWidget {
  const _DockItem({
    required this.item,
    required this.selected,
    required this.ink,
    required this.muted,
    required this.onTap,
  });

  final GlassDockItem item;
  final bool selected;
  final Color ink;
  final Color muted;
  final VoidCallback onTap;

  @override
  State<_DockItem> createState() => _DockItemState();
}

class _DockItemState extends State<_DockItem> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final color = widget.selected ? widget.ink : widget.muted;
    return Semantics(
      label: item.label,
      button: true,
      selected: widget.selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
          setState(() => _down = true);
        },
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: SizedBox(
          width: kDockItemWidth,
          height: kDockHeight,
          child: AnimatedScale(
            scale: _down ? .97 : 1,
            duration: _down ? kContact : kSettle,
            curve: kSettleCurve,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.selected ? (item.activeIcon ?? item.icon) : item.icon,
                  size: 20,
                  color: color,
                ),
                const SizedBox(height: 3),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: widget.selected
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  width: 12,
                  height: 1.5,
                  color: widget.selected ? widget.ink : Colors.transparent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
