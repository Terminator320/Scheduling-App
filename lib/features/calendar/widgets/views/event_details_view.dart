import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/application/event_details_controller.dart';
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/sections/appointment_form_fields.dart';
import 'package:scheduling/features/calendar/widgets/views/details_edit_body.dart';
import 'package:scheduling/features/calendar/widgets/views/details_view_body.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

class EventDetailsView extends ConsumerStatefulWidget {
  const EventDetailsView({
    required this.appointment,
    super.key,
    // Defaults CLOSED — a default of true once exposed admin-only Edit/Cancel/
    // Delete affordances to employees.
    this.showActions = false,
    this.initialEditing = false,
    this.scrollController,
    this.showHandle = false,
    this.onClose,
  });

  final AppointmentRecord appointment;
  final bool showActions;
  final bool initialEditing;
  final ScrollController? scrollController;
  final bool showHandle;
  final void Function(Object? result)? onClose;

  @override
  ConsumerState<EventDetailsView> createState() => _EventDetailsViewState();
}

class _EventDetailsViewState extends ConsumerState<EventDetailsView> {
  // Created lazily on first edit — view-only opens never need to allocate
  // these.
  AppointmentFormControllers? _editControllers;

  @override
  void initState() {
    super.initState();
    if (widget.initialEditing) {
      Future.microtask(() {
        if (!mounted) return;
        ref
            .read(
              eventDetailsControllerProvider(
                EventDetailsKey(widget.appointment),
              ).notifier,
            )
            .enterEditing();
      });
    }
  }

  AppointmentFormControllers _ensureControllers() {
    final a = widget.appointment;
    return _editControllers ??= AppointmentFormControllers(
      title: TextEditingController(text: a.title),
      date: TextEditingController(
        text: DateUtilsHelper.formatDate(a.startTime),
      ),
      endDate: TextEditingController(
        text: DateUtilsHelper.formatDate(lastWorkDayOf(a)),
      ),
      startTime: TextEditingController(
        text: DateUtilsHelper.formatTime(a.startTime),
      ),
      endTime: TextEditingController(
        text: DateUtilsHelper.formatTime(a.endTime),
      ),
      clientSearch: TextEditingController(text: a.clientName),
      address: TextEditingController(
        text: AddressParser.canonicalToDisplay(a.address),
      ),
      notes: TextEditingController(text: a.notes),
      materials: TextEditingController(text: a.materialsNeeded),
    );
  }

  @override
  void dispose() {
    _editControllers?.dispose();
    super.dispose();
  }

  void _handleClose([Object? result]) {
    if (!mounted) return;
    widget.onClose?.call(result);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      eventDetailsControllerProvider(EventDetailsKey(widget.appointment)),
    );
    // Cancelled visits stay editable — `showActions` is the only thing that
    // gates the edit form.
    final showEdit = state.isEditing && widget.showActions;
    // The edit form owns its own sheet chrome (FormSheetFrame), so it replaces
    // the read view's scroll shell rather than nesting inside it.
    if (showEdit) {
      return DetailsEditBody(
        appointment: widget.appointment,
        controllers: _ensureControllers(),
        onSaved: _handleClose,
        onClose: _handleClose,
      );
    }
    return DetailSheetListView(
      scrollController: widget.scrollController,
      showHandle: widget.showHandle,
      handleGap: AppSpacing.sp8,
      children: [
        DetailsViewBody(
          appointment: widget.appointment,
          showActions: widget.showActions,
          onClose: _handleClose,
          // Closes with the draft; `showEventDetails` opens the add sheet.
          onBookAgain: _handleClose,
        ),
      ],
    );
  }
}
