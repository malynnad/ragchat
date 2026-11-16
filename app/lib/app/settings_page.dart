// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../rag/model_catalog.dart';
import '../rag/token_budget.dart';
import '../verify_page.dart';
import 'app_state.dart';
import 'format.dart';
import 'ios_dialogs.dart';
import 'ios_widgets.dart';
import 'paper.dart';
import 'persona.dart';
import 'persona_editor.dart';
import 'theme.dart';

/// 设置：模型切换/候选下载、人设卡、后端开关、存储占用、
/// 一键清空聊天数据（二次确认）。iOS 风格。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final stats = state.storageStats();
    return PaperScaffold(
      title: '设置',
      code: '03 / CONFIG',
      body: Column(
        children: [
          _modelSection(context, state),
          const SizedBox(height: 28),
          _CatalogSection(state: state),
          const SizedBox(height: 28),
          const _PersonaSection(),
          const SizedBox(height: 28),
          _gpuSection(context, state),
          const SizedBox(height: 28),
          _storageSection(context, stats),
          const SizedBox(height: 28),
          _clearButton(context, state),
          const SizedBox(height: 28),
          _verifySection(context),
        ],
      ),
    );
  }

  /// v2 P2：角色选择（动作表切换本地 GGUF）+ 重新扫描/重载。
  Widget _modelSection(BuildContext context, AppState state) {
    final s = state.settings;
    final chatPaths = state
        .filesForRole(isChat: true)
        .map((f) => f.path)
        .toList();
    final embedPaths = state
        .filesForRole(isChat: false)
        .map((f) => f.path)
        .toList();
    final busy = state.downloadProgress != null;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return IosSection(
      header: '01 / MODEL',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _rolePicker(
            context,
            state,
            isChat: true,
            paths: chatPaths,
            enabled: !busy,
          ),
          const Divider(height: 16),
          _rolePicker(
            context,
            state,
            isChat: false,
            paths: embedPaths,
            enabled: !busy,
          ),
          const SizedBox(height: 8),
          Text(
            state.gatewayLoaded
                ? '已加载（${s.useGpu ? "Vulkan GPU" : "CPU"} 后端）'
                : '未加载',
            style: TextStyle(fontSize: kFontCaption, color: secondary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                minimumSize: Size.zero,
                onPressed: busy ? null : state.rescanModels,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.refresh, size: 18),
                    SizedBox(width: 4),
                    Text('重新扫描', style: TextStyle(fontSize: kFontBody)),
                  ],
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                minimumSize: Size.zero,
                onPressed: busy ? null : state.reloadModels,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.play_circle, size: 18),
                    SizedBox(width: 4),
                    Text('重新加载', style: TextStyle(fontSize: kFontBody)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rolePicker(
    BuildContext context,
    AppState state, {
    required bool isChat,
    required List<String> paths,
    required bool enabled,
  }) {
    final current = isChat
        ? state.settings.chatModelPath
        : state.settings.embedModelPath;
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 6),
      onPressed: enabled
          ? () => _pickModel(context, state, isChat, paths)
          : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isChat ? '聊天模型' : '嵌入模型（可选，v2 情景记忆用）',
                  style: TextStyle(fontSize: kFontCaption, color: secondary),
                ),
                const SizedBox(height: 2),
                Text(
                  current == null ? '未选择' : p.basename(current),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: kFontBody, color: label),
                ),
              ],
            ),
          ),
          Icon(CupertinoIcons.chevron_right, size: 18, color: secondary),
        ],
      ),
    );
  }

  Future<void> _pickModel(
    BuildContext context,
    AppState state,
    bool isChat,
    List<String> paths,
  ) async {
    if (paths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isChat ? '未找到可用的聊天模型，请先下载或导入' : '未找到可用的嵌入模型，请先下载或导入'),
        ),
      );
      return;
    }
    final current = isChat
        ? state.settings.chatModelPath
        : state.settings.embedModelPath;
    final v = await showIosActionSheet<String>(
      context: context,
      title: isChat ? '选择聊天模型' : '选择嵌入模型',
      actions: [for (final path in paths) IosAction(p.basename(path), path)],
    );
    if (v != null && v != current && context.mounted) {
      await _confirmSwitch(context, state, isChat: isChat, path: v);
    }
  }

  Future<void> _confirmSwitch(
    BuildContext context,
    AppState state, {
    required bool isChat,
    required String path,
  }) async {
    final ok = await showIosConfirm(
      context: context,
      title: isChat ? '切换聊天模型' : '切换嵌入模型',
      message: isChat
          ? '将重新加载模型（数十秒），之后聊天使用新模型。'
          : '嵌入模型仅用于后续情景记忆；MVP 聊天不依赖它。\n\n继续切换？',
      confirmLabel: '切换',
    );
    if (ok) {
      await state.switchModel(isChat: isChat, path: path);
    }
  }

  Widget _gpuSection(BuildContext context, AppState state) {
    final s = state.settings;
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final accent = paperOf(context).ink;
    return IosSection(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vulkan GPU 加速',
                  style: TextStyle(fontSize: kFontBody, color: label),
                ),
                const SizedBox(height: 2),
                Text(
                  '本机实测 CPU 更快且更省内存（ADR-0005）；切换需重新加载模型',
                  style: TextStyle(fontSize: kFontCaption, color: secondary),
                ),
              ],
            ),
          ),
          CupertinoSwitch(
            value: s.useGpu,
            activeTrackColor: accent,
            onChanged: (v) => _confirmGpu(context, state, v),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmGpu(
    BuildContext context,
    AppState state,
    bool value,
  ) async {
    final ok = await showIosConfirm(
      context: context,
      title: '切换推理后端',
      message:
          '将重新加载两个模型（数十秒）。'
          '本机实测：CPU 比 Vulkan 更快、内存余量更大（ADR-0005）。',
      confirmLabel: '切换',
    );
    if (ok) await state.updateUseGpu(value);
  }

  Widget _storageSection(
    BuildContext context,
    ({int dbBytes, int modelBytes}) stats,
  ) {
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: TextStyle(fontSize: kFontBody, color: label),
            ),
          ),
          Text(
            v,
            style: TextStyle(fontSize: kFontBody, color: secondary),
          ),
        ],
      ),
    );
    return IosSection(
      header: '04 / STORAGE',
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          row('聊天数据 DB', formatBytes(stats.dbBytes)),
          const Divider(height: 1),
          row('模型文件', formatBytes(stats.modelBytes)),
        ],
      ),
    );
  }

  Widget _clearButton(BuildContext context, AppState state) {
    return IosSection(
      contentPadding: EdgeInsets.zero,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(vertical: 14),
        onPressed: () => _confirmClear(context, state),
        child: Text(
          '清空聊天数据（二次确认）',
          style: TextStyle(
            fontSize: kFontBody,
            color: CupertinoColors.systemRed.resolveFrom(context),
          ),
        ),
      ),
    );
  }

  /// US-10：二次确认后才清空。
  Future<void> _confirmClear(BuildContext context, AppState state) async {
    final first = await showIosConfirm(
      context: context,
      title: '清空聊天数据',
      message: '将删除全部会话记录。模型文件保留。',
      confirmLabel: '继续',
    );
    if (!first || !context.mounted) return;
    final second = await showIosConfirm(
      context: context,
      title: '再次确认',
      message: '此操作不可恢复。还会删除全部记忆，确定继续？',
      confirmLabel: '清空',
      destructive: true,
    );
    if (second) {
      try {
        await state.clearAllData();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('清空失败: $e')));
        }
      }
    }
  }

  Widget _verifySection(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return IosSection(
      contentPadding: EdgeInsets.zero,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        onPressed: () =>
            Navigator.of(context)
                .push(CupertinoPageRoute(builder: (_) => const VerifyPage())),
        child: Row(
          children: [
            Icon(CupertinoIcons.ant, size: 20, color: secondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '真机诊断',
                    style: TextStyle(fontSize: kFontBody, color: label),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'nobodywho 加载 / 测速 / 内存验证页',
                    style: TextStyle(fontSize: kFontCaption, color: secondary),
                  ),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right, size: 18, color: secondary),
          ],
        ),
      ),
    );
  }
}

/// v2 P2：候选模型目录下载（hf-mirror，HEAD 已验证）。可折叠分组。
class _CatalogSection extends StatefulWidget {
  const _CatalogSection({required this.state});

  final AppState state;

  @override
  State<_CatalogSection> createState() => _CatalogSectionState();
}

class _CatalogSectionState extends State<_CatalogSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final busy = state.downloadProgress != null;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    // v2 bugfix：候选先按类型（生成→嵌入）再按体积升序。
    final sorted = sortedCatalog();
    return IosSection(
      header: '02 / CANDIDATES',
      contentPadding: EdgeInsets.zero,
      child: Column(
        children: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '国内镜像；下载即切换，不支持断点续传',
                    style: TextStyle(fontSize: kFontBody, color: secondary),
                  ),
                ),
                Icon(
                  _expanded
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 18,
                  color: secondary,
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            // v2 圆环进度：进度改为"正在下载那一行"的行内圆环（见 _catalogRow），
            // 移除原顶部全局线性条（离屏导致用户看不到下载已开始）。
            for (final m in sorted) _catalogRow(context, state, m, busy: busy),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Text(
                '只留聊天够用的两档：0.6B 更快，2B 更稳。'
                '嵌入模型只在 v2 情景记忆时用得上，聊天不必装。',
                style: TextStyle(fontSize: kFontCaption, color: secondary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// v2 bugfix：候选行。已下载（URL 文件名忽略大小写匹配本机模型列表，
  /// 含 nobodywho 缓存；本机文件名为小写）显示 ✓「已下载」灰态；
  /// 未下载显示云朵下载按钮。
  Widget _catalogRow(
    BuildContext context,
    AppState state,
    CatalogModel m, {
    required bool busy,
  }) {
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final accent = paperOf(context).ink;
    final divider = CupertinoColors.separator.resolveFrom(context);
    final urlName = p.basename(m.url).toLowerCase();
    final downloaded = state.modelFiles.any(
      (f) => f.name.toLowerCase() == urlName,
    );
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: divider, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.label,
                  style: TextStyle(
                    fontSize: kFontBody,
                    fontWeight: FontWeight.w600,
                    color: label,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatBytes(m.sizeBytes)} · ${m.note}',
                  style: TextStyle(fontSize: kFontCaption, color: secondary),
                ),
              ],
            ),
          ),
          if (state.downloadingUrl == m.url)
            // v2 圆环进度：正在下载的这一行，云朵位置换圆环+百分比，
            // 点按瞬间即现 0% 圆环，用户立刻知道"已开始、下的是哪个"。
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      value: state.downloadProgress ?? 0,
                      strokeWidth: 2.5,
                      color: accent,
                      backgroundColor: divider,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${((state.downloadProgress ?? 0) * 100).round()}%',
                    style: TextStyle(fontSize: kFontCaption, color: secondary),
                  ),
                ],
              ),
            )
          else if (downloaded)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.check_mark_circled_solid,
                    size: 20,
                    color: secondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '已下载',
                    style: TextStyle(fontSize: kFontCaption, color: secondary),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.only(left: 8),
                    minimumSize: Size.zero,
                    onPressed: busy
                        ? null
                        : () => _confirmDelete(context, state, m),
                    child: Icon(
                      CupertinoIcons.trash,
                      size: 20,
                      color: secondary,
                    ),
                  ),
                ],
              ),
            )
          else
            CupertinoButton(
              padding: const EdgeInsets.only(left: 8),
              minimumSize: Size.zero,
              onPressed: busy
                  ? null
                  : () async {
                      try {
                        await state.downloadModel(isChat: m.isChat, url: m.url);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('下载失败（可重试或手动导入）: $e')),
                          );
                        }
                      }
                    },
              child: Icon(
                CupertinoIcons.cloud_download,
                size: 22,
                color: accent,
              ),
            ),
        ],
      ),
    );
  }

  /// v2 删除已下载模型：iOS 确认弹层 → deleteModel（带活跃/下载中安全闸）。
  Future<void> _confirmDelete(
    BuildContext context,
    AppState state,
    CatalogModel m,
  ) async {
    final urlName = p.basename(m.url).toLowerCase();
    final matches = state.modelFiles.where(
      (f) => f.name.toLowerCase() == urlName,
    );
    if (matches.isEmpty) return;
    final path = matches.first.path;
    final ok = await showIosConfirm(
      context: context,
      title: '删除模型',
      message: '删除 ${m.label} 的本机文件？删除后需重新下载。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final err = await state.deleteModel(path);
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }
}

/// 人设（单卡）：显示当前这张、进编辑器改正文、可恢复内置预设。
/// 改完写进 settings.json，下一轮 system 消息立即用新文本。
class _PersonaSection extends StatelessWidget {
  const _PersonaSection();

  Future<void> _edit(
    BuildContext context,
    AppState state,
    PersonaCard card,
  ) async {
    final edited = await showPersonaEditor(context, initial: card);
    if (edited == null) return;
    await state.savePersona(edited);
  }

  Future<void> _reset(BuildContext context, AppState state) async {
    final ok = await showIosConfirm(
      context: context,
      title: '恢复默认人设',
      message: '现在写的这段会被内置「${builtinPersonas.first.name}」替换，回不来。',
      confirmLabel: '替换',
      destructive: true,
    );
    if (ok) await state.resetPersona();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final card = state.activePersonaCard();
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final label = CupertinoColors.label.resolveFrom(context);
    final used = estimateTokens(card.render());
    return IosSection(
      header: '03 / PERSONA',
      footer:
          '只有这一张，和长期记忆共用 800 token 的 system 预算（人设建议 ≤$personaSoftBudgetTokens）；改完下一轮生效。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.name.isEmpty ? '未命名' : card.name,
                      style: TextStyle(fontSize: kFontBody, color: label),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '≈ $used token',
                      style: TextStyle(
                        fontSize: kFontCaption,
                        color: used > personaSoftBudgetTokens
                            ? CupertinoColors.systemRed.resolveFrom(context)
                            : secondary,
                      ),
                    ),
                  ],
                ),
              ),
              CupertinoButton(
                key: const ValueKey('persona-edit'),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                onPressed: () => _edit(context, state, card),
                child: const Text(
                  '编辑',
                  style: TextStyle(fontSize: kFontBody),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            card.render(),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: kFontCaption, color: secondary),
          ),
          const Divider(height: 16),
          Row(
            children: [
              CupertinoButton(
                key: const ValueKey('persona-reset'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                minimumSize: Size.zero,
                onPressed: () => _reset(context, state),
                child: const Text(
                  '恢复默认',
                  style: TextStyle(fontSize: kFontBody),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
