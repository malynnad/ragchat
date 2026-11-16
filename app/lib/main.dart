// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nobodywho/nobodywho.dart' as nobodywho;

import 'app/app_state.dart';
import 'app/home_page.dart';
import 'app/ios_dialogs.dart';
import 'app/model_prep_page.dart';
import 'app/theme.dart';

/// 正式入口：首启模型准备页（US-1），确认后底部标签栏主页（iOS 风格）。
/// VerifyPage 保留为设置里的真机诊断工具。
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // nobodywho 要求全应用恰好调用一次 init（动态链接 Rust 库）
  await nobodywho.NobodyWho.init();
  final state = AppState();
  await state.init();
  runApp(AppStateScope(state: state, child: const RagKbApp()));
}

class RagKbApp extends StatelessWidget {
  const RagKbApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    return MaterialApp(
      title: 'RAGchat',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(state.accent.light),
      darkTheme: buildDarkTheme(state.accent.dark),
      themeMode: state.themeMode,
      // Cupertino 弹层/控件查找 CupertinoLocalizations；显式补默认 delegate 兜底。
      localizationsDelegates: const [DefaultCupertinoLocalizations.delegate],
      // CupertinoTheme 放在根 Navigator 之上，使所有路由继承 iOS 主题。
      builder: (context, child) {
        final platform = MediaQuery.platformBrightnessOf(context);
        final isDark =
            state.themeMode == ThemeMode.dark ||
            (state.themeMode == ThemeMode.system &&
                platform == Brightness.dark);
        return iosAppBuilder(
          context,
          child,
          theme: isDark
              ? buildCupertinoDarkTheme(state.accent.dark)
              : buildCupertinoLightTheme(state.accent.light),
        );
      },
      home: AnimatedBuilder(
        animation: state,
        builder: (_, _) =>
            state.entered ? const HomePage() : const ModelPrepPage(),
      ),
    );
  }
}
