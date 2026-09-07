import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/app_language.dart';
import 'package:scheduling/features/maps/address_map_launcher.dart';
import 'package:scheduling/features/maps/application/maps_providers.dart';
import 'package:scheduling/features/presence/application/live_map_providers.dart';
import 'package:scheduling/features/presence/domain/live_map_aggregator.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';

/// Bottom overlay shown when a staff marker is tapped — avatar, name,
/// freshness line, and an address with an "Open in Maps" action. Watches the
/// 30s tick to keep the freshness line refreshed.
class StaffInfoCard extends ConsumerWidget {
  const StaffInfoCard({
    required this.point,
    required this.onClose,
    super.key,
  });

  final StaffMapPoint point;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    ref.watch(liveMapTickProvider); // drives the 30 s freshness refresh
    final now = ref.watch(liveMapClockProvider)();
    final stale = LiveMapAggregator.isStale(point.updatedAt, now);
    final bucket = LiveMapAggregator.freshnessOf(point.updatedAt, now);

    // Locale switch rebuilds this card with the right language (server only speaks en/fr).
    final lang = Localizations.localeOf(context).languageCode;
    final key = ReverseGeocodeQuery(
      lat: point.lat,
      lng: point.lng,
      locale: serverLocaleOf(lang),
    );
    final addressAsync = ref.watch(reverseGeocodeProvider(key));
    final resolvedAddress = addressAsync.value;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sp12),
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sp16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppAvatar(name: point.name, color: point.color),
                    const SizedBox(width: AppSpacing.sp12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            point.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sp4),
                          _FreshnessLine(bucket: bucket, stale: stale),
                          _AddressLine(addressAsync: addressAsync),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonLabel,
                      onPressed: onClose,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sp8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.directions_outlined),
                    label: Text(context.l10n.liveMap_openInMaps),
                    onPressed: () => AddressMapLauncher.showMapChoices(
                      context,
                      ref,
                      address: resolvedAddress?.isNotEmpty ?? false
                          ? resolvedAddress!
                          : '${point.lat},${point.lng}',
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

class _FreshnessLine extends StatelessWidget {
  const _FreshnessLine({required this.bucket, required this.stale});

  final FreshnessBucket bucket;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ago = _bucketText(context, bucket);
    final text = stale ? context.l10n.liveMap_offlineLastSeen(ago) : ago;
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: stale ? scheme.onSurfaceVariant : scheme.onSurface,
      ),
    );
  }

  static String _bucketText(BuildContext context, FreshnessBucket bucket) {
    final l10n = context.l10n;
    return switch (bucket) {
      FreshnessJustNow() => l10n.liveMap_lastUpdatedJustNow,
      FreshnessMinutesAgo(:final minutes) => l10n.liveMap_lastUpdatedMinutesAgo(
        minutes,
      ),
      FreshnessHoursAgo(:final hours) => l10n.liveMap_lastUpdatedHoursAgo(
        hours,
      ),
    };
  }
}

class _AddressLine extends StatelessWidget {
  const _AddressLine({required this.addressAsync});

  final AsyncValue<String?> addressAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return switch (addressAsync) {
      AsyncData(:final value) when value != null && value.isNotEmpty => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sp4),
        child: Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurface,
          ),
        ),
      ),
      AsyncLoading() => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sp4),
        child: Text(
          context.l10n.liveMap_resolvingAddress,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
      // Error or a null result → the address line is hidden entirely.
      _ => const SizedBox.shrink(),
    };
  }
}
