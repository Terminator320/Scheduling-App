import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/adaptive/adaptive_action_sheet.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/application/calendar_crew_filter_provider.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';

/// The admin calendar's "show one person's jobs" control.
///
/// Sits beside the day-route button in the header and wears the same 48px
/// chip. Painted primary while a filter is active, since the header is the
/// one thing still on screen once the grid collapses.
class CrewFilterButton extends ConsumerWidget {
  const CrewFilterButton({super.key});

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final roster = ref.read(assignableEmployeesProvider).asData?.value ?? [];
    final filter = ref.read(calendarCrewFilterProvider.notifier);
    // Chosen by INDEX: the "All crew" row selects null, which is also what a
    // dismissal returns.
    final chosen = await showAdaptiveActionSheet<int>(
      context,
      title: l10n.calendar_showJobsFor,
      actions: [
        AdaptiveSheetAction(value: 0, label: l10n.calendar_allCrew),
        for (var i = 0; i < roster.length; i++)
          AdaptiveSheetAction(value: i + 1, label: roster[i].displayName),
      ],
    );
    if (chosen == null) return;
    filter.selection = chosen == 0 ? null : roster[chosen - 1].id;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isActive = ref.watch(calendarCrewFilterProvider) != null;
    final label = context.l10n.calendar_crewFilter;
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Material(
              color: isActive ? scheme.primary : scheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.rIcon),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _pick(context, ref),
                highlightColor: theme.palette.blueTintPressed,
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: Icon(
                    Icons.person_search_rounded,
                    size: 19,
                    color: isActive
                        ? scheme.onPrimary
                        : scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Showing Marc · Clear" — drawn above the agenda header while the calendar
/// is filtered, so the narrowed schedule is never mistaken for a quiet day.
class CrewFilterBanner extends ConsumerWidget {
  const CrewFilterBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(calendarCrewFilterProvider);
    if (id == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final name = ref.watch(employeeNameMapProvider)[id] ?? id;
    final color = ref.watch(employeeColorMapProvider)[id];
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, AppSpacing.sp8, 18, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sp12,
          vertical: AppSpacing.sp4,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.r12),
        ),
        child: Row(
          children: [
            AppAvatar(name: name, color: color, size: AvatarSize.xs),
            const SizedBox(width: AppSpacing.sp8),
            Expanded(
              child: Text(
                context.l10n.calendar_showingCrewMember(name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: ref.read(calendarCrewFilterProvider.notifier).clear,
              child: Text(context.l10n.calendar_clearFilter),
            ),
          ],
        ),
      ),
    );
  }
}
