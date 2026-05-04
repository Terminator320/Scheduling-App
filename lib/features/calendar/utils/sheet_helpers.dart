import 'package:flutter/material.dart';
import '../models/appointment_record.dart';
import '../widgets/add_appointment_sheet.dart';
import '../widgets/details_edit_sheet.dart';

Future<AppointmentRecord?> showAddEventPopup(
  BuildContext context, {
  DateTime? initialDate,
}) {
  return showModalBottomSheet<AppointmentRecord>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => EventDetailsSheet(appointment: a, showActions: showActions),
  );
}
