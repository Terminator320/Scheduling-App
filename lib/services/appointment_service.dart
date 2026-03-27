import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/appointment_record.dart';

class AppointmentService {
  static final CollectionReference<Map<String, dynamic>> _appointments =
  FirebaseFirestore.instance.collection('appointments');

  static Future<void> addAppointment({
    required String title,
    required String date,
    required String startTime,
    required String endTime,
    required String clientId,
    required String clientName,
    required String clientPhone,
    required String employeeId,
    required String employeeName,
    required String address,
    required String notes,
    required String materialsNeeded,
    required String pictures,
  }) async {
    await _appointments.add({
      'title': title.trim(),
      'date': date.trim(),
      'startTime': startTime.trim(),
      'endTime': endTime.trim(),
      'clientId': clientId,
      'clientName': clientName.trim(),
      'clientPhone': clientPhone.trim(),
      'employeeId': employeeId,
      'employeeName': employeeName.trim(),
      'address': address.trim(),
      'notes': notes.trim(),
      'materialsNeeded': materialsNeeded.trim(),
      'pictures': pictures.trim(),
      'status': 'booked',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<List<AppointmentRecord>> appointmentsStream() {
    return _appointments
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
          snapshot.docs.map((doc) => AppointmentRecord.fromDoc(doc)).toList(),
    );
  }

  static Future<AppointmentRecord?> getAppointmentById(String appointmentId) async {
    final doc = await _appointments.doc(appointmentId).get();

    if (!doc.exists) {
      return null;
    }

    return AppointmentRecord.fromDoc(doc);
  }

  static Future<void> updateAppointment({
    required String appointmentId,
    required String title,
    required String date,
    required String startTime,
    required String endTime,
    required String employeeId,
    required String employeeName,
    required String address,
    required String notes,
    required String materialsNeeded,
    required String pictures,
  }) async {
    await _appointments.doc(appointmentId).update({
      'title': title.trim(),
      'date': date.trim(),
      'startTime': startTime.trim(),
      'endTime': endTime.trim(),
      'employeeId': employeeId,
      'employeeName': employeeName.trim(),
      'address': address.trim(),
      'notes': notes.trim(),
      'materialsNeeded': materialsNeeded.trim(),
      'pictures': pictures.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> updateAppointmentStatus({
    required String appointmentId,
    required String status,
  }) async {
    await _appointments.doc(appointmentId).update({
      'status': status.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteAppointment(String appointmentId) async {
    await _appointments.doc(appointmentId).delete();
  }

  static Stream<List<AppointmentRecord>> employeeAppointmentsStream(
      String employeeId,
      ) {
    return _appointments
        .where('employeeId', isEqualTo: employeeId)
        .snapshots()
        .map(
          (snapshot) =>
          snapshot.docs.map((doc) => AppointmentRecord.fromDoc(doc)).toList(),
    );
  }
}