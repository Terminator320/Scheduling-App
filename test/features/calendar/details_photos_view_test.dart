import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/photo_upload_notifier.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/views/details_view_leaf_widgets.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockAppointmentsRepo extends Mock implements AppointmentsRepository {}

void main() {
  final appointment = AppointmentRecord(
    id: 'a1',
    title: 'Leak',
    startTime: DateTime(2026, 9, 6, 9),
    endTime: DateTime(2026, 9, 6, 10),
  );

  testWidgets('a pending upload renders the section on a job with no photos', (
    tester,
  ) async {
    final notifier = PhotoUploadNotifier()..reportPending({'a1': 1});
    addTearDown(notifier.dispose);
    // The controller reads this to seed/re-read stored photos; without an
    // override `ref.read(appointmentsRepositoryProvider)` hits real Firebase.
    final appointments = _MockAppointmentsRepo();
    when(
      () => appointments.fetchAppointmentPictures(any()),
    ).thenAnswer((_) async => const []);
    when(
      () => appointments.onLocalWrite,
    ).thenAnswer((_) => const Stream.empty());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          photoUploadNotifierProvider.overrideWithValue(notifier),
          appointmentsRepositoryProvider.overrideWithValue(appointments),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DetailsPhotosView(
              appointment: appointment,
              isCancelled: false,
              onRetry: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Before: hasPhotos ignored pendingCount, so the whole section was a
    // SizedBox.shrink and the first photo on a job vanished while uploading.
    expect(find.text('PHOTOS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a background upload started with the sheet already open reveals the '
    'section without a remount',
    (tester) async {
      final notifier = PhotoUploadNotifier();
      addTearDown(notifier.dispose);
      final appointments = _MockAppointmentsRepo();
      when(
        () => appointments.fetchAppointmentPictures(any()),
      ).thenAnswer((_) async => const []);
      when(
        () => appointments.onLocalWrite,
      ).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            photoUploadNotifierProvider.overrideWithValue(notifier),
            appointmentsRepositoryProvider.overrideWithValue(appointments),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: DetailsPhotosView(
                appointment: appointment,
                isCancelled: false,
                onRetry: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // No photos, nothing pending yet: the section stays hidden.
      expect(find.text('PHOTOS'), findsNothing);

      // A background upload (e.g. DetailsFieldRecordView._addPhotos, from
      // view mode) reports pending on the SAME notifier instance with no
      // remount of this widget. Before: the outer gate read
      // `notifier.pending.value` once at build time and never listened, so
      // this transition was invisible until the upload finished and
      // `existingImages` picked it up.
      notifier.reportPending({'a1': 1});
      await tester.pump();

      expect(find.text('PHOTOS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
