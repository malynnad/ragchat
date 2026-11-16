// 纸页与档案主题单点入口：一套色、一套字阶，不再提供多色主题。
// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';

import 'paper.dart';

/// 字阶（只取规范里的档位）：档案码 9 / dock 11 / 次要 12 / 正文 13 /
/// 控件 14 / 区块标题 18 / 报头 23。
const double kFontCode = 9;
const double kFontDock = 11;
const double kFontCaption = 12;
const double kFontBody = 13;
const double kFontControl = 14;
const double kFontTitle = 18;
const double kFontMasthead = 23;

/// 旧代码里的字号别名，映射到新字阶。
const double kFontBodyLegacy = kFontBody;

CupertinoThemeData buildCupertinoLightTheme() => CupertinoThemeData(
  brightness: Brightness.light,
  primaryColor: PaperPalette.light.ink,
  scaffoldBackgroundColor: Color(0xFFF4F3EF),
  barBackgroundColor: PaperPalette.light.surface,
  textTheme: _cupertinoTextTheme(Brightness.light),
);

CupertinoThemeData buildCupertinoDarkTheme() => CupertinoThemeData(
  brightness: Brightness.dark,
  primaryColor: PaperPalette.dark.ink,
  scaffoldBackgroundColor: Color(0xFF191919),
  barBackgroundColor: PaperPalette.dark.surface,
  textTheme: _cupertinoTextTheme(Brightness.dark),
);

CupertinoTextThemeData _cupertinoTextTheme(Brightness b) =>
    CupertinoTextThemeData(
      textStyle: TextStyle(
        fontSize: kFontBody,
        color: b == Brightness.light
            ? PaperPalette.light.ink
            : PaperPalette.dark.ink,
      ),
    );

/// material 亮色主题：只用于残留的 Material 组件（SnackBar / 进度等）。
ThemeData buildLightTheme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  colorScheme: ColorScheme.fromSeed(
    seedColor: PaperPalette.light.ink,
    brightness: Brightness.light,
  ),
  scaffoldBackgroundColor: Color(0xFFF4F3EF),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFFFDFCFA),
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: true,
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    color: Color(0xFFFDFCFA),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
  ),
  dividerTheme: const DividerThemeData(
    thickness: 0.6,
    space: 0.6,
    color: Color(0xFFD8DBD5),
  ),
  snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(fontSize: kFontBody, color: Color(0xFF181818)),
  ),
);

ThemeData buildDarkTheme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(
    seedColor: PaperPalette.dark.ink,
    brightness: Brightness.dark,
  ),
  scaffoldBackgroundColor: Color(0xFF191919),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF242424),
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: true,
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    color: Color(0xFF242424),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
  ),
  dividerTheme: const DividerThemeData(
    thickness: 0.6,
    space: 0.6,
    color: Color(0xFF3C3C3C),
  ),
  snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(fontSize: kFontBody, color: Color(0xFFF2F2F2)),
  ),
);
