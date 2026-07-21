import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/sheets/add_appointment_sheet.dart';
import 'package:scheduling/features/calendar/widgets/sheets/details_edit_sheet.dart';
import 'package:scheduling/shared/widgets/sheets/app_bottom_sheet.dart';

const _kSheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.r20)),
);

Future<AppointmentRecord?> showAddEventPopup(
  BuildContext context, {
  DateTime? initialDate,
}) {
  return showAppBottomSheet<AppointmentRecord>(
    context,
    shape: _kSheetShape,
    builder: (_) => AddEventSheet(initialDate: initialDate),
  );
}

/// Opens the appointment detail sheet.
///
/// [showActions] is REQUIRED, not defaulted: it gates the admin-only Edit /
/// Cancel / Delete affordances, and a call site that silently defaulted to
/// `true` showed employees three controls the rules reject with
/// `permission-denied`. Pass the caller's resolved role.
Future<void> showEventDetails(
  BuildContext context,
  AppointmentRecord a, {
  required bool showActions,
}) {
  return showAppBottomSheet<void>(
    context,
    shape: _kSheetShape,
    builder: (_) => EventDetailsSheet(appointment: a, showActions: showActions),
  );
}
