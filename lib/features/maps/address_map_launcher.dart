import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AddressMapLauncher {
  const AddressMapLauncher._();

  static Future<void> showMapChoices(
    BuildContext context, {
    required String address,
  }) async {
    final cleanAddress = address.trim();
    if (cleanAddress.isEmpty) return;

    final options = <_MapOption>[
      if (Platform.isIOS)
        _MapOption(
          label: 'Apple Maps',
          icon: Icons.map_outlined,
          uri: Uri.parse(
            'http://maps.apple.com/?q=${Uri.encodeComponent(cleanAddress)}',
          ),
        ),
      _MapOption(
        label: 'Google Maps',
        icon: Icons.map_outlined,
        uri: Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(cleanAddress)}',
        ),
      ),
      _MapOption(
        label: 'Waze',
        icon: Icons.navigation_outlined,
        uri: Uri.parse(
          'https://waze.com/ul?q=${Uri.encodeComponent(cleanAddress)}&navigate=yes',
        ),
      ),
    ];

    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Open address with',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  cleanAddress,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                ...options.map(
                  (option) => ListTile(
                    leading: Icon(option.icon),
                    title: Text(option.label),
                    contentPadding: EdgeInsets.zero,
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final opened = await launchUrl(
                        option.uri,
                        mode: LaunchMode.externalApplication,
                      );

                      if (!opened && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Could not open ${option.label}.'),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MapOption {
  final String label;
  final IconData icon;
  final Uri uri;

  const _MapOption({
    required this.label,
    required this.icon,
    required this.uri,
  });
}
