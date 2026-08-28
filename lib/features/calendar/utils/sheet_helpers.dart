import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/sheets/add_appointment_sheet.dart';
import 'package:scheduling/features/calendar/widgets/sheets/details_edit_sheet.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/shared/widgets/sheets/app_bottom_sheet.dart';

const _kSheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.rSheet)),
);

Future<AppointmentRecord?> showAddEventPopup(
  BuildContext context, {
  DateTime? initialDate,
  ClientRecord? initialClient,
}) {
  return showAppBottomSheet<AppointmentRecord>(
    context,
    shape: _kSheetShape,
    builder: (_) =>
        AddEventSheet(initialDate: initialDate, initialClient: initialClient),
  );
}

/// Opens the appointment detail sheet with explicit action visibility.
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
