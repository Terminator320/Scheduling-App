import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/calendar/application/appointment_series_editor.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';

class _MockRepo extends Mock implements AppointmentsRepository {}

AppointmentRecord _appt({
  required String id,
  required DateTime start,
  String status = 'pending',
  String seriesId = '',
  String title = 'Leak fix',
}) => AppointmentRecord(
  id: id,
  title: title,
  startTime: start,
  endTime: start.add(const Duration(hours: 1)),
  status: status,
  seriesId: seriesId,
);

void main() {
  setUpAll(() {
    registerFallbackValue(
      AppointmentRecord(startTime: DateTime(2026), endTime: DateTime(2026)),
    );
    registerFallbackValue(<String>[]);
    registerFallbackValue(<AppointmentRecord>[]);
  });

  late _MockRepo repo;
  late AppointmentSeriesEditor editor;

  setUp(() {
    repo = _MockRepo();
    editor = AppointmentSeriesEditor(repo);
    var docCounter = 0;
    when(() => repo.newDocId()).thenAnswer((_) => 'copy-${docCounter++}');
    when(
      () => repo.rewriteSeries(
        updated: any(named: 'updated'),
        deleteIds: any(named: 'deleteIds'),
        copies: any(named: 'copies'),
      ),
    ).thenAnswer((_) async {});
    when(() => repo.updateAppointments(any())).thenAnswer((_) async {});
  });

  group('rewrite', () {
    test(
      'starting a new series books the cadence and removes nothing',
      () async {
        final start = DateTime(2026, 1, 15, 9);
        final appointment = _appt(id: 'a1', start: start); // seriesId is empty
        final updated = appointment.copyWith(repeat: RepeatInterval.oneYear);

        final result = await editor.rewrite(
          updated: updated,
          appointment: appointment,
          id: 'a1',
          start: start,
          end: start.add(const Duration(hours: 1)),
          repeat: RepeatInterval.oneYear,
        );

        // oneYear across the 60-month horizon books 5 future occurrences.
        expect(result.futureBookings, 5);
        expect(result.removedBookings, 0);
        // The series anchors to the visit's own id.
        expect(result.updated.seriesId, 'a1');
        // No prior series exists, so none is fetched.
        verifyNever(() => repo.getSeries(any()));

        final captured = verify(
          () => repo.rewriteSeries(
            updated: captureAny(named: 'updated'),
            deleteIds: captureAny(named: 'deleteIds'),
            copies: captureAny(named: 'copies'),
          ),
        ).captured;
        final deleteIds = (captured[1] as List).cast<String>();
        final copies = (captured[2] as List).cast<AppointmentRecord>();
        expect(deleteIds, isEmpty);
        expect(copies, hasLength(5));
        // Copies start fresh — pending, no photos of their own (each document
        // has its own `images` subcollection, and a copy simply has none), and
        // the same series id.
        expect(
          copies.every((c) => c.status == 'pending' && c.pictureCount == 0),
          isTrue,
        );
        expect(copies.every((c) => c.seriesId == 'a1'), isTrue);
        expect(copies.map((c) => c.id).toSet(), hasLength(5));
      },
    );

    test(
      'rewriting an existing series drops only future non-terminal siblings',
      () async {
        final start = DateTime(2026, 1, 15, 9);
        final appointment = _appt(id: 'a2', start: start, seriesId: 's1');
        final series = [
          appointment,
          // future + pending -> removed
          _appt(id: 'a3', start: DateTime(2026, 6, 15, 9), seriesId: 's1'),
          // future but done -> kept as a record
          _appt(
            id: 'a4',
            start: DateTime(2026, 7, 15, 9),
            seriesId: 's1',
            status: 'done',
          ),
          // past -> untouched
          _appt(id: 'a5', start: DateTime(2025, 6, 15, 9), seriesId: 's1'),
        ];
        when(() => repo.getSeries('s1')).thenAnswer((_) async => series);

        final result = await editor.rewrite(
          updated: appointment.copyWith(repeat: RepeatInterval.oneYear),
          appointment: appointment,
          id: 'a2',
          start: start,
          end: start.add(const Duration(hours: 1)),
          repeat: RepeatInterval.oneYear,
        );

        expect(result.removedBookings, 1);
        final captured = verify(
          () => repo.rewriteSeries(
            updated: captureAny(named: 'updated'),
            deleteIds: captureAny(named: 'deleteIds'),
            copies: captureAny(named: 'copies'),
          ),
        ).captured;
        expect((captured[1] as List).cast<String>(), ['a3']);
      },
    );
  });

  group('propagate', () {
    test(
      'edits future siblings, keeping each sibling date and status',
      () async {
        final anchorStart = DateTime(2026, 1, 15, 9);
        final appointment = _appt(id: 'p1', start: anchorStart, seriesId: 'ps');
        final series = [
          appointment,
          // future + pending -> propagated
          _appt(id: 'p2', start: DateTime(2026, 3, 20, 14), seriesId: 'ps'),
          // future but cancelled -> left untouched
          _appt(
            id: 'p3',
            start: DateTime(2026, 4, 20, 9),
            seriesId: 'ps',
            status: 'cancelled',
          ),
          // past -> left untouched
          _appt(id: 'p4', start: DateTime(2025, 12, 20, 9), seriesId: 'ps'),
        ];
        when(() => repo.getSeries('ps')).thenAnswer((_) async => series);

        final editedStart = DateTime(2026, 1, 15, 11); // moved to 11:00
        final updated = appointment.copyWith(
          title: 'New Title',
          notes: 'call ahead',
          startTime: editedStart,
          endTime: DateTime(2026, 1, 15, 12),
        );

        final count = await editor.propagate(
          updated: updated,
          appointment: appointment,
          id: 'p1',
          start: editedStart,
          end: DateTime(2026, 1, 15, 12),
        );

        expect(count, 1);
        final written =
            (verify(() => repo.updateAppointments(captureAny())).captured.single
                    as List)
                .cast<AppointmentRecord>();
        // The anchor is written first, then the propagated siblings.
        expect(written.first, updated);
        final propagated = written[1];
        expect(propagated.id, 'p2');
        expect(propagated.title, 'New Title');
        expect(propagated.notes, 'call ahead');
        // It keeps its own calendar date but adopts the new time-of-day.
        expect(propagated.startTime, DateTime(2026, 3, 20, 11));
        // Status is per-visit and never propagated.
        expect(propagated.status, 'pending');
      },
    );

    test('carries isAllDay and isPersonal onto every sibling', () async {
      final anchorStart = DateTime(2026, 1, 15, 9);
      final appointment = _appt(id: 'p1', start: anchorStart, seriesId: 'ps');
      final sibling = _appt(
        id: 'p2',
        start: DateTime(2026, 3, 20, 14),
        seriesId: 'ps',
      );
      when(
        () => repo.getSeries('ps'),
      ).thenAnswer((_) async => [appointment, sibling]);

      // Turning All day on rewrites the anchor to midnight-23:59.
      final allDayStart = DateTime(2026, 1, 15);
      final allDayEnd = DateTime(2026, 1, 15, 23, 59);
      final updated = appointment.copyWith(
        isAllDay: true,
        isPersonal: true,
        startTime: allDayStart,
        endTime: allDayEnd,
      );

      await editor.propagate(
        updated: updated,
        appointment: appointment,
        id: 'p1',
        start: allDayStart,
        end: allDayEnd,
      );

      final written =
          (verify(() => repo.updateAppointments(captureAny())).captured.single
                  as List)
              .cast<AppointmentRecord>();
      final propagated = written[1];
      // Without the flags the sibling spans midnight-23:59 while still reading
      // isAllDay:false — the travel sweep then stops skipping it and pushes a
      // "time to leave" for a block that has no departure time.
      expect(propagated.isAllDay, isTrue);
      expect(propagated.isPersonal, isTrue);
      expect(propagated.startTime, DateTime(2026, 3, 20));
    });
  });
}
