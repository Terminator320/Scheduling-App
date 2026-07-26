import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/application/add_event_controller.dart';

/// L3: `AddEventController.addImages` caps selected images at
/// `maxImagesPerAppointment` (10) to bound RAM, silently truncating the
/// incoming list rather than throwing.
void main() {
  late ProviderContainer container;
  final initialDate = DateTime(2026, 5, 15);
  final provider = addEventControllerProvider(initialDate);

  setUp(() {
    // Keep the autoDispose provider alive across reads.
    container = ProviderContainer()..listen(provider, (_, _) {});
    addTearDown(container.dispose);
  });

  AddEventController readNotifier() => container.read(provider.notifier);
  AddEventState readState() => container.read(provider);

  // `File` is a value type in dart:io — constructing one with a path does no
  // disk I/O, which is all the controller cares about.
  List<File> stubFiles(int count) =>
      List.generate(count, (i) => File('/tmp/stub_$i.jpg'));

  test('addImages accepts everything up to the cap', () {
    readNotifier().addImages(stubFiles(10));
    expect(readState().selectedImages.length, 10);
  });

  test('addImages truncates a single oversized batch to the cap', () {
    readNotifier().addImages(stubFiles(12));
    expect(readState().selectedImages.length, 10);
  });

  test('addImages stays capped across multiple calls', () {
    readNotifier()
      ..addImages(stubFiles(7))
      ..addImages(stubFiles(5));
    expect(readState().selectedImages.length, 10);
  });
}
