import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/views/details_view_body.dart';

void main() {
  AppointmentRecord job({
    bool isAllDay = false,
    bool isPersonal = false,
    String clientId = 'c1',
  }) => AppointmentRecord(
    id: 'a1',
    title: 'Leak',
    startTime: DateTime(2026, 9, 7, 9),
    endTime: DateTime(2026, 9, 7, 10),
    isAllDay: isAllDay,
    isPersonal: isPersonal,
    clientId: clientId,
  );

  group('offersPushBack', () {
    test('offered on an ordinary open job the admin can act on', () {
      expect(
        DetailsViewBody.offersPushBack(
          job(),
          showActions: true,
          isClosed: false,
          hasOptions: true,
        ),
        isTrue,
      );
    });

    test('an all-day block has no clock to shift', () {
      expect(
        DetailsViewBody.offersPushBack(
          job(isAllDay: true),
          showActions: true,
          isClosed: false,
          hasOptions: true,
        ),
        isFalse,
      );
    });

    test('a closed job has nothing to delay', () {
      expect(
        DetailsViewBody.offersPushBack(
          job(),
          showActions: true,
          isClosed: true,
          hasOptions: true,
        ),
        isFalse,
      );
    });

    test('never offered without the admin actions', () {
      expect(
        DetailsViewBody.offersPushBack(
          job(),
          showActions: false,
          isClosed: false,
          hasOptions: true,
        ),
        isFalse,
      );
    });

    test('not offered when no slot remains today', () {
      expect(
        DetailsViewBody.offersPushBack(
          job(),
          showActions: true,
          isClosed: false,
          hasOptions: false,
        ),
        isFalse,
      );
    });
  });

  group('offersBookAgain', () {
    test('offered on a client job the admin can act on', () {
      expect(
        DetailsViewBody.offersBookAgain(
          job(),
          showActions: true,
          hasHandler: true,
        ),
        isTrue,
      );
    });

    test('a personal job has no client to rebook', () {
      expect(
        DetailsViewBody.offersBookAgain(
          job(isPersonal: true),
          showActions: true,
          hasHandler: true,
        ),
        isFalse,
      );
    });

    test('a job with no client id has nothing to rebook', () {
      expect(
        DetailsViewBody.offersBookAgain(
          job(clientId: '   '),
          showActions: true,
          hasHandler: true,
        ),
        isFalse,
      );
    });

    test('never offered without the admin actions', () {
      expect(
        DetailsViewBody.offersBookAgain(
          job(),
          showActions: false,
          hasHandler: true,
        ),
        isFalse,
      );
    });

    test('not offered when the host wired no handler', () {
      expect(
        DetailsViewBody.offersBookAgain(
          job(),
          showActions: true,
          hasHandler: false,
        ),
        isFalse,
      );
    });
  });
}
