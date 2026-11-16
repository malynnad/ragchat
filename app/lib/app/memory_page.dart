// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';

import '../chat/app_db.dart';
import 'app_state.dart';
import 'ios_dialogs.dart';
import 'ios_widgets.dart';
import 'paper.dart';
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
    final p = paperOf(context);
    final flat = state.memories;
    return PaperScaffold(
      title: '记忆',
      code: '02 / MEMORY',
      scrollable: false,
      actions: [
        _extracting
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CupertinoActivityIndicator(),
                ),
              )
            : IosNavBarAction(
                icon: CupertinoIcons.arrow_clockwise,
                tooltip: '从当前会话提取记忆',
                onPressed: _extract,
              ),
      ],
      body: state.memories.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.archivebox,
                      size: 34,
                      color: p.ink.withValues(alpha: .35),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '还没有记忆',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: p.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '聊过几轮后从会话里提取，或开启新对话时自动整理。'
                      '记忆会常驻注入聊天，可随时编辑、停用、删除。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: kFontCaption,
                        height: 1.6,
                        color: p.muted,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, 20, 0, 120),
              children: [
                ArchiveSection(
                  code: '01 / RECORDS',
                  title: '记忆条目',
                  subtitle: '共 ${flat.length} 条；点一条可编辑、停用或删除',
                  child: const SizedBox.shrink(),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < flat.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kPageMargin,
                      ),
                      child: ContentPanel(
                        padding: const EdgeInsets.all(18),
                        onTap: () => _entryActions(flat[i]),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                ArchiveCode(
                                  'WK-${(i + 1).toString().padLeft(5, '0')}',
                                ),
                                const SizedBox(width: 9),
                                Text(
                                  _kindLabels[flat[i].kind]!,
                                  style: TextStyle(
                                    fontSize: kFontCode,
                                    letterSpacing: 1.05,
                                    color: p.muted,
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  CupertinoIcons.chevron_up_chevron_down,
                                  size: 14,
                                  color: p.muted,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              flat[i].content,
                              style: TextStyle(
                                fontSize: kFontBody,
                                height: 1.5,
                                color: flat[i].active ? p.ink : p.muted,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '重要度 ${flat[i].importance}'
                              '${flat[i].active ? '' : ' · 已停用'}',
                              style: TextStyle(
                                fontSize: kFontCode,
                                letterSpacing: 1.05,
                                color: p.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
