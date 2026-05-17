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
    final data = {
      ..._toFirestoreMap(appointment),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (appointment.id != null) {
      await _appointments.doc(appointment.id).set(data);
    } else {
      await _appointments.add(data);
    }
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

  static const _allowedStatuses = {
    'pending',
    'confirmed',
    'in_progress',
    'done',
    'cancelled',
  };

  @override
  Future<void> updateAppointmentStatus({
    required String id,
    required String status,
  }) async {
    final trimmed = status.trim();
    if (!_allowedStatuses.contains(trimmed)) {
      throw ArgumentError.value(
        status,
        'status',
        'must be one of $_allowedStatuses',
      );
    }
    await _appointments.doc(id).update({
      'status': trimmed,
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
        .limit(500)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AppointmentRecord.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Stream<List<AppointmentRecord>> watchForEmployeeInRange(
    String employeeId,
    AppointmentDateRange range,
  ) {
    return _appointments
        .where('employeeIds', arrayContains: employeeId)
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
  Future<List<EmployeeRecord>> findBusyEmployees({
    required List<EmployeeRecord> candidates,
    required DateTime start,
    required DateTime end,
  }) async {
    if (candidates.isEmpty) return const [];

    final ids = candidates.map((e) => e.id).toList();
    final busyIds = <String>{};

    for (var i = 0; i < ids.length; i += 30) {
      final batch = ids.sublist(i, i + 30 < ids.length ? i + 30 : ids.length);
      final snapshot = await _appointments
          .where('employeeIds', arrayContainsAny: batch)
          .where('startTime', isLessThan: Timestamp.fromDate(end))
          .where('endTime', isGreaterThan: Timestamp.fromDate(start))
          .get();
      for (final doc in snapshot.docs) {
        final empIds = doc.data()['employeeIds'] as List<dynamic>? ?? const [];
        for (final id in empIds) {
          if (id is String) busyIds.add(id);
        }
      }
    }

    return candidates.where((e) => busyIds.contains(e.id)).toList();
  }

  Map<String, dynamic> _toFirestoreMap(AppointmentRecord appointment) {
    final base = Map<String, dynamic>.from(appointment.toMap());
    base['startTime'] = Timestamp.fromDate(appointment.startTime);
    base['endTime'] = Timestamp.fromDate(appointment.endTime);
    base['pictures'] = appointment.pictures.map(_imageToFirestoreMap).toList();
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
