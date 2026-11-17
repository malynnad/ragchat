import 'dart:async';

// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../rag/models.dart';
import 'app_state.dart';
import 'ios_dialogs.dart';
import 'ios_widgets.dart';
import 'paper.dart';
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

  /// 看门狗触发：生成太久被自动掐掉。
  bool timedOut = false;
  DateTime? startedAt;
  Duration? elapsed;
}

class _QaPageState extends State<QaPage> with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _entries = <Object>[]; // _UserEntry | _AssistantEntry
  bool _busy = false;
  StreamSubscription<AnswerEvent>? _sub;
  Timer? _watchdog;
  bool _restored = false;

  /// 「新对话」动作总线订阅（保留接缝，供外部触发）。
  AppState? _busState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// 键盘顶起/收起会改可视高度：贴回底部，别让最后一条消息被切一半。
  @override
  void didChangeMetrics() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

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
    WidgetsBinding.instance.removeObserver(this);
    _busState?.newConversationBus.removeListener(_onNewConversationBus);
    _watchdog?.cancel();
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
    _startWatchdog(assistant);
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
                  _watchdog?.cancel();
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
                  _watchdog?.cancel();
                  assistant.contextFull = true;
                  assistant.busy = false;
                  _busy = false;
                }
                if (e is AnswerError) {
                  _watchdog?.cancel();
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

  /// 生成看门狗：2B 模型偶尔会长时间自言自语，45s 还没完就停掉。
  void _startWatchdog(_AssistantEntry assistant) {
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 45), () {
      if (!mounted || !assistant.busy) return;
      AppStateScope.of(context).stopGeneration();
      setState(() {
        assistant.timedOut = true;
        assistant.busy = false;
        _busy = false;
        assistant.elapsed = assistant.startedAt == null
            ? null
            : DateTime.now().difference(assistant.startedAt!);
      });
    });
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
    final p = paperOf(context);
    final usage = state.contextUsage();
    final usageColor = usage >= 1
        ? const Color(0xFFB3261E)
        : usage >= 0.75
        ? p.ink
        : p.muted;
    return PaperScaffold(
      title: '聊天',
      code: '01 / CONVERSATION',
      scrollable: false,
      actions: [
        Text(
          '${(usage * 100).round()}%',
          style: TextStyle(fontSize: kFontCode, color: usageColor),
        ),
        IosNavBarAction(
          icon: CupertinoIcons.add_circled,
          tooltip: '新对话',
          onPressed: _busy ? null : () => _newConversation(),
        ),
      ],
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(
                kPageMargin,
                8,
                kPageMargin,
                120,
              ),
              children: [
                if (_entries.isEmpty) _emptyState(p),
                for (final e in _entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _entryWidget(e),
                  ),
              ],
            ),
          ),
          _inputBar(context),
        ],
      ),
    );
  }

  /// 空状态三段式：一句状态 + 一句范围 + 一句动作。
  Widget _emptyState(PaperPalette p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            CupertinoIcons.paperplane,
            size: 34,
            color: p.ink.withValues(alpha: .35),
          ),
          const SizedBox(height: 14),
          Text(
            '还没有对话',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: p.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '说点什么就会记在这里。开启新对话时会自动整理记忆。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: kFontCaption,
              height: 1.6,
              color: p.muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputBar(BuildContext context) {
    final p = paperOf(context);
    // 键盘收起时给悬空 dock 让位；键盘弹起时 dock 已滑走，只需常规留白。
    final keyboardOpen = KeyboardDockScope.of(context);
    return SafeArea(
      top: false,
      // 键盘弹起时底部安全区已被键盘吃掉了，再留一次就会在输入框下空一条。
      bottom: !keyboardOpen,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          kPageMargin,
          8,
          kPageMargin,
          keyboardOpen ? 8 : kDockReserve,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: p.hairline, width: 0.7),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: CupertinoTextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  placeholder: '说点什么',
                  placeholderStyle: TextStyle(
                    fontSize: kFontBody,
                    color: p.muted,
                  ),
                  style: TextStyle(fontSize: kFontBody, color: p.ink),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: const BoxDecoration(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (_busy)
              _StopButton(
                onPressed: () => AppStateScope.of(context).stopGeneration(),
              )
            else
              _SendButton(onPressed: _ask),
          ],
        ),
      ),
    );
  }

  Widget _entryWidget(Object e) {
    final p = paperOf(context);
    if (e is _UserEntry) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: p.ink,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            e.text,
            style: TextStyle(fontSize: kFontBody, height: 1.5, color: p.milk),
          ),
        ),
      );
    }
    final a = e as _AssistantEntry;
    return Align(
      alignment: Alignment.centerLeft,
      child: ContentPanel(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (a.contextFull)
              _noticeRow(
                icon: CupertinoIcons.hourglass,
                text: '上下文将满，本轮未生成。请开启新对话。',
              ),
            if (a.timedOut)
              _noticeRow(
                icon: CupertinoIcons.hourglass,
                text: a.elapsed == null
                    ? '生成太久，已自动停止。'
                    : '生成超过 ${a.elapsed!.inSeconds} 秒，已自动停止。'
                          '把「随机性」调到稳定再试。',
              ),
            if (a.error)
              _noticeRow(
                icon: CupertinoIcons.exclamationmark_circle,
                text: '生成失败，请重试。',
              ),
            if (!a.busy &&
                a.answer.isEmpty &&
                !a.error &&
                !a.contextFull &&
                !a.timedOut)
              _noticeRow(
                icon: CupertinoIcons.stop_circle,
                text: '本轮未生成回复（可能已停止）。',
              ),
            if (a.answer.isNotEmpty)
              Text(
                a.answer,
                style: TextStyle(
                  fontSize: kFontBody,
                  height: 1.6,
                  color: p.ink,
                ),
              ),
            if (a.busy)
              Padding(
                padding: const EdgeInsets.only(top: 8),
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

  Widget _noticeRow({required IconData icon, required String text}) {
    final p = paperOf(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.raisedHigh,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: p.muted),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: kFontCaption,
                height: 1.5,
                color: p.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 停止：和发送同款圆形墨块，里面换成 X。
class _StopButton extends StatefulWidget {
  const _StopButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_StopButton> createState() => _StopButtonState();
}

class _StopButtonState extends State<_StopButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = paperOf(context);
    return Semantics(
      label: '停止',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
          setState(() => _down = true);
        },
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _down ? .97 : 1,
          duration: _down ? kContact : kSettle,
          curve: kSettleCurve,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: p.ink, shape: BoxShape.circle),
            child: Icon(CupertinoIcons.xmark, size: 20, color: p.milk),
          ),
        ),
      ),
    );
  }
}

/// 发送：46 圆形墨块 + 奶白箭头（控件用胶囊/圆形，纸面板才用 4 圆角）。
class _SendButton extends StatefulWidget {
  const _SendButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = paperOf(context);
    return Semantics(
      label: '发送',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
          setState(() => _down = true);
        },
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _down ? .97 : 1,
          duration: _down ? kContact : kSettle,
          curve: kSettleCurve,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: p.ink, shape: BoxShape.circle),
            child: Icon(CupertinoIcons.arrow_up, size: 20, color: p.milk),
          ),
        ),
      ),
    );
  }
}
