import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/domain/appointment_crew.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/calendar/widgets/cards/appointment_card.dart';
import 'package:scheduling/features/clients/application/appointment_history_providers.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/skeleton_loader.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';

/// Job history block on the admin-only detail view. Shows appointments most-recent
/// first, and each one is tappable into the detail sheet.
// "Book again" is deferred for now — it would need invasive changes to the create flow.
class ClientJobHistorySection extends ConsumerWidget {
  const ClientJobHistorySection({required this.clientId, super.key});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(clientJobHistoryProvider(clientId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(context.l10n.clients_jobHistory),
        const SizedBox(height: AppSpacing.sp8),
        history.when(
          data: (jobs) => jobs.isEmpty
              ? _EmptyLine(text: context.l10n.clients_noPastJobs)
              : _JobList(
                  jobs: jobs,
                  colorMap: ref.watch(employeeColorMapProvider),
                ),
          loading: () => const Column(
            children: [
              SkeletonAppointmentRow(),
              SizedBox(height: AppSpacing.sp8),
              SkeletonAppointmentRow(),
            ],
          ),
          // Compose the cause+tag notice without logging — this provider read isn't the
          // UI-layer catch site, so logging happens elsewhere.
          error: (e, _) => _EmptyLine(
            text: composeErrorNotice(
              context,
              intro: context.l10n.error_introLoadHistory,
              error: e,
            ),
          ),
        ),
      ],
    );
  }
}

class _JobList extends StatelessWidget {
  const _JobList({required this.jobs, required this.colorMap});

  final List<AppointmentRecord> jobs;
  final Map<String, Color> colorMap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final job in jobs) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sp4),
            child: Text(
              DateUtilsHelper.formatDate(job.startTime),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          AppointmentCard(
            appointment: job,
            // No live name map on this surface — crewFor falls back to the
            // record's denormalized employeeNames, which is what it showed
            // before.
            crew: crewFor(job, colorMap: colorMap),
            dimWhenCancelled: true,
            onTap: () => showEventDetails(context, job, showActions: false),
          ),
          const SizedBox(height: AppSpacing.sp8),
        ],
      ],
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
