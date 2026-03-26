import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();
  static const String _isDarkModeKey = 'isDarkMode';
  static const String _uiScaleKey = 'uiScale';
  static const String _textScaleKey = 'textScale';
  static const String _showLinkPreviewsKey = 'showLinkPreviews';
  static const String _reduceMotionKey = 'reduceMotion';

  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;
  double _uiScale = 1.0;
  double _textScale = 1.0;
  bool _showLinkPreviews = true;
  bool _reduceMotion = false;

  double get uiScale => _uiScale;
  double get textScale => _textScale;
  bool get showLinkPreviews => _showLinkPreviews;
  bool get reduceMotion => _reduceMotion;

  // Initialize theme from saved preference
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool(_isDarkModeKey) ?? false;
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    _uiScale = (prefs.getDouble(_uiScaleKey) ?? 1.0).clamp(0.65, 1.65);
    _textScale = (prefs.getDouble(_textScaleKey) ?? 1.0).clamp(0.7, 1.5);
    _showLinkPreviews = prefs.getBool(_showLinkPreviewsKey) ?? true;
    _reduceMotion = prefs.getBool(_reduceMotionKey) ?? false;
    notifyListeners();
  }

  // Toggle dark mode
  Future<void> toggleTheme() async {
    _themeMode = _themeMode == ThemeMode.light
        ? ThemeMode.dark
        : ThemeMode.light;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isDarkModeKey, _themeMode == ThemeMode.dark);

    notifyListeners();
  }

  // Set specific theme
  Future<void> setTheme(ThemeMode mode) async {
    _themeMode = mode;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isDarkModeKey, mode == ThemeMode.dark);

    notifyListeners();
  }

  Future<void> setUiScale(double value) async {
    final next = value.clamp(0.65, 1.65);
    if ((_uiScale - next).abs() < 0.001) return;
    _uiScale = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_uiScaleKey, _uiScale);
    notifyListeners();
  }

  Future<void> setTextScale(double value) async {
    final next = value.clamp(0.7, 1.5);
    if ((_textScale - next).abs() < 0.001) return;
    _textScale = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_textScaleKey, _textScale);
    notifyListeners();
  }

  Future<void> setShowLinkPreviews(bool value) async {
    if (_showLinkPreviews == value) return;
    _showLinkPreviews = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showLinkPreviewsKey, value);
    notifyListeners();
  }

  Future<void> setReduceMotion(bool value) async {
    if (_reduceMotion == value) return;
    _reduceMotion = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reduceMotionKey, value);
    notifyListeners();
  }

  static ThemeData get lightTheme => lightThemeFor();

  static ThemeData lightThemeFor({double uiScale = 1.0}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F766E),
      brightness: Brightness.light,
    );
    final baseTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 1,
      ),
      scaffoldBackgroundColor: colorScheme.surface,
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
    );
    return _applyUiScale(baseTheme, uiScale: uiScale);
  }

  static ThemeData get darkTheme => darkThemeFor();

  static ThemeData darkThemeFor({double uiScale = 1.0}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F766E),
      brightness: Brightness.dark,
    );
    final baseTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 1,
      ),
      scaffoldBackgroundColor: colorScheme.surface,
      cardTheme: CardThemeData(
        elevation: 2,
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
    );
    return _applyUiScale(baseTheme, uiScale: uiScale);
  }

  static ThemeData _applyUiScale(
    ThemeData baseTheme, {
    required double uiScale,
  }) {
    final scale = uiScale.clamp(0.65, 1.65);
    final visualDensity = ((scale - 1.0) * 4.0).clamp(-1.8, 2.0);
    final cornerRadius = (12 * scale).clamp(10.0, 20.0);
    final toolbarHeight = (56 * scale).clamp(52.0, 72.0);
    final minTileHeight = (56 * scale).clamp(48.0, 74.0);
    final horizontalPadding = (16 * scale).clamp(12.0, 24.0);
    final inputVerticalPadding = (12 * scale).clamp(10.0, 18.0);
    final iconSize = (24 * scale).clamp(20.0, 32.0);
    final fabExtent = (56 * scale).clamp(48.0, 72.0);
    final tabPadding = (12 * scale).clamp(10.0, 18.0);

    OutlineInputBorder inputBorder(Color color, {double width = 1}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(cornerRadius),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return baseTheme.copyWith(
      visualDensity: VisualDensity(
        horizontal: visualDensity,
        vertical: visualDensity,
      ),
      iconTheme: baseTheme.iconTheme.copyWith(size: iconSize),
      primaryIconTheme: baseTheme.primaryIconTheme.copyWith(size: iconSize),
      appBarTheme: baseTheme.appBarTheme.copyWith(toolbarHeight: toolbarHeight),
      listTileTheme: baseTheme.listTileTheme.copyWith(
        minTileHeight: minTileHeight,
        minLeadingWidth: (24 * scale).clamp(20.0, 40.0),
        contentPadding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      ),
      tabBarTheme: baseTheme.tabBarTheme.copyWith(
        labelPadding: EdgeInsets.symmetric(horizontal: tabPadding),
      ),
      cardTheme: baseTheme.cardTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cornerRadius),
        ),
      ),
      inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
        contentPadding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: inputVerticalPadding,
        ),
        border: inputBorder(Colors.transparent, width: 0),
        enabledBorder: inputBorder(Colors.transparent, width: 0),
        focusedBorder: inputBorder(baseTheme.colorScheme.primary, width: 1.4),
      ),
      floatingActionButtonTheme: baseTheme.floatingActionButtonTheme.copyWith(
        sizeConstraints: BoxConstraints.tightFor(
          width: fabExtent,
          height: fabExtent,
        ),
      ),
    );
  }
}
