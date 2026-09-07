import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/data/appointment_images_store.dart';
import 'package:scheduling/features/calendar/domain/models/field_note.dart';

/// Reads and writes crew notes in `appointments/{id}/fieldNotes`.
///
/// Deliberately shaped like [AppointmentImagesStore]: the crew ADD to the
/// record and nothing more, so there is no update and no delete here — both
/// stay with the admin, in the rules and in this API.
class AppointmentFieldNotesStore {
  AppointmentFieldNotesStore({
    required CollectionReference<Map<String, dynamic>> appointments,
    required AppLogger logger,
  }) : _appointments = appointments,
       _logger = logger;

  final CollectionReference<Map<String, dynamic>> _appointments;
  final AppLogger _logger;

  /// The literal subcollection path shared with rules.
  static const String notesSubcollection = 'fieldNotes';

  /// Maximum note documents fetched for one appointment.
  static const int scanLimit = 200;

  CollectionReference<Map<String, dynamic>> _notesOf(String id) =>
      _appointments.doc(id).collection(notesSubcollection);

  /// Appends one note. The parent document is NOT touched: a note changes no
  /// field the history search reads, and leaving the parent alone keeps this
  /// write off the assignee `allow update` branches entirely.
  Future<void> append(
    String appointmentId, {
    required String text,
    required String authorId,
    required String authorName,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _notesOf(appointmentId).add({
      'text': trimmed,
      'authorId': authorId,
      'authorName': authorName,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Reads the NEWEST [scanLimit] notes and returns them oldest-first.
  ///
  /// Descending is load-bearing: ascending made the cap drop the newest notes,
  /// so past [scanLimit] nothing anyone wrote — the admin included — was
  /// visible, and an assignee could bury the record by filing cheap notes.
  Future<FieldNoteThread> fetch(String appointmentId) async {
    final snapshot = await _notesOf(
      appointmentId,
    ).orderBy('createdAt', descending: true).limit(scanLimit).get();
    final truncated = snapshot.docs.length >= scanLimit;
    if (truncated) {
      _logger.warn(
        'APPT-FIELDNOTE subcollection read for $appointmentId hit the '
        '$scanLimit-doc cap - older notes were not loaded',
      );
    }
    return (
      notes: [
        for (final doc in snapshot.docs.reversed)
          FieldNote.fromMap(doc.id, doc.data()),
      ],
      truncated: truncated,
    );
  }
}
