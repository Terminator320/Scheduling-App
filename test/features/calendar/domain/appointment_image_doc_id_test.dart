import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/policies/appointment_image_doc_id.dart';

/// The worked examples here are shared VERBATIM with
/// `functions/__tests__/appointment_image_ids.test.js`. The two
/// implementations are hand-mirrors, and the failure they guard against is
/// silent: a backfilled photo and the client's later retry of the same photo
/// landing on different ids, so it renders twice with nothing erroring. If you
/// change a case here, change it there.
void main() {
  const realPath =
      'appointments/aBc123XyZ/images/1754835600000_image_picker_A1.jpg';
  const realUrl =
      'https://firebasestorage.googleapis.com/v0/b/schedulingapp-88727'
      '.firebasestorage.app/o/appointments%2FaBc123XyZ%2Fimages%2F'
      '1754835600000_image_picker_A1.jpg?alt=media&token='
      '8f3e1c2a-4b5d-6e7f-8a9b-0c1d2e3f4a5b';

  group('identity', () {
    test('keys on storagePath, which is what renders and deletes the photo',
        () {
      expect(
        appointmentImageDocIdFor(storagePath: realPath, url: realUrl),
        'img_appointments_aBc123XyZ_images_1754835600000_image_picker_A1.jpg',
      );
    });

    test('the same photo always resolves to the same id', () {
      // This is the whole point: the offline queue re-appends an already
      // uploaded photo, so the second write must be a no-op rather than a
      // duplicate. The array form got this from arrayUnion's deep-equality
      // dedupe, which depended on every field serializing identically.
      const a = AppointmentImage(storagePath: realPath, url: realUrl);
      const b = AppointmentImage(
        storagePath: realPath,
        url: realUrl,
        fileName: 'something_else.jpg',
        // A differing uploadedAt is exactly what used to defeat the array
        // dedupe. It must not matter here.
      );
      expect(appointmentImageDocId(a), appointmentImageDocId(b));
    });

    test('two photos on one appointment do not collide', () {
      const other =
          'appointments/aBc123XyZ/images/1754835600001_image_picker_A2.jpg';
      expect(
        appointmentImageDocIdFor(storagePath: realPath, url: ''),
        isNot(appointmentImageDocIdFor(storagePath: other, url: '')),
      );
    });
  });

  group('the legacy url fallback', () {
    // Docs predating storagePath carry a url and nothing else — the same ones
    // AppointmentImageLoader falls back for. Without this branch every
    // legacy photo on an appointment keys on '' and they collapse into one.
    test('falls back to url when storagePath is empty', () {
      final id = appointmentImageDocIdFor(storagePath: '', url: realUrl);
      expect(id, startsWith('img_'));
      expect(id, contains('8f3e1c2a'));
    });

    test('two legacy photos with different urls do not collide', () {
      final a = appointmentImageDocIdFor(storagePath: '', url: realUrl);
      final b = appointmentImageDocIdFor(
        storagePath: '',
        url: realUrl.replaceAll('8f3e1c2a', '9a4f2d3b'),
      );
      expect(a, isNot(b));
    });

    test('a blank storagePath that is only whitespace still falls back', () {
      expect(
        appointmentImageDocIdFor(storagePath: '   ', url: realUrl),
        appointmentImageDocIdFor(storagePath: '', url: realUrl),
      );
    });
  });

  group('Firestore id legality', () {
    test('never contains a slash', () {
      expect(
        appointmentImageDocIdFor(storagePath: realPath, url: ''),
        isNot(contains('/')),
      );
      expect(
        appointmentImageDocIdFor(storagePath: '', url: realUrl),
        isNot(contains('/')),
      );
    });

    test('the img_ prefix keeps the reserved __.*__ shape unreachable', () {
      // A storage path beginning with '/' sanitizes to a leading underscore,
      // which is how a bare key could otherwise reach Firestore's reserved id
      // shape and be rejected at write time.
      final id = appointmentImageDocIdFor(storagePath: '/_x_/', url: '');
      expect(id, startsWith('img_'));
      expect(RegExp(r'^__.*__$').hasMatch(id), isFalse);
    });

    test('is never "." or ".."', () {
      expect(appointmentImageDocIdFor(storagePath: '.', url: ''), 'img_.');
      expect(appointmentImageDocIdFor(storagePath: '..', url: ''), 'img_..');
    });

    test('caps length while keeping the unique tail', () {
      // Truncating from the head is what preserves uniqueness — both key
      // shapes carry their distinguishing part at the end.
      final long = 'appointments/${'x' * 500}/images/UNIQUE_TAIL.jpg';
      final id = appointmentImageDocIdFor(storagePath: long, url: '');
      expect(id.length, lessThanOrEqualTo(304)); // 'img_' + 300
      expect(id, endsWith('UNIQUE_TAIL.jpg'));
    });

    test('two long paths differing only in their tail do not collide', () {
      final a = 'appointments/${'x' * 500}/images/TAIL_A.jpg';
      final b = 'appointments/${'x' * 500}/images/TAIL_B.jpg';
      expect(
        appointmentImageDocIdFor(storagePath: a, url: ''),
        isNot(appointmentImageDocIdFor(storagePath: b, url: '')),
      );
    });
  });

  test('an image with no identity at all yields an empty id', () {
    // The caller must skip these rather than write them: Firestore rejects an
    // empty document id, and such an entry has nothing to render anyway.
    expect(appointmentImageDocIdFor(storagePath: '', url: ''), '');
    expect(appointmentImageDocId(const AppointmentImage()), '');
  });
}
