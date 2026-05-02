import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:scheduling/features/calendar/models/appointment_record.dart';

import '../../employees/models/employee_record.dart';

class AppointmentService {
  final CollectionReference<Map<String, dynamic>> appointments =
      FirebaseFirestore.instance.collection('appointments');

  DocumentReference<Map<String, dynamic>> newDocRef() => appointments.doc();

  Future<void> addAppointment(AppointmentRecord appointment) async {
    final ref = appointment.id != null
        ? appointments.doc(appointment.id)
        : appointments.doc();
    await ref.set({
      ...appointment.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<AppointmentRecord>> getAllAppointments() {
    return appointments.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return AppointmentRecord.fromMap(doc.id, doc.data());
      }).toList();
    });
  }

  Stream<List<AppointmentRecord>> getAppointmentStatus(String status) {
    return appointments
        .where('status', isEqualTo: status)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AppointmentRecord.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<AppointmentRecord?> getAppointmentById(String appointmentId) async {
    final doc = await appointments.doc(appointmentId).get();

    if (!doc.exists) {
      return null;
    }

    return AppointmentRecord.fromMap(doc.id, doc.data()!);
  }

  Future<void> updateAppointment(AppointmentRecord appointment) async {
    if (appointment.id == null) return;
    await appointments.doc(appointment.id).update({
      ...appointment.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateAppointmentStatus({
    required String appointmentId,
    required String status,
  }) async {
    await appointments.doc(appointmentId).update({
      'status': status.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteAppointment(String appointmentId) async {
    await FirebaseFirestore.instance
        .collection('appointments')
        .doc(appointmentId)
        .delete();
  }

  Future<List<EmployeeRecord>> checkAvailableEmployee({
    required List<EmployeeRecord> employeeId,
    required DateTime start,
    required DateTime end,
  }) async {
    List<EmployeeRecord> busyEmployees = [];


    for (final employee in employeeId) {
      final snapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('employeeIds', arrayContains: employee.id)
          .where('startTime', isLessThan: Timestamp.fromDate(end))
          .where('endTime', isGreaterThan: Timestamp.fromDate(start))
          .get();

      if (snapshot.docs.isNotEmpty) {
        busyEmployees.add(employee);
      }
    }

    return busyEmployees;
  }

  Stream<List<AppointmentRecord>> employeeAppointmentsStream(
    String employeeId,
  ) {
    return appointments
        .where('employeeIds', arrayContains: employeeId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AppointmentRecord.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }
}
