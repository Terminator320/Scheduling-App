import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

/// The photo-indicator half of the `pictures` → `appointments/{id}/images`
/// migration. During phase 1 a document legitimately lives in EITHER store, so
/// `hasPictures` has to read both — testing one alone makes the card's photo
/// indicator vanish for half the fleet's data, silently.
AppointmentRecord _record({
  List<AppointmentImage> pictures = const [],
  int pictureCount = 0,
}) => AppointmentRecord(
  id: 'a1',
  title: 'Job',
  startTime: DateTime(2026, 8, 15, 9),
  endTime: DateTime(2026, 8, 15, 17),
  pictures: pictures,
  pictureCount: pictureCount,
);

const _image = AppointmentImage(
  url: 'https://example.test/photo.jpg',
  storagePath: 'appointments/a1/photo.jpg',
);

void main() {
  group('hasPictures reads BOTH stores', () {
    test('a legacy doc with only the array has pictures', () {
      // The trigger only fires on a photo write, so an older doc carries its
      // array and no `pictureCount` until the backfill reaches it.
      expect(_record(pictures: const [_image]).hasPictures, isTrue);
    });

    test('a migrated doc with only the counter has pictures', () {
      // Photos that arrived after the move live in the subcollection; the
      // parent doc carries the count alone.
      expect(_record(pictureCount: 2).hasPictures, isTrue);
    });

    test('a doc carrying both stores has pictures', () {
      expect(
        _record(pictures: const [_image], pictureCount: 1).hasPictures,
        isTrue,
      );
    });

    test('a doc with neither store has no pictures', () {
      expect(_record().hasPictures, isFalse);
    });
  });

  group('pictureCount parsing', () {
    test('an absent field reads as zero rather than throwing', () {
      // Every doc the trigger has not reached yet is this shape.
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

    test(
      'a doc parsed with an empty count but a populated array still has photos',
      () {
        // The exact migration shape: array present, counter absent.
        final record = AppointmentRecord.fromMap('a1', <String, dynamic>{
          'pictures': [
            {'url': 'https://example.test/p.jpg', 'storagePath': 'a/p.jpg'},
          ],
        });
        expect(record.pictureCount, 0);
        expect(record.hasPictures, isTrue);
      },
    );
  });

  test('toMap never emits the function-owned pictureCount', () {
    // `recountAppointmentPictures` owns it and the rules reject a client write
    // that touches it — emitting it turns every save into permission-denied.
    expect(
      _record(pictureCount: 5).toMap().containsKey('pictureCount'),
      isFalse,
    );
  });
}
