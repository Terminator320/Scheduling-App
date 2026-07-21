import 'package:flutter/material.dart';

import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/views/event_details_view.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

class EventDetailsSheet extends StatelessWidget {
  const EventDetailsSheet({
    required this.appointment,
    super.key,
    // Defaults CLOSED — see AppointmentTile.showActions.
    this.showActions = false,
    this.initialEditing = false,
  });

  final AppointmentRecord appointment;
  final bool showActions;
  final bool initialEditing;

  @override
  Widget build(BuildContext context) {
    return DraggableSheetFrame(
      builder: (sheetContext, scrollController) {
        return EventDetailsView(
          appointment: appointment,
          showActions: showActions,
          initialEditing: initialEditing,
          scrollController: scrollController,
          showHandle: true,
          onClose: (result) {
            if (Navigator.canPop(sheetContext)) {
              Navigator.pop(sheetContext, result);
            }
          },
        );
      },
    );
  }
}
