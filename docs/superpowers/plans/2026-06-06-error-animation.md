# Animated + Debuggable Error Handling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Field errors shake + fade-slide in app-wide via `LabeledTextField`, and every generic "Something went wrong" notice becomes "{intro} — {cause}. ({TAG})" with the tag mirrored into the Crashlytics log label.

**Architecture:** Animation is baked into the shared `LabeledTextField` (shake via a rewritten `AnimatedFormFieldWrapper`, error-row entrance via `AnimatedSize` + `AnimatedSwitcher`), so all forms get it with no call-site changes. Message quality comes from a new `lib/core/errors/error_cause.dart` (classifier + composer) applied at 13 catch/error sites.

**Tech Stack:** Flutter 3.44 / Dart 3.12, Riverpod 3 (manual providers), gen_l10n (EN template + FR), `flutter_test`. The wrapper's `flutter_animate` dependency is replaced with a plain `AnimationController` (no remount → keyboard focus survives the shake; fixes the autoplay-on-mount bug by construction).

**Spec:** `docs/superpowers/specs/2026-06-06-error-animation-design.md`

**Discoveries that refine the spec (verified in code):**
- `EventDetailsFailed` and `AddEventFailed` **already carry** `final Object error` — views just don't destructure it. No outcome-class change needed.
- `EventDetailsController.deleteAppointment` returns `bool` and swallows the error → change it to `Future<Object?>` (null = success) so APPT-DEL can classify the cause. Two call sites.
- `employee_form_sheet`'s catch covers **both** create and edit → intro key is `error_introSaveEmployee` ("Couldn't save the employee"); tag stays `EMP-CREATE` per spec.
- flutter_animate's `shakeX(duration: 320.ms, hz: 3, amount: 6)` computes `count = round(0.32*3) = 1` → **one** sine cycle of ±6px. The rewritten wrapper mirrors exactly that: `dx = sin(t·2π) · 6`.

**Project rules that bind every task:** analyzer must stay at 0 issues; ARB keys need `@key` metadata in EN (FR stays bare); FR strings use the curly apostrophe `’` and literal accents — NEVER `\uXXXX` escapes (the editor mangles them); `flutter gen-l10n` after ARB edits; commit after each task.

---

## File map

| File | Action | Responsibility |
|---|---|---|
| `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb` | Modify | 18 new keys: 1 template, 4 causes, 13 intros |
| `lib/core/errors/error_cause.dart` | Create | `ErrorCause` enum, `classifyError`, `composeErrorNotice` |
| `test/core/errors/error_cause_test.dart` | Create | classifier + composer unit tests |
| `lib/core/animations/animated_form_field_wrapper.dart` | Rewrite | controller-based shake; no autoplay; reduced-motion aware |
| `test/core/animations/animated_form_field_wrapper_test.dart` | Create | shake-on-transition, no-shake-on-mount, reduced-motion |
| `lib/shared/widgets/fields/labeled_text_field.dart` | Modify | wrap TextField in wrapper; `_AnimatedFieldError` slot |
| `test/shared/widgets/fields/labeled_text_field_test.dart` | Modify | error-row in/out animation tests |
| `lib/features/calendar/application/event_details_controller.dart` | Modify | `deleteAppointment` → `Object?`; tagged warn labels |
| `lib/features/calendar/application/add_event_controller.dart` | Modify | tagged warn label |
| `test/features/calendar/application/event_details_delete_test.dart` | Create | delete returns the thrown error |
| 9 UI files (see Tasks 6–8) | Modify | compose cause+tag messages |

---

### Task 1: l10n keys

**Files:**
- Modify: `lib/l10n/app_en.arb` (insert before the final `}`; the current last key is `error_couldNotDeleteAccount` ~line 1101 — add a trailing comma to its `@` block)
- Modify: `lib/l10n/app_fr.arb` (same position; FR keys are bare, no `@` blocks)

- [ ] **Step 1: Add EN keys** — append inside the top-level object:

```json
  "error_noticeWithCause": "{intro} — {cause}. ({tag})",
  "@error_noticeWithCause": {
    "description": "Error-notice template: operation intro, sanitized cause, short tag matching the Crashlytics log label",
    "placeholders": {
      "intro": {"type": "String"},
      "cause": {"type": "String"},
      "tag": {"type": "String"}
    }
  },
  "error_causeOffline": "you appear to be offline",
  "@error_causeOffline": {"description": "Sanitized error cause: network/offline"},
  "error_causePermissionDenied": "you don't have permission to do this",
  "@error_causePermissionDenied": {"description": "Sanitized error cause: permission denied"},
  "error_causeNotFound": "it no longer exists",
  "@error_causeNotFound": {"description": "Sanitized error cause: document not found"},
  "error_causeUnknown": "something went wrong",
  "@error_causeUnknown": {"description": "Sanitized error cause: fallback"},
  "error_introDeleteEmployee": "Couldn't delete the employee",
  "@error_introDeleteEmployee": {"description": "Error intro for EMP-DEL"},
  "error_introChangeEmployeeStatus": "Couldn't update the employee's account status",
  "@error_introChangeEmployeeStatus": {"description": "Error intro for EMP-STATUS"},
  "error_introSaveEmployee": "Couldn't save the employee",
  "@error_introSaveEmployee": {"description": "Error intro for EMP-CREATE (covers create and edit)"},
  "error_introCreateAppointment": "Couldn't create the appointment",
  "@error_introCreateAppointment": {"description": "Error intro for APPT-CREATE"},
  "error_introSaveAppointment": "Couldn't save the appointment changes",
  "@error_introSaveAppointment": {"description": "Error intro for APPT-SAVE"},
  "error_introDeleteAppointment": "Couldn't delete the appointment",
  "@error_introDeleteAppointment": {"description": "Error intro for APPT-DEL"},
  "error_introLoadAppointments": "Couldn't load appointments",
  "@error_introLoadAppointments": {"description": "Error intro for APPT-LOAD"},
  "error_introDeleteAccount": "Couldn't delete your account",
  "@error_introDeleteAccount": {"description": "Error intro for ACCT-DEL"},
  "error_introAddClient": "Couldn't add the client",
  "@error_introAddClient": {"description": "Error intro for CLI-ADD"},
  "error_introSaveClient": "Couldn't save the client changes",
  "@error_introSaveClient": {"description": "Error intro for CLI-SAVE"},
  "error_introDeleteClient": "Couldn't delete the client",
  "@error_introDeleteClient": {"description": "Error intro for CLI-DEL"},
  "error_introLoadHistory": "Couldn't load the appointment history",
  "@error_introLoadHistory": {"description": "Error intro for HIST-LOAD"},
  "error_introLoadClients": "Couldn't load clients",
  "@error_introLoadClients": {"description": "Error intro for CLI-LIST"}
```

- [ ] **Step 2: Add FR keys** (bare; literal accents and `’`, never `\u` escapes):

```json
  "error_noticeWithCause": "{intro} — {cause}. ({tag})",
  "error_causeOffline": "vous semblez être hors ligne",
  "error_causePermissionDenied": "vous n’avez pas la permission de faire ceci",
  "error_causeNotFound": "l’élément n’existe plus",
  "error_causeUnknown": "une erreur s’est produite",
  "error_introDeleteEmployee": "Impossible de supprimer l’employé",
  "error_introChangeEmployeeStatus": "Impossible de modifier le statut du compte de l’employé",
  "error_introSaveEmployee": "Impossible d’enregistrer l’employé",
  "error_introCreateAppointment": "Impossible de créer le rendez-vous",
  "error_introSaveAppointment": "Impossible d’enregistrer les modifications du rendez-vous",
  "error_introDeleteAppointment": "Impossible de supprimer le rendez-vous",
  "error_introLoadAppointments": "Impossible de charger les rendez-vous",
  "error_introDeleteAccount": "Impossible de supprimer votre compte",
  "error_introAddClient": "Impossible d’ajouter le client",
  "error_introSaveClient": "Impossible d’enregistrer les modifications du client",
  "error_introDeleteClient": "Impossible de supprimer le client",
  "error_introLoadHistory": "Impossible de charger l’historique des rendez-vous",
  "error_introLoadClients": "Impossible de charger les clients"
```

- [ ] **Step 3: Regenerate and verify**

Run: `flutter gen-l10n`
Expected: exit 0. Then check `lib/l10n/.gen/untranslated.json` — must be empty/`{}`. The generated method is `String error_noticeWithCause(String intro, String cause, String tag)` (positional, declaration order).

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_fr.arb
git commit -m "feat(l10n): error cause + operation tag keys"
```

---

### Task 2: `error_cause.dart` (TDD)

**Files:**
- Create: `lib/core/errors/error_cause.dart`
- Create: `test/core/errors/error_cause_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/errors/error_cause.dart';

FirebaseException _fb(String code) =>
    FirebaseException(plugin: 'cloud_firestore', code: code);

void main() {
  group('classifyError', () {
    test('network-ish Firebase codes map to offline', () {
      expect(classifyError(_fb('unavailable')), ErrorCause.offline);
      expect(classifyError(_fb('network-request-failed')), ErrorCause.offline);
      expect(classifyError(_fb('deadline-exceeded')), ErrorCause.offline);
    });

    test('permission-denied maps to permissionDenied', () {
      expect(classifyError(_fb('permission-denied')), ErrorCause.permissionDenied);
    });

    test('not-found maps to notFound', () {
      expect(classifyError(_fb('not-found')), ErrorCause.notFound);
    });

    test('socket and timeout exceptions map to offline', () {
      expect(classifyError(const SocketException('x')), ErrorCause.offline);
      expect(classifyError(TimeoutException('x')), ErrorCause.offline);
    });

    test('anything else maps to unknown', () {
      expect(classifyError(Exception('boom')), ErrorCause.unknown);
      expect(classifyError(_fb('aborted')), ErrorCause.unknown);
    });
  });

  group('composeErrorNotice', () {
    testWidgets('formats intro, cause, and tag', (tester) async {
      late String message;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              message = composeErrorNotice(
                context,
                intro: 'Couldn\'t delete the client',
                tag: 'CLI-DEL',
                error: _fb('unavailable'),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(
        message,
        'Couldn\'t delete the client — you appear to be offline. (CLI-DEL)',
      );
    });
  });
}
```

Add `import 'package:scheduling/l10n/l10n.dart';` to the test imports (for `AppLocalizations`).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/errors/error_cause_test.dart`
Expected: FAIL — `error_cause.dart` does not exist / `classifyError` undefined.

- [ ] **Step 3: Write the implementation**

```dart
import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import 'package:scheduling/l10n/l10n.dart';

/// Sanitized error categories safe to surface in UI text.
/// Raw Firebase codes and stack traces must never reach the UI (security.md);
/// full detail still goes to Crashlytics via the catch site's logger.warn.
enum ErrorCause { offline, permissionDenied, notFound, unknown }

ErrorCause classifyError(Object error) {
  if (error is FirebaseException) {
    return switch (error.code) {
      'unavailable' || 'network-request-failed' || 'deadline-exceeded' =>
        ErrorCause.offline,
      'permission-denied' => ErrorCause.permissionDenied,
      'not-found' => ErrorCause.notFound,
      _ => ErrorCause.unknown,
    };
  }
  if (error is SocketException || error is TimeoutException) {
    return ErrorCause.offline;
  }
  return ErrorCause.unknown;
}

/// "{intro} — {cause}. ({tag})". The tag must match the prefix of the
/// catch site's logger.warn label so user reports map to Crashlytics lines.
String composeErrorNotice(
  BuildContext context, {
  required String intro,
  required String tag,
  required Object error,
}) {
  final l10n = context.l10n;
  final cause = switch (classifyError(error)) {
    ErrorCause.offline => l10n.error_causeOffline,
    ErrorCause.permissionDenied => l10n.error_causePermissionDenied,
    ErrorCause.notFound => l10n.error_causeNotFound,
    ErrorCause.unknown => l10n.error_causeUnknown,
  };
  return l10n.error_noticeWithCause(intro, cause, tag);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/errors/error_cause_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/errors/error_cause.dart test/core/errors/error_cause_test.dart
git commit -m "feat(errors): sanitized cause classifier + tagged notice composer"
```

---

### Task 3: Rewrite `AnimatedFormFieldWrapper` (TDD)

**Files:**
- Rewrite: `lib/core/animations/animated_form_field_wrapper.dart`
- Create: `test/core/animations/animated_form_field_wrapper_test.dart`

Why a rewrite: the current flutter_animate version (a) autoplays a shake on first build, and (b) replays via a changed `key`, which remounts the subtree and would drop keyboard focus once `LabeledTextField` uses it. A plain `AnimationController` + `Transform.translate` keeps the element tree stable and only animates on error transitions. Public API (`child`, `hasError`) is unchanged — auth call sites keep compiling.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/animations/animated_form_field_wrapper.dart';

double _shakeDx(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find
        .descendant(
          of: find.byType(AnimatedFormFieldWrapper),
          matching: find.byType(Transform),
        )
        .first,
  );
  return transform.transform.getTranslation().x;
}

Widget _host({required bool hasError, bool disableAnimations = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: AnimatedFormFieldWrapper(
        hasError: hasError,
        child: const SizedBox(width: 120, height: 40),
      ),
    ),
  );
}

void main() {
  testWidgets('does not shake on first build, even with an error', (
    tester,
  ) async {
    await tester.pumpWidget(_host(hasError: true));
    await tester.pump(const Duration(milliseconds: 80));
    expect(_shakeDx(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shakes when hasError flips false to true, then settles', (
    tester,
  ) async {
    await tester.pumpWidget(_host(hasError: false));
    await tester.pumpWidget(_host(hasError: true));
    await tester.pump(const Duration(milliseconds: 80));
    expect(_shakeDx(tester), isNot(0));

    await tester.pumpAndSettle();
    expect(_shakeDx(tester).abs(), lessThan(0.001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion disables the shake', (tester) async {
    await tester.pumpWidget(_host(hasError: false, disableAnimations: true));
    await tester.pumpWidget(_host(hasError: true, disableAnimations: true));
    await tester.pump(const Duration(milliseconds: 80));
    expect(_shakeDx(tester), 0);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/animations/animated_form_field_wrapper_test.dart`
Expected: FAIL — first test fails (current version autoplays: dx ≠ 0 at 80ms).

- [ ] **Step 3: Replace the file's entire contents**

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shakes [child] horizontally when [hasError] flips from false to true.
/// One sine cycle of ±6px over 320ms — same motion as the previous
/// flutter_animate shakeX(duration: 320.ms, hz: 3, amount: 6).
class AnimatedFormFieldWrapper extends StatefulWidget {
  const AnimatedFormFieldWrapper({
    required this.child,
    super.key,
    this.hasError = false,
  });

  final Widget child;
  final bool hasError;

  @override
  State<AnimatedFormFieldWrapper> createState() =>
      _AnimatedFormFieldWrapperState();
}

class _AnimatedFormFieldWrapperState extends State<AnimatedFormFieldWrapper>
    with SingleTickerProviderStateMixin {
  static const double _amount = 6;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void didUpdateWidget(covariant AnimatedFormFieldWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasError &&
        !oldWidget.hasError &&
        !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.translate(
        offset: Offset(math.sin(_controller.value * math.pi * 2) * _amount, 0),
        child: child,
      ),
      child: widget.child,
    );
  }
}
```

- [ ] **Step 4: Run tests + the auth scale-sweep suite (wrapper consumers)**

Run: `flutter test test/core/animations/animated_form_field_wrapper_test.dart test/features/auth/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/animations/animated_form_field_wrapper.dart test/core/animations/animated_form_field_wrapper_test.dart
git commit -m "fix(animations): shake only on error transitions; keep element tree stable"
```

---

### Task 4: Animated error slot in `LabeledTextField` (TDD)

**Files:**
- Modify: `lib/shared/widgets/fields/labeled_text_field.dart`
- Modify: `test/shared/widgets/fields/labeled_text_field_test.dart`

- [ ] **Step 1: Add the failing tests** (append inside `main()`; the file's `_wrap` helper already provides l10n delegates):

```dart
  testWidgets('error row animates in when errorText is set', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String? errorText;
    late StateSetter setError;

    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) {
            setError = setState;
            return LabeledTextField(
              label: 'Phone',
              controller: controller,
              errorText: errorText,
            );
          },
        ),
      ),
    );
    expect(find.text('Required'), findsNothing);

    setError(() => errorText = 'Required');
    await tester.pumpAndSettle();

    expect(find.text('Required'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('error row animates out when errorText clears', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String? errorText = 'Required';
    late StateSetter setError;

    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) {
            setError = setState;
            return LabeledTextField(
              label: 'Phone',
              controller: controller,
              errorText: errorText,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsOneWidget);

    setError(() => errorText = null);
    await tester.pumpAndSettle();

    expect(find.text('Required'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('field mounted with an error shows it and does not throw', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _wrap(
        LabeledTextField(
          label: 'Phone',
          controller: controller,
          errorText: 'Required',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Required'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
```

- [ ] **Step 2: Run to verify the new tests fail**

Run: `flutter test test/shared/widgets/fields/labeled_text_field_test.dart`
Expected: the two "animates" tests FAIL (errors currently appear/disappear without the animated slot — the *in* test may pass trivially; the structural change is verified by all tests passing after Step 3 with the new widgets in the tree). If all three pass before the change, proceed — they pin behavior during the refactor.

- [ ] **Step 3: Modify `labeled_text_field.dart`**

Add imports (package group, alphabetical):

```dart
import 'package:scheduling/core/animations/animated_form_field_wrapper.dart';
import 'package:scheduling/core/animations/app_animation_constants.dart';
```

In `build()`, wrap the `TextField` and replace the error row:

```dart
        AnimatedFormFieldWrapper(
          hasError: errorText != null,
          child: TextField(
            // ... existing TextField arguments unchanged ...
          ),
        ),
        if (showCounter && maxLength != null)
          _MaxLengthWarning(controller: controller, maxLength: maxLength!),
        _AnimatedFieldError(message: errorText),
```

(The old line was `if (errorText != null) _FieldError(errorText!),` — delete it.)

Replace `_MaxLengthWarning`'s builder body:

```dart
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => _AnimatedFieldError(
        // Grapheme count matches what TextField.maxLength enforces.
        message: value.text.characters.length < maxLength
            ? null
            : context.l10n.validation_maximumCharacterLimitReached,
      ),
    );
```

Add the animated slot widget and give `_FieldError` a key parameter:

```dart
// Fade + 4px slide entrance/exit for the error row (style A from the spec);
// AnimatedSize lets fields below glide instead of jumping.
class _AnimatedFieldError extends StatelessWidget {
  const _AnimatedFieldError({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppAnimationDurations.quick;
    return AnimatedSize(
      duration: duration,
      curve: AppAnimationCurves.entrance,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: AppAnimationCurves.entrance,
        switchOutCurve: AppAnimationCurves.entrance,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.25),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: message == null
            ? const SizedBox.shrink()
            : _FieldError(message!, key: ValueKey(message)),
      ),
    );
  }
}
```

```dart
class _FieldError extends StatelessWidget {
  const _FieldError(this.message, {super.key});
  // ... rest unchanged ...
```

- [ ] **Step 4: Run the full file's tests**

Run: `flutter test test/shared/widgets/fields/labeled_text_field_test.dart`
Expected: PASS (all 6: 3 pre-existing counter tests + 3 new).

- [ ] **Step 5: Run the form-heavy feature suites + analyzer**

Run: `flutter test test/features/clients/ && flutter analyze`
Expected: tests PASS; `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/shared/widgets/fields/labeled_text_field.dart test/shared/widgets/fields/labeled_text_field_test.dart
git commit -m "feat(fields): shake + fade-slide error animation in LabeledTextField"
```

---

### Task 5: `deleteAppointment` surfaces its error (TDD)

**Files:**
- Modify: `lib/features/calendar/application/event_details_controller.dart:352-364`
- Modify: `lib/features/calendar/widgets/views/details_edit_body.dart:234-246` (delete flow)
- Modify: `lib/features/calendar/widgets/views/details_view_body.dart:184` (pre-ship delete button)
- Create: `test/features/calendar/application/event_details_delete_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/event_details_controller.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

class _ThrowingRepo implements AppointmentsRepository {
  @override
  Future<void> deleteAppointment(String id) async {
    throw Exception('boom');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  test('deleteAppointment returns the error when the repository throws', () async {
    final container = ProviderContainer(
      overrides: [
        appointmentsRepositoryProvider.overrideWithValue(_ThrowingRepo()),
      ],
    );
    addTearDown(container.dispose);

    final appointment = AppointmentRecord(
      id: 'a1',
      startTime: DateTime(2026, 6, 6, 9),
      endTime: DateTime(2026, 6, 6, 10),
    );
    final provider = eventDetailsControllerProvider(appointment);
    // AutoDispose family: keep state alive across reads (testing.md).
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);

    final error = await container
        .read(provider.notifier)
        .deleteAppointment(appointment);

    expect(error, isNotNull);
    expect(error.toString(), contains('boom'));
  });
}
```

If the controller's `build()` watches other providers and the test throws on read, add the corresponding override, e.g. `allUsersStreamProvider.overrideWith((ref) => Stream.value(const <EmployeeRecord>[]))` (import `employees_providers.dart` + the model). Add only what the failure message demands.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/calendar/application/event_details_delete_test.dart`
Expected: FAIL — compile error (`deleteAppointment` returns `Future<bool>`; `error.toString()` on `bool` is legal, so the failure shows as `expect(error, isNotNull)` holding `false`… the compile signal is `isNotNull` matching `false` → assertion failure "Expected: not null, Actual: <false>"). Either way: red.

- [ ] **Step 3: Change the controller method** (replace lines 352-364):

```dart
  /// Returns null on success, or the error that caused the failure.
  Future<Object?> deleteAppointment(AppointmentRecord appointment) async {
    final id = appointment.id;
    if (id == null) {
      return StateError('Cannot delete an appointment without an id.');
    }
    state = state.copyWith(isSaving: true);
    try {
      await ref.read(appointmentsRepositoryProvider).deleteAppointment(id);
      return null;
    } catch (e, st) {
      ref.read(loggerProvider).warn('APPT-DEL deleteAppointment failed', e, st);
      state = state.copyWith(isSaving: false);
      return e;
    }
  }
```

Also tag the save path while in this file — replace the `saveChanges` catch (currently `} catch (e) {` at ~line 346):

```dart
    } catch (e, st) {
      ref.read(loggerProvider).warn('APPT-SAVE saveChanges failed', e, st);
      state = state.copyWith(isSaving: false);
      return EventDetailsFailed(e);
    }
```

- [ ] **Step 4: Update the two call sites**

`details_edit_body.dart` `_confirmDelete` (currently `final ok = await notifier.deleteAppointment(appointment); ... if (ok) {...} else { ...somethingWentWrong }`):

```dart
    final error = await notifier.deleteAppointment(appointment);
    if (!context.mounted) return;
    if (error == null) {
      ref
          .read(noticeServiceProvider)
          .success(context.l10n.common_appointmentDeleted);
      onClose();
    } else {
      ref
          .read(noticeServiceProvider)
          .error(
            composeErrorNotice(
              context,
              intro: context.l10n.error_introDeleteAppointment,
              tag: 'APPT-DEL',
              error: error,
            ),
          );
    }
```

Add to `details_edit_body.dart` imports: `import 'package:scheduling/core/errors/error_cause.dart';`

`details_view_body.dart:184` (pre-ship testing button — minimal touch, keep its `TODO(pre-ship)` context):

```dart
                  if (await notifier.deleteAppointment(appointment) == null) {
```

- [ ] **Step 5: Run tests + analyzer**

Run: `flutter test test/features/calendar/ && flutter analyze`
Expected: PASS; `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/calendar/application/event_details_controller.dart lib/features/calendar/widgets/views/details_edit_body.dart lib/features/calendar/widgets/views/details_view_body.dart test/features/calendar/application/event_details_delete_test.dart
git commit -m "feat(calendar): deleteAppointment surfaces its error; APPT-DEL/APPT-SAVE tags"
```

---

### Task 6: Calendar notice sites — APPT-CREATE, APPT-SAVE, APPT-LOAD

**Files:**
- Modify: `lib/features/calendar/widgets/sheets/add_appointment_sheet.dart:178-181`
- Modify: `lib/features/calendar/application/add_event_controller.dart:257`
- Modify: `lib/features/calendar/widgets/views/details_edit_body.dart:215-219`
- Modify: `lib/features/calendar/screens/main_calendar_screen.dart` (`onAsyncChange`)

- [ ] **Step 1: APPT-CREATE.** In `add_appointment_sheet.dart`, replace:

```dart
      case AddEventFailed():
        ref
            .read(noticeServiceProvider)
            .error(context.l10n.error_somethingWentWrongCreatingTheAppointment);
```

with (note the destructure — `AddEventFailed` already has `final Object error`):

```dart
      case AddEventFailed(:final error):
        ref
            .read(noticeServiceProvider)
            .error(
              composeErrorNotice(
                context,
                intro: context.l10n.error_introCreateAppointment,
                tag: 'APPT-CREATE',
                error: error,
              ),
            );
```

Add import: `import 'package:scheduling/core/errors/error_cause.dart';`

In `add_event_controller.dart:257`, retag the warn label:

```dart
      ref.read(loggerProvider).warn('APPT-CREATE submit failed', e, st);
```

- [ ] **Step 2: APPT-SAVE.** In `details_edit_body.dart` (save outcome switch), replace:

```dart
      case EventDetailsFailed():
        ref
            .read(noticeServiceProvider)
            .error(context.l10n.error_somethingWentWrongSavingChanges);
```

with:

```dart
      case EventDetailsFailed(:final error):
        ref
            .read(noticeServiceProvider)
            .error(
              composeErrorNotice(
                context,
                intro: context.l10n.error_introSaveAppointment,
                tag: 'APPT-SAVE',
                error: error,
              ),
            );
```

(The `error_cause.dart` import was added in Task 5.)

- [ ] **Step 3: APPT-LOAD.** In `main_calendar_screen.dart`'s `onAsyncChange`, replace the `.error(context.l10n.error_couldNotLoadAppointments)` call:

```dart
      if (next is AsyncError && previous is! AsyncError) {
        ref
            .read(noticeServiceProvider)
            .error(
              composeErrorNotice(
                context,
                intro: context.l10n.error_introLoadAppointments,
                tag: 'APPT-LOAD',
                error: next.error,
              ),
            );
      }
```

Add import: `import 'package:scheduling/core/errors/error_cause.dart';`

- [ ] **Step 4: Verify**

Run: `flutter test test/features/calendar/ && flutter analyze`
Expected: PASS; `No issues found!` (If the analyzer flags `error_somethingWentWrongCreatingTheAppointment`/`error_couldNotLoadAppointments` as unused l10n getters — it doesn't, gen_l10n keys aren't linted — no action; leave the old keys in the ARBs.)

- [ ] **Step 5: Commit**

```bash
git add lib/features/calendar/ 
git commit -m "feat(calendar): cause+tag error notices (APPT-CREATE/SAVE/LOAD)"
```

---

### Task 7: Clients notice sites — CLI-ADD, CLI-SAVE, CLI-DEL, HIST-LOAD, CLI-LIST

**Files:**
- Modify: `lib/features/clients/widgets/sheets/add_client_sheet.dart:213-220`
- Modify: `lib/features/clients/widgets/views/client_detail_view.dart` (save catch ~line 235; delete catch ~line 270)
- Modify: `lib/features/clients/widgets/views/appointment_history_view.dart:46-49`
- Modify: `lib/features/clients/widgets/views/clients_list_view.dart:191-192`

All four files need: `import 'package:scheduling/core/errors/error_cause.dart';`

- [ ] **Step 1: CLI-ADD.** In `add_client_sheet.dart`'s `_save` catch, replace the warn + error lines:

```dart
    } catch (e, st) {
      ref.read(loggerProvider).warn('CLI-ADD addClient failed', e, st);
      if (!mounted) return;
      setState(() => _isSaving = false);
      ref
          .read(noticeServiceProvider)
          .error(
            composeErrorNotice(
              context,
              intro: context.l10n.error_introAddClient,
              tag: 'CLI-ADD',
              error: e,
            ),
          );
    }
```

- [ ] **Step 2: CLI-SAVE.** In `client_detail_view.dart`'s `_save` catch:

```dart
    } catch (e, st) {
      ref.read(loggerProvider).warn('CLI-SAVE updateClient failed', e, st);
      if (!mounted) return;
      ref
          .read(noticeServiceProvider)
          .error(
            composeErrorNotice(
              context,
              intro: context.l10n.error_introSaveClient,
              tag: 'CLI-SAVE',
              error: e,
            ),
          );
    }
```

- [ ] **Step 3: CLI-DEL.** In `client_detail_view.dart`'s `_confirmDelete`, the catch is currently `} catch (_) {` and does not log — replace with:

```dart
    } catch (e, st) {
      ref.read(loggerProvider).warn('CLI-DEL deleteClient failed', e, st);
      if (!mounted) return;
      setState(() => _isDeleting = false);
      notices.error(
        composeErrorNotice(
          context,
          intro: context.l10n.error_introDeleteClient,
          tag: 'CLI-DEL',
          error: e,
        ),
      );
    }
```

- [ ] **Step 4: HIST-LOAD.** In `appointment_history_view.dart`, replace the `error:` branch:

```dart
        error: (err, st) {
          ref.read(loggerProvider).warn('HIST-LOAD history stream error', err, st);
          return Center(
            child: Text(
              composeErrorNotice(
                context,
                intro: context.l10n.error_introLoadHistory,
                tag: 'HIST-LOAD',
                error: err,
              ),
            ),
          );
        },
```

- [ ] **Step 5: CLI-LIST.** In `clients_list_view.dart`, replace the first-page error builder (the `state` variable from `PagingListener`'s builder closure is in scope; ISP only captures `Exception`s, so `state.error` may be null in odd paths — fall back):

```dart
                firstPageErrorIndicatorBuilder: (_) => Center(
                  child: Text(
                    composeErrorNotice(
                      context,
                      intro: context.l10n.error_introLoadClients,
                      tag: 'CLI-LIST',
                      error: state.error ?? Exception('clients page load failed'),
                    ),
                  ),
                ),
```

(Reminder from CLAUDE.md: this builder must stay non-scrolling — `Center`/`Text` is fine.)

- [ ] **Step 6: Verify**

Run: `flutter test test/features/clients/ && flutter analyze`
Expected: PASS; `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/features/clients/
git commit -m "feat(clients): cause+tag error notices (CLI-ADD/SAVE/DEL, HIST-LOAD, CLI-LIST)"
```

---

### Task 8: Employees + settings notice sites — EMP-DEL, EMP-STATUS, EMP-CREATE, ACCT-DEL

**Files:**
- Modify: `lib/features/employees/widgets/views/employee_details_view.dart` (two catches, ~lines 57-64 and 92-99)
- Modify: `lib/features/employees/widgets/sheets/employee_form_sheet.dart:116-122`
- Modify: `lib/features/settings/screens/settings_screen.dart:357-361`

All three files need: `import 'package:scheduling/core/errors/error_cause.dart';`

- [ ] **Step 1: EMP-DEL.** In `employee_details_view.dart` `_confirmDelete` catch:

```dart
    } catch (e, st) {
      ref.read(loggerProvider).warn('EMP-DEL deleteEmployee failed', e, st);
      if (!mounted) return;
      setState(() => _isDeleting = false);
      ref
          .read(noticeServiceProvider)
          .error(
            composeErrorNotice(
              context,
              intro: context.l10n.error_introDeleteEmployee,
              tag: 'EMP-DEL',
              error: e,
            ),
          );
    }
```

- [ ] **Step 2: EMP-STATUS.** In `_confirmDisable` catch:

```dart
    } catch (e, st) {
      ref.read(loggerProvider).warn('EMP-STATUS toggleEmployeeStatus failed', e, st);
      if (!mounted) return;
      setState(() => _isDisabling = false);
      ref
          .read(noticeServiceProvider)
          .error(
            composeErrorNotice(
              context,
              intro: context.l10n.error_introChangeEmployeeStatus,
              tag: 'EMP-STATUS',
              error: e,
            ),
          );
    }
```

- [ ] **Step 3: EMP-CREATE.** In `employee_form_sheet.dart`, the catch covers both create and edit and currently does not log. Replace:

```dart
    } catch (e) {
      if (!mounted) return;
      if (e is EmployeesFailureEmailAlreadyExists) {
        setState(() => _errors['email'] = e.toLocalizedMessage(context));
      } else {
        notices.error(context.l10n.error_couldNotCreateEmployee);
      }
    } finally {
```

with:

```dart
    } catch (e, st) {
      if (!mounted) return;
      if (e is EmployeesFailureEmailAlreadyExists) {
        setState(() => _errors['email'] = e.toLocalizedMessage(context));
      } else {
        ref.read(loggerProvider).warn('EMP-CREATE saveEmployee failed', e, st);
        notices.error(
          composeErrorNotice(
            context,
            intro: context.l10n.error_introSaveEmployee,
            tag: 'EMP-CREATE',
            error: e,
          ),
        );
      }
    } finally {
```

If `loggerProvider` isn't imported there, add `import 'package:scheduling/core/logging/app_logger.dart';`.

- [ ] **Step 4: ACCT-DEL.** In `settings_screen.dart` `_runDeletion`'s generic catch (the `AuthFailure` branch above it stays untouched):

```dart
    } catch (e, st) {
      logger.warn('ACCT-DEL settings.delete_account', e, st);
      if (!mounted) return;
      notices.error(
        composeErrorNotice(
          context,
          intro: context.l10n.error_introDeleteAccount,
          tag: 'ACCT-DEL',
          error: e,
        ),
      );
      return;
    }
```

- [ ] **Step 5: Verify**

Run: `flutter test test/features/employees/ test/features/settings/ && flutter analyze`
Expected: PASS; `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/employees/ lib/features/settings/
git commit -m "feat(employees,settings): cause+tag error notices (EMP-DEL/STATUS/CREATE, ACCT-DEL)"
```

---

### Task 9: Full verification

- [ ] **Step 1: Analyzer** — Run: `flutter analyze` → Expected: `No issues found!` (hard invariant)
- [ ] **Step 2: l10n drift** — Run: `flutter gen-l10n`, then confirm `lib/l10n/.gen/untranslated.json` is empty.
- [ ] **Step 3: Full suite** — Run: `flutter test` → Expected: all pass (~370+, includes the ~9 new tests).
- [ ] **Step 4: Device spot-check (manual, per testing.md):** `flutter run` — submit the add-client form empty (fields shake, error rows fade in), toggle airplane mode and delete a client (notice reads "Couldn't delete the client — you appear to be offline. (CLI-DEL)"), and check French. Remember: widget errors go to Crashlytics, not stdout — temporarily add `FlutterError.dumpErrorToConsole(details)` if chasing a silent failure.
- [ ] **Step 5: Final commit** of anything outstanding; report results faithfully (including any test that had to change).

---

## Self-review notes (spec coverage)

- Spec §1 (shake + fade-slide in `LabeledTextField`, wrapper fix, `AnimatedSize` glide) → Tasks 3-4. The wrapper fix is implemented as a rewrite (stronger than the spec's guard: no remount → focus survives); motion parameters preserved exactly.
- Spec §2 (reduced motion) → Task 3 Step 3 (`disableAnimationsOf` in wrapper) + Task 4 Step 3 (`Duration.zero` in `_AnimatedFieldError`); tested in Task 3.
- Spec §3 (classifier, composer, security rule, log-label tags) → Task 2; labels tagged in Tasks 5-8.
- Spec §4 (13 sites incl. the APPT-SAVE outcome nuance) → Tasks 5-8; `EventDetailsFailed` already carried the error, so the "controller change" became the `deleteAppointment` return-type change + view destructures.
- Spec §5 (l10n) → Task 1 (all-new uniform intro keys; old keys left in place).
- Spec Testing → Tasks 2-5 test steps; controller "carries error" covered by the delete-path test (the save path's `EventDetailsFailed(e)` pre-exists and is exercised by the destructuring call site compiling).
