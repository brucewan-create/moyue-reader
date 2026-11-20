import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 阅读主题预设
enum ReaderTheme {
  paper('纸张', Color(0xFFFAF6ED), Color(0xFF2C2C2C)),
  white('纯白', Color(0xFFFFFFFF), Color(0xFF222222)),
  green('护眼绿', Color(0xFFCCE8CF), Color(0xFF2C2C2C)),
  sepia('米黄', Color(0xFFF5E6C8), Color(0xFF4A3C28)),
  gray('浅灰', Color(0xFFE8E8E8), Color(0xFF333333)),
  dark('夜间', Color(0xFF1A1A1A), Color(0xFFB0B0B0)),
  midnight('深蓝夜', Color(0xFF0F1419), Color(0xFFA0AAB5));

  final String label;
  final Color background;
  final Color text;

  const ReaderTheme(this.label, this.background, this.text);
}

/// 阅读设置
class ReaderSettings {
  final ReaderTheme theme;
  final double fontSize;
  final double lineHeight;
  final double letterSpacing;
  final int fontFamilyIndex;
  final bool isDarkMode;
  final bool showStatusBar;
  final bool pageTurnAnimation;
  final int pageTurnMode; // 0=左右翻页 1=上下滚动
  final int indent; // 首行缩进字符数

  ReaderSettings({
    this.theme = ReaderTheme.paper,
    this.fontSize = 18,
    this.lineHeight = 1.7,
    this.letterSpacing = 0.5,
    this.fontFamilyIndex = 0,
    this.isDarkMode = false,
    this.showStatusBar = true,
    this.pageTurnAnimation = true,
    this.pageTurnMode = 0,
    this.indent = 2,
  });

  ReaderSettings copyWith({
    ReaderTheme? theme,
    double? fontSize,
    double? lineHeight,
    double? letterSpacing,
    int? fontFamilyIndex,
    bool? isDarkMode,
    bool? showStatusBar,
    bool? pageTurnAnimation,
    int? pageTurnMode,
    int? indent,
  }) =>
      ReaderSettings(
        theme: theme ?? this.theme,
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight ?? this.lineHeight,
        letterSpacing: letterSpacing ?? this.letterSpacing,
        fontFamilyIndex: fontFamilyIndex ?? this.fontFamilyIndex,
        isDarkMode: isDarkMode ?? this.isDarkMode,
        showStatusBar: showStatusBar ?? this.showStatusBar,
        pageTurnAnimation: pageTurnAnimation ?? this.pageTurnAnimation,
        pageTurnMode: pageTurnMode ?? this.pageTurnMode,
        indent: indent ?? this.indent,
      );

  static const List<String> fontFamilies = [
    '系统默认',
    '宋体',
    '黑体',
    '楷体',
  ];

  String get fontFamily {
    switch (fontFamilyIndex) {
      case 1:
        return 'serif';
      case 2:
        return 'sans-serif';
      case 3:
        return 'cursive';
      default:
        return '';
    }
  }
}

/// 设置服务
class SettingsService extends ChangeNotifier {
  static final SettingsService instance = SettingsService._internal();
  SettingsService._internal();

  late SharedPreferences _prefs;
  ReaderSettings _settings = ReaderSettings();
  bool _loaded = false;

  ReaderSettings get settings => _settings;
  bool get loaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();

    final themeIndex = _prefs.getInt('theme') ?? 0;
    _settings = ReaderSettings(
      theme: ReaderTheme.values[themeIndex.clamp(0, ReaderTheme.values.length - 1)],
      fontSize: _prefs.getDouble('fontSize') ?? 18,
      lineHeight: _prefs.getDouble('lineHeight') ?? 1.7,
      letterSpacing: _prefs.getDouble('letterSpacing') ?? 0.5,
      fontFamilyIndex: _prefs.getInt('fontFamilyIndex') ?? 0,
      isDarkMode: _prefs.getBool('isDarkMode') ?? false,
      showStatusBar: _prefs.getBool('showStatusBar') ?? true,
      pageTurnAnimation: _prefs.getBool('pageTurnAnimation') ?? true,
      pageTurnMode: _prefs.getInt('pageTurnMode') ?? 0,
      indent: _prefs.getInt('indent') ?? 2,
    );
    _loaded = true;
    notifyListeners();
  }

  Future<void> update(ReaderSettings newSettings) async {
    _settings = newSettings;
    await _prefs.setInt('theme', newSettings.theme.index);
    await _prefs.setDouble('fontSize', newSettings.fontSize);
    await _prefs.setDouble('lineHeight', newSettings.lineHeight);
    await _prefs.setDouble('letterSpacing', newSettings.letterSpacing);
    await _prefs.setInt('fontFamilyIndex', newSettings.fontFamilyIndex);
    await _prefs.setBool('isDarkMode', newSettings.isDarkMode);
    await _prefs.setBool('showStatusBar', newSettings.showStatusBar);
    await _prefs.setBool('pageTurnAnimation', newSettings.pageTurnAnimation);
    await _prefs.setInt('pageTurnMode', newSettings.pageTurnMode);
    await _prefs.setInt('indent', newSettings.indent);
    notifyListeners();
  }
}
