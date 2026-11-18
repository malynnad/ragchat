// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import 'app_state.dart';
import 'ios_dialogs.dart';
import 'ios_widgets.dart';
import 'paper.dart';
import 'theme.dart';

/// US-1 模型准备页：首启必经。下载（hf-mirror + 进度）或手动导入兜底，
/// 角色指派确认后进入聊天主页。iOS 风格。
class ModelPrepPage extends StatelessWidget {
  const ModelPrepPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final label = paperOf(context).ink;
    final p = paperOf(context);
    final chatPaths = state
        .filesForRole(isChat: true)
        .map((f) => f.path)
        .toList();
    final embedPaths = state
        .filesForRole(isChat: false)
        .map((f) => f.path)
        .toList();
    return PaperScaffold(
      title: '模型准备',
      code: '00 / SETUP',
      body: Column(
        children: [
          ArchiveSection(
            code: '00 / PREPARATION',
            title: '先准备模型',
            subtitle: '陪聊只需聊天模型。嵌入模型可选，仅用于后续情景记忆；准备完成后聊天与记忆全程离线。',
            child: Column(
              children: [
                _roleCard(context, state, isChat: true, paths: chatPaths),
                const SizedBox(height: 12),
                _roleCard(context, state, isChat: false, paths: embedPaths),
                if (state.downloadLabel != null) ...[
                  const SizedBox(height: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.downloadLabel!,
                        style: TextStyle(fontSize: kFontBody, color: label),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: state.downloadProgress,
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                _UsbDisclosure(modelsDirPath: state.modelsDirPath),
                Align(
                  alignment: Alignment.centerLeft,
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onPressed: state.rescanModels,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.refresh, size: 18, color: p.ink),
                        const SizedBox(width: 9),
                        Text(
                          '重新扫描',
                          style: TextStyle(
                            fontSize: kFontControl,
                            color: p.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(kPageMargin, 8, kPageMargin, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: state.modelsReady ? state.confirmModels : null,
                child: Container(
                  height: 54,
                  width: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: state.modelsReady ? p.ink : p.track,
                    borderRadius: BorderRadius.circular(27),
                  ),
                  child: Text(
                    '保存并开始聊天',
                    style: TextStyle(
                      fontSize: kFontControl,
                      fontWeight: FontWeight.w600,
                      color: state.modelsReady ? p.milk : p.muted,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              CupertinoButton(
                key: const ValueKey('skip-model-setup'),
                padding: const EdgeInsets.symmetric(vertical: 8),
                onPressed: state.skipModelSetup,
                child: Text(
                  '稍后配置，先进入',
                  style: TextStyle(
                    fontSize: kFontControl,
                    fontWeight: FontWeight.w500,
                    color: p.ink,
                  ),
                ),
              ),
              Text(
                '没有模型时也能看界面；设置里随时能再打开这一页。',
                style: TextStyle(fontSize: kFontCode, color: p.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleCard(
    BuildContext context,
    AppState state, {
    required bool isChat,
    required List<String> paths,
  }) {
    final current = isChat
        ? state.settings.chatModelPath
        : state.settings.embedModelPath;
    final file = state.modelFiles
        .where((f) => f.path == current)
        .map((f) => f.size)
        .firstOrNull;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final busy = state.downloadProgress != null;
    return IosSection(
      header: isChat ? '01 / CHAT MODEL' : '02 / EMBEDDING',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isChat
                ? '推荐 Qwen3.5-4B Q4_K_M（2B 更快，但容易跑题）'
                : '可选；仅 v2 情景记忆需要',
            style: TextStyle(fontSize: kFontCaption, color: secondary),
          ),
          const SizedBox(height: 8),
          _rolePicker(context, state, isChat: isChat, paths: paths),
          if (file != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${(file / 1e9).toStringAsFixed(2)} GB',
                style: TextStyle(fontSize: kFontCaption, color: secondary),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                minimumSize: Size.zero,
                onPressed: busy
                    ? null
                    : () => _download(context, state, isChat),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.cloud_download, size: 18),
                    SizedBox(width: 4),
                    Text('下载', style: TextStyle(fontSize: kFontBody)),
                  ],
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                minimumSize: Size.zero,
                onPressed: busy ? null : () => _import(context, state),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.folder_open, size: 18),
                    SizedBox(width: 4),
                    Text('导入本地文件', style: TextStyle(fontSize: kFontBody)),
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
  }) {
    final current = isChat
        ? state.settings.chatModelPath
        : state.settings.embedModelPath;
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 6),
      onPressed: () async {
        if (paths.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isChat ? '未找到可用的聊天模型，请先下载或导入' : '未找到可用的嵌入模型，请先下载或导入',
              ),
            ),
          );
          return;
        }
        final v = await showIosActionSheet<String>(
          context: context,
          title: isChat ? '选择聊天模型' : '选择嵌入模型',
          actions: [
            for (final path in paths) IosAction(path.split('/').last, path),
          ],
        );
        if (v != null) state.assignModel(isChat: isChat, path: v);
      },
      child: Row(
        children: [
          Expanded(
            child: Text(
              current == null ? '选择 GGUF 文件' : current.split('/').last,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: kFontBody, color: label),
            ),
          ),
          Icon(CupertinoIcons.chevron_right, size: 18, color: secondary),
        ],
      ),
    );
  }

  Future<void> _download(
    BuildContext context,
    AppState state,
    bool isChat,
  ) async {
    try {
      await state.downloadModel(isChat: isChat);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('下载失败（可重试或手动导入）: $e')));
      }
    }
  }

  Future<void> _import(BuildContext context, AppState state) async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      final file = files.firstOrNull;
      if (file == null) return;
      await state.importModelFile(file);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败: $e')));
      }
    }
  }
}

/// USB 手动导入说明（可折叠）。
class _UsbDisclosure extends StatefulWidget {
  const _UsbDisclosure({required this.modelsDirPath});

  final String modelsDirPath;

  @override
  State<_UsbDisclosure> createState() => _UsbDisclosureState();
}

class _UsbDisclosureState extends State<_UsbDisclosure> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return IosSection(
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
                    'USB 手动导入说明（网络兜底）',
                    style: TextStyle(fontSize: kFontBody, color: label),
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
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SelectableText(
                '电脑 adb push GGUF 到以下目录，或在上方用「导入本地文件」'
                '从手机存储选择：\n${widget.modelsDirPath}\n\n'
                '示例：\nadb push Qwen3.5-2B-Q4_K_M.gguf ${widget.modelsDirPath}/\n'
                'push 完成后回到本页点「重新扫描」。',
                style: TextStyle(fontSize: kFontCaption, color: secondary),
              ),
            ),
        ],
      ),
    );
  }
}
