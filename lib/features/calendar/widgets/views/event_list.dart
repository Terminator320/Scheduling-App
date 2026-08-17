import 'package:flutter/material.dart';
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/views/agenda_sliver_list.dart';

/// The agenda as a standalone scrolling pane, for hosts that are not the
/// portrait calendar's single viewport — the split layout's right pane and the
/// master-detail surfaces. The content itself lives in [AgendaSliverList], so
/// both hosts build the same rows.
class EventList extends StatelessWidget {
  const EventList({
    required this.events,
    required this.nameMap,
    required this.colorMap,
    super.key,
    this.isAdmin = true,
    this.isLoading = false,
    this.onAppointmentTap,
    this.selectedAppointmentId,
    this.bottomClearance = 0,
  });

  /// One entry per day the job runs — see [AgendaSliverList.events].
  final List<AppointmentDaySlice> events;
  final Map<String, String> nameMap;
  final Map<String, Color> colorMap;
  final bool isAdmin;
  final bool isLoading;
  final void Function(AppointmentRecord appointment)? onAppointmentTap;
  final String? selectedAppointmentId;

  /// See [AgendaSliverList.bottomClearance] — forwarded so a host that floats
  /// a FAB over this pane can clear the last card.
  final double bottomClearance;

  @override
  Widget build(BuildContext context) => Expanded(
    child: CustomScrollView(
      slivers: [
        AgendaSliverList(
          events: events,
          nameMap: nameMap,
          colorMap: colorMap,
          isAdmin: isAdmin,
          isLoading: isLoading,
          onAppointmentTap: onAppointmentTap,
          selectedAppointmentId: selectedAppointmentId,
          bottomClearance: bottomClearance,
        ),
      ],
    ),
  );
}
