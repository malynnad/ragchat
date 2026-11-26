// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../chat/app_db.dart';
import '../rag/model_catalog.dart';
import 'backup.dart';
import '../rag/pricing.dart';
import '../rag/token_budget.dart';
import 'app_state.dart';
import 'format.dart';
import 'ios_dialogs.dart';
import 'ios_widgets.dart';
import 'paper.dart';
import 'model_prep_page.dart';
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
          _samplingSection(context, state),
          const SizedBox(height: 28),
          const _CloudSection(),
          const SizedBox(height: 28),
          const _VoiceSection(),
          const SizedBox(height: 28),
          _storageSection(context, state, stats),
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
                key: const ValueKey('open-model-prep-from-settings'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                minimumSize: Size.zero,
                onPressed: () => Navigator.of(context).push(
                  CupertinoPageRoute(builder: (_) => const ModelPrepPage()),
                ),
                child: Text('准备页', style: TextStyle(fontSize: kFontControl)),
              ),
              CupertinoButton(
                key: const ValueKey('calibrate-embed'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                minimumSize: Size.zero,
                onPressed: busy
                    ? null
                    : () => _calibrateEmbedding(context, state),
                child: Text('标定', style: TextStyle(fontSize: kFontControl)),
              ),
              CupertinoButton(
                key: const ValueKey('retrieval-eval'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                minimumSize: Size.zero,
                onPressed: busy
                    ? null
                    : () => _runRetrievalEval(context, state),
                child: Text('自检', style: TextStyle(fontSize: kFontControl)),
              ),
              const Spacer(),
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

  /// 嵌入标定（ADR-0016 第 0 步）：跑固定探针 → 完整报告进剪贴板和日志，
  /// 弹框只报要点。阈值要等真机数值回来才定，所以这里不做任何写入。
  Future<void> _calibrateEmbedding(BuildContext context, AppState state) async {
    try {
      final report = await state.calibrateEmbedding();
      final md = report.toMarkdown();
      await Clipboard.setData(ClipboardData(text: md));
      if (!context.mounted) return;
      final timing = report.batchMs == null
          ? '单条平均 ${report.singleAvgMs} ms'
          : '单条平均 ${report.singleAvgMs} ms，批量 ${report.batchMs} ms';
      final verdict = report.warnings.isEmpty
          ? '没有发现异常'
          : '${report.warnings.length} 条异常：${report.warnings.first}';
      final threshold = report.suggestedThreshold == null
          ? '阈值无法给出（分布塌陷）'
          : '建议阈值 ${report.suggestedThreshold!.toStringAsFixed(2)}'
                '（地板 ${report.noiseFloor!.toStringAsFixed(3)}）';
      await showIosAlert(
        context: context,
        title: report.ok ? '标定完成' : '标定有问题',
        message:
            '维度 ${report.dim}（期望 ${report.expectedDim}）'
            '${report.dimOk ? "" : " ✗"}\n'
            '$timing\n$threshold\n$verdict\n\n完整报告已复制到剪贴板。',
      );
    } catch (e) {
      if (!context.mounted) return;
      await showIosAlert(context: context, title: '标定失败', message: '$e');
    }
  }

  /// 检索自检（ADR-0016 第 4 步）：报告进剪贴板与日志，弹框只报两组数字。
  Future<void> _runRetrievalEval(BuildContext context, AppState state) async {
    try {
      final eval = await state.runRetrievalEval();
      await Clipboard.setData(ClipboardData(text: eval.toMarkdown()));
      if (!context.mounted) return;
      await showIosAlert(
        context: context,
        title: '自检完成',
        message:
            '命中 ${eval.hitCount} / ${eval.rows.length} 题'
            '（cos ≥ ${eval.threshold.toStringAsFixed(2)}）\n'
            '压力预算下排序被改写 ${eval.changedCount} 题\n\n'
            '完整报告已复制到剪贴板。',
      );
    } catch (e) {
      if (!context.mounted) return;
      await showIosAlert(context: context, title: '自检失败', message: '$e');
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
    AppState state,
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
      header: '07 / STORAGE',
      info: '删除按钮要按满一格才会弹确认：按下去会从左往右变红，松手即取消。',
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          row('聊天数据 DB', formatBytes(stats.dbBytes)),
          const Divider(height: 1),
          row('模型文件', formatBytes(stats.modelBytes)),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                CupertinoButton(
                  key: const ValueKey('export-backup'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  onPressed: () => _exportBackup(context, state),
                  child: Text(
                    '导出备份',
                    style: TextStyle(fontSize: kFontBody, color: label),
                  ),
                ),
                CupertinoButton(
                  key: const ValueKey('import-backup'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  onPressed: () => _importBackup(context, state),
                  child: Text(
                    '导入备份',
                    style: TextStyle(fontSize: kFontBody, color: label),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: HoldToConfirmButton(
              key: const ValueKey('delete-db'),
              label: '删除聊天数据',
              onCompleted: () => _confirmDeleteDb(context, state),
            ),
          ),
        ],
      ),
    );
  }

  /// 导出：打包成 .ragchat.zip，交给系统文件选择器保存。
  Future<void> _exportBackup(BuildContext context, AppState state) async {
    try {
      final bytes = await state.exportBackupBytes();
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}-'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}';
      final uri = await FilePicker.saveFile(
        fileName: 'ragchat-$stamp.ragchat.zip',
        bytes: bytes,
        mimeType: 'application/zip',
        dialogTitle: '保存 RAGchat 备份',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(uri == null ? '已取消保存' : '备份已保存'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }

  /// 导入：选文件 → 预览条数 → 二次确认 → 覆盖恢复。
  Future<void> _importBackup(BuildContext context, AppState state) async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      dialogTitle: '选择 .ragchat.zip',
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!context.mounted) return;
    try {
      final preview = inspectBackup(bytes);
      final ok = await showIosConfirm(
        context: context,
        title: '导入备份',
        message:
            '将覆盖当前全部会话与记忆，并恢复人设/温度/语音/后端设置。'
            'API key 与模型路径不受影响。\n\n备份内容：${preview.summary}',
        confirmLabel: '覆盖导入',
        destructive: true,
      );
      if (!ok) return;
      final applied = await state.importBackupBytes(bytes);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入：${applied.summary}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    }
  }

  /// 采样参数：温度三档即时生效；思考开关要重载模型。
  Widget _samplingSection(BuildContext context, AppState state) {
    final s = state.settings;
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    // 三档就近取整：0.4 稳定 / 0.7 平衡 / 1.0 活跃。
    final tier = s.temperature <= 0.5
        ? 'steady'
        : s.temperature >= 0.75
        ? 'lively'
        : 'balanced';
    return IosSection(
      header: '04 / SAMPLING',
      info: '温度低更稳、少跑题；高了更容易语无伦次。改完下一次生成就生效。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '随机性（temperature）',
            style: TextStyle(fontSize: kFontBody, color: label),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: CupertinoSlidingSegmentedControl<String>(
              groupValue: tier,
              children: const {
                'steady': Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('稳定', style: TextStyle(fontSize: kFontBody)),
                ),
                'balanced': Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('平衡', style: TextStyle(fontSize: kFontBody)),
                ),
                'lively': Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('活跃', style: TextStyle(fontSize: kFontBody)),
                ),
              },
              onValueChanged: (v) {
                if (v == null) return;
                final t = v == 'steady'
                    ? 0.4
                    : v == 'lively'
                    ? 0.9
                    : 0.6;
                state.updateTemperature(t);
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '当前 ${s.temperature.toStringAsFixed(1)}',
            style: TextStyle(fontSize: kFontCaption, color: secondary),
          ),
        ],
      ),
    );
  }

  /// 长按数据库才弹删除：一次确认，写清不可恢复。
  Future<void> _confirmDeleteDb(BuildContext context, AppState state) async {
    final ok = await showIosConfirm(
      context: context,
      title: '删除全部聊天数据',
      message: '会话记录与记忆会一起删除，模型文件保留。此操作不可恢复。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await state.clearAllData();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败: $e')));
      }
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已删除聊天数据')));
    }
  }
}

/// 对话后端：本地 GGUF 或云端 OpenAI 兼容 API（DeepSeek 默认）。
class _CloudSection extends StatefulWidget {
  const _CloudSection();

  @override
  State<_CloudSection> createState() => _CloudSectionState();
}

class _CloudSectionState extends State<_CloudSection> {
  late final _base = TextEditingController();
  late final _model = TextEditingController();
  late final _key = TextEditingController();
  bool _ready = false;
  bool _testing = false;
  String? _status;
  bool _statusError = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;
    final s = AppStateScope.of(context).settings;
    _base.text = s.cloudBaseUrl;
    _model.text = s.cloudModel;
    _key.text = AppStateScope.of(context).cloudApiKey;
  }

  @override
  void dispose() {
    _base.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save(AppState state) async {
    await state.setCloudEndpoint(baseUrl: _base.text, model: _model.text);
    await state.setCloudKey(_key.text);
    if (!mounted) return;
    setState(() {
      _status = '已保存';
      _statusError = false;
    });
  }

  Future<void> _test(AppState state) async {
    await _save(state);
    setState(() {
      _testing = true;
      _status = '正在连接…';
      _statusError = false;
    });
    try {
      final models = await state.testCloudConnection();
      if (!mounted) return;
      setState(() {
        _testing = false;
        _statusError = false;
        _status = models.isEmpty
            ? '连接成功（没拿到模型列表）'
            : '连接成功：${models.take(3).join(' / ')}'
                  '${models.length > 3 ? ' …' : ''}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _statusError = true;
        _status = '$e';
      });
    }
  }

  /// 用量一行：token 与估算费用（按闲时价）。
  Widget _usageRow(String label, UsageSummary u, dynamic p, {bool withCount = false}) {
    final muted = CupertinoColors.secondaryLabel.resolveFrom(context);
    final text = u.count == 0
        ? '还没有记录'
        : '↑${formatTokens(u.promptTokens)} ↓${formatTokens(u.completionTokens)}'
              ' · ≈${formatCost(u.cost)}'
              '${withCount ? '（${u.count} 次）' : ''}';
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(
            label,
            style: TextStyle(fontSize: kFontCaption, color: muted),
          ),
        ),
        Text(
          text,
          style: TextStyle(
            fontSize: kFontCaption,
            color: u.count == 0 ? muted : paperOf(context).ink,
          ),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController c, {bool obscure = false}) {
    final p = paperOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: kFontCode, color: p.muted),
          ),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: p.milk,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: p.hairline, width: 0.7),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: CupertinoTextField(
              controller: c,
              obscureText: obscure,
              style: TextStyle(fontSize: kFontBody, color: p.ink),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(),
              placeholder: label,
              placeholderStyle: TextStyle(fontSize: kFontBody, color: p.muted),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final p = paperOf(context);
    final cloud = state.settings.backend == 'cloud';
    return IosSection(
      header: '05 / BACKEND',
      info: cloud
          ? '云端会把每轮对话、人设和记忆发给服务商；不用时切回本地。'
          : '本地模型全程离线；想用 DeepSeek 之类的大模型再切云端。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: CupertinoSlidingSegmentedControl<String>(
              groupValue: cloud ? 'cloud' : 'local',
              children: const {
                'local': Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('本地模型', style: TextStyle(fontSize: kFontBody)),
                ),
                'cloud': Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('云端 API', style: TextStyle(fontSize: kFontBody)),
                ),
              },
              onValueChanged: (v) {
                if (v == null) return;
                state.setBackend(v);
              },
            ),
          ),
          if (cloud) ...[
            const SizedBox(height: 14),
            _field('Base URL', _base),
            _field('模型名', _model),
            _field('API key', _key, obscure: true),
            Row(
              children: [
                CupertinoButton(
                  key: const ValueKey('cloud-save'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  onPressed: () => _save(state),
                  child: Text(
                    '保存',
                    style: TextStyle(fontSize: kFontBody, color: p.ink),
                  ),
                ),
                CupertinoButton(
                  key: const ValueKey('cloud-test'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  onPressed: _testing ? null : () => _test(state),
                  child: Text(
                    _testing ? '测试中…' : '测试连接',
                    style: TextStyle(fontSize: kFontBody, color: p.ink),
                  ),
                ),
              ],
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _status!,
                  style: TextStyle(
                    fontSize: kFontCaption,
                    height: 1.5,
                    color: _statusError ? const Color(0xFFB3261E) : p.muted,
                  ),
                ),
              ),
            if (state.cloudApiKey.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '还没填 key：聊天会继续走本地模型。',
                  style: TextStyle(fontSize: kFontCode, color: p.muted),
                ),
              ),
            const Divider(height: 18),
            _usageRow(
              '今日',
              state.todayUsage,
              p,
            ),
            const SizedBox(height: 4),
            _usageRow('累计', state.totalUsage, p, withCount: true),
          ],
        ],
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
                    '魔搭 ModelScope（国内直连）；下载即切换，不支持断点续传',
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
                '2B 速度档，4B 默认，9B 质量档；嵌入模型只在 v2 情景记忆时用得上。',
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

/// 人设：本地 / 云端两个槽位，各自可编辑；切换后端只是换用对应那张。
/// 点槽位 = 切到那个后端，不是「恢复预设」；改名会跟着显示在槽位上。
class _PersonaSection extends StatelessWidget {
  const _PersonaSection();

  static const _slots = [
    ('local', '本地模型'),
    ('cloud', '云端 API'),
  ];

  Future<void> _edit(
    BuildContext context,
    AppState state,
    PersonaCard card,
  ) async {
    // 先把焦点从模型名/API key 输入框收掉：否则编辑完返回，
    // 系统会把焦点还给那个输入框，键盘自己弹出来。
    FocusManager.instance.primaryFocus?.unfocus();
    final edited = await showPersonaEditor(context, initial: card);
    if (edited == null) return;
    await state.savePersona(edited);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final cards = state.settings.personas();

    PersonaCard cardFor(String id) =>
        cards.where((c) => c.id == id).firstOrNull ??
        personaSlotDefault(id);

    return IosSection(
      header: '03 / PERSONA',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _slots.length; i++) ...[
            if (i > 0) const Divider(height: 14),
            _slotRow(
              context: context,
              state: state,
              id: _slots[i].$1,
              label: _slots[i].$2,
              card: cardFor(_slots[i].$1),
              isActive: state.settings.backend == _slots[i].$1,
            ),
          ],
          const SizedBox(height: 10),
          HoldToConfirmButton(
            key: const ValueKey('persona-reset'),
            label: '恢复预设',
            icon: CupertinoIcons.arrow_counterclockwise,
            onCompleted: () => state.resetPersona(),
          ),
        ],
      ),
    );
  }

  Widget _slotRow({
    required BuildContext context,
    required AppState state,
    required String id,
    required String label,
    required PersonaCard card,
    required bool isActive,
  }) {
    final p = paperOf(context);
    final used = estimateTokens(card.render());
    return CupertinoButton(
      key: ValueKey('persona-slot-$id'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      minimumSize: Size.zero,
      onPressed: () => state.setBackend(id),
      child: Row(
        children: [
          Icon(
            isActive
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.circle,
            size: 18,
            color: isActive ? p.ink : p.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: kFontCode, color: p.muted),
                ),
                const SizedBox(height: 2),
                Text(
                  '${card.name.isEmpty ? '未命名' : card.name}'
                  ' · ≈$used token',
                  style: TextStyle(fontSize: kFontBody, color: p.ink),
                ),
              ],
            ),
          ),
          CupertinoButton(
            key: ValueKey('persona-edit-$id'),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            onPressed: () => _edit(context, state, card),
            child: const Text('编辑', style: TextStyle(fontSize: kFontBody)),
          ),
        ],
      ),
    );
  }
}

/// 系统 TTS：自动朗读、语速、音调（滑块）。引擎/音色用系统默认。
class _VoiceSection extends StatefulWidget {
  const _VoiceSection();

  @override
  State<_VoiceSection> createState() => _VoiceSectionState();
}

class _VoiceSectionState extends State<_VoiceSection> {
  double? _rate;
  double? _pitch;

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final p = paperOf(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final s = state.settings;
    final rate = (_rate ?? s.ttsRate).clamp(0.2, 0.8);
    final pitch = (_pitch ?? s.ttsPitch).clamp(0.7, 1.3);

    Widget sliderRow({
      required String label,
      required String value,
      required double v,
      required double min,
      required double max,
      required int divisions,
      required ValueChanged<double> onChanged,
      required ValueChanged<double> onChangeEnd,
      required Key key,
    }) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(fontSize: kFontBody)),
            const Spacer(),
            Text(
              value,
              style: TextStyle(fontSize: kFontCaption, color: secondary),
            ),
          ],
        ),
        // Column 是 start 对齐：不撑满的话 slider 会缩到很窄。
        SizedBox(
          width: double.infinity,
          child: CupertinoSlider(
            key: key,
            value: v,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: p.ink,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    );

    return IosSection(
      header: '06 / VOICE',
      info: '用手机自带的语音引擎，离线、免费、不耗流量。'
          '想换发音人要去系统设置里换默认 TTS 引擎，App 里只调语速和音调。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '新回复自动朗读',
                  style: TextStyle(fontSize: kFontBody),
                ),
              ),
              CupertinoSwitch(
                key: const ValueKey('tts-auto-read'),
                value: s.ttsAutoRead,
                activeTrackColor: p.ink,
                onChanged: (v) => state.setTtsAutoRead(v),
              ),
            ],
          ),
          const Divider(height: 16),
          sliderRow(
            label: '语速',
            value: '${(rate * 100).round()}%',
            v: rate,
            min: 0.2,
            max: 0.8,
            divisions: 12,
            key: const ValueKey('tts-rate-slider'),
            onChanged: (v) => setState(() => _rate = v),
            onChangeEnd: (v) async {
              await state.setTtsRate(v);
              if (mounted) setState(() => _rate = null);
            },
          ),
          const SizedBox(height: 4),
          sliderRow(
            label: '音调',
            value: pitch.toStringAsFixed(2),
            v: pitch,
            min: 0.7,
            max: 1.3,
            divisions: 12,
            key: const ValueKey('tts-pitch-slider'),
            onChanged: (v) => setState(() => _pitch = v),
            onChangeEnd: (v) async {
              await state.setTtsPitch(v);
              if (mounted) setState(() => _pitch = null);
            },
          ),
        ],
      ),
    );
  }
}
