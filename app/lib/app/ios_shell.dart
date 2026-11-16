// Apple/iOS 风格外壳。
//
// 结构（authentic iPhone 应用）：底部常驻标签栏（CupertinoTabBar）一点即切，
// 各页自带 CupertinoNavigationBar 顶栏（自动避开状态栏）。
// 不做 macOS 桌面元素（红绿灯 / 菜单栏 / 侧边抽屉）——手机没有窗口管理语义。
// 标签切换带轻触感；IndexedStack 保留各页状态（会话不丢）。
// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';

import 'app_state.dart';
import 'memory_page.dart';
import 'motion.dart';
import 'qa_page.dart';
import 'settings_page.dart';

class IosShell extends StatefulWidget {
  const IosShell({super.key});

  @override
  State<IosShell> createState() => _IosShellState();
}

class _IosShellState extends State<IosShell> {
  int _index = 0;

  static const _titles = ['聊天', '记忆', '设置'];
  static const _icons = [
    CupertinoIcons.chat_bubble,
    CupertinoIcons.person_2,
    CupertinoIcons.settings,
  ];
  static const _activeIcons = [
    CupertinoIcons.chat_bubble_fill,
    CupertinoIcons.person_2_fill,
    CupertinoIcons.settings_solid,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppStateScope.of(context).warmUp();
    });
  }

  void _select(int i) {
    if (i == _index) return;
    macHaptic();
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final cup = CupertinoTheme.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cup.scaffoldBackgroundColor,
      body: Column(
        children: [
          if (state.loadStage.isNotEmpty && !state.gatewayLoaded)
            Container(
              color: scheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(state.loadStage)),
                ],
              ),
            ),
          if (state.loadError != null)
            Container(
              color: scheme.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '模型加载失败: ${state.loadError}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                  TextButton(onPressed: state.warmUp, child: const Text('重试')),
                ],
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: const [QaPage(), MemoryPage(), SettingsPage()],
            ),
          ),
        ],
      ),
      bottomNavigationBar: CupertinoTabBar(
        currentIndex: _index,
        onTap: _select,
        activeColor: cup.primaryColor,
        items: [
          for (var i = 0; i < _titles.length; i++)
            BottomNavigationBarItem(
              icon: Icon(_icons[i]),
              activeIcon: Icon(_activeIcons[i]),
              label: _titles[i],
            ),
        ],
      ),
    );
  }
}
