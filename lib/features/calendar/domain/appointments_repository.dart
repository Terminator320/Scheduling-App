import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

abstract class AppointmentsRepository {
  String newDocId();

  Future<AppointmentRecord?> getAppointmentById(String id);

  Future<void> addAppointment(AppointmentRecord appointment);

  Future<void> updateAppointment(AppointmentRecord appointment);

  Future<void> updateAppointmentPictures(
    String id,
    List<AppointmentImage> pictures,
  );

  Future<void> updateAppointmentStatus({
    required String id,
    required String status,
  });

  Future<void> deleteAppointment(String id);

  Stream<List<AppointmentRecord>> watchAll();

  Stream<List<AppointmentRecord>> watchInRange(AppointmentDateRange range);

  Stream<List<AppointmentRecord>> watchHistory();

  Stream<List<AppointmentRecord>> watchForEmployeeInRange(
    String employeeId,
    AppointmentDateRange range,
  );

  Future<List<EmployeeRecord>> findBusyEmployees({
    required List<EmployeeRecord> candidates,
    required DateTime start,
    required DateTime end,
  });
}
