import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/application/assignee_availability_provider.dart';
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/assignee_availability.dart';
import 'package:scheduling/features/calendar/domain/policies/appointment_form_validator.dart';

/// The availability the assignee picker renders, for a form's CURRENT schedule
/// fields.
///
/// Both save flows call this from `build`, so the answer is date-DERIVED and
/// re-resolves as the date, the end date, the times and the all-day flag
/// change — which is the whole point: a picker showing yesterday's answer is
/// worse than one showing none.
///
/// **An undetermined span answers nothing.** A date with no times could still
/// become an 8 pm job, so dimming whoever is booked that morning would be a
/// guess presented as a fact; the picker offers everyone until the span is
/// real. That covers the "no date picked yet" state too.
///
/// **A PERSONAL block dims nobody, and that is not a nicety.** Dimming means
/// untappable, and the person a day off is FOR is exactly the person most
/// likely to have jobs that day — so dimming them makes their absence
/// unbookable, and makes the clash alert that exists to clean up after it
/// unreachable. A clash is not a reason to refuse time off; it is the thing
/// the alert reports afterwards. Same carve-out, same reason, as both
/// controllers skipping the Save-time busy prompt when `isPersonal`.
AssigneeAvailability watchAssigneeAvailability(
  WidgetRef ref, {
  required DateTime? date,
  required DateTime? endDate,
  required bool isAllDay,
  required bool isPersonal,
  required TimeOfDay? startTime,
  required TimeOfDay? endTime,
  required Set<String> alreadyAssignedIds,
  String? excludeAppointmentId,
}) {
  if (date == null || isPersonal) return AssigneeAvailability.none;
  if (!isAllDay && (startTime == null || endTime == null)) {
    return AssigneeAvailability.none;
  }

  final (:start, :end) = appointmentSpan(
    date: date,
    endDate: endDate ?? date,
    isAllDay: isAllDay,
    startTime: startTime,
    endTime: endTime,
  );

  final clashes = ref
      .watch(
        assigneeAvailabilityProvider((
          start: start,
          end: end,
          excludeAppointmentId: excludeAppointmentId,
        )),
      )
      // A pending or failed lookup dims nobody. The provider logs its own
      // failure; rendering "everyone is free" would be the lie, so the picker
      // simply says nothing until it settles.
      .value;
  if (clashes == null || clashes.isEmpty) return AssigneeAvailability.none;

  return AssigneeAvailability(
    clashes: clashes,
    alreadyAssignedIds: alreadyAssignedIds,
    whenLabel: _whenLabel(start: start, end: end, isAllDay: isAllDay),
  );
}

/// `26 – 28 Aug` for an absence-shaped span, `26 Aug, 8:00 AM – 12:00 PM`
/// otherwise — the fragment the nobody-free sentence names.
String _whenLabel({
  required DateTime start,
  required DateTime end,
  required bool isAllDay,
}) {
  final days = DateUtilsHelper.formatDayRange(
    start,
    lastWorkDayOfWindow(start, end),
  );
  if (isAllDay) return days;
  return '$days, ${DateUtilsHelper.formatTime(start)} – '
      '${DateUtilsHelper.formatTime(end)}';
}
