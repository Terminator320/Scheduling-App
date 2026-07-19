import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/maps/application/maps_providers.dart';
import 'package:scheduling/features/presence/application/live_map_providers.dart';
import 'package:scheduling/features/presence/domain/live_map_aggregator.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';

/// Apple "Find My"-style bottom sheet: every staff member currently sharing a
/// location, ordered nearest-first relative to the viewing admin, each row
/// showing their city and how far they are from the admin. Tapping a row pops
/// the sheet with that [StaffMapPoint] so the map can recenter + select it.
///
/// Watches [liveMapPointsProvider] + the tick/clock directly, so the list
/// stays live (new fixes, freshness, someone dropping off) while it's open.
Future<StaffMapPoint?> showStaffRosterSheet(
  BuildContext context, {
  required String? selfDocId,
}) {
  return showModalBottomSheet<StaffMapPoint>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    sheetAnimationStyle: AppMotion.sheetStyle,
    builder: (_) => StaffRosterSheet(selfDocId: selfDocId),
  );
}

class StaffRosterSheet extends ConsumerWidget {
  const StaffRosterSheet({required this.selfDocId, super.key});

  /// The viewing admin's own users-doc id, so their row is labelled "You" and
  /// distances are measured from their live position. Null → no self anchor.
  final String? selfDocId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final points = ref.watch(liveMapPointsProvider).value ?? const [];
    final ordered = LiveMapAggregator.sortedByProximity(
      points,
      selfDocId: selfDocId,
    );

    StaffMapPoint? self;
    for (final p in points) {
      if (p.userDocId == selfDocId) {
        self = p;
        break;
      }
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sp12),
        child: Material(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.r20),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SheetGrabHandle(),
                _RosterHeader(count: ordered.length),
                const Divider(height: 1),
                Flexible(
                  child: ordered.isEmpty
                      ? const _RosterEmpty()
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.sp8,
                          ),
                          itemCount: ordered.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, indent: 72),
                          itemBuilder: (context, i) {
                            final point = ordered[i];
                            return StaffRosterRow(
                              point: point,
                              isSelf: point.userDocId == selfDocId,
                              distanceMeters: self == null
                                  ? null
                                  : LiveMapAggregator.distanceMeters(
                                      self.lat,
                                      self.lng,
                                      point.lat,
                                      point.lng,
                                    ),
                              onTap: () => Navigator.of(context).pop(point),
                            );
                          },
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

class _SheetGrabHandle extends StatelessWidget {
  const _SheetGrabHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(
          top: AppSpacing.sp8,
          bottom: AppSpacing.sp4,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _RosterHeader extends StatelessWidget {
  const _RosterHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sp16,
        AppSpacing.sp8,
        AppSpacing.sp16,
        AppSpacing.sp12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.liveMap_rosterTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (count > 0)
            Text(
              context.l10n.liveMap_rosterCount(count),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _RosterEmpty extends StatelessWidget {
  const _RosterEmpty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sp24),
      child: Text(
        context.l10n.liveMap_emptyState,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// One roster row: avatar, name (+ "You"), city · freshness, distance. Watches
/// the reverse-geocode + tick/clock providers itself so the city fills in and
/// freshness ticks without rebuilding the whole sheet.
class StaffRosterRow extends ConsumerWidget {
  const StaffRosterRow({
    required this.point,
    required this.isSelf,
    required this.distanceMeters,
    required this.onTap,
    super.key,
  });

  final StaffMapPoint point;
  final bool isSelf;
  final double? distanceMeters;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    ref.watch(liveMapTickProvider); // ticks freshness / staleness
    final now = ref.watch(liveMapClockProvider)();
    final stale = LiveMapAggregator.isStale(point.updatedAt, now);
    final bucket = LiveMapAggregator.freshnessOf(point.updatedAt, now);

    final lang = Localizations.localeOf(context).languageCode;
    final geoKey = ReverseGeocodeQuery(
      lat: point.lat,
      lng: point.lng,
      locale: lang == 'fr' ? 'fr' : 'en',
    );
    final city = LiveMapAggregator.cityFromAddress(
      ref.watch(reverseGeocodeProvider(geoKey)).value,
    );

    final subtitle = _subtitle(context, city: city, stale: stale, bucket: bucket);

    return ListTile(
      onTap: onTap,
      leading: Opacity(
        opacity: stale ? 0.5 : 1,
        child: AppAvatar(name: point.name, color: point.color),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              point.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (isSelf) ...[
            const SizedBox(width: AppSpacing.sp8),
            _YouBadge(),
          ],
        ],
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      trailing: isSelf || distanceMeters == null
          ? null
          : Text(
              _formatDistance(context, distanceMeters!),
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
    );
  }

  String _subtitle(
    BuildContext context, {
    required String? city,
    required bool stale,
    required FreshnessBucket bucket,
  }) {
    final l10n = context.l10n;
    final ago = switch (bucket) {
      FreshnessJustNow() => l10n.liveMap_lastUpdatedJustNow,
      FreshnessMinutesAgo(:final minutes) => l10n.liveMap_lastUpdatedMinutesAgo(
        minutes,
      ),
      FreshnessHoursAgo(:final hours) => l10n.liveMap_lastUpdatedHoursAgo(hours),
    };
    final freshness = stale ? l10n.liveMap_offlineLastSeen(ago) : ago;
    final place = city ?? l10n.liveMap_locatingCity;
    return '$place · $freshness';
  }

  String _formatDistance(BuildContext context, double meters) {
    final l10n = context.l10n;
    final localeName = Localizations.localeOf(context).toString();
    if (meters < 1000) {
      final rounded = (meters / 10).round() * 10;
      return l10n.liveMap_distanceMeters(rounded.toString());
    }
    final km = meters / 1000;
    final value = NumberFormat.decimalPatternDigits(
      locale: localeName,
      decimalDigits: 1,
    ).format(km);
    return l10n.liveMap_distanceKm(value);
  }
}

class _YouBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp8,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.r8),
      ),
      child: Text(
        context.l10n.liveMap_you,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
