// 纸页与档案外壳：纸底 + 三页 IndexedStack + 底部玻璃 dock。
// 切换只换内容区，各页状态保留（会话不丢）；动效一次性落定，无循环。
// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';

import 'app_state.dart';
import 'memory_page.dart';
import 'paper.dart';
import 'qa_page.dart';
import 'theme.dart';
import 'settings_page.dart';

class IosShell extends StatefulWidget {
  const IosShell({super.key});

  @override
  State<IosShell> createState() => _IosShellState();
}

class _IosShellState extends State<IosShell> {
  int _index = 0;

  static const _items = [
    GlassDockItem(
      CupertinoIcons.chat_bubble,
      '聊天',
      activeIcon: CupertinoIcons.chat_bubble_fill,
    ),
    GlassDockItem(
      CupertinoIcons.archivebox,
      '记忆',
      activeIcon: CupertinoIcons.archivebox_fill,
    ),
    GlassDockItem(
      CupertinoIcons.slider_horizontal_3,
      '设置',
      activeIcon: CupertinoIcons.slider_horizontal_3,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppStateScope.of(context).warmUp();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final p = paperOf(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: Atmosphere(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (state.loadStage.isNotEmpty && !state.gatewayLoaded)
                _Banner(
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CupertinoActivityIndicator(radius: 7),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          state.loadStage,
                          style: TextStyle(fontSize: kFontCaption, color: p.muted),
                        ),
                      ),
                    ],
                  ),
                ),
              if (state.loadError != null)
                _Banner(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '模型加载失败：${state.loadError}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: kFontCaption,
                            color: const Color(0xFFB3261E),
                          ),
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        onPressed: state.warmUp,
                        child: Text(
                          '重试',
                          style: TextStyle(fontSize: kFontControl),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: const [QaPage(), MemoryPage(), SettingsPage()],
                ),
              ),
              GlassDock(
                selectedIndex: _index,
                onSelected: (i) => setState(() => _index = i),
                items: _items,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶部提示条：纸面 + 发丝底边，不抢层级。
class _Banner extends StatelessWidget {
  const _Banner({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = paperOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: kPageMargin, vertical: 10),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.hairline, width: 0.6)),
      ),
      child: child,
    );
  }
}
