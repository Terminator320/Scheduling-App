import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

/// The photo-indicator half of the `pictures` → `appointments/{id}/images`
/// move, now that the CONTRACT step has taken the array away.
///
/// `pictureCount` is the only store left, so it is also what the detail sheet
/// gates its subcollection read on — a job whose count reads 0 while photos
/// exist shows none of them, silently. Every write path is covered: a create
/// stamps an explicit 0, `recountAppointmentPictures` owns it afterwards, and
/// the cleanup script stamped it on everything older.
AppointmentRecord _record({int pictureCount = 0}) => AppointmentRecord(
  id: 'a1',
  title: 'Job',
  startTime: DateTime(2026, 8, 15, 9),
  endTime: DateTime(2026, 8, 15, 17),
  pictureCount: pictureCount,
);

void main() {
  group('hasPictures reads the counter', () {
    test('a job with photos in the subcollection has pictures', () {
      expect(_record(pictureCount: 2).hasPictures, isTrue);
    });

    test('a job with a zero count has none', () {
      expect(_record().hasPictures, isFalse);
    });
  });

  group('pictureCount parsing', () {
    test('an absent field reads as zero rather than throwing', () {
      final record = AppointmentRecord.fromMap('a1', <String, dynamic>{
        'title': 'Job',
      });
      expect(record.pictureCount, 0);
      expect(record.hasPictures, isFalse);
    });

    test('an int is taken as written', () {
      final record = AppointmentRecord.fromMap('a1', <String, dynamic>{
        'pictureCount': 3,
      });
      expect(record.pictureCount, 3);
      expect(record.hasPictures, isTrue);
    });

    test('a non-integer num is truncated, not rejected', () {
      final record = AppointmentRecord.fromMap('a1', <String, dynamic>{
        'pictureCount': 2.9,
      });
      expect(record.pictureCount, 2);
    });

    test('a negative count clamps to zero', () {
      final record = AppointmentRecord.fromMap('a1', <String, dynamic>{
        'pictureCount': -4,
      });
      expect(record.pictureCount, 0);
      expect(record.hasPictures, isFalse);
    });

    test('an unparseable value reads as zero rather than throwing', () {
      // This feeds a display affordance, not a decision, so a console-written
      // string must degrade rather than blow up the whole range stream.
      final record = AppointmentRecord.fromMap('a1', <String, dynamic>{
        'pictureCount': 'seven',
      });
      expect(record.pictureCount, 0);
    });

    test('a null value reads as zero', () {
      final record = AppointmentRecord.fromMap('a1', <String, dynamic>{
        'pictureCount': null,
      });
      expect(record.pictureCount, 0);
    });
  });

  group('the retired array', () {
    test('a leftover pictures array on a legacy document is ignored', () {
      // The cleanup script empties these, but a document it has not reached
      // must not resurrect the field — the photos are in the subcollection and
      // the count is what says so.
      final record = AppointmentRecord.fromMap('a1', <String, dynamic>{
        'pictures': [
          {'url': 'https://example.test/p.jpg', 'storagePath': 'a/p.jpg'},
        ],
        'pictureCount': 1,
      });
      expect(record.hasPictures, isTrue);
      expect(record.toMap().containsKey('pictures'), isFalse);
    });

    test('toMap never emits the array, so no write can recreate it', () {
      expect(_record().toMap().containsKey('pictures'), isFalse);
    });
  });

  test('toMap never emits the function-owned pictureCount', () {
    // `recountAppointmentPictures` owns it after creation and the rules reject
    // an UPDATE that moves it — emitting it here turns every edit into an
    // opaque permission-denied. The create writes its 0 in the repository, not
    // through this map.
    expect(
      _record(pictureCount: 5).toMap().containsKey('pictureCount'),
      isFalse,
    );
  });
}
