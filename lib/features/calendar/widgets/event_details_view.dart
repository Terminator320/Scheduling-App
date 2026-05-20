import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/application/event_details_controller.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/details_edit_body.dart';
import 'package:scheduling/features/calendar/widgets/details_view_body.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/shared/widgets/sheet_widgets.dart';

class EventDetailsView extends ConsumerStatefulWidget {
  const EventDetailsView({
    required this.appointment,
    super.key,
    this.showActions = true,
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
  late final TextEditingController _titleController;
  late final TextEditingController _dateController;
  late final TextEditingController _startTimeController;
  late final TextEditingController _endTimeController;
  late final TextEditingController _clientSearchController;
  late final TextEditingController _addressController;
  late final TextEditingController _notesController;
  late final TextEditingController _materialsController;

  late final DetailsEditControllers _editControllers;

  @override
  void initState() {
    super.initState();
    _initControllers();
    if (widget.initialEditing) {
      Future.microtask(() {
        if (!mounted) return;
        ref
            .read(eventDetailsControllerProvider(widget.appointment).notifier)
            .enterEditing();
      });
    }
  }

  void _initControllers() {
    final a = widget.appointment;
    _titleController = TextEditingController(text: a.title);
    _dateController = TextEditingController(
      text: DateUtilsHelper.formatDate(a.startTime),
    );
    _startTimeController = TextEditingController(
      text: DateUtilsHelper.formatTime(a.startTime),
    );
    _endTimeController = TextEditingController(
      text: DateUtilsHelper.formatTime(a.endTime),
    );
    _clientSearchController = TextEditingController(text: a.clientName);
    _addressController = TextEditingController(
      text: AddressParser.canonicalToDisplay(a.address),
    );
    _notesController = TextEditingController(text: a.notes);
    _materialsController = TextEditingController(text: a.materialsNeeded);
    _editControllers = DetailsEditControllers(
      title: _titleController,
      date: _dateController,
      startTime: _startTimeController,
      endTime: _endTimeController,
      clientSearch: _clientSearchController,
      address: _addressController,
      notes: _notesController,
      materials: _materialsController,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _dateController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    _clientSearchController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    _materialsController.dispose();
    super.dispose();
  }

  void _handleClose([Object? result]) {
    if (!mounted) return;
    widget.onClose?.call(result);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(eventDetailsControllerProvider(widget.appointment));
    final isCancelled = widget.appointment.status.toLowerCase() == 'cancelled';
    final showEdit = state.isEditing && !isCancelled && widget.showActions;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.only(
        left: AppSpacing.sp16,
        right: AppSpacing.sp16,
        top: AppSpacing.sp12,
        bottom: bottomInset + AppSpacing.sp24,
      ),
      children: [
        if (widget.showHandle) const SheetHandle(),
        if (widget.showHandle) const SizedBox(height: AppSpacing.sp8),
        if (showEdit)
          DetailsEditBody(
            appointment: widget.appointment,
            controllers: _editControllers,
            onSaved: _handleClose,
            onClose: _handleClose,
          )
        else
          DetailsViewBody(
            appointment: widget.appointment,
            showActions: widget.showActions,
            onClose: _handleClose,
          ),
      ],
    );
  }
}
