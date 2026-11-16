import 'dart:async';

// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../rag/models.dart';
import 'app_state.dart';
import 'ios_dialogs.dart';
import 'ios_widgets.dart';
import 'theme.dart';

/// 聊天页（US-18）：气泡 / 流式 / 停止 / 上下文占用 / 新对话。
/// 会话持久化（US-19）：进页恢复最近会话，完成轮写盘；
/// 新对话触发记忆提取（ADR-0009）。iOS 风格外壳。
class QaPage extends StatefulWidget {
  const QaPage({super.key});

  @override
  State<QaPage> createState() => _QaPageState();
}

class _UserEntry {
  _UserEntry(this.text);
  final String text;
}

class _AssistantEntry {
  String answer = '';
  bool busy = false;
  bool contextFull = false;
  bool error = false;
  DateTime? startedAt;
  Duration? elapsed;
}

class _QaPageState extends State<QaPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _entries = <Object>[]; // _UserEntry | _AssistantEntry
  bool _busy = false;
  StreamSubscription<AnswerEvent>? _sub;
  bool _restored = false;

  /// 「新对话」动作总线订阅（保留接缝，供外部触发）。
  AppState? _busState;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppStateScope.of(context);
    if (!identical(state, _busState)) {
      _busState?.newConversationBus.removeListener(_onNewConversationBus);
      _busState = state;
      state.newConversationBus.addListener(_onNewConversationBus);
    }
    // US-19：恢复最近会话的轮次为气泡（仅一次）。
    if (!_restored) {
      _restored = true;
      for (final t in state.sessionTurns) {
        _entries.addAll([
          _UserEntry(t.question),
          _AssistantEntry()..answer = t.answer,
        ]);
      }
      _scrollToBottom();
    }
  }

  void _onNewConversationBus() {
    if (mounted) _newConversation();
  }

  @override
  void dispose() {
    _busState?.newConversationBus.removeListener(_onNewConversationBus);
    _sub?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final q = _controller.text.trim();
    if (q.isEmpty || _busy) return;
    final state = AppStateScope.of(context);
    // 容量预检（ADR-0006）：满了不发起请求，直接引导新对话。
    if (state.contextUsage() >= 1) {
      _showContextFullDialog();
      return;
    }
    setState(() {
      _busy = true;
      _entries.addAll([_UserEntry(q), _AssistantEntry()..busy = true]);
      _controller.clear();
    });
    _scrollToBottom();
    final assistant = _entries.last as _AssistantEntry;
    assistant.startedAt = DateTime.now();
    try {
      final service = await state.ensureChat();
      _sub = service
          .ask(
            q,
            systemPrompt: state.systemPrompt(),
            history: state.sessionTurns.toList(),
          )
          .listen(
            (e) {
              if (!mounted) return;
              setState(() {
                if (e is AnswerToken) assistant.answer += e.text;
                if (e is AnswerDone) {
                  assistant.busy = false;
                  assistant.elapsed = assistant.startedAt == null
                      ? null
                      : DateTime.now().difference(assistant.startedAt!);
                  _busy = false;
                  // 空回答不进历史（避免污染记忆提取与预算）。
                  if (assistant.answer.isNotEmpty) {
                    state.persistTurn(q, assistant.answer);
                  }
                }
                if (e is AnswerContextFull) {
                  assistant.contextFull = true;
                  assistant.busy = false;
                  _busy = false;
                }
                if (e is AnswerError) {
                  assistant.error = true;
                  assistant.busy = false;
                  _busy = false;
                }
              });
              _scrollToBottom();
              if (e is AnswerContextFull) _showContextFullDialog();
            },
            onError: (Object e) {
              if (!mounted) return;
              setState(() {
                assistant.error = true;
                assistant.busy = false;
                _busy = false;
              });
            },
          );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        assistant.error = true;
        assistant.busy = false;
        _busy = false;
      });
    }
  }

  /// ADR-0006/0009：新对话清空屏幕记录与会话历史；
  /// 状态层负责记忆提取 + 新 session + 模型侧上下文重置。
  Future<void> _newConversation({bool skipConfirm = false}) async {
    if (_busy) return;
    final state = AppStateScope.of(context);
    if (!skipConfirm && _entries.isNotEmpty) {
      final ok = await showIosConfirm(
        context: context,
        title: '开启新对话',
        message: '将清空当前屏幕上的聊天记录，并从这段对话中提取记忆。开启后开始全新会话。',
        confirmLabel: '新对话',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    await state.startNewConversation();
    if (!mounted) return;
    setState(() {
      _entries.clear();
    });
  }

  Future<void> _showContextFullDialog() async {
    final ok = await showIosConfirm(
      context: context,
      title: '上下文将满',
      message:
          '当前会话已接近模型上下文容量上限。'
          '开启新对话后可继续聊天（屏幕上的聊天记录会清空，记忆保留）。',
      confirmLabel: '开启新对话',
      cancelLabel: '稍后',
    );
    if (ok && mounted) _newConversation(skipConfirm: true);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final cup = CupertinoTheme.of(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final usage = state.contextUsage();
    final usageColor = usage >= 1
        ? CupertinoColors.systemRed.resolveFrom(context)
        : usage >= 0.75
        ? CupertinoColors.systemOrange.resolveFrom(context)
        : secondary;
    return Scaffold(
      backgroundColor: cup.scaffoldBackgroundColor,
      appBar: CupertinoNavigationBar(
        middle: const Text('聊天'),
        border: null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: '会话上下文占用：历史聊天 / 可用预算\n满后需开启新对话',
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  '${(usage * 100).round()}%',
                  style: TextStyle(fontSize: kFontCaption, color: usageColor),
                ),
              ),
            ),
            IosNavBarAction(
              icon: CupertinoIcons.add_circled,
              tooltip: '新对话',
              onPressed: _busy ? null : () => _newConversation(),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              children: [
                if (_entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      '随便聊聊吧。\n\n我会记住你告诉我的重要事情；'
                      '开启新对话时会自动整理记忆。\n上下文将满时请开启新对话。',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: kFontBody, color: secondary),
                    ),
                  ),
                for (final e in _entries) _entryWidget(e),
              ],
            ),
          ),
          _inputBar(context),
        ],
      ),
    );
  }

  Widget _inputBar(BuildContext context) {
    final card = CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
      context,
    );
    final border = CupertinoColors.separator.resolveFrom(context);
    final label = CupertinoColors.label.resolveFrom(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                placeholder: '说点什么…',
                style: TextStyle(fontSize: kFontBody, color: label),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border, width: 0.5),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _busy
                ? CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    color: CupertinoColors.systemGrey.resolveFrom(context),
                    onPressed: () => AppStateScope.of(context).stopGeneration(),
                    child: const Text(
                      '停止',
                      style: TextStyle(color: CupertinoColors.white),
                    ),
                  )
                : CupertinoButton.filled(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    onPressed: _ask,
                    child: Icon(
                      CupertinoIcons.arrow_up,
                      size: 20,
                      color: onAccent(CupertinoTheme.of(context).primaryColor),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _entryWidget(Object e) {
    final accent = CupertinoTheme.of(context).primaryColor;
    final assistantBg = CupertinoColors.secondarySystemGroupedBackground
        .resolveFrom(context);
    if (e is _UserEntry) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(
            e.text,
            style: TextStyle(fontSize: kFontBody, color: onAccent(accent)),
          ),
        ),
      );
    }
    final a = e as _AssistantEntry;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, right: 24),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: assistantBg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (a.contextFull)
              _noticeRow(
                icon: CupertinoIcons.hourglass,
                tint: CupertinoColors.systemOrange.resolveFrom(context),
                text: '上下文将满，本轮未生成。请开启新对话。',
              ),
            if (a.error)
              _noticeRow(
                icon: CupertinoIcons.exclamationmark_circle,
                tint: CupertinoColors.systemRed.resolveFrom(context),
                text: '生成失败，请重试。',
              ),
            if (!a.busy && a.answer.isEmpty && !a.error && !a.contextFull)
              _noticeRow(
                icon: CupertinoIcons.stop_circle,
                tint: CupertinoColors.secondaryLabel.resolveFrom(context),
                text: '本轮未生成回复（可能已停止）。',
              ),
            if (a.answer.isNotEmpty)
              Text(
                a.answer,
                style: TextStyle(
                  fontSize: kFontBody,
                  height: 1.4,
                  color: CupertinoColors.label.resolveFrom(context),
                ),
              ),
            if (a.busy)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CupertinoActivityIndicator(radius: 7),
                ),
              ),
            if (!a.busy && a.answer.isNotEmpty) _answerFooter(a),
          ],
        ),
      ),
    );
  }

  /// 答案耗时 + 复制按钮（说明字号）。
  Widget _answerFooter(_AssistantEntry a) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final secs = a.elapsed == null
        ? null
        : (a.elapsed!.inMilliseconds / 1000).toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          if (secs != null)
            Text(
              '耗时 ${secs}s',
              style: TextStyle(fontSize: kFontCaption, color: secondary),
            ),
          const Spacer(),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            minimumSize: Size.zero,
            onPressed: () => _copyAnswer(a),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.doc_on_doc, size: 14, color: secondary),
                const SizedBox(width: 4),
                Text(
                  '复制',
                  style: TextStyle(fontSize: kFontCaption, color: secondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyAnswer(_AssistantEntry a) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已复制')));
    await Clipboard.setData(ClipboardData(text: a.answer));
  }

  Widget _noticeRow({
    required IconData icon,
    required Color tint,
    required String text,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: tint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: kFontBody,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
