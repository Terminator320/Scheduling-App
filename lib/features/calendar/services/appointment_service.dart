import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:scheduling/features/calendar/models/appointment_image.dart';
import 'package:scheduling/features/calendar/models/appointment_record.dart';

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
    return appointments.orderBy('startTime', descending: true).snapshots().map((
      snapshot,
    ) {
      return snapshot.docs.map((doc) {
        return AppointmentRecord.fromMap(doc.id, doc.data());
      }).toList();
    });
  }

  Stream<List<AppointmentRecord>> appointmentsInRange(
    AppointmentDateRange range,
  ) {
    // Firestore can filter by date range so the calendar does not stream every appointment.
    return appointments
        .where(
          'startTime',
          isGreaterThanOrEqualTo: Timestamp.fromDate(range.start),
        )
        .where('startTime', isLessThan: Timestamp.fromDate(range.end))
        .orderBy('startTime')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AppointmentRecord.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Stream<List<AppointmentRecord>> getAppointmentStatus(
    String status, {
    int? limit,
  }) {
    Query<Map<String, dynamic>> query = appointments.where(
      'status',
      isEqualTo: status,
    );
    if (limit != null) query = query.limit(limit);

    return query.snapshots().map(
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

class AppointmentDateRange {
  final DateTime start;
  final DateTime end;

  const AppointmentDateRange({required this.start, required this.end});

  factory AppointmentDateRange.visibleMonth(DateTime focusedDay) {
    // Include a one-week buffer for calendar rows that show days from nearby months.
    final firstOfMonth = DateTime(focusedDay.year, focusedDay.month);
    final firstOfNextMonth = DateTime(focusedDay.year, focusedDay.month + 1);
    return AppointmentDateRange(
      start: firstOfMonth.subtract(const Duration(days: 7)),
      end: firstOfNextMonth.add(const Duration(days: 7)),
    );
  }
}
