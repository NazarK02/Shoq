import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the app locale: follows device locale by default,
/// allows the user to override with a specific language in Settings.
///
/// Supported locales must match the ARB files in lib/l10n/:
///   en, pt_PT, uk
class LocaleService extends ChangeNotifier {
  static final LocaleService _instance = LocaleService._internal();
  factory LocaleService() => _instance;
  LocaleService._internal();

  static const _prefKey = 'user_locale_override';

  // null means "follow the device locale"
  Locale? _localeOverride;
  Locale? get localeOverride => _localeOverride;

  /// The effective locale passed to MaterialApp.locale.
  /// Returning null tells Flutter to use the device locale.
  Locale? get locale => _localeOverride;

  static const supportedLocales = [
    Locale('en'),
    Locale('pt', 'PT'),
    Locale('uk'),
  ];

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null) {
      _localeOverride = null;
    } else {
      _localeOverride = _parseLocale(raw);
    }
    // No notifyListeners here — called before runApp.
  }

  /// Sets an explicit locale override and persists it.
  Future<void> setLocale(Locale? locale) async {
    if (_localeOverride == locale) return;
    _localeOverride = locale;
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_prefKey);
    } else {
      await prefs.setString(_prefKey, _serializeLocale(locale));
    }
    notifyListeners();
  }

  /// Resets to device locale.
  Future<void> clearOverride() => setLocale(null);

  bool get isOverriding => _localeOverride != null;

  /// Returns a human-readable display name for use in the Settings UI.
  /// Falls back to the locale tag if the locale is not in the supported list.
  static String displayNameFor(Locale locale, {required Locale uiLocale}) {
    // Names are always shown in the target language, not the current UI locale,
    // so the user can recognise their own language regardless of current setting.
    const names = {
      'en':    'English',
      'pt_PT': 'Português (Portugal)',
      'uk':    'Українська',
    };
    return names[_serializeLocale(locale)] ?? locale.toLanguageTag();
  }

  // ─── private helpers ────────────────────────────────────────────────────────

  static String _serializeLocale(Locale locale) {
    if (locale.countryCode != null && locale.countryCode!.isNotEmpty) {
      return '${locale.languageCode}_${locale.countryCode}';
    }
    return locale.languageCode;
  }

  static Locale _parseLocale(String raw) {
    final parts = raw.split('_');
    if (parts.length >= 2) return Locale(parts[0], parts[1]);
    return Locale(parts[0]);
  }
}
