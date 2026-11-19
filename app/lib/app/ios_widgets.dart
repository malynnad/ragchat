// 纸页与档案的共享件（原 iOS 分组样式已并入 paper.dart 的纸卡 / 玻璃件）。
// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';

import 'motion.dart';
import 'paper.dart';
import 'theme.dart';

/// 设置 / 列表里的一节：小号档案码 + 纸卡 + 可选脚注。
/// 语义沿用原 IosSection（header / footer / child），视觉换成纸。
class IosSection extends StatelessWidget {
  const IosSection({
    super.key,
    this.header,
    this.footer,
    this.info,
    required this.child,
    this.contentPadding = const EdgeInsets.all(16),
  });

  final String? header;
  final String? footer;

  /// 有它就不显示 footer：说明收进 header 右侧的小圆圈，点开是气泡。
  final String? info;
  final Widget child;
  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context) {
    final p = paperOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kPageMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null) ...[
            Row(
              children: [
                Text(
                  header!.toUpperCase(),
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: kFontCode,
                    letterSpacing: 1.05,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w500,
                    color: p.muted,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Container(
                    height: 0.6,
                    color: p.ink.withValues(alpha: 0.18),
                  ),
                ),
                if (info != null) ...[
                  const SizedBox(width: 8),
                  InfoDot(message: info!),
                ],
              ],
            ),
            const SizedBox(height: 8),
          ],
          ContentPanel(padding: contentPadding, child: child),
          if (footer != null && info == null) ...[
            const SizedBox(height: 8),
            Text(
              footer!,
              style: TextStyle(
                fontSize: kFontCaption,
                height: 1.5,
                color: p.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 胶囊标签：选中=墨色实心 + 奶白字，未选=透明底 + 发丝描边。
class IosPill extends StatelessWidget {
  const IosPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = paperOf(context);
    return GestureDetector(
      onTap: () {
        macHaptic();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? p.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: p.hairline, width: 0.7),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: kFontControl,
            color: selected ? p.milk : p.ink,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// 页头动作（46 宽命中区内的图标按钮，供测试与无障碍定位）。
class IosNavBarAction extends StatelessWidget {
  const IosNavBarAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 46,
        height: 46,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: onPressed,
          child: Icon(icon, size: 21),
        ),
      ),
    );
  }
}

/// 水平可滚动的胶囊标签行。
class IosPillBar extends StatelessWidget {
  const IosPillBar({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.allLabel = '全部',
  });

  final List<String> labels;
  final String? selected;
  final ValueChanged<String?> onSelected;
  final String allLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: kPageMargin, vertical: 4),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IosPill(
              label: allLabel,
              selected: selected == null,
              onTap: () => onSelected(null),
            ),
          ),
          for (final c in labels)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IosPill(
                label: c,
                selected: selected == c,
                onTap: () => onSelected(c),
              ),
            ),
        ],
      ),
    );
  }
}


/// 小圆圈里的「!」：点开在它下方弹一个纸卡气泡，承接原本的脚注说明。
class InfoDot extends StatelessWidget {
  const InfoDot({super.key, required this.message, this.size = 18});

  final String message;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = paperOf(context);
    return Semantics(
      button: true,
      label: '说明',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showInfoBubble(context, message),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: p.muted, width: 1),
          ),
          child: Text(
            '!',
            style: TextStyle(
              fontSize: size * 0.62,
              height: 1,
              fontWeight: FontWeight.w600,
              color: p.muted,
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showInfoBubble(BuildContext context, String message) async {
  final box = context.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) return;
  final pos = box.localToGlobal(Offset.zero, ancestor: overlay);
  const width = 262.0;
  final screenW = overlay.size.width;
  final left = (pos.dx - width + box.size.width).clamp(
    12.0,
    screenW - width - 12,
  );
  var top = pos.dy + box.size.height + 8;
  final maxTop = overlay.size.height - 180;
  if (top > maxTop) top = pos.dy - 150;

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭说明',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (c, _, _) => Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          child: Material(
            color: Colors.transparent,
            child: ContentPanel(
              padding: const EdgeInsets.all(14),
              child: Text(
                message,
                style: TextStyle(
                  fontSize: kFontCaption,
                  height: 1.55,
                  color: paperOf(c).ink,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
    transitionBuilder: (c, a, _, child) =>
        FadeTransition(opacity: a, child: child),
  );
}
