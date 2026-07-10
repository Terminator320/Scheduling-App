import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Persistent app-level offline indicator (U13): a slim strip that appears
/// on every screen while the device has no network connection and reassures
/// that changes sync on reconnect (Firestore's local queue).
///
/// Mounted by `main.dart` below the app's `Navigator`, docked at the
/// *bottom* edge of the window — deliberately opposite `NoticeListener`,
/// whose transient banners slide in at the top, so the two can never cover
/// each other. Wraps its own bottom [SafeArea] (the navigator above keeps
/// its regular insets).
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(isOfflineProvider);
    if (!offline) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.inverseSurface,
      child: SafeArea(
        top: false,
        child: Semantics(
          // Announce appearing/disappearing to screen readers.
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sp16,
              vertical: AppSpacing.sp8,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 16,
                  color: scheme.onInverseSurface,
                ),
                const SizedBox(width: AppSpacing.sp8),
                Flexible(
                  child: Text(
                    context.l10n.common_offlineBanner,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onInverseSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
