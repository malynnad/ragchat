// Apple/iOS 风格弹层助手。
//
// Cupertino 控件查找 CupertinoLocalizations（MaterialApp 默认提供，
// main.dart 另显式补 DefaultCupertinoLocalizations.delegate 兜底）。
// 路由内容位于根 Navigator 之上，main.dart 的 builder 已在 Navigator 之上
// 注入 CupertinoTheme，故所有路由（对话框/动作表/弹层）都能继承主题。
//
// 动效：底部弹层用弹簧滑入 + 拖拽继承速度 + 可中断（[showIosSheet]）；
// 系统「减少动态效果」时降级为直接显现 / 淡入。
// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';

import 'motion.dart';

/// 供 MaterialApp.builder 使用：把 CupertinoTheme 放在根 Navigator 之上，
/// 使所有路由都能继承 iOS 主题。
///
/// 同时补一层正常 DefaultTextStyle：MaterialApp 的应用级默认样式是
/// 「错误提示样式」（monospace + w900 + 黄色双下划线），主页面靠 Material/
/// Scaffold 自带的默认样式盖掉它，但纯 Cupertino 子树（如 showIosSheet 弹层）
/// 没有 Material，plain Text 会落到错误样式上（黄双下划线根因）。
/// 这里在根 Navigator 之上统一提供正文字号/颜色的干净默认样式。
Widget iosAppBuilder(
  BuildContext context,
  Widget? child, {
  required CupertinoThemeData theme,
}) {
  return CupertinoTheme(
    data: theme,
    child: DefaultTextStyle(
      style: theme.textTheme.textStyle,
      child: child ?? const SizedBox.shrink(),
    ),
  );
}

/// iOS 提示框（单按钮）。
Future<void> showIosAlert({
  required BuildContext context,
  required String title,
  required String message,
  String okLabel = '好',
}) {
  return showCupertinoDialog<void>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(title),
      content: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(message),
      ),
      actions: [
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: Text(okLabel),
        ),
      ],
    ),
  );
}

/// iOS 二选一确认框。返回 true=确认，false/取消屏障=false。
/// [destructive] 时确认按钮用系统红。
Future<bool> showIosConfirm({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  bool destructive = false,
}) async {
  final r = await showCupertinoDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(title),
      content: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(message),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        CupertinoDialogAction(
          isDefaultAction: !destructive,
          isDestructiveAction: destructive,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// 动作表条目。
class IosAction<T> {
  const IosAction(this.label, this.value, {this.destructive = false});
  final String label;
  final T value;
  final bool destructive;
}

/// iOS 动作表（底部弹出的选项列表，替代 Material PopupMenu）。
Future<T?> showIosActionSheet<T>({
  required BuildContext context,
  String? title,
  String? message,
  required List<IosAction<T>> actions,
  String cancelLabel = '取消',
}) {
  return showCupertinoModalPopup<T>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: title == null ? null : Text(title),
      message: message == null ? null : Text(message),
      actions: [
        for (final a in actions)
          CupertinoActionSheetAction(
            isDestructiveAction: a.destructive,
            onPressed: () => Navigator.pop(ctx, a.value),
            child: Text(a.label),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(ctx),
        child: Text(cancelLabel),
      ),
    ),
  );
}

/// iOS 文本输入对话框（重命名 / 新建等）。返回输入文本，取消=null。
/// 对话框自持 TextEditingController（State.dispose 释放），避免退出动画
/// 期间重建用到已 dispose 的控制器（沿用红屏修复的持有权模式）。
Future<String?> showIosTextPrompt({
  required BuildContext context,
  required String title,
  String? message,
  String initialValue = '',
  String placeholder = '',
  String confirmLabel = '保存',
  String cancelLabel = '取消',
}) {
  return showCupertinoDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _IosTextPromptDialog(
      title: title,
      message: message,
      initialValue: initialValue,
      placeholder: placeholder,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
    ),
  );
}

class _IosTextPromptDialog extends StatefulWidget {
  const _IosTextPromptDialog({
    required this.title,
    required this.message,
    required this.initialValue,
    required this.placeholder,
    required this.confirmLabel,
    required this.cancelLabel,
  });

  final String title;
  final String? message;
  final String initialValue;
  final String placeholder;
  final String confirmLabel;
  final String cancelLabel;

  @override
  State<_IosTextPromptDialog> createState() => _IosTextPromptDialogState();
}

class _IosTextPromptDialogState extends State<_IosTextPromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(widget.message!),
            ),
          const SizedBox(height: 12),
          CupertinoTextField(
            controller: _controller,
            autofocus: true,
            placeholder: widget.placeholder,
            clearButtonMode: OverlayVisibilityMode.editing,
          ),
        ],
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.cancelLabel),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// iOS 底部弹层：弹簧滑入、可拖拽关闭（继承释放速度）、可中断。
/// [builder] 提供内容（内部已包圆角面板 + 抓手 + 安全区）。
Future<T?> showIosSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return Navigator.of(context, rootNavigator: true).push<T>(
    _IosSheetRoute<T>(builder: builder, barrierDismissible: barrierDismissible),
  );
}

class _IosSheetRoute<T> extends PopupRoute<T> {
  _IosSheetRoute({required this.builder, required this.barrierDismissible});

  final WidgetBuilder builder;

  @override
  final bool barrierDismissible;

  /// 弹层全程不碰焦点：开层不抢焦点（键盘保持原状），pop 时_home 路由
  /// setFirstFocus 恢复的是开层前的原焦点，不会因「scope 无焦点 child →
  /// 自动聚焦第一个可聚焦组件（输入框）」而在退出后带起键盘。
  @override
  bool get requestFocus => false;

  @override
  Color get barrierColor => const Color(0x59000000);

  @override
  String get barrierLabel => '关闭';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _IosSheetBody<T>(child: Builder(builder: builder));
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 屏障淡入淡出由路由驱动；弹层本体的弹簧运动在 _IosSheetBody 内。
    return FadeTransition(opacity: animation, child: child);
  }
}

/// 弹层内容滚动控制器注入点：内容里的 SingleChildScrollView 传
/// `controller: IosSheetScrollScope.maybeOf(context)`，弹层据此判断
/// 「是否到顶」以决定下滑手势归关闭还是归滚动。
class IosSheetScrollScope extends InheritedWidget {
  const IosSheetScrollScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final ScrollController controller;

  static ScrollController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<IosSheetScrollScope>()
      ?.controller;

  @override
  bool updateShouldNotify(IosSheetScrollScope oldWidget) =>
      controller != oldWidget.controller;
}

/// 内容区协作拖拽识别器：仅在「内容到顶（或无滚动视图）」时参与手势；
/// 首个移动向上 = 想滚动 → 让出竞技场；向下 = 想关弹层 → 接管拖拽。
class _SheetContentDragRecognizer extends VerticalDragGestureRecognizer {
  _SheetContentDragRecognizer({required this.scroll});

  final ScrollController scroll;
  bool _lockedDown = false;

  @override
  bool isPointerAllowed(PointerEvent event) {
    final atTop = !scroll.hasClients || scroll.position.pixels <= 0.0;
    return atTop && super.isPointerAllowed(event);
  }

  @override
  void addPointer(PointerDownEvent event) {
    _lockedDown = false;
    super.addPointer(event);
  }

  /// 半阈值接受：内层滚动视图在命中路径更深处、先入竞技场，同帧接受会赢；
  /// 本识别器提前接受才能拿到「到顶下滑」的拖拽权。
  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind kind,
    double? touchSlop,
  ) {
    return globalDistanceMoved > (touchSlop ?? kTouchSlop) * 0.4;
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent && !_lockedDown) {
      if (event.delta.dy < 0) {
        resolve(GestureDisposition.rejected); // 上滑 = 滚动，让位
        return;
      }
      if (event.delta.dy > 0) _lockedDown = true;
    }
    super.handleEvent(event);
  }
}

/// 弹层本体：自持弹簧控制器做滑入/拖拽/关闭，与路由生命周期解耦，
/// 因此入场途中即可拖拽、反向打断不跳变。
class _IosSheetBody<T> extends StatefulWidget {
  const _IosSheetBody({required this.child});

  final Widget child;

  @override
  State<_IosSheetBody<T>> createState() => _IosSheetBodyState<T>();
}

class _IosSheetBodyState<T> extends State<_IosSheetBody<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(
    vsync: this,
    value: 0,
    duration: const Duration(milliseconds: 350),
  );
  late final ScrollController _contentScroll = ScrollController();
  final GlobalKey _panelKey = GlobalKey();
  bool _closing = false;
  T? _pendingResult;

  /// 弹层视为「已滑出屏幕」的值阈值：到此立即 pop，不等弹簧停稳，
  /// 消除临界阻尼弹簧收尾的 0.5–1s 延迟。
  static const double _offscreenEps = 0.02;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        springTo(_slide, 1, context: context, spring: macGestureSpring());
      }
    });
  }

  @override
  void dispose() {
    _slide.removeListener(_onSlide);
    _slide.dispose();
    _contentScroll.dispose();
    super.dispose();
  }

  void _onSlide() {
    if (_closing && _slide.value <= _offscreenEps) {
      _finishClose();
    }
  }

  void _finishClose() {
    _slide.removeListener(_onSlide);
    if (mounted) Navigator.of(context).pop(_pendingResult);
  }

  /// 弹簧下滑、滑出屏幕即真正 pop（减少动态效果时直接 pop）。
  void _close([T? result]) {
    if (_closing) return;
    _closing = true;
    _pendingResult = result;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // 已拖到底（value≈0）直接 pop，无需动画。
    if (reduce || _slide.value <= _offscreenEps) {
      Navigator.of(context).pop(result);
      return;
    }
    _slide.addListener(_onSlide);
    // 快弹簧（ζ0.8/T0.3）+ 滑出即 pop，避免等停稳的长尾延迟。
    springTo(_slide, 0, context: context, spring: macGestureSpring());
    if (_slide.value <= _offscreenEps) _finishClose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
      context,
    );
    // 键盘弹出时把弹层整体抬到键盘之上（管理分类输入框不再被挡）。
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight - keyboard;
        // 拖拽 1:1 跟手：位移按弹层自身高度换算（而非全屏高），
        // 手指拖到底即 value≈0 → 立即 pop，无补动画延迟。
        // 在拖拽发生时读取面板实际高度（首帧 build 时尚未布局）。
        double sheetH() => _panelKey.currentContext?.size?.height ?? height;
        // 拖拽关闭：抓手全程可拖；内容区由协作识别器在「到顶+下滑」时接管
        // （不依赖滚动通知——该子树里 ScrollNotification 链不可靠）。
        void dragUpdate(double dy) {
          if (_closing) return;
          _slide.value = (_slide.value - dy / sheetH()).clamp(0.0, 1.0);
        }

        void dragEnd(double velocity) {
          if (_closing) return;
          final h = sheetH();
          final v = -velocity / h; // 向上为正
          if (shouldSettleOpen(_slide.value, v * h)) {
            springTo(
              _slide,
              1,
              context: context,
              spring: macGestureSpring(),
              velocity: v,
            );
          } else {
            _close();
          }
        }

        return Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedBuilder(
              animation: _slide,
              builder: (context, child) => FractionalTranslation(
                translation: Offset(0, 1 - _slide.value),
                child: child,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: height * 0.9),
                child: Container(
                  key: _panelKey,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 抓手：拖拽下滑关闭（继承释放速度、可中断）。
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragUpdate: (d) => dragUpdate(d.delta.dy),
                          onVerticalDragEnd: (d) =>
                              dragEnd(d.primaryVelocity ?? 0),
                          child: Container(
                            width: 36,
                            height: 5,
                            margin: const EdgeInsets.only(top: 8, bottom: 8),
                            decoration: BoxDecoration(
                              color: CupertinoColors.tertiaryLabel.resolveFrom(
                                context,
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        // 内容区：到顶再下滑 = 关闭弹层（iOS 手感）；
                        // 其余方向/位置让位给内容正常滚动。
                        Flexible(
                          child: IosSheetScrollScope(
                            controller: _contentScroll,
                            child: RawGestureDetector(
                              behavior: HitTestBehavior.translucent,
                              gestures: <Type, GestureRecognizerFactory>{
                                _SheetContentDragRecognizer:
                                    GestureRecognizerFactoryWithHandlers<
                                      _SheetContentDragRecognizer
                                    >(
                                      () => _SheetContentDragRecognizer(
                                        scroll: _contentScroll,
                                      ),
                                      (r) {
                                        r.onUpdate = (d) =>
                                            dragUpdate(d.delta.dy);
                                        r.onEnd = (d) =>
                                            dragEnd(d.primaryVelocity ?? 0);
                                      },
                                    ),
                              },
                              child: widget.child,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
