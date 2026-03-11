import 'employee_record.dart';
import 'client_record.dart';

class AppointmentRecord {
  AppointmentRecord({
    required this.title,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.clientName,
    required this.clientPhone,
    required this.address,
    required this.jobType,
    required this.notes,
    required this.materialsNeeded,
    required this.pictures,
  });

  final String title;
  final String date;
  final String startTime;
  final String endTime;
  final String clientName;
  final String clientPhone;
  final String address;
  final String jobType;
  final String notes;
  final String materialsNeeded;
  final String pictures;
}

final List<AppointmentRecord> kAppointments = [
  AppointmentRecord(
    title: 'Job title',
    date: 'May 20, 2026',
    startTime: '9:00 AM',
    endTime: '10:00 AM',
    clientName: 'Client name',
    clientPhone: '(514) 555-0112',
    address: '123 Main Street',
    jobType: 'Item 1',
    notes: 'General appointment notes',
    materialsNeeded: 'Standard tools',
    pictures: 'No pictures added',
  ),
  AppointmentRecord(
    title: 'Job title',
    date: 'May 20, 2026',
    startTime: '11:00 AM',
    endTime: '12:00 PM',
    clientName: 'Client name',
    clientPhone: '(514) 555-0135',
    address: '456 Park Avenue',
    jobType: 'Item 2',
    notes: 'Customer requested confirmation call',
    materialsNeeded: 'Replacement parts',
    pictures: '2 pictures attached',
  ),
  AppointmentRecord(
    title: 'Job title',
    date: 'May 21, 2026',
    startTime: '1:30 PM',
    endTime: '2:30 PM',
    clientName: 'Client name',
    clientPhone: '(514) 555-0174',
    address: '789 Elm Street',
    jobType: 'Item 3',
    notes: 'Access through side entrance',
    materialsNeeded: 'Inspection checklist',
    pictures: 'No pictures added',
  ),
  AppointmentRecord(
    title: 'Job title',
    date: 'May 21, 2026',
    startTime: '3:00 PM',
    endTime: '4:00 PM',
    clientName: 'Client name',
    clientPhone: '(514) 555-0180',
    address: '22 Cedar Road',
    jobType: 'Item 4',
    notes: 'Call on arrival',
    materialsNeeded: 'Cleaning supplies',
    pictures: '1 picture attached',
  ),
  AppointmentRecord(
    title: 'Job title',
    date: 'May 22, 2026',
    startTime: '8:30 AM',
    endTime: '9:30 AM',
    clientName: 'Client name',
    clientPhone: '(514) 555-0193',
    address: '98 River Lane',
    jobType: 'Item 5',
    notes: 'Bring extra materials',
    materialsNeeded: 'Extra fittings',
    pictures: '3 pictures attached',
  ),
];
