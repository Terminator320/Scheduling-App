import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/features/calendar/application/event_details_controller.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/views/event_details_view.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

class EventDetailsSheet extends ConsumerWidget {
  const EventDetailsSheet({
    required this.appointment,
    super.key,
    // Defaults CLOSED — see EventDetailsView.showActions.
    this.showActions = false,
    this.initialEditing = false,
  });

  final AppointmentRecord appointment;
  final bool showActions;
  final bool initialEditing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEditing = ref.watch(
      eventDetailsControllerProvider(
        EventDetailsKey(appointment),
      ).select((s) => s.isEditing),
    );

    void close(Object? result) {
      if (Navigator.canPop(context)) Navigator.pop(context, result);
    }

    // The edit form brings its own FormSheetFrame, which IS a sheet — wrapping
    // it in DraggableSheetFrame would nest two draggable sheets.
    if (isEditing && showActions) {
      return EventDetailsView(
        appointment: appointment,
        showActions: showActions,
        initialEditing: initialEditing,
        onClose: close,
      );
    }

    return DraggableSheetFrame(
      builder: (sheetContext, scrollController) => EventDetailsView(
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
      ),
    );
  }
}
