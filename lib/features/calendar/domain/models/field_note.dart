import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:scheduling/core/utils/firestore_parsing.dart';

part 'field_note.freezed.dart';

/// One crew note on a job — `appointments/{id}/fieldNotes/{noteId}`.
///
/// A document rather than a field on the parent, because two assignees on the
/// same job used to overwrite each other's single `fieldNotes` string, and
/// because the admin reading the record needs to know who wrote what.
@freezed
abstract class FieldNote with _$FieldNote {
  const factory FieldNote({
    required String id,
    @Default('') String text,
    @Default('') String authorId,
    @Default('') String authorName,
    DateTime? createdAt,
  }) = _FieldNote;
  const FieldNote._();

  factory FieldNote.fromMap(String id, Map<String, dynamic> data) => FieldNote(
    id: id,
    text: (data['text'] ?? '').toString(),
    authorId: (data['authorId'] ?? '').toString(),
    authorName: (data['authorName'] ?? '').toString(),
    createdAt: firestoreDateTime(data['createdAt']),
  );

  /// The appointment's own `fieldNotes` string, shown unattributed at the top
  /// of the thread. Nothing writes that field any more.
  factory FieldNote.legacy(String text) => FieldNote(id: legacyId, text: text);

  /// Document id given to the pre-subcollection `fieldNotes` string, so the
  /// thread can render it beside real notes without colliding with one.
  static const String legacyId = 'legacy';

  bool get hasAuthor => authorName.trim().isNotEmpty;
}

/// One job's notes plus whether the read hit its cap and dropped older ones.
typedef FieldNoteThread = ({List<FieldNote> notes, bool truncated});
