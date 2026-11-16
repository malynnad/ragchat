// Apple/iOS 风格共享组件：分组卡片 / 胶囊标签 / 导航栏动作。
// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';

import 'motion.dart';
import 'theme.dart';

/// iOS 分组列表的「一节」：可选节标题 + 圆角分组卡片 + 可选节脚注。
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
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final card = CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
      context,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 6),
              child: Text(
                header!.toUpperCase(),
                style: TextStyle(fontSize: kFontCaption, color: secondary),
              ),
            ),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: contentPadding,
            child: child,
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 6, right: 16),
              child: Text(
                footer!,
                style: TextStyle(fontSize: kFontCaption, color: secondary),
              ),
            ),
        ],
      ),
    );
  }
}

/// iOS 胶囊标签（分类过滤 / 检索范围）：选中=强调色实心，未选=卡片底+描边。
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
    final accent = CupertinoTheme.of(context).primaryColor;
    final card = CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
      context,
    );
    final labelColor = selected
        ? onAccent(accent)
        : CupertinoColors.label.resolveFrom(context);
    final border = CupertinoColors.separator.resolveFrom(context);
    return GestureDetector(
      onTap: () {
        macHaptic();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accent : card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? accent : border, width: 0.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: kFontBody,
            color: labelColor,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// 导航栏图标动作（带 Tooltip，便于无障碍与测试定位）。
/// [onPressed] 为 null 时呈禁用态。
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
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: Size.zero,
        onPressed: onPressed,
        child: Icon(icon, size: 22),
      ),
    );
  }
}

/// 水平可滚动的胶囊标签行（分类多时不溢出）。
class IosPillBar extends StatelessWidget {
  const IosPillBar({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.allLabel = '全部',
  });

  /// 不含「全部」的分类列表；null 选中态由 [selected]==null 表示。
  final List<String> labels;
  final String? selected;
  final ValueChanged<String?> onSelected;
  final String allLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
