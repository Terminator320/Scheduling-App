import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/launchers/phone_call_launcher.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/month_grid.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/clients/email_compose_launcher.dart';
import 'package:scheduling/features/employees/application/employee_schedule_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/domain/policies/work_schedule_policy.dart';
import 'package:scheduling/features/employees/widgets/cards/employee_profile_card.dart';
import 'package:scheduling/features/employees/widgets/sections/employee_today_section.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/cards/key_value_panel.dart';
import 'package:scheduling/shared/widgets/primitives/mono_section_label.dart';
import 'package:scheduling/shared/widgets/primitives/quick_action_button.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

class EmployeeDetailsView extends ConsumerWidget {
  const EmployeeDetailsView({
    required this.employee,
    required this.isCurrentUserAdmin,
    required this.onEdit,
    super.key,
    this.scrollController,
    this.showHandle = false,
    this.bottomPadding = 24,
  });

  final EmployeeRecord employee;
  final bool isCurrentUserAdmin;

  /// Disable/enable moved into the edit sheet and delete was withdrawn, so
  /// Edit is the only action this surface can raise.
  final VoidCallback onEdit;
  final ScrollController? scrollController;
  final bool showHandle;
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final materialL10n = MaterialLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final weekStart = weekStartForLocale(locale);

    // Handlers built here (where `ref` lives) so the widgets stay
    // presentational. Both delegate to launchExternalUri.
    final onCall = employee.phone.isEmpty
        ? null
        : () => launchPhoneCall(context, ref, employee.phone);
    final onCallEmergency = employee.emergencyPhone.isEmpty
        ? null
        : () => launchPhoneCall(context, ref, employee.emergencyPhone);
    final onEmail = employee.email.isEmpty
        ? null
        : () => EmailComposeLauncher.showEmailChoices(
            context,
            ref,
            email: employee.email,
          );

    final hoursValue = employee.workingDays.contains(true)
        ? '${materialL10n.formatTimeOfDay(minutesToTimeOfDay(employee.workStartMinutes))}'
              ' – '
              '${materialL10n.formatTimeOfDay(minutesToTimeOfDay(employee.workEndMinutes))}'
        : l10n.employees_noWorkingDays;

    final infoRows = <KeyValueRow>[
      if (employee.phone.isNotEmpty)
        KeyValueRow(
          label: l10n.employees_phoneKey,
          value: employee.phone,
          onTap: onCall,
          emphasize: true,
        ),
      if (employee.email.isNotEmpty)
        KeyValueRow(
          label: l10n.employees_emailKey,
          value: employee.email,
          onTap: onEmail,
          emphasize: true,
        ),
      KeyValueRow(label: l10n.employees_hoursKey, value: hoursValue),
      // Approved design: days are a phrase here, not a seven-cell strip. The
      // grid lives only in the edit sheet, where tapping a day is the point.
      KeyValueRow(
        label: l10n.employees_daysKey,
        value: formatWorkingDays(
          l10n,
          employee.workingDays,
          weekStart: weekStart,
          labels: weekdayAbbreviationsForLocale(locale),
        ),
      ),
      if (employee.maxJobsPerDay > 0)
        KeyValueRow(
          label: l10n.employees_maxPerDayKey,
          value: l10n.employees_jobsPerDay(employee.maxJobsPerDay),
        ),
      // NO `ON CALL` row — the profile card carries it as a chip, and a row
      // here would state the same boolean twice on one screen.
      KeyValueRow(
        label: l10n.employees_accessKey,
        value: employee.isAdmin
            ? l10n.common_admin
            : l10n.common_employeeRoleValue,
      ),
    ];

    // Its own panel, not two more rows in the block above: who to call if
    // something goes wrong on site is a different question from someone's
    // hours and access level, and it is the one you scan for in a hurry.
    final emergencyRows = <KeyValueRow>[
      if (employee.emergencyContact.isNotEmpty)
        KeyValueRow(
          label: l10n.employees_emergencyKey,
          value: employee.emergencyContact,
        ),
      if (employee.emergencyPhone.isNotEmpty)
        KeyValueRow(
          label: l10n.employees_emergencyPhoneKey,
          value: employee.emergencyPhone,
          onTap: onCallEmergency,
          emphasize: true,
        ),
    ];

    return DetailSheetListView(
      scrollController: scrollController,
      showHandle: showHandle,
      bottomPadding: bottomPadding,
      children: [
        EmployeeProfileCard(
          employee: employee,
          onEdit: isCurrentUserAdmin ? onEdit : null,
        ),
        if (onCall != null || onEmail != null) ...[
          const SizedBox(height: AppSpacing.sp16),
          QuickActionsRow(
            buttons: [
              if (onCall != null)
                QuickActionButton(
                  icon: Icons.phone_outlined,
                  label: l10n.clients_call,
                  onTap: onCall,
                ),
              if (onEmail != null)
                QuickActionButton(
                  icon: Icons.mail_outline,
                  label: l10n.common_email,
                  onTap: onEmail,
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.sp24),
        KeyValuePanel(rows: infoRows),
        if (emergencyRows.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sp24),
          MonoSectionLabel(l10n.employees_sectionEmergency),
          const SizedBox(height: AppSpacing.sp8),
          KeyValuePanel(rows: emergencyRows),
        ],
        const SizedBox(height: AppSpacing.sp24),
        EmployeeTodaySection(
          employeeId: employee.id,
          onJobTap: (appointmentId) =>
              _openJob(context, ref, appointmentId, employee.id),
        ),
      ],
    );
  }

  /// Opens the appointment sheet for the tapped card. `showActions` carries
  /// the caller's resolved role — never `true`.
  void _openJob(
    BuildContext context,
    WidgetRef ref,
    String appointmentId,
    String employeeId,
  ) {
    final jobs = ref.read(employeeTodayJobsProvider(employeeId));
    for (final job in jobs) {
      if (job.id == appointmentId) {
        showEventDetails(context, job, showActions: isCurrentUserAdmin);
        return;
      }
    }
  }
}
