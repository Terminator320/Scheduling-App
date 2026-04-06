import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/appointment_record.dart';

class AppointmentService {
  final CollectionReference<Map<String, dynamic>> _appointments =
      FirebaseFirestore.instance.collection('appointments');

  Future<void> addAppointment(AppointmentRecord appointment) async {
    await _appointments.add({
      ...appointment.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<AppointmentRecord>> appointmentsStream() {
    return _appointments
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AppointmentRecord.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<AppointmentRecord?> getAppointmentById(String appointmentId) async {
    final doc = await _appointments.doc(appointmentId).get();

    if (!doc.exists) {
      return null;
    }

    return AppointmentRecord.fromMap(doc.id, doc.data()!);
  }


  Future<void> updateAppointment(AppointmentRecord appointment) async {
    if (appointment.id == null) return;
    await _appointments.doc(appointment.id).update({
      ...appointment.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateAppointmentStatus({
    required String appointmentId,
    required String status,
  }) async {
    await _appointments.doc(appointmentId).update({
      'status': status.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteAppointment(String appointmentId) async {
    await _appointments.doc(appointmentId).delete();
  }

  Stream<List<AppointmentRecord>> employeeAppointmentsStream(
      String employeeId) {
    return _appointments
        .where('employeeIds', arrayContains: employeeId)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => AppointmentRecord.fromMap(doc.id, doc.data()))
        .toList());
  }
}
