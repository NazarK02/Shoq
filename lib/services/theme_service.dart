import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();
  static const String _isDarkModeKey = 'isDarkMode';
  static const String _uiScaleKey = 'uiScale';
  static const String _showLinkPreviewsKey = 'showLinkPreviews';
  static const String _reduceMotionKey = 'reduceMotion';

  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;
  double _uiScale = 1.0;
  bool _showLinkPreviews = true;
  bool _reduceMotion = false;

  double get uiScale => _uiScale;
  bool get showLinkPreviews => _showLinkPreviews;
  bool get reduceMotion => _reduceMotion;

  // Initialize theme from saved preference
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool(_isDarkModeKey) ?? false;
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    _uiScale = (prefs.getDouble(_uiScaleKey) ?? 1.0).clamp(0.85, 1.35);
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
    final next = value.clamp(0.85, 1.35);
    if ((_uiScale - next).abs() < 0.001) return;
    _uiScale = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_uiScaleKey, _uiScale);
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

  // Light theme
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F766E),
      brightness: Brightness.light,
    );
    return ThemeData(
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
  }

  // Dark theme
  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F766E),
      brightness: Brightness.dark,
    );
    return ThemeData(
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
  }
}
