import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/notification_service.dart';
import '../services/theme_service.dart';

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
    
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Notifications',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.person_add_alt),
                  title: const Text('Friend Requests'),
                  subtitle: const Text('Get notified when someone sends you a friend request'),
                  value: _friendRequestsEnabled,
                  onChanged: (value) {
                    setState(() {
                      _friendRequestsEnabled = value;
                    });
                    _updateNotificationSettings();
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.message),
                  title: const Text('Messages'),
                  subtitle: const Text('Get notified when you receive a new message'),
                  value: _messagesEnabled,
                  onChanged: (value) {
                    setState(() {
                      _messagesEnabled = value;
                    });
                    _updateNotificationSettings();
                  },
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Appearance',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                SwitchListTile(
                  secondary: Icon(
                    themeService.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                  ),
                  title: const Text('Dark Mode'),
                  subtitle: Text(
                    themeService.isDarkMode ? 'Dark theme enabled' : 'Light theme enabled',
                  ),
                  value: themeService.isDarkMode,
                  onChanged: (value) {
                    themeService.toggleTheme();
                  },
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'General',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.lock),
                  title: const Text('Privacy'),
                  subtitle: const Text('Control your privacy settings'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Privacy settings coming soon')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.security),
                  title: const Text('Security'),
                  subtitle: const Text('Password and authentication'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Security settings coming soon')),
                    );
                  },
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Preferences',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: const Text('Language'),
                  subtitle: const Text('English'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Language settings coming soon')),
                    );
                  },
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Support',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('Help & Support'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Help & Support coming soon')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.description),
                  title: const Text('Terms of Service'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Terms of Service coming soon')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip),
                  title: const Text('Privacy Policy'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Privacy Policy coming soon')),
                    );
                  },
                ),
        ],
      ),
    );
  }
}
