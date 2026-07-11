# iOS Adaptive Feel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the app render native iOS primitives (dialogs, action sheets, switches, spinners, pull-to-refresh, back chevron) on iPhone/iPad while leaving Android byte-for-byte unchanged.

**Architecture:** A small, isolated `lib/core/adaptive/` layer exposes a single `context.isCupertino` platform switch plus a few adaptive helpers. High-frequency shared widgets/helpers route through it; every branch's Android arm is identical to today's behavior. No screens, scaffolds, or the design-token system are touched.

**Tech Stack:** Flutter (Material + Cupertino), Dart `^3.10.7`, Riverpod. Spec: `docs/superpowers/specs/2026-07-01-ios-adaptive-feel-design.md`.

**Non-negotiable invariant:** Android must render exactly as today. Every task's Android arm is the current code verbatim. iOS behavior is additive and gated on `context.isCupertino`.

**Already free (verified, NO work):** iOS swipe-back page transitions (default `PageTransitionsTheme` → `CupertinoPageTransitionsBuilder`; no override in `themes.dart`) and iOS bouncing scroll (`MaterialScrollBehavior` default). See spec §B / "out of scope". Do not add wrappers for these.

**Test harness note:** Widgets using `context.l10n` need `localizationsDelegates: [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate]` + `supportedLocales: AppLocalizations.supportedLocales`. Force platform in tests via `ThemeData(platform: TargetPlatform.iOS | .android)`.

---

### Task 1: Foundation — `context.isCupertino`

**Files:**
- Create: `lib/core/adaptive/adaptive.dart`
- Test: `test/core/adaptive/adaptive_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/adaptive/adaptive_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/adaptive/adaptive.dart';

Widget _host(TargetPlatform platform, ValueChanged<bool> onBuilt) {
  return MaterialApp(
    theme: ThemeData(platform: platform),
    home: Builder(
      builder: (context) {
        onBuilt(context.isCupertino);
        return const SizedBox.shrink();
      },
    ),
  );
}

void main() {
  testWidgets('isCupertino is true on iOS', (tester) async {
    late bool value;
    await tester.pumpWidget(_host(TargetPlatform.iOS, (v) => value = v));
    expect(value, isTrue);
  });

  testWidgets('isCupertino is true on macOS', (tester) async {
    late bool value;
    await tester.pumpWidget(_host(TargetPlatform.macOS, (v) => value = v));
    expect(value, isTrue);
  });

  testWidgets('isCupertino is false on Android', (tester) async {
    late bool value;
    await tester.pumpWidget(_host(TargetPlatform.android, (v) => value = v));
    expect(value, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/adaptive/adaptive_test.dart`
Expected: FAIL — `adaptive.dart` / `isCupertino` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/adaptive/adaptive.dart
import 'package:flutter/material.dart';

/// iOS-only adaptive layer. [isCupertino] is the single source of truth for
/// whether the UI should render its Cupertino (iOS/macOS) variant. Reads
/// `Theme.of(context).platform` (not `defaultTargetPlatform`) so widget tests
/// can force either look via `ThemeData(platform: ...)`. Mirrors the
/// `context.isWide` extension convention in `core/layout/breakpoints.dart`.
extension AdaptivePlatform on BuildContext {
  bool get isCupertino {
    final platform = Theme.of(this).platform;
    return platform == TargetPlatform.iOS ||
        platform == TargetPlatform.macOS;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/adaptive/adaptive_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/adaptive/adaptive.dart test/core/adaptive/adaptive_test.dart
git commit -m "feat(ios): add context.isCupertino adaptive platform switch"
```

---

### Task 2: `AdaptiveProgressIndicator` + wire into shared button primitives

**Files:**
- Create: `lib/core/adaptive/adaptive_progress_indicator.dart`
- Test: `test/core/adaptive/adaptive_progress_indicator_test.dart`
- Modify: `lib/shared/widgets/primitives/busy_button_icon.dart:28-36`
- Modify: `lib/core/animations/animated_loading_button.dart:44-55`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/adaptive/adaptive_progress_indicator_test.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/adaptive/adaptive_progress_indicator.dart';

Widget _host(TargetPlatform platform) => MaterialApp(
  theme: ThemeData(platform: platform),
  home: const Scaffold(body: AdaptiveProgressIndicator(size: 20)),
);

void main() {
  testWidgets('renders CupertinoActivityIndicator on iOS', (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.iOS));
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('renders CircularProgressIndicator on Android', (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.android));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/adaptive/adaptive_progress_indicator_test.dart`
Expected: FAIL — `AdaptiveProgressIndicator` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/adaptive/adaptive_progress_indicator.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:scheduling/core/adaptive/adaptive.dart';

/// Platform-adaptive busy spinner: `CupertinoActivityIndicator` on iOS,
/// `CircularProgressIndicator` on Android. Both render at [size] and honour
/// [color], so in-button brand spinners keep their colour on iOS instead of
/// defaulting to grey. [strokeWidth] applies to the Android arm only.
class AdaptiveProgressIndicator extends StatelessWidget {
  const AdaptiveProgressIndicator({
    super.key,
    this.size = 20,
    this.color,
    this.strokeWidth = 2,
  });

  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: context.isCupertino
          ? CupertinoActivityIndicator(radius: size / 2, color: color)
          : CircularProgressIndicator(strokeWidth: strokeWidth, color: color),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/adaptive/adaptive_progress_indicator_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Wire into `BusyButtonIcon`**

In `lib/shared/widgets/primitives/busy_button_icon.dart`, add import after the existing `material.dart` import:

```dart
import 'package:scheduling/core/adaptive/adaptive_progress_indicator.dart';
```

Replace the `build` body's busy branch (lines 28-36):

```dart
  @override
  Widget build(BuildContext context) {
    if (!isBusy) return Icon(icon, size: iconSize, color: color);
    return AdaptiveProgressIndicator(
      size: spinnerSize ?? iconSize,
      color: color,
    );
  }
```

- [ ] **Step 6: Wire into `AnimatedLoadingButton`**

In `lib/core/animations/animated_loading_button.dart`, add import after the existing `material.dart` import:

```dart
import 'package:scheduling/core/adaptive/adaptive_progress_indicator.dart';
```

Replace the `isLoading ? SizedBox(...)` spinner (lines 44-55) with:

```dart
      child: isLoading
          ? AdaptiveProgressIndicator(
              key: const ValueKey('spinner'),
              size: 22,
              strokeWidth: 2.2,
              color: variant == AnimatedLoadingButtonVariant.filled
                  ? colour.onPrimary
                  : colour.primary,
            )
```

(The `: Text(...)` label branch and its `ValueKey('label')` are unchanged.)

- [ ] **Step 7: Verify analyze + existing button tests still pass**

Run: `flutter analyze lib/shared/widgets/primitives/busy_button_icon.dart lib/core/animations/animated_loading_button.dart lib/core/adaptive/`
Expected: No issues.
Run: `flutter test test/core/adaptive/adaptive_progress_indicator_test.dart`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/core/adaptive/adaptive_progress_indicator.dart test/core/adaptive/adaptive_progress_indicator_test.dart lib/shared/widgets/primitives/busy_button_icon.dart lib/core/animations/animated_loading_button.dart
git commit -m "feat(ios): adaptive activity spinner in shared button primitives"
```

---

### Task 3: Spinner sweep — remaining standalone neutral spinners

**Files (each a `SizedBox`+`CircularProgressIndicator` → `AdaptiveProgressIndicator`):**
- Modify: `lib/shared/widgets/fields/address_autocomplete_field.dart:191-195`
- Modify: `lib/features/clients/widgets/fields/client_search_field.dart:57-61`
- Modify: `lib/features/calendar/widgets/sections/photo_picker_section.dart:398-405`
- Modify: `lib/features/wave/widgets/wave_settings_section.dart:168-172`
- Modify: `lib/features/settings/screens/settings_screen.dart:433-437`

- [ ] **Step 1: `address_autocomplete_field.dart`** — add import
`import 'package:scheduling/core/adaptive/adaptive_progress_indicator.dart';`
then replace:

```dart
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
```
with:
```dart
                  child: const AdaptiveProgressIndicator(size: 16),
```

- [ ] **Step 2: `client_search_field.dart`** — add the same import, then replace:

```dart
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
```
with:
```dart
                        child: const AdaptiveProgressIndicator(size: 16),
```

- [ ] **Step 3: `photo_picker_section.dart`** — add the same import, then replace:

```dart
    child: SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(scheme.outline),
      ),
    ),
```
with:
```dart
    child: AdaptiveProgressIndicator(size: 18, color: scheme.outline),
```

- [ ] **Step 4: `wave_settings_section.dart`** — add the same import, then replace:

```dart
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
```
with:
```dart
        child: const AdaptiveProgressIndicator(size: 20),
```

- [ ] **Step 5: `settings_screen.dart`** — add the same import, then replace:

```dart
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
```
with:
```dart
                    const AdaptiveProgressIndicator(size: 20),
```

- [ ] **Step 6: Verify analyze**

Run: `flutter analyze lib/shared/widgets/fields/address_autocomplete_field.dart lib/features/clients/widgets/fields/client_search_field.dart lib/features/calendar/widgets/sections/photo_picker_section.dart lib/features/wave/widgets/wave_settings_section.dart lib/features/settings/screens/settings_screen.dart`
Expected: No new issues. (If a `prefer_const_constructors` lint fires on a now-const-eligible parent, add `const`; if `unused_import` fires anywhere the SizedBox was the only user, that is expected only if no other spinner remains — leave the AdaptiveProgressIndicator import.)

- [ ] **Step 7: Commit**

```bash
git add lib/shared/widgets/fields/address_autocomplete_field.dart lib/features/clients/widgets/fields/client_search_field.dart lib/features/calendar/widgets/sections/photo_picker_section.dart lib/features/wave/widgets/wave_settings_section.dart lib/features/settings/screens/settings_screen.dart
git commit -m "feat(ios): adaptive spinner at remaining standalone loading sites"
```

---

### Task 4: Adaptive `showConfirmDialog`

**Files:**
- Modify: `lib/shared/widgets/dialogs/confirm_dialog.dart` (full rewrite of the function)
- Test: `test/shared/widgets/dialogs/confirm_dialog_adaptive_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/shared/widgets/dialogs/confirm_dialog_adaptive_test.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/dialogs/confirm_dialog.dart';

Widget _host(TargetPlatform platform) => MaterialApp(
  theme: ThemeData(platform: platform),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => showConfirmDialog(
            context,
            title: 'Delete?',
            confirmLabel: 'Delete',
            message: 'Are you sure?',
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('shows CupertinoAlertDialog on iOS', (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.iOS));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('shows Material AlertDialog on Android', (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.android));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/widgets/dialogs/confirm_dialog_adaptive_test.dart`
Expected: FAIL — iOS case still shows `AlertDialog`.

- [ ] **Step 3: Rewrite `confirm_dialog.dart`**

```dart
// lib/shared/widgets/dialogs/confirm_dialog.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:scheduling/core/adaptive/adaptive.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Cancel/confirm dialog shared by the destructive flows; resolves true only
/// on confirm. Pass [content] instead of [message] for a rich body. Renders a
/// [CupertinoAlertDialog] on iOS and the Material [AlertDialog] on Android.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? message,
  Widget? content,
  bool destructive = true,
}) async {
  assert(message != null || content != null, 'message or content is required');
  final bool? result;
  if (context.isCupertino) {
    result = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: content ?? Text(message!),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.common_cancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: destructive,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  } else {
    result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text(title),
          content: content ?? Text(message!),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.l10n.common_cancel),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: scheme.error,
                      foregroundColor: scheme.onError,
                    )
                  : null,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
  }
  return result ?? false;
}
```

(The `else` branch is the original implementation verbatim — Android is unchanged.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/shared/widgets/dialogs/confirm_dialog_adaptive_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Regression-check existing confirm-dialog callers' tests**

Run: `flutter test test/shared/widgets/dialogs/`
Expected: PASS (all existing confirm-dialog tests still green — Android path unchanged).

- [ ] **Step 6: Commit**

```bash
git add lib/shared/widgets/dialogs/confirm_dialog.dart test/shared/widgets/dialogs/confirm_dialog_adaptive_test.dart
git commit -m "feat(ios): CupertinoAlertDialog for shared confirm dialog"
```

---

### Task 5: `showAdaptiveActionSheet` helper

**Files:**
- Create: `lib/core/adaptive/adaptive_action_sheet.dart`
- Test: `test/core/adaptive/adaptive_action_sheet_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/adaptive/adaptive_action_sheet_test.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/adaptive/adaptive_action_sheet.dart';
import 'package:scheduling/l10n/l10n.dart';

Widget _host(TargetPlatform platform) => MaterialApp(
  theme: ThemeData(platform: platform),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => showAdaptiveActionSheet<int>(
            context,
            actions: const [
              AdaptiveSheetAction(value: 1, label: 'Camera', icon: Icons.camera_alt),
              AdaptiveSheetAction(value: 2, label: 'Gallery', icon: Icons.photo),
            ],
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('shows CupertinoActionSheet on iOS', (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.iOS));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
  });

  testWidgets('shows Material bottom sheet with ListTiles on Android', (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.android));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsNothing);
    expect(find.byType(ListTile), findsNWidgets(2));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/adaptive/adaptive_action_sheet_test.dart`
Expected: FAIL — `showAdaptiveActionSheet` / `AdaptiveSheetAction` do not exist.

- [ ] **Step 3: Write implementation**

```dart
// lib/core/adaptive/adaptive_action_sheet.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:scheduling/core/adaptive/adaptive.dart';
import 'package:scheduling/l10n/l10n.dart';

/// One selectable option in [showAdaptiveActionSheet].
class AdaptiveSheetAction<T> {
  const AdaptiveSheetAction({
    required this.value,
    required this.label,
    this.icon,
    this.isDestructive = false,
  });

  /// Returned from the sheet when this action is chosen.
  final T value;
  final String label;

  /// Leading glyph on the Android bottom-sheet row (ignored on iOS).
  final IconData? icon;

  /// Renders the iOS action (and the Android row) in the error colour.
  final bool isDestructive;
}

/// Platform-adaptive chooser: a `CupertinoActionSheet` (with a Cancel button)
/// on iOS, and the app's Material `showModalBottomSheet` list on Android.
/// Returns the chosen action's value, or null if dismissed/cancelled.
Future<T?> showAdaptiveActionSheet<T>(
  BuildContext context, {
  required List<AdaptiveSheetAction<T>> actions,
  String? title,
  String? message,
}) {
  if (context.isCupertino) {
    return showCupertinoModalPopup<T>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: title == null ? null : Text(title),
        message: message == null ? null : Text(message),
        actions: [
          for (final action in actions)
            CupertinoActionSheetAction(
              isDestructiveAction: action.isDestructive,
              onPressed: () => Navigator.pop(ctx, action.value),
              child: Text(action.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: Text(ctx.l10n.common_cancel),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    builder: (ctx) {
      final error = Theme.of(ctx).colorScheme.error;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in actions)
              ListTile(
                leading: action.icon == null ? null : Icon(action.icon),
                title: Text(action.label),
                textColor: action.isDestructive ? error : null,
                iconColor: action.isDestructive ? error : null,
                onTap: () => Navigator.pop(ctx, action.value),
              ),
          ],
        ),
      );
    },
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/adaptive/adaptive_action_sheet_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/adaptive/adaptive_action_sheet.dart test/core/adaptive/adaptive_action_sheet_test.dart
git commit -m "feat(ios): showAdaptiveActionSheet helper"
```

---

### Task 6: Wire action sheets into image picker + series-scope

**Files:**
- Modify: `lib/features/calendar/widgets/sheets/image_source_picker.dart:47-68` (`_showSourceSheet`)
- Modify: `lib/features/calendar/widgets/dialogs/series_scope_dialog.dart` (add iOS branch)

- [ ] **Step 1: Rewrite `_showSourceSheet` to use the helper**

In `image_source_picker.dart`, replace the `_showSourceSheet` function (and drop the now-unused `showModalBottomSheet` usage) with:

```dart
Future<ImageSource?> _showSourceSheet(BuildContext context) {
  final l = context.l10n;
  return showAdaptiveActionSheet<ImageSource>(
    context,
    actions: [
      AdaptiveSheetAction(
        value: ImageSource.camera,
        label: l.calendar_takePhoto,
        icon: Icons.photo_camera_outlined,
      ),
      AdaptiveSheetAction(
        value: ImageSource.gallery,
        label: l.calendar_chooseFromGallery,
        icon: Icons.photo_library_outlined,
      ),
    ],
  );
}
```

Add import at the top with the other `package:scheduling` imports:
```dart
import 'package:scheduling/core/adaptive/adaptive_action_sheet.dart';
```
(The Android arm renders the same two `ListTile`s as before — behavior unchanged.)

- [ ] **Step 2: Add iOS branch to `showSeriesScopeDialog`**

In `series_scope_dialog.dart`, add imports:
```dart
import 'package:flutter/cupertino.dart';
import 'package:scheduling/core/adaptive/adaptive.dart';
```
Then, as the FIRST statement inside `showSeriesScopeDialog` (before the existing `return showDialog<SeriesScopeChoice>(`), insert:

```dart
  if (context.isCupertino) {
    return showCupertinoModalPopup<SeriesScopeChoice>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(title),
        message: Text(message),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: destructive,
            onPressed: () => Navigator.pop(ctx, SeriesScopeChoice.thisOnly),
            child: Text(thisOnlyLabel),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: destructive,
            onPressed: () =>
                Navigator.pop(ctx, SeriesScopeChoice.thisAndFuture),
            child: Text(thisAndFutureLabel),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: Text(ctx.l10n.common_cancel),
        ),
      ),
    );
  }
```

(The existing Material `AlertDialog` below stays exactly as-is — Android unchanged. The generic helper is intentionally NOT used here because its Android arm is a bottom sheet, which would change the current dialog look.)

- [ ] **Step 3: Verify analyze**

Run: `flutter analyze lib/features/calendar/widgets/sheets/image_source_picker.dart lib/features/calendar/widgets/dialogs/series_scope_dialog.dart`
Expected: No issues (confirm no leftover unused `flutter/material.dart` symbols in the image picker; it still uses `Icons`, so the import stays).

- [ ] **Step 4: Device sanity note**

`ImagePickerService` has no unit tests (method-channel plugin). Verify Camera/Gallery selection + the series-scope sheet on an iOS device/simulator during Task 10.

- [ ] **Step 5: Commit**

```bash
git add lib/features/calendar/widgets/sheets/image_source_picker.dart lib/features/calendar/widgets/dialogs/series_scope_dialog.dart
git commit -m "feat(ios): action sheets for image source + series scope on iOS"
```

---

### Task 7: Adaptive switches (3 sites)

**Files:**
- Modify: `lib/features/employees/widgets/sheets/employee_form_sheet.dart:257`
- Modify: `lib/features/clients/widgets/views/client_edit_form.dart:252`
- Modify: `lib/features/clients/widgets/sheets/add_client_sheet.dart:178`

`Switch.adaptive` / `SwitchListTile.adaptive` are drop-in `material.dart` constructors that render `CupertinoSwitch` on iOS (which self-provides its toggle haptic). `settings_screen.dart` already uses `Switch.adaptive` — no change there.

- [ ] **Step 1: `employee_form_sheet.dart`** — change `Switch(` at line 257 to `Switch.adaptive(`. Only the constructor name changes; all args stay.

- [ ] **Step 2: `client_edit_form.dart`** — change `SwitchListTile(` at line 252 to `SwitchListTile.adaptive(`.

- [ ] **Step 3: `add_client_sheet.dart`** — change `SwitchListTile(` at line 178 to `SwitchListTile.adaptive(`.

- [ ] **Step 4: Verify analyze + touched form tests**

Run: `flutter analyze lib/features/employees/widgets/sheets/employee_form_sheet.dart lib/features/clients/widgets/views/client_edit_form.dart lib/features/clients/widgets/sheets/add_client_sheet.dart`
Expected: No issues.
Run: `flutter test test/features/clients/ test/features/employees/`
Expected: PASS (existing form tests green; `.adaptive` renders a Material `Switch` internally on the default test platform).

- [ ] **Step 5: Commit**

```bash
git add lib/features/employees/widgets/sheets/employee_form_sheet.dart lib/features/clients/widgets/views/client_edit_form.dart lib/features/clients/widgets/sheets/add_client_sheet.dart
git commit -m "feat(ios): adaptive switches (CupertinoSwitch on iOS)"
```

---

### Task 8: Adaptive pull-to-refresh (2 sites)

**Files:**
- Modify: `lib/features/clients/widgets/views/clients_list_view.dart:244`
- Modify: `lib/features/clients/widgets/views/appointment_history_view.dart:304`

`RefreshIndicator.adaptive` is a drop-in `material.dart` constructor that shows the Cupertino-style refresh spinner on iOS.

- [ ] **Step 1: `clients_list_view.dart`** — change `RefreshIndicator(` at line 244 to `RefreshIndicator.adaptive(`. Args unchanged.

- [ ] **Step 2: `appointment_history_view.dart`** — change `RefreshIndicator(` at line 304 to `RefreshIndicator.adaptive(`. Args unchanged.

- [ ] **Step 3: Verify analyze + touched tests**

Run: `flutter analyze lib/features/clients/widgets/views/clients_list_view.dart lib/features/clients/widgets/views/appointment_history_view.dart`
Expected: No issues.
Run: `flutter test test/features/clients/`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/features/clients/widgets/views/clients_list_view.dart lib/features/clients/widgets/views/appointment_history_view.dart
git commit -m "feat(ios): adaptive pull-to-refresh on clients + history lists"
```

---

### Task 9: iOS back chevron in `AppBackButton`

**Files:**
- Modify: `lib/shared/widgets/primitives/app_back_button.dart:66`
- Test: `test/shared/widgets/primitives/app_back_button_adaptive_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/shared/widgets/primitives/app_back_button_adaptive_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/shared/widgets/primitives/app_back_button.dart';

Widget _host(TargetPlatform platform) => MaterialApp(
  theme: ThemeData(platform: platform),
  home: Scaffold(body: AppBackButton(onTap: () {})),
);

void main() {
  testWidgets('uses iOS chevron on iOS', (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.iOS));
    expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
  });

  testWidgets('uses Material arrow on Android', (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.android));
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/widgets/primitives/app_back_button_adaptive_test.dart`
Expected: FAIL — iOS case still finds `arrow_back_rounded`.

- [ ] **Step 3: Make the icon adaptive**

In `app_back_button.dart`, add import after the existing imports:
```dart
import 'package:scheduling/core/adaptive/adaptive.dart';
```
Replace line 66 `child: const Icon(Icons.arrow_back_rounded),` with:
```dart
          child: Icon(
            context.isCupertino
                ? Icons.arrow_back_ios_new
                : Icons.arrow_back_rounded,
          ),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/shared/widgets/primitives/app_back_button_adaptive_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/primitives/app_back_button.dart test/shared/widgets/primitives/app_back_button_adaptive_test.dart
git commit -m "feat(ios): iOS back chevron in AppBackButton"
```

---

### Task 10: App-wide iOS scrollbar (`CupertinoScrollbar`)

**Files:**
- Create: `lib/core/adaptive/app_scroll_behavior.dart`
- Test: `test/core/adaptive/app_scroll_behavior_test.dart`
- Modify: `lib/main.dart` (add `scrollBehavior:` to `MaterialApp` + import)

- [ ] **Step 1: Write the failing test**

```dart
// test/core/adaptive/app_scroll_behavior_test.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/adaptive/app_scroll_behavior.dart';

Widget _host(TargetPlatform platform) => MaterialApp(
  theme: ThemeData(platform: platform),
  scrollBehavior: const AppScrollBehavior(),
  home: Scaffold(
    body: ListView.builder(
      itemCount: 100,
      itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row $i')),
    ),
  ),
);

void main() {
  testWidgets('wraps scrollables in CupertinoScrollbar on iOS', (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.iOS));
    expect(find.byType(CupertinoScrollbar), findsOneWidget);
  });

  testWidgets('no CupertinoScrollbar on Android', (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.android));
    expect(find.byType(CupertinoScrollbar), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/adaptive/app_scroll_behavior_test.dart`
Expected: FAIL — `AppScrollBehavior` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/adaptive/app_scroll_behavior.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// App-wide scroll behavior: renders a fading iOS-style [CupertinoScrollbar] on
/// iOS/macOS, and defers to the Material default (no persistent scrollbar on
/// touch, standard overscroll glow) everywhere else — so Android is unchanged.
/// Set on `MaterialApp.scrollBehavior`.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    switch (getPlatform(context)) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return CupertinoScrollbar(
          controller: details.controller,
          child: child,
        );
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return super.buildScrollbar(context, child, details);
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/adaptive/app_scroll_behavior_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Wire into `MaterialApp` in `main.dart`**

Add the import alongside the other `package:scheduling` imports:
```dart
import 'package:scheduling/core/adaptive/app_scroll_behavior.dart';
```
In the `MaterialApp(...)` (currently starting near line 239), add one property next to `themeMode: _themeMode,`:
```dart
              scrollBehavior: const AppScrollBehavior(),
```

- [ ] **Step 6: Verify analyze**

Run: `flutter analyze lib/main.dart lib/core/adaptive/app_scroll_behavior.dart`
Expected: No issues.

- [ ] **Step 7: Commit**

```bash
git add lib/core/adaptive/app_scroll_behavior.dart test/core/adaptive/app_scroll_behavior_test.dart lib/main.dart
git commit -m "feat(ios): app-wide CupertinoScrollbar via AppScrollBehavior"
```

---

### Task 11: Full verification + polish notes

**Files:** none (verification only).

- [ ] **Step 1: Analyze the whole project for real issues**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"`
Expected: no output (only pre-existing info lints remain).

- [ ] **Step 2: Run the full adaptive + touched test suites**

Run: `flutter test test/core/adaptive/ test/shared/widgets/ test/features/clients/ test/features/employees/`
Expected: all PASS.

- [ ] **Step 3: Confirm the "already-free" items on device**

On an iPhone/simulator via `flutter run` (release/profile fine), confirm:
- Login → Forgot password → edge-swipe from the left pops back (iOS slide).
- A long list rubber-bands at the top/bottom (bouncing scroll).
(These require no code — this step is a verification that the defaults hold.)

- [ ] **Step 4: Device walkthrough of the new adaptive surfaces (iOS)**

- Delete a client / appointment → `CupertinoAlertDialog` with red destructive action.
- Add photo → `CupertinoActionSheet` (Take Photo / Choose from Gallery / Cancel).
- Delete/edit a repeating appointment → series-scope `CupertinoActionSheet`.
- Settings dark-mode + app-lock toggles → `CupertinoSwitch` with its toggle haptic.
- Pull down Clients / History → iOS refresh spinner.
- Any screen with a back arrow → iOS chevron.
- Scroll any long list → thin fading `CupertinoScrollbar` appears at the right edge.

- [ ] **Step 5: Polish — haptics reality check (document, no code)**

The chosen "adaptive haptics on toggles/pickers" polish is delivered **by the
adaptive widgets themselves**: `CupertinoSwitch` (via `Switch.adaptive`) fires
its own selection haptic, and the existing `cupertino_time_picker` /
`CupertinoPicker` self-haptic on scroll. No manual `HapticFeedback` calls are
added — bolting extra haptics onto a native `CupertinoActionSheet` tap would be
non-idiomatic for iOS. If, during Step 4, a specific interaction feels like it
is missing expected feedback, note it and add a single `HapticFeedback` call at
that one site (not a blanket pass).

- [ ] **Step 6: Polish — rough-edge fixes**

List any small, safe UX gaps found while editing the touched files (missing
loading/empty state, an absent `Semantics`/tooltip on an icon control). Fix
only the safe, obvious ones and note each in the final summary; report anything
non-trivial rather than changing it here.

- [ ] **Step 7: Final commit (if any Step 5–6 fixes were made)**

```bash
git add -A
git commit -m "polish(ios): safe rough-edge fixes from adaptive pass"
```

---

## Self-Review (completed by plan author)

**Spec coverage:**
- §A foundation → Task 1. §B (swipe-back) → documented as already-free (no task, by design). §C1 confirm dialog → Task 4. §C2 action sheets → Tasks 5–6. §C3 progress indicator → Tasks 2–3. §C4 switches → Task 7. §C5 pull-to-refresh → Task 8. §C6 back button → Task 9. §C7 scrollbar → Task 10. §D polish (haptics/rough edges) → Task 11 Steps 5–6. Testing/verification → Task 11. All spec sections mapped.
- Bouncing scroll (spec "out of scope / already free") → Task 11 Step 3 verification only. Correct.

**Placeholder scan:** No TBD/TODO; every code step shows full code; no "similar to Task N".

**Type consistency:** `context.isCupertino` (Task 1) used identically in Tasks 2, 4, 6, 9. `AdaptiveProgressIndicator({size, color, strokeWidth})` defined in Task 2 and called with those exact params in Tasks 2–3. `AdaptiveSheetAction({value, label, icon, isDestructive})` + `showAdaptiveActionSheet(context, {actions, title, message})` defined in Task 5 and called with matching params in Task 6. Icon names (`Icons.arrow_back_ios_new`, `Icons.arrow_back_rounded`) consistent between Task 9 impl and test.
