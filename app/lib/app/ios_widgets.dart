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
    required this.child,
    this.contentPadding = const EdgeInsets.all(16),
  });

  final String? header;
  final String? footer;
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
              ],
            ),
            const SizedBox(height: 8),
          ],
          ContentPanel(
            padding: contentPadding,
            registration: false,
            child: child,
          ),
          if (footer != null) ...[
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
