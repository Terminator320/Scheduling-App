// Pins the POSITIONAL contract between `existingImages`, the loaded BYTES and
// the viewer index.
//
// Every failure this file guards against shipped once: removing photo 0
// rendered the photo just deleted, an untapped placeholder opened a NEW photo,
// and the viewer's `initialIndex` (composed as `existingBytes.length + i`) ran
// past the end of the provider list and threw a RangeError out of Save/Share.
// A Storage round-trip per photo is a real window, not a frame or two, so the
// unloaded state below is the normal one, not an edge case.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/adaptive/adaptive_progress_indicator.dart';
import 'package:scheduling/core/images/appointment_image_loader.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/widgets/dialogs/image_viewer.dart';
import 'package:scheduling/features/calendar/widgets/sections/photo_picker_section.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockStorage extends Mock implements FirebaseStorage {}

/// Hands out a `Completer` per `loadAll` call so a test can hold the fetch
/// open — which is the state the widget spends real time in.
class _FakeLoader extends AppointmentImageLoader {
  _FakeLoader() : super(storage: _MockStorage(), logger: AppLogger());

  final calls = <Completer<List<Uint8List>>>[];

  @override
  Future<List<Uint8List>> loadAll(List<AppointmentImage> images) {
    final completer = Completer<List<Uint8List>>();
    calls.add(completer);
    return completer.future;
  }
}

/// Empty bytes are the REFUSAL sentinel; anything non-empty renders.
final _refused = Uint8List(0);
final _photo = Uint8List.fromList(_kTransparentPng);

/// 1x1 transparent PNG, so `Image.file` decodes a real picked photo.
const _kTransparentPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
];

const _imageA = AppointmentImage(
  url: 'https://storage/a?token=a',
  storagePath: 'appointments/j1/images/1_a.jpg',
);
const _imageB = AppointmentImage(
  url: 'https://storage/b?token=b',
  storagePath: 'appointments/j1/images/2_b.jpg',
);

/// `pumpAndSettle` cannot be used here: the unloaded state renders a
/// `CircularProgressIndicator`, which animates forever, so settling never
/// completes. These pumps cover the load's microtask plus the viewer's
/// 250 ms route transition.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  late _FakeLoader loader;
  late Directory tempDir;

  setUp(() {
    loader = _FakeLoader();
    tempDir = Directory.systemTemp.createTempSync('photo_picker_test');
    addTearDown(() => tempDir.deleteSync(recursive: true));
  });

  File newPhoto(String name) {
    final file = File('${tempDir.path}${Platform.pathSeparator}$name')
      ..writeAsBytesSync(Uint8List.fromList(_kTransparentPng));
    return file;
  }

  Future<void> pumpSection(
    WidgetTester tester, {
    List<AppointmentImage> existingImages = const [],
    List<File> newImages = const [],
    bool isEditing = true,
    int failedCount = 0,
    VoidCallback? onRetry,
  }) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appointmentImageLoaderProvider.overrideWithValue(loader),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: PhotoPickerSection(
                existingImages: existingImages,
                newImages: newImages,
                failedCount: failedCount,
                isEditing: isEditing,
                onPickImages: () {},
                onRemoveExisting: (_) {},
                onRemoveNew: (_) {},
                onRetry: onRetry,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('editing photo strip exposes add-more as an InkWell surface', (
    tester,
  ) async {
    await pumpSection(tester, failedCount: 1);

    expect(find.widgetWithText(InkWell, 'Add more'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('upload failures expose retry as a TextButton', (tester) async {
    await pumpSection(tester, failedCount: 1, onRetry: () {});

    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('the _resolvedFor gate', () {
    testWidgets('serves nothing while the first load is outstanding', (
      tester,
    ) async {
      await pumpSection(tester, existingImages: const [_imageA, _imageB]);

      // Empty rather than partial: every consumer indexes the bytes
      // positionally beside `newImages`, so a short list shifts them.
      expect(find.byType(AdaptiveProgressIndicator), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('drops the previous bytes the moment a photo is removed', (
      tester,
    ) async {
      // THE regression: after removing photo 0 the widget rebuilds with a
      // shorter `existingImages` while the OLD bytes are still in hand, so
      // index 0 rendered the photo that was just deleted.
      await pumpSection(tester, existingImages: const [_imageA, _imageB]);
      loader.calls.single.complete([_refused, _photo]);
      await settle(tester);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);

      await pumpSection(tester, existingImages: const [_imageB]);
      await tester.pump();

      // imageB's bytes are not refused, so a stale read at index 0 would keep
      // showing imageA's error tile. The gate must fall back to placeholders.
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      expect(find.byType(AdaptiveProgressIndicator), findsOneWidget);
      expect(loader.calls, hasLength(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a late load for a longer list never reaches the strip', (
      tester,
    ) async {
      // The removal's load is in flight when the FIRST one lands. Serving
      // it would put two entries against a one-photo list.
      await pumpSection(tester, existingImages: const [_imageA, _imageB]);
      await pumpSection(tester, existingImages: const [_imageB]);

      loader.calls.first.complete([_refused, _refused]);
      await settle(tester);

      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      expect(find.byType(AdaptiveProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a late load cannot un-render the one that already landed', (
      tester,
    ) async {
      // Out-of-order completion: the removal's load settles first, then the
      // superseded one arrives. Stored without the list check, it overwrites
      // `_resolvedFor` with the OLD list, the gate stops matching, and a photo
      // that had rendered drops back to a spinner it never leaves.
      await pumpSection(tester, existingImages: const [_imageA, _imageB]);
      await pumpSection(tester, existingImages: const [_imageB]);

      loader.calls.last.complete([_refused]);
      await settle(tester);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);

      loader.calls.first.complete([_refused, _refused]);
      await settle(tester);

      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      expect(find.byType(AdaptiveProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('empty bytes are a REFUSAL, not a pending load', () {
    testWidgets('renders the error tile rather than a spinner', (tester) async {
      await pumpSection(tester, existingImages: const [_imageA]);
      loader.calls.single.complete([_refused]);
      await settle(tester);

      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      expect(find.byType(AdaptiveProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps the error tile untappable', (tester) async {
      // Fetching nothing is the point: there is no url to fall back to by
      // design, so there is no photo to open.
      await pumpSection(tester, existingImages: const [_imageA]);
      loader.calls.single.complete([_refused]);
      await settle(tester);

      await tester.tap(
        find.byIcon(Icons.broken_image_outlined),
        warnIfMissed: false,
      );
      await settle(tester);

      expect(find.byType(ImageViewer), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('the viewer index a thumbnail opens at', () {
    testWidgets('an unloaded existing photo is not tappable', (tester) async {
      // A placeholder that opens the viewer opens whatever provider sits at
      // this index — while the load is outstanding that is a NEW photo.
      await pumpSection(
        tester,
        existingImages: const [_imageA],
        newImages: [newPhoto('picked.png')],
      );

      await tester.tap(
        find.byType(AdaptiveProgressIndicator),
        warnIfMissed: false,
      );
      await settle(tester);

      expect(find.byType(ImageViewer), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a new photo is offset by the entries the viewer is handed', (
      tester,
    ) async {
      // While the load is outstanding the viewer is handed the FILES only,
      // so counting `existingImages` instead points one past this photo — two
      // new photos are what make that visible, since with one the viewer's own
      // clamp would quietly absorb the off-by-one and open the same file.
      await pumpSection(
        tester,
        existingImages: const [_imageA],
        newImages: [newPhoto('first.png'), newPhoto('second.png')],
      );

      await tester.tap(find.byType(Image).first, warnIfMissed: false);
      await settle(tester);

      final viewer = tester.widget<ImageViewer>(find.byType(ImageViewer));
      expect(viewer.images, hasLength(2));
      expect(viewer.initialIndex, 0);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a new photo sits after the loaded photos once they land', (
      tester,
    ) async {
      // A refused photo still occupies its slot, so the offset is 1 here — the
      // substituted provider is what keeps the indices lined up.
      await pumpSection(
        tester,
        existingImages: const [_imageA],
        newImages: [newPhoto('picked.png')],
      );
      loader.calls.single.complete([_refused]);
      await settle(tester);

      await tester.tap(find.byType(Image), warnIfMissed: false);
      await settle(tester);

      final viewer = tester.widget<ImageViewer>(find.byType(ImageViewer));
      expect(viewer.images, hasLength(2));
      expect(viewer.initialIndex, 1);
      expect(find.text('2 / 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
