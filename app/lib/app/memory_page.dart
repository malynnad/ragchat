// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';

import '../chat/app_db.dart';
import 'app_state.dart';
import 'ios_dialogs.dart';
import 'ios_widgets.dart';
import 'theme.dart';

/// 记忆页（US-21）：按 kind 分组的记忆列表 + 手动提取 + 导出导入入口。
class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key});

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

const _kindLabels = {
  MemoryKind.fact: '事实',
  MemoryKind.preference: '偏好',
  MemoryKind.event: '事件',
  MemoryKind.relation: '关系',
};

class _MemoryPageState extends State<MemoryPage> {
  bool _extracting = false;

  Future<void> _extract() async {
    if (_extracting) return;
    final state = AppStateScope.of(context);
    if (state.sessionTurns.isEmpty) {
      await showIosAlert(
        context: context,
        title: '没有可提取的内容',
        message: '当前会话还没有对话记录，先去聊几句再回来提取。',
      );
      return;
    }
    setState(() => _extracting = true);
    try {
      final n = await state.extractMemoriesManually();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(n > 0 ? '提取并保存了 $n 条记忆' : '模型没有提取出新记忆')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('提取失败: $e')));
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  Future<void> _entryActions(MemoryEntry m) async {
    final state = AppStateScope.of(context);
    final action = await showIosActionSheet<String>(
      context: context,
      actions: [
        IosAction('编辑', 'edit'),
        IosAction(m.active ? '停用' : '启用', m.active ? 'deactivate' : 'activate'),
        IosAction('删除', 'delete', destructive: true),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'edit':
        await _editDialog(m);
      case 'deactivate':
        await state.deactivateMemory(m.id);
      case 'activate':
        await state.editMemory(
          m.copyWith(active: true, updatedAt: DateTime.now()),
        );
      case 'delete':
        final ok = await showIosConfirm(
          context: context,
          title: '删除记忆',
          message: '「${m.content}」将被永久删除。',
          confirmLabel: '删除',
          destructive: true,
        );
        if (ok && mounted) await state.deleteMemory(m.id);
    }
  }

  Future<void> _editDialog(MemoryEntry m) async {
    final controller = TextEditingController(text: m.content);
    var importance = m.importance;
    final ok = await showIosSheet<bool>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CupertinoTextField(
              controller: controller,
              maxLines: 3,
              minLines: 1,
              autofocus: true,
              style: TextStyle(fontSize: kFontBody),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '重要度',
                  style: TextStyle(
                    fontSize: kFontCaption,
                    color: CupertinoColors.secondaryLabel.resolveFrom(ctx),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CupertinoSlidingSegmentedControl<int>(
                    groupValue: importance,
                    children: {for (var i = 1; i <= 5; i++) i: Text('$i')},
                    onValueChanged: (v) {
                      if (v != null) importance = v;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: CupertinoButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消'),
                  ),
                ),
                Expanded(
                  child: CupertinoButton.filled(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (ok != true || !mounted) return;
    final content = controller.text.trim();
    if (content.isEmpty || content == m.content && importance == m.importance) {
      return;
    }
    await AppStateScope.of(context).editMemory(
      m.copyWith(
        content: content,
        importance: importance,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final cup = CupertinoTheme.of(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final label = CupertinoColors.label.resolveFrom(context);
    final groups = {
      for (final kind in MemoryKind.values)
        kind: state.memories.where((m) => m.kind == kind).toList(),
    };

    return Scaffold(
      backgroundColor: cup.scaffoldBackgroundColor,
      appBar: CupertinoNavigationBar(
        middle: const Text('记忆'),
        border: null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _extracting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CupertinoActivityIndicator(),
                  )
                : IosNavBarAction(
                    icon: CupertinoIcons.arrow_clockwise,
                    tooltip: '从当前会话提取记忆',
                    onPressed: _extract,
                  ),
          ],
        ),
      ),
      body: state.memories.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  '还没有记忆。\n\n聊天后点右上角按钮从会话提取，\n或开启新对话时自动提取。'
                  '\n记忆会常驻注入聊天，可随时编辑、停用、删除。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: kFontBody, color: secondary),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final kind in MemoryKind.values)
                  if (groups[kind]!.isNotEmpty)
                    IosSection(
                      header: _kindLabels[kind]!,
                      child: Column(
                        children: [
                          for (final m in groups[kind]!)
                            _memoryRow(m, label, secondary),
                        ],
                      ),
                    ),
              ],
            ),
    );
  }

  Widget _memoryRow(MemoryEntry m, Color label, Color secondary) {
    return GestureDetector(
      onTap: () => _entryActions(m),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: CupertinoColors.separator.resolveFrom(context),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.content,
                    style: TextStyle(
                      fontSize: kFontBody,
                      color: m.active ? label : secondary,
                      fontStyle: m.active ? FontStyle.normal : FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '重要度 ${m.importance}${m.active ? '' : ' · 已停用'}',
                    style: TextStyle(fontSize: kFontCaption, color: secondary),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_up_chevron_down,
              size: 14,
              color: secondary,
            ),
          ],
        ),
      ),
    );
  }
}
