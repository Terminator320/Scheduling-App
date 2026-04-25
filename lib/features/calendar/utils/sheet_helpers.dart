import 'package:flutter/material.dart';
import 'package:scheduling/features/calendar/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/add_appointment_sheet.dart';
import 'package:scheduling/features/calendar/widgets/details_edit_sheet.dart';


Future<AppointmentRecord?> showAddEventPopup(BuildContext context) {
  return showModalBottomSheet<AppointmentRecord>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => AddEventSheet(),
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
    builder: (_) => EventDetailsSheet(
      appointment: a,
      showActions: showActions,
    ),
  );
}