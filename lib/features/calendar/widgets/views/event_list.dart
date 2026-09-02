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
    required List<AppointmentDaySlice> this.events,
    required DateTime this.day,
    required Map<String, String> this.nameMap,
    required Map<String, Color> this.colorMap,
    super.key,
    this.isAdmin = true,
    this.isLoading = false,
    this.onAppointmentTap,
    this.selectedAppointmentId,
    this.bottomClearance = 0,
  }) : slivers = null;

  /// The pane around slivers the host already built — the calendar's week
  /// agenda, which is not one day's rows.
  const EventList.slivers({required List<Widget> this.slivers, super.key})
    : events = null,
      day = null,
      nameMap = null,
      colorMap = null,
      isAdmin = true,
      isLoading = false,
      onAppointmentTap = null,
      selectedAppointmentId = null,
      bottomClearance = 0;

  /// One entry per day the job runs — see [AgendaSliverList.events].
  final List<AppointmentDaySlice>? events;
  final Map<String, String>? nameMap;
  final Map<String, Color>? colorMap;
  final bool isAdmin;
  final bool isLoading;
  final void Function(AppointmentRecord appointment)? onAppointmentTap;
  final String? selectedAppointmentId;

  /// See [AgendaSliverList.bottomClearance] — forwarded so a host that floats
  /// a FAB over this pane can clear the last card.
  final double bottomClearance;

  /// See [AgendaSliverList.day] — forwarded so the split layout shows the same
  /// holiday row the portrait calendar does.
  final DateTime? day;

  /// Host-built slivers, replacing the day agenda. See [EventList.slivers].
  final List<Widget>? slivers;

  @override
  Widget build(BuildContext context) => Expanded(
    child: CustomScrollView(
      slivers:
          slivers ??
          [
            AgendaSliverList(
              events: events!,
              nameMap: nameMap!,
              colorMap: colorMap!,
              isAdmin: isAdmin,
              isLoading: isLoading,
              onAppointmentTap: onAppointmentTap,
              selectedAppointmentId: selectedAppointmentId,
              bottomClearance: bottomClearance,
              day: day!,
            ),
          ],
    ),
  );
}
