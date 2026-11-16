// Apple/iOS 风格主题单点入口。
// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';

/// 双轨主题（iOS 化）：
/// - [buildCupertinoLightTheme]/[buildCupertinoDarkTheme]：CupertinoThemeData，
///   供 CupertinoNavigationBar/CupertinoTabBar/Cupertino 控件与弹层使用。
/// - [buildLightTheme]/[buildDarkTheme]：material_ui ThemeData，供页面内残留
///   Material 组件（ScaffoldMessenger/SnackBar/进度指示等）使用，已对齐 iOS 配色。
/// 两者共享同一组强调色与表面色，保证混搭视觉一致。

/// 应用强调色（Nord 霜青，iOS 化后作为 primaryColor / activeColor）。
const Color kIosAccentLight = Color(0xFF8FBCBB); // Nord Frost teal
const Color kIosAccentDark = Color(0xFF8FBCBB);

/// 默认强调色（Nord 霜蓝 81a1c1，用户指定色号）。
const Color kDefaultAccentLight = Color(0xFF81A1C1);
const Color kDefaultAccentDark = Color(0xFF81A1C1);

/// 三档字号（v2 字号统一；再批改整体 -1.5）：标题 / 正文 / 说明。
const double kFontTitle = 15.5;
const double kFontBody = 13.5;
const double kFontCaption = 10.5;

/// 强调色之上的文字/图标色：浅底用 Nord 深墨、深底用白，保证对比度。
/// 阈值 0.30：粉彩(81a1c1/8fbcbb/d8dee9/b48ead/d08770)落深墨、4c566a 落白。
Color onAccent(Color bg) => bg.computeLuminance() > 0.30
    ? const Color(0xFF2E3440)
    : CupertinoColors.white;

/// 一档可选主题色：id 持久化、label 展示、light/dark 双模式色值。
class AccentChoice {
  const AccentChoice({
    required this.id,
    required this.label,
    required this.light,
    required this.dark,
  });

  final String id;
  final String label;
  final Color light;
  final Color dark;
}

/// 主题色色板（v2 设置页「主题颜色」）：用户指定六色号（Nord 系），
/// 亮/暗同色；默认霜蓝在首。色号：81a1c1 / 4c566a / d8dee9 / 8fbcbb /
/// b48ead / d08770。
const List<AccentChoice> kAccents = [
  AccentChoice(
    id: 'blue',
    label: '霜蓝',
    light: kDefaultAccentLight,
    dark: kDefaultAccentDark,
  ),
  AccentChoice(
    id: 'slate',
    label: '墨蓝',
    light: Color(0xFF4C566A),
    dark: Color(0xFF4C566A),
  ),
  AccentChoice(
    id: 'gray',
    label: '浅灰',
    light: Color(0xFFD8DEE9),
    dark: Color(0xFFD8DEE9),
  ),
  AccentChoice(
    id: 'teal',
    label: '霜青',
    light: kIosAccentLight,
    dark: kIosAccentDark,
  ),
  AccentChoice(
    id: 'purple',
    label: '雾紫',
    light: Color(0xFFB48EAD),
    dark: Color(0xFFB48EAD),
  ),
  AccentChoice(
    id: 'orange',
    label: '赭橙',
    light: Color(0xFFD08770),
    dark: Color(0xFFD08770),
  ),
];

/// 默认主题色 id（与 [AppSettings.accentId] 默认值保持一致）。
const String kDefaultAccentId = 'blue';

/// 按 id 取色板档位；未知 id 回退默认档（旧配置/手改 json 兜底）。
AccentChoice accentById(String id) =>
    kAccents.firstWhere((a) => a.id == id, orElse: () => kAccents.first);

/// iOS 分组背景 / 卡片 / 导航栏表面色（亮 / 暗）。
const Color kIosGroupedBgLight = Color(0xFFF2F2F7);
const Color kIosGroupedBgDark = Color(0xFF000000);
const Color kIosCardLight = Color(0xFFFFFFFF);
const Color kIosCardDark = Color(0xFF1C1C1E);
const Color kIosBarLight = Color(0xFFF9F9F9);
const Color kIosBarDark = Color(0xFF1C1C1E);
const Color kIosSeparatorLight = Color(0xFFC6C6C8);
const Color kIosSeparatorDark = Color(0xFF38383A);

/// iOS 系统语义色（destructive / warning）。
const Color kIosRed = Color(0xFFFF3B30);
const Color kIosOrange = Color(0xFFFF9500);

CupertinoThemeData buildCupertinoLightTheme([
  Color accent = kDefaultAccentLight,
]) => CupertinoThemeData(
  brightness: Brightness.light,
  primaryColor: accent,
  scaffoldBackgroundColor: kIosGroupedBgLight,
  barBackgroundColor: kIosBarLight,
  textTheme: _cupertinoTextTheme(Brightness.light),
);

CupertinoThemeData buildCupertinoDarkTheme([
  Color accent = kDefaultAccentDark,
]) => CupertinoThemeData(
  brightness: Brightness.dark,
  primaryColor: accent,
  scaffoldBackgroundColor: kIosGroupedBgDark,
  barBackgroundColor: kIosBarDark,
  textTheme: _cupertinoTextTheme(Brightness.dark),
);

/// 隐式正文降到正文字号（导航标题仍 17），避免 Cupertino 默认 17 显大。
CupertinoTextThemeData _cupertinoTextTheme(Brightness b) =>
    CupertinoTextThemeData(
      textStyle: TextStyle(
        fontSize: kFontBody,
        color: b == Brightness.light
            ? const Color(0xFF000000)
            : const Color(0xFFFFFFFF),
      ),
    );

/// material 亮色主题（对齐 iOS 分组背景与圆角，供残留 Material 组件）。
ThemeData buildLightTheme([Color accent = kDefaultAccentLight]) => ThemeData(
  colorSchemeSeed: accent,
  useMaterial3: true,
  brightness: Brightness.light,
  scaffoldBackgroundColor: kIosGroupedBgLight,
  appBarTheme: const AppBarTheme(
    backgroundColor: kIosBarLight,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: true,
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    color: kIosCardLight,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
  dividerTheme: const DividerThemeData(
    thickness: 0.5,
    space: 0.5,
    color: kIosSeparatorLight,
  ),
  snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(fontSize: kFontCaption, color: Color(0xFF000000)),
  ),
);

/// material 暗色主题。
ThemeData buildDarkTheme([Color accent = kDefaultAccentDark]) => ThemeData(
  colorSchemeSeed: accent,
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: kIosGroupedBgDark,
  appBarTheme: const AppBarTheme(
    backgroundColor: kIosBarDark,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: true,
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    color: kIosCardDark,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
  dividerTheme: const DividerThemeData(
    thickness: 0.5,
    space: 0.5,
    color: kIosSeparatorDark,
  ),
  snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(fontSize: kFontCaption, color: Color(0xFFFFFFFF)),
  ),
);
