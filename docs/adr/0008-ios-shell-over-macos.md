# 视觉外壳转向 Apple/iOS（底部标签栏），取代仿 macOS 方案

v2 计划（docs/specs/2026-11-15-v2-update.md）原定视觉为「仿 macOS 桌面风格」并等待用户提供专用 skill。2026-11-15 用户纠正方向：「是仿 apple，不是 macos」，并反馈 macOS 外壳把导航藏进汉堡抽屉，在手机上「根本无法切换标签页」。经确认「整体改 iOS 风格」后，移除 macos_ui，改用 Cupertino 底部标签栏外壳。本 ADR 记录该决策反转（类比 ADR-0007 对人设排除项的受限反转）。

## 状态

accepted

## 决策

1. **导航模型**：底部常驻 `CupertinoTabBar`（问答 / 文档 / 设置）一点即切，`IndexedStack` 保留各页状态（会话输入不丢）；每页自带 `CupertinoNavigationBar` 作为 Material `Scaffold.appBar`（实现 PreferredSizeWidget，自动避开状态栏）。**不做 macOS 桌面元素**（红绿灯 / 菜单栏 / 侧边抽屉 / 窗口拖拽缩放）——手机没有窗口管理语义。
2. **控件 Cupertino 化**：输入框、按钮、开关、滑杆、分段控件、警告框、动作表、底部弹层统一 Cupertino；保留 Material `Scaffold` 以复用 ScaffoldMessenger / SnackBar / 安全区 / 键盘避让。Cupertino 无需 MaterialLocalizations 桥接（比 macos_ui 简单）。
3. **动效保留**：motion.dart 弹簧（SpringSimulation，默认 ζ1.0/T0.35、手势 ζ0.8/T0.3）、手势速度继承、触感降级静默、减少动态效果直接跳变；`showIosSheet` 为可中断弹簧底部弹层（拖拽可反向关闭）。
4. **红屏修法延续**：弹层 / 文本对话框为 StatefulWidget 自持 `TextEditingController`，在 `State.dispose` 释放（不在 `await showDialog` 后立即 dispose——该 Future 在 pop 开始即完成，焦点恢复会在退场动画中重建已释放控制器）。
5. **主题双轨**：theme.dart 同时提供 Cupertino 与 Material 双主题，teal 主色（浅 0xFF0D9488 / 暗 0xFF2DD4BF）+ 分组背景；`iosAppBuilder` 在根 Navigator 之上注入 CupertinoTheme，使所有路由继承。

## 后果

- 取代计划 P5「仿 macOS + 等待 skill」视觉决策；pubspec 移除 macos_ui，删除 mac_shell.dart / mac_dialogs.dart 及其测试。
- 根治两个真机缺陷：「无法切换标签页」与「顶栏压状态栏」。2026-11-15 真机（d504870）截图验证：问答↔文档↔设置 三向切换正常、选中指示同步、切回保留输入；各页顶栏均不压状态栏。
- 业务逻辑（检索 / 会话 / 分类 / 风格 / 模型切换）不变；74/74 主机测试绿、分析器零警告（新增 ios_shell_test.dart 4 例：标签渲染、切文档、切设置、切页保留状态）。
- 功能冒烟的中文输入部分仍待用户真机执行（豆包输入法阻挡 adb 注入，agent 以截图核对）。