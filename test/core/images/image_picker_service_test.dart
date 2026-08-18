import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/images/image_picker_service.dart';
import 'package:scheduling/core/logging/app_logger.dart';

class _MockPicker extends Mock implements ImagePicker {}

class _RecordingLogger extends AppLogger {
  final warnings = <String>[];

  @override
  void warn(String message, [Object? error, StackTrace? stack]) {
    warnings.add(message);
  }
}

void main() {
  late _MockPicker picker;
  late _RecordingLogger logger;
  late ImagePickerService service;

  setUp(() {
    picker = _MockPicker();
    logger = _RecordingLogger();
    service = ImagePickerService(picker: picker, logger: logger);
  });

  test('pickImage returns a File for a picked image', () async {
    when(
      () => picker.pickImage(
        source: ImageSource.camera,
        maxWidth: any(named: 'maxWidth'),
        maxHeight: any(named: 'maxHeight'),
        imageQuality: any(named: 'imageQuality'),
      ),
    ).thenAnswer((_) async => XFile('/tmp/photo.jpg'));

    final file = await service.pickImage(ImageSource.camera);

    expect(file, isA<File>());
    expect(file!.path, '/tmp/photo.jpg');
  });

  test('pickImage returns null when the plugin throws', () async {
    when(
      () => picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: any(named: 'maxWidth'),
        maxHeight: any(named: 'maxHeight'),
        imageQuality: any(named: 'imageQuality'),
      ),
    ).thenThrow(StateError('picker failed'));

    expect(await service.pickImage(ImageSource.gallery), isNull);
    expect(logger.warnings.single, 'IMG-PICK single pick failed');
  });

  test('pickMultiImages returns files for picked images', () async {
    when(
      () => picker.pickMultiImage(
        maxWidth: any(named: 'maxWidth'),
        maxHeight: any(named: 'maxHeight'),
        imageQuality: any(named: 'imageQuality'),
      ),
    ).thenAnswer(
      (_) async => [XFile('/tmp/a.jpg'), XFile('/tmp/b.jpg')],
    );

    final files = await service.pickMultiImages();

    expect(files.map((f) => f.path), ['/tmp/a.jpg', '/tmp/b.jpg']);
  });

  test('pickMultiImages returns an empty list when the plugin throws', () async {
    when(
      () => picker.pickMultiImage(
        maxWidth: any(named: 'maxWidth'),
        maxHeight: any(named: 'maxHeight'),
        imageQuality: any(named: 'imageQuality'),
      ),
    ).thenThrow(StateError('picker failed'));

    expect(await service.pickMultiImages(), isEmpty);
    expect(logger.warnings.single, 'IMG-PICK multi pick failed');
  });
}
