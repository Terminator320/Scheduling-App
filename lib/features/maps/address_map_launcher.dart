import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:url_launcher/url_launcher.dart';

class AddressMapLauncher {
  const AddressMapLauncher._();

  static Future<void> showMapChoices(
    BuildContext context, {
    required String address,
  }) async {
    final cleanAddress = address.trim();
    if (cleanAddress.isEmpty) return;

    final navAddress = _stripAptForNav(cleanAddress);
    final navEncoded = Uri.encodeComponent(navAddress);
    final displayAddress = AddressParser.canonicalToDisplay(cleanAddress);

    final options = <_MapOption>[
      if (Platform.isIOS)
        _MapOption(
          label: context.l10n.appleMaps,
          icon: Icons.map_outlined,
          uri: Uri.parse('http://maps.apple.com/?q=$navEncoded'),
        ),
      _MapOption(
        label: context.l10n.googleMaps,
        icon: Icons.map_outlined,
        uri: Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$navEncoded',
        ),
      ),
      _MapOption(
        label: context.l10n.waze,
        icon: Icons.navigation_outlined,
        uri: Uri.parse('https://waze.com/ul?q=$navEncoded&navigate=yes'),
      ),
    ];

    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 280),
        reverseDuration: Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
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
                  context.l10n.openAddressWith,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  displayAddress,
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
                        final scheme = Theme.of(context).colorScheme;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: scheme.errorContainer,
                            content: Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: scheme.onErrorContainer,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    context.l10n.couldNotOpenMapApp,
                                    style: TextStyle(
                                      color: scheme.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
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

String _stripAptForNav(String address) {
  final parts = AddressParser.splitApt(address);
  return parts?.street ?? address;
}

class _MapOption {
  const _MapOption({
    required this.label,
    required this.icon,
    required this.uri,
  });
  final String label;
  final IconData icon;
  final Uri uri;
}
