# Speech-to-Text Dictation Implementation Plan

> **STATUS: IMPLEMENTED 2026-07-13 (branch `notification`).** All 9 tasks built
> with the mockup-decided UI (inline mic + transient waveform listening bar);
> `flutter analyze` clean, full suite green (873 tests, incl. merge/service/
> button/bar/field coverage). **Only Task 9 Step 4 (on-device mic verification)
> remains** — method-channel plugin, same class as `ImagePickerService`, can't
> run on this Windows box. See the device checklist in Task 9.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an in-app microphone button to the appointment **Notes** and **Materials needed** fields that dictates speech into the field live-as-you-speak, using on-device OS speech recognition.

**Architecture:** A pure text-merge function (`dictation_text_merge.dart`) + a thin `DictationService` wrapping the `speech_to_text` plugin (single active session, lazy init, injectable for tests) + a `DictationMicButton` widget composed into `LabeledTextField`'s suffix slot alongside the existing `ClearTextButton` behind an opt-in `enableDictation` flag. Permission gating extends the existing `MediaPermissionService` pattern; failures surface via `NoticeService`; dictated text flows through the normal controller path so validation/caps/save need no changes.

**Tech Stack:** Flutter/Dart (`^3.10.7`), `speech_to_text` (new dep, v7.x), `permission_handler ^12.0.2` (existing), Riverpod manual providers, mocktail for tests.

**Scope decisions (user, 2026-07-10):** Notes-style fields only (appointment Notes + Materials) — no mic on names, email, phone, or search bars. Live-as-you-speak partial results. Note the iOS system keyboard's dictation key already works in every field; this in-app mic adds an always-discoverable affordance that doesn't depend on keyboard settings.

**UI design decision (mockup, 2026-07-13):** "A's inline mic, but only show B's waveform bar while listening" — the resting state is just the inline suffix mic beside the clear-✕ (no new chrome; idle fields are byte-for-byte the current form); tapping it lights the mic blue + pulsing and slides in a transient **waveform bar with a Stop** *under that field only*, which collapses back the moment dictation stops. Two independent state cues (mic icon shape+color AND the bar) so state never relies on color alone (a11y rule). The bar animates in/out with the app's standard field-error entrance (fade+slide), collapsing to instant under reduce-motion. Mockup artifact: https://claude.ai/code/artifact/8ef8190a-4926-45d4-8152-486e94307567

> **Task 6 impact:** the `DictationMicButton` in the plan below renders only the mic-icon swap. The chosen design ALSO requires a transient listening bar (waveform + "Listening…" label + Stop) rendered beneath the field while `_isListening` is true. Two clean ways to fit it: (a) have `LabeledTextField` render the bar below the field when its `DictationMicButton` reports a listening state (lift `_isListening` via a callback/`ValueNotifier`), or (b) keep the button self-contained and add a sibling `DictationListeningBar` that `LabeledTextField._defaultSuffix`/body wires in. Reuse the app's fade+slide error-row entrance and gate motion on `MediaQuery.disableAnimationsOf`. Waveform can be a lightweight CustomPaint/animated bars (no new dep). This is a UI addition only — the merge logic (T3), service (T5), and permission gate (T4) are unaffected.

**Background facts an implementer must know (verified in-code 2026-07-10):**
- `LabeledTextField` (`lib/shared/widgets/fields/labeled_text_field.dart:87-94`) has ONE suffix slot: a custom `suffixIcon` displaces the built-in `ClearTextButton`. The mic must be composed WITH the clear-x in a `Row(mainAxisSize: min)`.
- `MediaPermissionService` (`lib/core/permissions/media_permission_service.dart`) is 1 method (`ensureCamera`) + a result enum; denial UX pattern is in `lib/features/calendar/widgets/sheets/image_source_picker.dart:30-42` (NoticeService, NOT dialogs/SnackBars).
- `AppLogger.warn(String message, [Object? error, StackTrace? stack])` at `lib/core/logging/app_logger.dart:17`; `loggerProvider` at line 28.
- Target fields: `lib/features/calendar/widgets/sections/appointment_form_fields.dart` — Notes (lines 298-309), Materials (312-322). Both `maxLines: 2`, capped via `TextLimits`.
- l10n: keys in BOTH `lib/l10n/app_en.arb` + `app_fr.arb`; EN keys need `@key` metadata blocks or gen-l10n fails. **An ARB-edit hook auto-runs `flutter gen-l10n` — never run it manually.**
- `flutter pub get` after dependency changes needs the sandbox disabled on this box (plugin-symlink error).
- Repo rule: quote-free commit messages (PowerShell 5.1 quoting); commits via Bash tool are fine but keep messages quote-free anyway.

---

### Task 1: Dependency + platform config

**Files:**
- Modify: `pubspec.yaml` (dependencies block, after `connectivity_plus`)
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `ios/Runner/Info.plist`

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml` after the `connectivity_plus: ^7.2.0` line:

```yaml
  # On-device speech recognition (dictation mic on notes fields)
  speech_to_text: ^7.0.0
```

- [ ] **Step 2: Fetch packages**

Run: `flutter pub get` (disable sandbox for this command — known plugin-symlink issue).
Expected: `Got dependencies!` and `speech_to_text` resolves to a 7.x version in `pubspec.lock`.

- [ ] **Step 3: Android manifest**

In `android/app/src/main/AndroidManifest.xml`, after the `WRITE_CONTACTS` permission (line 10):

```xml
    <!-- Dictation mic on notes fields (speech_to_text). -->
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
```

And inside the existing `<queries>` block (lines 53-58), add a sibling `<intent>` (Android 11+ package visibility for the recognizer):

```xml
        <intent>
            <action android:name="android.speech.RecognitionService"/>
        </intent>
```

(No INTERNET permission needed — Firebase already merges it. Skip the README's Bluetooth permissions: YAGNI.)

- [ ] **Step 4: iOS Info.plist**

In `ios/Runner/Info.plist`, alongside the existing `NSCameraUsageDescription` (lines 44-45), add both keys (both are required by `speech_to_text` on iOS):

```xml
	<key>NSMicrophoneUsageDescription</key>
	<string>The microphone lets you dictate text into notes and other fields.</string>
	<key>NSSpeechRecognitionUsageDescription</key>
	<string>Speech recognition converts your dictation into text.</string>
```

- [ ] **Step 5: Verify + commit**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"`
Expected: no output (clean).

```bash
git add pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml ios/Runner/Info.plist
git commit -m "chore: add speech_to_text dep and mic/speech platform permissions"
```

---

### Task 2: Localization keys

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_fr.arb`

- [ ] **Step 1: EN keys with metadata**

Add to `app_en.arb` — `common_*` keys near the other `common_` entries (e.g. after `common_clearText`), `error_*` keys near `error_cameraPermissionDenied`:

```json
"common_dictate": "Dictate",
"@common_dictate": {
  "description": "Tooltip on the microphone button that starts voice dictation into a text field"
},
"common_stopDictation": "Stop dictation",
"@common_stopDictation": {
  "description": "Tooltip on the microphone button while dictation is actively listening"
},
"error_microphonePermissionDenied": "Microphone access is needed to dictate.",
"@error_microphonePermissionDenied": {
  "description": "Shown when the microphone permission request is denied"
},
"error_microphonePermissionPermanentlyDenied": "Enable microphone access in Settings to use dictation.",
"@error_microphonePermissionPermanentlyDenied": {
  "description": "Shown when the microphone permission is permanently denied and must be enabled from system settings"
},
"error_dictationUnavailable": "Dictation is not available on this device.",
"@error_dictationUnavailable": {
  "description": "Shown when the device speech recognizer fails to initialize or start"
}
```

- [ ] **Step 2: FR keys (values only, same positions)**

Match the apostrophe style already used in `app_fr.arb` (check a neighboring key; use the typographic ’ if that is what the file uses):

```json
"common_dictate": "Dicter",
"common_stopDictation": "Arrêter la dictée",
"error_microphonePermissionDenied": "L'accès au microphone est nécessaire pour dicter.",
"error_microphonePermissionPermanentlyDenied": "Activez l'accès au microphone dans les réglages pour utiliser la dictée.",
"error_dictationUnavailable": "La dictée n'est pas disponible sur cet appareil."
```

- [ ] **Step 3: Verify generation**

The ARB-edit hook runs `flutter gen-l10n` automatically. Confirm: `lib/l10n/.gen/untranslated.json` shows no new EN/FR drift, and `flutter analyze 2>&1 | grep -E "error -"` is clean.

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_fr.arb
git commit -m "feat: l10n keys for dictation mic and microphone permission errors"
```

---

### Task 3: Pure merge logic (TDD)

**Files:**
- Create: `lib/core/speech/dictation_text_merge.dart`
- Test: `test/core/speech/dictation_text_merge_test.dart`

Each partial result from the recognizer is the FULL recognized utterance so far, so every merge replays against the same snapshot (`base` text + caret captured when dictation started). The function is pure — plain `test()`, no Firebase, no plugins.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/speech/dictation_text_merge.dart';

void main() {
  group('mergeDictation', () {
    test('inserts recognized text into an empty field', () {
      final m = mergeDictation(base: '', insertAt: 0, recognized: 'hello world');
      expect(m.text, 'hello world');
      expect(m.caret, 11);
    });

    test('appends with a separating space when base does not end in whitespace', () {
      final m = mergeDictation(base: 'call client', insertAt: 11, recognized: 'tomorrow');
      expect(m.text, 'call client tomorrow');
      expect(m.caret, 20);
    });

    test('adds no extra space when base already ends in whitespace', () {
      final m = mergeDictation(base: 'call client ', insertAt: 12, recognized: 'tomorrow');
      expect(m.text, 'call client tomorrow');
    });

    test('splices at a mid-text caret and leaves the tail intact', () {
      final m = mergeDictation(base: 'before after', insertAt: 6, recognized: 'now');
      expect(m.text, 'before now after');
      expect(m.caret, 10);
    });

    test('clamps an out-of-range caret to the end of base', () {
      final m = mergeDictation(base: 'abc', insertAt: 99, recognized: 'def');
      expect(m.text, 'abc def');
    });

    test('caps the inserted segment at maxLength and preserves base', () {
      final m = mergeDictation(
        base: '12345',
        insertAt: 5,
        recognized: 'abcdef',
        maxLength: 8,
      );
      expect(m.text, '12345 ab');
      expect(m.text.length, 8);
    });

    test('inserts nothing when base already fills maxLength', () {
      final m = mergeDictation(
        base: '12345',
        insertAt: 5,
        recognized: 'abc',
        maxLength: 5,
      );
      expect(m.text, '12345');
      expect(m.caret, 5);
    });

    test('replaying successive partials against the same snapshot is stable', () {
      final first = mergeDictation(base: 'note:', insertAt: 5, recognized: 'buy');
      final second = mergeDictation(base: 'note:', insertAt: 5, recognized: 'buy pipe');
      expect(first.text, 'note: buy');
      expect(second.text, 'note: buy pipe');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/speech/dictation_text_merge_test.dart`
Expected: FAIL — `dictation_text_merge.dart` does not exist.

- [ ] **Step 3: Implement**

```dart
import 'package:characters/characters.dart';

/// Result of splicing dictated text into a field snapshot.
typedef DictationMerge = ({String text, int caret});

/// Splices [recognized] into [base] at [insertAt] (the caret captured when
/// dictation started). Each partial result replays against the same snapshot,
/// so calling this repeatedly with growing [recognized] is stable.
///
/// Adds a separating space when the character before the splice point is not
/// whitespace. [maxLength] caps the inserted segment (grapheme-counted, like
/// TextField.maxLength) while always preserving [base] intact.
DictationMerge mergeDictation({
  required String base,
  required int insertAt,
  required String recognized,
  int? maxLength,
}) {
  final at = insertAt.clamp(0, base.length);
  var segment = recognized;
  if (segment.isNotEmpty && at > 0 && base[at - 1].trim().isNotEmpty) {
    segment = ' $segment';
  }
  if (maxLength != null) {
    final allowed = maxLength - base.characters.length;
    segment = allowed <= 0
        ? ''
        : segment.characters.take(allowed).toString();
  }
  final text = base.substring(0, at) + segment + base.substring(at);
  return (text: text, caret: at + segment.length);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/core/speech/dictation_text_merge_test.dart`
Expected: all 8 PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/speech/dictation_text_merge.dart test/core/speech/dictation_text_merge_test.dart
git commit -m "feat: pure dictation text merge with caret splice and maxLength cap"
```

---

### Task 4: `MediaPermissionService.ensureMicrophone()`

**Files:**
- Modify: `lib/core/permissions/media_permission_service.dart`

`permission_handler`'s static `Permission.microphone.request()` is a method-channel call — `ensureCamera` has no unit test for the same reason; this mirrors it exactly and is device-verified (Task 9). On iOS, `speech_to_text` needs BOTH microphone and speech-recognition grants; `Permission.speech` maps to nothing on Android, so gate it with `Platform.isIOS` (capability check — the sanctioned non-`isCupertino` case, same as `AddressMapLauncher`).

- [ ] **Step 1: Implement**

Add to the class body after `ensureCamera()` (and add `import 'dart:io';` as the first import):

```dart
  /// Microphone + (iOS-only) speech recognition, gated for dictation.
  Future<MediaPermissionResult> ensureMicrophone() async {
    final results = <PermissionStatus>[await Permission.microphone.request()];
    if (Platform.isIOS) {
      results.add(await Permission.speech.request());
    }
    if (results.any((s) => s.isPermanentlyDenied || s.isRestricted)) {
      return MediaPermissionResult.permanentlyDenied;
    }
    if (results.every((s) => s.isGranted || s.isLimited)) {
      return MediaPermissionResult.granted;
    }
    return MediaPermissionResult.denied;
  }
```

- [ ] **Step 2: Verify + commit**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"` — expected clean.

```bash
git add lib/core/permissions/media_permission_service.dart
git commit -m "feat: microphone and speech permission gate in MediaPermissionService"
```

---

### Task 5: `DictationService` (TDD)

**Files:**
- Create: `lib/core/speech/dictation_service.dart`
- Test: `test/core/speech/dictation_service_test.dart`
- Modify (dev deps): `pubspec.yaml` — confirm `mocktail` is present in dev_dependencies; if absent, add `mocktail: ^1.0.4` and re-run `flutter pub get` (sandbox off).

Plain class, optional injected deps (`SpeechToText`, `AppLogger`) per the `AuthService` pattern. Invariants: lazy one-time `initialize`; ONE active session (starting a new one cancels the old and fires its `onSessionEnded`); plugin failures return `false`/log — never throw raw platform errors to UI.

- [ ] **Step 1: Write the failing tests**

```dart
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
    await service.start(onResult: (_, {required isFinal}) {}, onSessionEnded: () {});
    await service.start(onResult: (_, {required isFinal}) {}, onSessionEnded: () {});
    verify(
      () => speech.initialize(
        onError: any(named: 'onError'),
        onStatus: any(named: 'onStatus'),
      ),
    ).called(1);
  });

  test('starting while another session is live cancels it and ends the old session', () async {
    var firstEnded = false;
    await service.start(
      onResult: (_, {required isFinal}) {},
      onSessionEnded: () => firstEnded = true,
    );
    when(() => speech.isListening).thenReturn(true);
    await service.start(onResult: (_, {required isFinal}) {}, onSessionEnded: () {});
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/speech/dictation_service_test.dart`
Expected: FAIL — `dictation_service.dart` does not exist.

- [ ] **Step 3: Implement**

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Field-level dictation over the platform speech recognizer.
///
/// One session at a time: starting a new session cancels the previous one and
/// fires its onSessionEnded. Injectable deps for tests (AuthService pattern).
class DictationService {
  DictationService({SpeechToText? speech, AppLogger? logger})
    : _speech = speech ?? SpeechToText(),
      _logger = logger ?? AppLogger();

  final SpeechToText _speech;
  final AppLogger _logger;

  bool? _available;
  VoidCallback? _onSessionEnded;

  Future<bool> _ensureInitialized() async {
    if (_available != null) return _available!;
    try {
      _available = await _speech.initialize(
        onError: _handleError,
        onStatus: _handleStatus,
      );
    } catch (e, st) {
      _logger.warn('DICTATE initialize failed', e, st);
      _available = false;
    }
    return _available!;
  }

  /// Speech locale matching the app language, or null for the system default.
  Future<String?> localeIdFor(String languageCode) async {
    if (!await _ensureInitialized()) return null;
    try {
      final locales = await _speech.locales();
      for (final locale in locales) {
        if (locale.localeId.startsWith(languageCode)) return locale.localeId;
      }
    } catch (e, st) {
      _logger.warn('DICTATE locales lookup failed', e, st);
    }
    return null;
  }

  /// Starts listening; partial results stream through [onResult] with the full
  /// utterance so far. Returns false when the recognizer is unavailable.
  Future<bool> start({
    required void Function(String recognized, {required bool isFinal}) onResult,
    required VoidCallback onSessionEnded,
    String? localeId,
  }) async {
    if (!await _ensureInitialized()) return false;
    try {
      if (_speech.isListening) await _speech.cancel();
      _onSessionEnded?.call();
      _onSessionEnded = onSessionEnded;
      await _speech.listen(
        onResult: (result) =>
            onResult(result.recognizedWords, isFinal: result.finalResult),
        listenOptions: SpeechListenOptions(localeId: localeId),
      );
      return true;
    } catch (e, st) {
      _logger.warn('DICTATE listen failed', e, st);
      _onSessionEnded = null;
      return false;
    }
  }

  Future<void> stop() => _speech.stop();

  void _handleStatus(String status) {
    // A stale notListening can arrive just after a new listen() starts (from
    // cancelling the previous session) - the isListening guard ignores it.
    if (_speech.isListening) return;
    if (status == 'done' || status == 'notListening') {
      final ended = _onSessionEnded;
      _onSessionEnded = null;
      ended?.call();
    }
  }

  void _handleError(SpeechRecognitionError error) {
    _logger.warn('DICTATE recognizer error ${error.errorMsg}');
  }
}

final dictationServiceProvider = Provider<DictationService>(
  (ref) => DictationService(),
);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/core/speech/dictation_service_test.dart`
Expected: all 5 PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/speech/dictation_service.dart test/core/speech/dictation_service_test.dart pubspec.yaml pubspec.lock
git commit -m "feat: DictationService wrapping speech_to_text with single-session invariant"
```

---

### Task 6: `DictationMicButton` widget (TDD)

**Files:**
- Create: `lib/shared/widgets/fields/dictation_mic_button.dart`
- Test: `test/shared/widgets/fields/dictation_mic_button_test.dart`

Suffix-slot sibling of `ClearTextButton` (same 16px IconButton styling). Idle = `Icons.mic_none` in `scheme.onSurfaceVariant`; listening = `Icons.mic` in `scheme.primary` (icon shape AND color change — color is never the sole indicator; no continuous animation, so no `disableAnimationsOf` handling needed). Follows the submit-reentrancy rule: the in-flight flag is set synchronously before the first await.

- [ ] **Step 1: Write the failing tests**

```dart
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

  setUp(() {
    permissions = _MockPermissions();
    dictation = _MockDictation();
    notices = _MockNotices();
    controller = TextEditingController();
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

  testWidgets('denied permission surfaces a notice and never starts listening',
      (tester) async {
    when(() => permissions.ensureMicrophone())
        .thenAnswer((_) async => MediaPermissionResult.denied);
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
  });

  testWidgets('granted permission starts a session and shows the listening icon',
      (tester) async {
    when(() => permissions.ensureMicrophone())
        .thenAnswer((_) async => MediaPermissionResult.granted);
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
  });

  testWidgets('failed start surfaces the unavailable notice and stays idle',
      (tester) async {
    when(() => permissions.ensureMicrophone())
        .thenAnswer((_) async => MediaPermissionResult.granted);
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
```

(If `noticeServiceProvider` is not a plain `Provider<NoticeService>` that supports `overrideWithValue`, check `lib/core/notices/notice_service.dart` and override however the existing notice tests do it — search `test/` for `noticeServiceProvider.override` and copy that harness.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/shared/widgets/fields/dictation_mic_button_test.dart`
Expected: FAIL — `dictation_mic_button.dart` does not exist.

- [ ] **Step 3: Implement**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/permissions/media_permission_service.dart';
import 'package:scheduling/core/speech/dictation_service.dart';
import 'package:scheduling/core/speech/dictation_text_merge.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Suffix-slot dictation mic for a text field. Tapping it (after the
/// microphone permission gate) streams live speech into [controller] at the
/// caret captured when dictation started; tapping again stops.
class DictationMicButton extends ConsumerStatefulWidget {
  const DictationMicButton({
    required this.controller,
    super.key,
    this.onChanged,
    this.maxLength,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final int? maxLength;

  @override
  ConsumerState<DictationMicButton> createState() =>
      _DictationMicButtonState();
}

class _DictationMicButtonState extends ConsumerState<DictationMicButton> {
  bool _isListening = false;
  bool _isStarting = false;
  String _baseText = '';
  int _insertAt = 0;

  @override
  void dispose() {
    if (_isListening) ref.read(dictationServiceProvider).stop();
    super.dispose();
  }

  Future<void> _start() async {
    if (_isStarting) return;
    _isStarting = true;
    try {
      final permission =
          await ref.read(mediaPermissionServiceProvider).ensureMicrophone();
      if (!mounted) return;
      if (permission != MediaPermissionResult.granted) {
        ref
            .read(noticeServiceProvider)
            .error(
              permission == MediaPermissionResult.permanentlyDenied
                  ? context.l10n.error_microphonePermissionPermanentlyDenied
                  : context.l10n.error_microphonePermissionDenied,
            );
        return;
      }
      final service = ref.read(dictationServiceProvider);
      final localeId = await service
          .localeIdFor(Localizations.localeOf(context).languageCode);
      if (!mounted) return;
      _baseText = widget.controller.text;
      final selection = widget.controller.selection;
      _insertAt = selection.isValid ? selection.end : _baseText.length;
      final started = await service.start(
        localeId: localeId,
        onResult: _applyResult,
        onSessionEnded: _handleSessionEnded,
      );
      if (!mounted) return;
      if (!started) {
        ref
            .read(noticeServiceProvider)
            .error(context.l10n.error_dictationUnavailable);
        return;
      }
      setState(() => _isListening = true);
    } finally {
      _isStarting = false;
    }
  }

  Future<void> _stop() => ref.read(dictationServiceProvider).stop();

  void _applyResult(String recognized, {required bool isFinal}) {
    final merged = mergeDictation(
      base: _baseText,
      insertAt: _insertAt,
      recognized: recognized,
      maxLength: widget.maxLength,
    );
    widget.controller.value = TextEditingValue(
      text: merged.text,
      selection: TextSelection.collapsed(offset: merged.caret),
    );
    widget.onChanged?.call(merged.text);
  }

  void _handleSessionEnded() {
    if (mounted) setState(() => _isListening = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(
        _isListening ? Icons.mic : Icons.mic_none,
        size: 16,
        color: _isListening ? scheme.primary : scheme.onSurfaceVariant,
      ),
      tooltip: _isListening
          ? context.l10n.common_stopDictation
          : context.l10n.common_dictate,
      onPressed: _isListening ? _stop : _start,
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/shared/widgets/fields/dictation_mic_button_test.dart`
Expected: all 4 PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/fields/dictation_mic_button.dart test/shared/widgets/fields/dictation_mic_button_test.dart
git commit -m "feat: DictationMicButton suffix widget with live merge into the controller"
```

---

### Task 7: `LabeledTextField.enableDictation` (TDD)

**Files:**
- Modify: `lib/shared/widgets/fields/labeled_text_field.dart` (constructor + fields + suffix logic at lines 87-94)
- Test: `test/shared/widgets/fields/labeled_text_field_dictation_test.dart`

Opt-in flag, default false — every existing call site renders byte-for-byte identically (and stays Riverpod-free; only `enableDictation: true` introduces the ConsumerWidget, so only those tests need a `ProviderScope`).

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/clear_text_button.dart';
import 'package:scheduling/shared/widgets/fields/dictation_mic_button.dart';
import 'package:scheduling/shared/widgets/fields/labeled_text_field.dart';

void main() {
  late TextEditingController controller;

  setUp(() => controller = TextEditingController());
  tearDown(() => controller.dispose());

  Widget harness(Widget child) => ProviderScope(
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  testWidgets('enableDictation shows the mic AND keeps the clear button',
      (tester) async {
    await tester.pumpWidget(
      harness(
        LabeledTextField(
          label: 'Notes',
          controller: controller,
          enableDictation: true,
        ),
      ),
    );
    expect(find.byType(DictationMicButton), findsOneWidget);
    expect(find.byType(ClearTextButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('default field has no mic', (tester) async {
    await tester.pumpWidget(
      harness(LabeledTextField(label: 'Name', controller: controller)),
    );
    expect(find.byType(DictationMicButton), findsNothing);
    expect(find.byType(ClearTextButton), findsOneWidget);
  });

  testWidgets('readOnly field has no mic even with enableDictation',
      (tester) async {
    await tester.pumpWidget(
      harness(
        LabeledTextField(
          label: 'Picker',
          controller: controller,
          readOnly: true,
          enableDictation: true,
        ),
      ),
    );
    expect(find.byType(DictationMicButton), findsNothing);
  });

  testWidgets('a custom suffixIcon wins over dictation', (tester) async {
    await tester.pumpWidget(
      harness(
        LabeledTextField(
          label: 'Custom',
          controller: controller,
          enableDictation: true,
          suffixIcon: const Icon(Icons.search),
        ),
      ),
    );
    expect(find.byType(DictationMicButton), findsNothing);
    expect(find.byIcon(Icons.search), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/shared/widgets/fields/labeled_text_field_dictation_test.dart`
Expected: FAIL — `enableDictation` is not a parameter.

- [ ] **Step 3: Implement**

In `labeled_text_field.dart`: add the import, the constructor param `this.enableDictation = false,` (after `this.focusNode,`), the field `final bool enableDictation;`, and replace the suffix expression (currently lines 87-94):

```dart
import 'package:scheduling/shared/widgets/fields/dictation_mic_button.dart';
```

```dart
              // Every editable field gets a clear "x" while it holds text;
              // a custom suffix or a readOnly (picker) field keeps its own.
              // enableDictation prepends a mic without displacing the "x".
              suffixIcon: suffixIcon ?? _defaultSuffix(),
```

And a private helper after `build()` (public API first, then private helpers — repo convention):

```dart
  Widget? _defaultSuffix() {
    if (readOnly) return null;
    final clear = ClearTextButton(
      controller: controller,
      onCleared: () => onChanged?.call(''),
    );
    if (!enableDictation) return clear;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DictationMicButton(
          controller: controller,
          onChanged: onChanged,
          maxLength: maxLength,
        ),
        clear,
      ],
    );
  }
```

- [ ] **Step 4: Run the new tests AND the existing field/form suites**

Run: `flutter test test/shared/widgets/fields/`
Expected: all PASS (existing `LabeledTextField`-consuming tests unaffected).

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/fields/labeled_text_field.dart test/shared/widgets/fields/labeled_text_field_dictation_test.dart
git commit -m "feat: opt-in enableDictation suffix on LabeledTextField"
```

---

### Task 8: Enable on Notes + Materials

**Files:**
- Modify: `lib/features/calendar/widgets/sections/appointment_form_fields.dart:298-322`

- [ ] **Step 1: Add the flag to both fields**

Notes (lines 299-308) — add one line:

```dart
          child: LabeledTextField(
            label: l10n.calendar_notes,
            hint: l10n.calendar_typeTheNoteHere,
            controller: controllers.notes,
            optional: true,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 2,
            maxLength: TextLimits.appointmentNotes,
            showCounter: true,
            enableDictation: true,
          ),
```

Materials (lines 313-321) — same addition:

```dart
          child: LabeledTextField(
            label: l10n.calendar_materialsNeeded,
            hint: materialsHint,
            controller: controllers.materials,
            optional: true,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 2,
            maxLength: TextLimits.appointmentMaterials,
            enableDictation: true,
          ),
```

- [ ] **Step 2: Run the calendar widget tests**

Run: `flutter test test/features/calendar/`
Expected: all PASS (the appointment form tests run inside a `ProviderScope` already; if any fail on a missing provider scope, wrap that test's harness in `ProviderScope` the way the other calendar tests do).

- [ ] **Step 3: Commit**

```bash
git add lib/features/calendar/widgets/sections/appointment_form_fields.dart
git commit -m "feat: dictation mic on appointment notes and materials fields"
```

---

### Task 9: Full verification

- [ ] **Step 1: Analyzer**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"`
Expected: no output.

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: all green (742+ existing tests plus the ~17 new ones).

- [ ] **Step 3: BOM scan on new/modified dart files**

Run (Bash): `for f in lib/core/speech/*.dart lib/shared/widgets/fields/dictation_mic_button.dart; do head -c 3 "$f" | od -An -tx1; done`
Expected: no `ef bb bf` lines.

- [ ] **Step 4: Device verification (Android dev device, method-channel plugin — same class as ImagePickerService, cannot be unit-tested)**

Via `flutter run` on the device:
1. Open an appointment form → Notes field → tap the mic → grant the permission prompt → speak → text appears live → tap mic again to stop → edit the text manually → save the appointment.
2. Deny the permission on a fresh install (`adb shell pm clear net.vogas.scheduling` first; note this regenerates the App Check debug token — re-register it in Firebase Console) → tapping the mic shows the top-slide error notice.
3. Start dictation on Notes, then tap the mic on Materials → the Notes session ends (icon reverts), Materials session runs.
4. Dictate past the Notes maxLength → text stops at the cap, counter shows the limit warning, no crash.
5. Switch the app language to French → dictate → French recognition is used.

Caveats: Android **emulators** often have no recognizer (`initialize` returns false → "Dictation is not available" notice — that is correct behavior, not a bug). iOS behavior (App Attest device, `NSSpeechRecognitionUsageDescription` prompt, `autoPunctuation`) verifies on the Mac per `docs/plans/IOS_APP_STORE_HANDOFF.md`.

- [ ] **Step 5: Docs**

Add a one-line note to `docs/ARCHITECTURE.md` (if it lists core services) and a CLAUDE.md bullet under Conventions: dictation goes through `DictationService` / `DictationMicButton`; never call `speech_to_text` directly from UI; the mic is opt-in via `LabeledTextField(enableDictation: true)`.

---

## Self-review notes

- Spec coverage: in-app mic (T6), notes-only scope (T8), live partials (T3+T6), permission gate + notices (T4+T6), platform config (T1), EN/FR (T2+locale mapping in T5). ✓
- Type consistency: `mergeDictation` record `({String text, int caret})` used identically in T3 and T6; `onResult(String, {required bool isFinal})` matches between T5 service and T6 button. ✓
- Known judgment calls an implementer may adjust: the exact `noticeServiceProvider` override mechanics in T6 tests (copy the existing notice-test harness), and FR apostrophe style in T2 (match the file).
