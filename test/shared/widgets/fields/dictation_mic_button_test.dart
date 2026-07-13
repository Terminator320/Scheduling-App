import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/permissions/media_permission_service.dart';
import 'package:scheduling/core/speech/dictation_service.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/dictation_mic_button.dart';

class _MockPermissions extends Mock implements MediaPermissionService {}

class _MockDictation extends Mock implements DictationService {}

class _MockNotices extends Mock implements NoticeService {}

void main() {
  late _MockPermissions permissions;
  late _MockDictation dictation;
  late _MockNotices notices;
  late TextEditingController controller;

  setUpAll(() {
    registerFallbackValue((String _, {required bool isFinal}) {});
    registerFallbackValue(() {});
  });

  setUp(() {
    permissions = _MockPermissions();
    dictation = _MockDictation();
    notices = _MockNotices();
    controller = TextEditingController();
    when(() => dictation.stop()).thenAnswer((_) async {});
  });

  tearDown(() => controller.dispose());

  Widget harness() => ProviderScope(
    overrides: [
      mediaPermissionServiceProvider.overrideWithValue(permissions),
      dictationServiceProvider.overrideWithValue(dictation),
      noticeServiceProvider.overrideWithValue(notices),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: DictationMicButton(controller: controller)),
    ),
  );

  testWidgets('renders the idle mic icon', (tester) async {
    await tester.pumpWidget(harness());
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsNothing);
  });

  testWidgets(
    'denied permission surfaces a notice and never starts listening',
    (tester) async {
      when(
        () => permissions.ensureMicrophone(),
      ).thenAnswer((_) async => MediaPermissionResult.denied);
      await tester.pumpWidget(harness());
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      verify(() => notices.error(any())).called(1);
      verifyNever(
        () => dictation.start(
          onResult: any(named: 'onResult'),
          onSessionEnded: any(named: 'onSessionEnded'),
          localeId: any(named: 'localeId'),
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'granted permission starts a session and shows the listening icon',
    (tester) async {
      when(
        () => permissions.ensureMicrophone(),
      ).thenAnswer((_) async => MediaPermissionResult.granted);
      when(() => dictation.localeIdFor(any())).thenAnswer((_) async => 'en_US');
      when(
        () => dictation.start(
          onResult: any(named: 'onResult'),
          onSessionEnded: any(named: 'onSessionEnded'),
          localeId: any(named: 'localeId'),
        ),
      ).thenAnswer((_) async => true);
      await tester.pumpWidget(harness());
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed start surfaces the unavailable notice and stays idle', (
    tester,
  ) async {
    when(
      () => permissions.ensureMicrophone(),
    ).thenAnswer((_) async => MediaPermissionResult.granted);
    when(() => dictation.localeIdFor(any())).thenAnswer((_) async => null);
    when(
      () => dictation.start(
        onResult: any(named: 'onResult'),
        onSessionEnded: any(named: 'onSessionEnded'),
        localeId: any(named: 'localeId'),
      ),
    ).thenAnswer((_) async => false);
    await tester.pumpWidget(harness());
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    verify(() => notices.error(any())).called(1);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
  });
}
