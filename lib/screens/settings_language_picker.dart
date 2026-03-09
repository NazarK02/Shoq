// lib/screens/settings_language_picker.dart
//
// Drop-in replacement for the "Language" ListTile in settings_screen.dart.
// Shows a modal bottom sheet with the three supported locales plus
// a "System default" option.
//
// Usage — replace the existing Language ListTile with:
//
//   const LanguagePickerTile(),
//

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/locale_service.dart';
import '../generated/app_localizations.dart';

class LanguagePickerTile extends StatelessWidget {
  const LanguagePickerTile({super.key});

  @override
  Widget build(BuildContext context) {
    final localeService = context.watch<LocaleService>();
    final l = AppLocalizations.of(context);

    final currentLabel = localeService.isOverriding
        ? LocaleService.displayNameFor(
            localeService.localeOverride!,
            uiLocale: Localizations.localeOf(context),
          )
        : l.systemDefault;

    return ListTile(
      leading: const Icon(Icons.language),
      title: Text(l.language),
      subtitle: Text(currentLabel),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () => _showPicker(context, localeService, l),
    );
  }

  void _showPicker(
    BuildContext context,
    LocaleService service,
    AppLocalizations l,
  ) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text(
                  l.selectLanguage,
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              const Divider(height: 1),
              // System default
              _LocaleTile(
                label: l.systemDefault,
                isSelected: !service.isOverriding,
                onTap: () {
                  service.clearOverride();
                  Navigator.pop(ctx);
                },
              ),
              // Supported locales
              ...LocaleService.supportedLocales.map((locale) {
                final isSelected =
                    service.isOverriding &&
                    service.localeOverride == locale;
                return _LocaleTile(
                  label: LocaleService.displayNameFor(
                    locale,
                    uiLocale: Localizations.localeOf(context),
                  ),
                  isSelected: isSelected,
                  onTap: () {
                    service.setLocale(locale);
                    Navigator.pop(ctx);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _LocaleTile extends StatelessWidget {
  const _LocaleTile({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      title: Text(label),
      trailing: isSelected
          ? Icon(Icons.check, color: colorScheme.primary)
          : null,
      onTap: onTap,
    );
  }
}
