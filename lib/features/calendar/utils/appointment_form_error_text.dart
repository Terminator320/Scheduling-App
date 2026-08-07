import 'package:flutter/widgets.dart';

import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/policies/appointment_form_validator.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Localized message for an [AppointmentFormError] (shared by add and edit flows).
String appointmentFormErrorText(
  BuildContext context,
  AppointmentFormError key,
) {
  return switch (key) {
    AppointmentFormError.titleRequired =>
      context.l10n.validation_titleIsRequired,
    AppointmentFormError.dateRequired =>
      context.l10n.validation_pleaseSelectADate,
    AppointmentFormError.startTimeRequired =>
      context.l10n.validation_pleaseSelectAStartTime,
    AppointmentFormError.endTimeRequired =>
      context.l10n.validation_pleaseSelectAnEndTime,
    AppointmentFormError.endDateBeforeStart =>
      context.l10n.validation_endDateBeforeStart,
    AppointmentFormError.spanTooLong => context.l10n.validation_spanTooLong(
      maxAppointmentSpanDays,
    ),
    AppointmentFormError.clientRequired =>
      context.l10n.validation_pleaseSelectAClient,
    AppointmentFormError.employeesRequired =>
      context.l10n.validation_pleaseSelectAtLeastOneEmployee,
  };
}
