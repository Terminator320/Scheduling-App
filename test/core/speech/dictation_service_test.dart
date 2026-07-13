import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/speech/dictation_service.dart';
import 'package:speech_to_text/speech_to_text.dart';

class _MockSpeechToText extends Mock implements SpeechToText {}

class _MockLogger extends Mock implements AppLogger {}

void main() {
  late _MockSpeechToText speech;
  late DictationService service;

  setUpAll(() {
    registerFallbackValue(SpeechListenOptions());
  });

  setUp(() {
    speech = _MockSpeechToText();
    service = DictationService(speech: speech, logger: _MockLogger());
    when(() => speech.isListening).thenReturn(false);
    when(
      () => speech.initialize(
        onError: any(named: 'onError'),
        onStatus: any(named: 'onStatus'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => speech.listen(
        onResult: any(named: 'onResult'),
        listenOptions: any(named: 'listenOptions'),
      ),
    ).thenAnswer((_) async {});
    when(() => speech.cancel()).thenAnswer((_) async {});
    when(() => speech.stop()).thenAnswer((_) async {});
  });

  test('start returns false when the recognizer fails to initialize', () async {
    when(
      () => speech.initialize(
        onError: any(named: 'onError'),
        onStatus: any(named: 'onStatus'),
      ),
    ).thenAnswer((_) async => false);
    final started = await service.start(
      onResult: (_, {required isFinal}) {},
      onSessionEnded: () {},
    );
    expect(started, false);
    verifyNever(
      () => speech.listen(
        onResult: any(named: 'onResult'),
        listenOptions: any(named: 'listenOptions'),
      ),
    );
  });

  test('start returns false when initialize throws (no rethrow)', () async {
    when(
      () => speech.initialize(
        onError: any(named: 'onError'),
        onStatus: any(named: 'onStatus'),
      ),
    ).thenThrow(Exception('platform down'));
    final started = await service.start(
      onResult: (_, {required isFinal}) {},
      onSessionEnded: () {},
    );
    expect(started, false);
  });

  test('initialize runs once across multiple starts', () async {
    await service.start(
      onResult: (_, {required isFinal}) {},
      onSessionEnded: () {},
    );
    await service.start(
      onResult: (_, {required isFinal}) {},
      onSessionEnded: () {},
    );
    verify(
      () => speech.initialize(
        onError: any(named: 'onError'),
        onStatus: any(named: 'onStatus'),
      ),
    ).called(1);
  });

  test('starting while another session is live cancels it and ends the old '
      'session', () async {
    var firstEnded = false;
    await service.start(
      onResult: (_, {required isFinal}) {},
      onSessionEnded: () => firstEnded = true,
    );
    when(() => speech.isListening).thenReturn(true);
    await service.start(
      onResult: (_, {required isFinal}) {},
      onSessionEnded: () {},
    );
    expect(firstEnded, true);
    verify(() => speech.cancel()).called(1);
  });

  test('start returns false and logs when listen throws', () async {
    when(
      () => speech.listen(
        onResult: any(named: 'onResult'),
        listenOptions: any(named: 'listenOptions'),
      ),
    ).thenThrow(Exception('busy'));
    final started = await service.start(
      onResult: (_, {required isFinal}) {},
      onSessionEnded: () {},
    );
    expect(started, false);
  });
}
