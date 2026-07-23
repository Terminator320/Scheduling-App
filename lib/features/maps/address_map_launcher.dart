import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:scheduling/core/adaptive/adaptive.dart';
import 'package:scheduling/core/adaptive/adaptive_action_sheet.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/error_snack_bar.dart';
import 'package:url_launcher/url_launcher.dart';

class AddressMapLauncher {
  const AddressMapLauncher._();

  static Future<void> showMapChoices(
    BuildContext context, {
    required String address,
  }) async {
    final cleanAddress = address.trim();
    if (cleanAddress.isEmpty) return;

    final navAddress =
        AddressParser.splitApt(cleanAddress)?.street ?? cleanAddress;
    final navEncoded = Uri.encodeComponent(navAddress);
    final displayAddress = AddressParser.canonicalToDisplay(cleanAddress);

    final options = <_MapOption>[
      if (Platform.isIOS)
        _MapOption(
          label: context.l10n.maps_appleMaps,
          icon: Icons.map_outlined,
          uri: Uri.parse('http://maps.apple.com/?q=$navEncoded'),
        ),
      _MapOption(
        label: context.l10n.maps_googleMaps,
        icon: Icons.map_outlined,
        uri: Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$navEncoded',
        ),
      ),
      _MapOption(
        label: context.l10n.maps_waze,
        icon: Icons.navigation_outlined,
        uri: Uri.parse('https://waze.com/ul?q=$navEncoded&navigate=yes'),
      ),
    ];

    if (!context.mounted) return;

    // iOS uses a native CupertinoActionSheet, Android the Material sheet; both resolve to one launched URI.
    final Uri? chosen;
    if (context.isCupertino) {
      chosen = await showAdaptiveActionSheet<Uri>(
        context,
        title: context.l10n.maps_openAddressWith,
        message: displayAddress,
        actions: [
          for (final option in options)
            AdaptiveSheetAction(
              value: option.uri,
              label: option.label,
              icon: option.icon,
            ),
        ],
      );
    } else {
      chosen = await showModalBottomSheet<Uri>(
        context: context,
        showDragHandle: true,
        sheetAnimationStyle: AppMotion.sheetStyle,
        builder: (sheetContext) {
          final theme = Theme.of(sheetContext);

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sp16,
                AppSpacing.sp4,
                AppSpacing.sp16,
                AppSpacing.sp16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.maps_openAddressWith,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sp4),
                  Text(
                    displayAddress,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sp12),
                  ...options.map(
                    (option) => ListTile(
                      leading: Icon(option.icon),
                      title: Text(option.label),
                      contentPadding: EdgeInsets.zero,
                      onTap: () => Navigator.pop(sheetContext, option.uri),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    if (chosen == null || !context.mounted) return;
    // Guard unguarded launchUrl throws (would become FATAL); log before mounted guard.
    var opened = false;
    try {
      opened = await launchUrl(chosen, mode: LaunchMode.externalApplication);
    } catch (e, st) {
      AppLogger().warn('LAUNCH-MAPS showMapChoices launchUrl failed', e, st);
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        errorSnackBar(context, context.l10n.error_couldNotOpenMapApp),
      );
    }
  }
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
