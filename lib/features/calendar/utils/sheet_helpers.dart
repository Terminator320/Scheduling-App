import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/sheets/add_appointment_sheet.dart';
import 'package:scheduling/features/calendar/widgets/sheets/details_edit_sheet.dart';

Future<AppointmentRecord?> showAddEventPopup(
  BuildContext context, {
  DateTime? initialDate,
}) {
  return showModalBottomSheet<AppointmentRecord>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    sheetAnimationStyle: AppMotion.sheetStyle,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.r20)),
    ),
    builder: (_) => AddEventSheet(initialDate: initialDate),
  );
}

Future<void> showEventDetails(
  BuildContext context,
  AppointmentRecord a, {
  bool showActions = true,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    sheetAnimationStyle: AppMotion.sheetStyle,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.r20)),
    ),
    builder: (_) => EventDetailsSheet(appointment: a, showActions: showActions),
  );
}
