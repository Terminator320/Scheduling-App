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

Future<void> showEventDetails(
  BuildContext context,
  AppointmentRecord a, {
  bool showActions = true,
}) {
  return showAppBottomSheet<void>(
    context,
    shape: _kSheetShape,
    builder: (_) => EventDetailsSheet(appointment: a, showActions: showActions),
  );
}
