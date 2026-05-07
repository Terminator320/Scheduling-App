import 'package:flutter/widgets.dart';

import 'package:scheduling/features/calendar/domain/policies/appointment_form_validator.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Localized message for an [AppointmentFormError]. Shared by the
/// add-appointment sheet and the edit-details body, which render the same
/// validation strings.
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
    AppointmentFormError.endTimeMustBeAfterStart =>
      context.l10n.calendar_mustBeAfterStartTime,
    AppointmentFormError.clientRequired =>
      context.l10n.validation_pleaseSelectAClient,
    AppointmentFormError.employeesRequired =>
      context.l10n.validation_pleaseSelectAtLeastOneEmployee,
  };
}
