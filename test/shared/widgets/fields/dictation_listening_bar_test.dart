import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scheduling/core/speech/dictation_service.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/dictation_listening_bar.dart';

class _MockDictation extends Mock implements DictationService {}

void main() {
  late _MockDictation dictation;

  setUp(() {
    dictation = _MockDictation();
    when(() => dictation.stop()).thenAnswer((_) async {});
  });

  Widget harness() => ProviderScope(
    overrides: [dictationServiceProvider.overrideWithValue(dictation)],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: DictationListeningBar()),
    ),
  );

  testWidgets('renders a waveform and the listening label', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();
    expect(find.byType(DictationWaveform), findsOneWidget);
    expect(find.text('Listening…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Stop ends the active session via the service', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();
    await tester.tap(find.text('Stop'));
    await tester.pump();
    verify(() => dictation.stop()).called(1);
  });
}
