import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/appointment_record.dart';

class AppointmentService {
  final CollectionReference<Map<String, dynamic>> appointments =
      FirebaseFirestore.instance.collection('appointments');

  Future<void> addAppointment(AppointmentRecord appointment) async {
    await appointments.add({
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

  Stream<List<AppointmentRecord>> employeeAppointmentsStream(
      String employeeId) {
    return appointments
        .where('employeeIds', arrayContains: employeeId)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => AppointmentRecord.fromMap(doc.id, doc.data()))
        .toList());
  }
}
