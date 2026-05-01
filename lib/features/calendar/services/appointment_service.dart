import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:scheduling/features/calendar/models/appointment_image.dart';
import 'package:scheduling/features/calendar/models/appointment_record.dart';

class AppointmentDateRange {
  final DateTime start;
  final DateTime end;

  const AppointmentDateRange({required this.start, required this.end});

  factory AppointmentDateRange.visibleMonth(DateTime date) {
    final firstDay = DateTime(date.year, date.month);
    final lastDay = DateTime(date.year, date.month + 1, 0);
    return AppointmentDateRange(
      start: firstDay.subtract(const Duration(days: 7)),
      end: lastDay.add(const Duration(days: 8)),
    );
  }
}

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

  Future<void> updateAppointmentPictures(
    String appointmentId,
    List<AppointmentImage> pictures,
  ) async {
    await appointments.doc(appointmentId).update({
      'pictures': pictures.map((p) => p.toMap()).toList(),
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
