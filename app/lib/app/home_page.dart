import 'package:material_ui/material_ui.dart';

import 'ios_shell.dart';

/// 主页入口（iOS 改造）：外壳交给 IosShell（底部常驻标签栏 +
/// 各页 CupertinoNavigationBar + 模型加载横幅）。
/// 保留 HomePage 类名供测试与 main.dart 引用。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => const IosShell();
}
