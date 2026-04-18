import 'package:flutter/material.dart';
import '../../models/employee_record.dart';

import 'package:scheduling/models/appointment_record.dart';
import '../../utils/calendar_utils/appointment_colors.dart';
import '../../utils/date_utils_helper.dart';
import '../../utils/calendar_utils/sheet_helpers.dart';

class EventList extends StatelessWidget {
  final ValueNotifier<List<AppointmentRecord>> events;
  final List<EmployeeRecord> employees;




  const EventList({super.key, required this.events,required this.employees});




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
              final empColor = colorForAppointment(e, employees);

              return Card(
              margin: EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              color: Theme.of(context).cardColor,  // neutral card, no tint
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => showEventDetails(context, e),
                child: Row(
                  children: [
                    // Colored left bar
                    Container(
                      width: 5,
                      height: 70,
                      decoration: BoxDecoration(
                        color: empColor ?? Colors.grey.shade300,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(10),
                          bottomLeft: Radius.circular(10),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    // Color dot
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: empColor ?? Colors.grey.shade400,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              "${DateUtilsHelper.formatTime(e.startTime)} - ${DateUtilsHelper.formatTime(e.endTime)}",
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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


