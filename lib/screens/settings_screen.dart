import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/notification_service.dart';
import '../services/theme_service.dart';
import '../generated/app_localizations.dart';
import 'settings_language_picker.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final NotificationService _notificationService = NotificationService();
  bool _friendRequestsEnabled = true;
  bool _messagesEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
  }

  Future<void> _loadNotificationSettings() async {
    final settings = await _notificationService.getNotificationSettings();
    if (mounted) {
      setState(() {
        _friendRequestsEnabled = settings['friendRequests'] ?? true;
        _messagesEnabled = settings['messages'] ?? true;
      });
    }
  }

  Future<void> _updateNotificationSettings() async {
    await _notificationService.updateNotificationSettings(
      friendRequests: _friendRequestsEnabled,
      messages: _messagesEnabled,
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // ── Notifications ─────────────────────────────────────────────────
          _SectionHeader(label: 'Notifications'),
          SwitchListTile(
            secondary: const Icon(Icons.person_add_alt),
            title: const Text('Friend Requests'),
            subtitle: const Text(
              'Get notified when someone sends you a friend request',
            ),
            value: _friendRequestsEnabled,
            onChanged: (value) {
              setState(() => _friendRequestsEnabled = value);
              _updateNotificationSettings();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.message),
            title: const Text('Messages'),
            subtitle: const Text('Get notified when you receive a new message'),
            value: _messagesEnabled,
            onChanged: (value) {
              setState(() => _messagesEnabled = value);
              _updateNotificationSettings();
            },
          ),
          const Divider(),

          // ── Appearance ────────────────────────────────────────────────────
          _SectionHeader(label: 'Appearance'),
          SwitchListTile(
            secondary: Icon(
              themeService.isDarkMode ? Icons.dark_mode : Icons.light_mode,
            ),
            title: Text(l.darkMode),
            subtitle: Text(
              themeService.isDarkMode ? l.darkThemeEnabled : l.lightThemeEnabled,
            ),
            value: themeService.isDarkMode,
            onChanged: (_) => themeService.toggleTheme(),
          ),
          ListTile(
            leading: const Icon(Icons.text_fields),
            title: Text(l.uiSize),
            subtitle: Text(
              l.uiSizeSubtitle((themeService.uiScale * 100).round()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Slider(
              min: 0.65,
              max: 1.65,
              divisions: 20,
              label: '${(themeService.uiScale * 100).round()}%',
              value: themeService.uiScale,
              onChanged: (value) => themeService.setUiScale(value),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.format_size),
            title: const Text('Text Size'),
            subtitle: Text(
              '${(themeService.textScale * 100).round()}% - Text size multiplier',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Slider(
              min: 0.7,
              max: 1.5,
              divisions: 16,
              label: '${(themeService.textScale * 100).round()}%',
              value: themeService.textScale,
              onChanged: (value) => themeService.setTextScale(value),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.animation_outlined),
            title: Text(l.reduceMotion),
            subtitle: Text(l.reduceMotionSubtitle),
            value: themeService.reduceMotion,
            onChanged: (value) => themeService.setReduceMotion(value),
          ),
          const Divider(),

          // ── Chat ──────────────────────────────────────────────────────────
          _SectionHeader(label: l.sectionChat),
          SwitchListTile(
            secondary: const Icon(Icons.link_outlined),
            title: Text(l.linkPreviews),
            subtitle: Text(l.linkPreviewsSubtitle),
            value: themeService.showLinkPreviews,
            onChanged: (value) => themeService.setShowLinkPreviews(value),
          ),
          const Divider(),

          // ── General ───────────────────────────────────────────────────────
          _SectionHeader(label: l.sectionGeneral),
          ListTile(
            leading: const Icon(Icons.lock),
            title: Text(l.privacy),
            subtitle: Text(l.privacySubtitle),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showSnack(context, l.privacySettingsComingSoon),
          ),
          ListTile(
            leading: const Icon(Icons.security),
            title: Text(l.security),
            subtitle: Text(l.securitySubtitle),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showSnack(context, l.securitySettingsComingSoon),
          ),
          const Divider(),

          // ── Preferences ───────────────────────────────────────────────────
          _SectionHeader(label: l.sectionPreferences),
          // Language — uses the dedicated picker widget
          const LanguagePickerTile(),
          const Divider(),

          // ── Support ───────────────────────────────────────────────────────
          _SectionHeader(label: l.sectionSupport),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: Text(l.helpSupport),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showSnack(context, l.helpSupportComingSoon),
          ),
          ListTile(
            leading: const Icon(Icons.description),
            title: Text(l.termsOfService),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showSnack(context, l.termsComingSoon),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip),
            title: Text(l.privacyPolicy),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showSnack(context, l.comingSoon),
          ),
        ],
      ),
    );
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

/// Reusable section header — avoids the const Text boilerplate repeated
/// throughout the original file.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }
}
