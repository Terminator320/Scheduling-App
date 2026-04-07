import 'package:flutter/material.dart';
import '../services/appointment_service.dart';

import 'package:scheduling/models/appointment_record.dart';
import '../utils/date_utils_helper.dart';
import '../utils/sheet_helpers.dart';
import 'add_appointment_sheet.dart';
import 'details_edit_sheet.dart';

class EventList extends StatelessWidget {
  final ValueNotifier<List<AppointmentRecord>> events;

  const EventList({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ValueListenableBuilder<List<AppointmentRecord>>(
        valueListenable: events,
        builder: (context, value, _) {
          value.sort((a, b) => a.startTime.compareTo(b.startTime));

          if (value.isEmpty) {
            return Center(child: Text("No events"));
          }

          return ListView.builder(
            itemCount: value.length,
            itemBuilder: (context, index) {
              final e = value[index];

              return Card(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ListTile(
                  leading: Icon(Icons.event),
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () async {
                      await AppointmentService().deleteAppointment(e.id!);
                    },
                  ),
                  onTap: () {
                    showEventDetails(context, e);
                  },

                  title: Text(e.title),

                  subtitle: Text(
                      "${DateUtilsHelper.formatTime(e.startTime)} - ${DateUtilsHelper.formatTime(e.endTime)}"
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}


