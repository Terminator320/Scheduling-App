import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

class FirebaseAppointmentsRepository implements AppointmentsRepository {
  FirebaseAppointmentsRepository(FirebaseFirestore firestore)
    : _appointments = firestore.collection('appointments');

  final CollectionReference<Map<String, dynamic>> _appointments;

  @override
  String newDocId() => _appointments.doc().id;

  @override
  Future<AppointmentRecord?> getAppointmentById(String id) async {
    final doc = await _appointments.doc(id).get();
    if (!doc.exists) return null;
    return AppointmentRecord.fromMap(doc.id, doc.data() ?? {});
  }

  @override
  Future<void> addAppointment(AppointmentRecord appointment) async {
    final ref = appointment.id != null
        ? _appointments.doc(appointment.id)
        : _appointments.doc();
    await ref.set({
      ..._toFirestoreMap(appointment),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> updateAppointment(AppointmentRecord appointment) async {
    if (appointment.id == null) return;
    await _appointments.doc(appointment.id).update({
      ..._toFirestoreMap(appointment),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> updateAppointmentPictures(
    String id,
    List<AppointmentImage> pictures,
  ) async {
    await _appointments.doc(id).update({
      'pictures': pictures.map(_imageToFirestoreMap).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> updateAppointmentStatus({
    required String id,
    required String status,
  }) async {
    await _appointments.doc(id).update({
      'status': status.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> deleteAppointment(String id) async {
    await _appointments.doc(id).delete();
  }

  @override
  Stream<List<AppointmentRecord>> watchAll() {
    return _appointments
        .orderBy('startTime', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AppointmentRecord.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Stream<List<AppointmentRecord>> watchInRange(AppointmentDateRange range) {
    return _appointments
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

  @override
  Stream<List<AppointmentRecord>> watchHistory() {
    return _appointments
        .where('status', whereIn: ['done', 'cancelled'])
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AppointmentRecord.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Stream<List<AppointmentRecord>> watchForEmployee(String employeeId) {
    return _appointments
        .where('employeeIds', arrayContains: employeeId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AppointmentRecord.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Future<List<EmployeeRecord>> findBusyEmployees({
    required List<EmployeeRecord> candidates,
    required DateTime start,
    required DateTime end,
  }) async {
    final busy = <EmployeeRecord>[];
    for (final employee in candidates) {
      final snapshot = await _appointments
          .where('employeeIds', arrayContains: employee.id)
          .where('startTime', isLessThan: Timestamp.fromDate(end))
          .where('endTime', isGreaterThan: Timestamp.fromDate(start))
          .get();
      if (snapshot.docs.isNotEmpty) busy.add(employee);
    }
    return busy;
  }

  /// Converts a domain `AppointmentRecord` into a Firestore-friendly map by
  /// rewriting `DateTime` fields to `Timestamp` and embedded picture
  /// `DateTime?` to `Timestamp?`. Domain layer stays pure-Dart.
  Map<String, dynamic> _toFirestoreMap(AppointmentRecord appointment) {
    final base = Map<String, dynamic>.from(appointment.toMap());
    base['startTime'] = Timestamp.fromDate(appointment.startTime);
    base['endTime'] = Timestamp.fromDate(appointment.endTime);
    base['pictures'] = appointment.pictures
        .map(_imageToFirestoreMap)
        .toList();
    return base;
  }

  Map<String, dynamic> _imageToFirestoreMap(AppointmentImage image) {
    return {
      'url': image.url,
      'storagePath': image.storagePath,
      'fileName': image.fileName,
      'uploadedAt': image.uploadedAt == null
          ? null
          : Timestamp.fromDate(image.uploadedAt!),
    };
  }
}
