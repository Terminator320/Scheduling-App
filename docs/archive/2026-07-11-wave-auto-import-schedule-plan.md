# Wave Automatic-Import Cadence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an admin pick whether the app imports Wave customers automatically (Off / Weekly / Monthly) via a Settings picker, backed by a daily scheduled Cloud Function.

**Architecture:** Cadence stored in the rules-locked `wave/connection` doc (`importSchedule` + `lastAutoImportAt`). A new daily `waveScheduledImport` runs the already-idempotent `importCustomers()` only when due, gated by a pure `isImportDue` helper. `waveGetConnection` returns the cadence; a new `waveSetImportSchedule` callable writes it. The app reads/writes only through those callables (never the `wave` collection).

**Tech Stack:** Firebase Cloud Functions (Node, `firebase-functions/v2`), Jest, Flutter/Dart, Riverpod, `gen_l10n`.

Design spec: `docs/plans/2026-07-11-wave-auto-import-schedule.md`

---

### Task 1: `isImportDue` pure helper (backend, jest-testable)

**Files:**
- Create: `functions/wave/import_schedule.js`
- Test: `functions/wave/__tests__/import_schedule.test.js`

- [ ] **Step 1: Write the failing test**

```js
"use strict";

const {isImportDue, SCHEDULE_VALUES} = require("../import_schedule");

const DAY = 24 * 60 * 60 * 1000;
const NOW = 1_000 * DAY; // arbitrary fixed "now" in ms

describe("isImportDue", () => {
  test("off is never due", () => {
    expect(isImportDue("off", null, NOW)).toBe(false);
    expect(isImportDue("off", NOW - 999 * DAY, NOW)).toBe(false);
  });

  test("unknown/empty schedule is never due", () => {
    expect(isImportDue("", null, NOW)).toBe(false);
    expect(isImportDue("yearly", null, NOW)).toBe(false);
    expect(isImportDue(undefined, null, NOW)).toBe(false);
  });

  test("weekly is due when never run", () => {
    expect(isImportDue("weekly", null, NOW)).toBe(true);
  });

  test("weekly is due just past 7 days, not before", () => {
    expect(isImportDue("weekly", NOW - 7 * DAY - 1, NOW)).toBe(true);
    expect(isImportDue("weekly", NOW - 7 * DAY + 1, NOW)).toBe(false);
    expect(isImportDue("weekly", NOW - 6 * DAY, NOW)).toBe(false);
  });

  test("monthly is due when never run", () => {
    expect(isImportDue("monthly", null, NOW)).toBe(true);
  });

  test("monthly is due just past 30 days, not before", () => {
    expect(isImportDue("monthly", NOW - 30 * DAY - 1, NOW)).toBe(true);
    expect(isImportDue("monthly", NOW - 30 * DAY + 1, NOW)).toBe(false);
    expect(isImportDue("monthly", NOW - 8 * DAY, NOW)).toBe(false);
  });

  test("SCHEDULE_VALUES lists exactly the accepted strings", () => {
    expect(SCHEDULE_VALUES).toEqual(["off", "weekly", "monthly"]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd functions && npx jest wave/__tests__/import_schedule.test.js`
Expected: FAIL — "Cannot find module '../import_schedule'".

- [ ] **Step 3: Write minimal implementation**

```js
"use strict";

/**
 * @fileoverview Pure cadence helper for the scheduled Wave import. Kept in a
 * plain module (no Storage/Firestore load at require time) so jest can require
 * it directly — the onSchedule module that uses it cannot be required in tests.
 * @module wave/import_schedule
 */

const DAY_MS = 24 * 60 * 60 * 1000;
const WEEK_MS = 7 * DAY_MS;
const MONTH_MS = 30 * DAY_MS;

/** The only accepted `importSchedule` wire values. */
const SCHEDULE_VALUES = ["off", "weekly", "monthly"];

/**
 * Decides whether a scheduled Wave import should run now.
 * @param {string} schedule One of `off` | `weekly` | `monthly`. Anything else
 *   (including undefined/"") is treated as `off`.
 * @param {?number} lastAutoImportMs Epoch ms of the last successful auto-import,
 *   or null/undefined when it has never run.
 * @param {number} nowMs Current epoch ms.
 * @return {boolean} True when the import is due.
 */
function isImportDue(schedule, lastAutoImportMs, nowMs) {
  let intervalMs;
  if (schedule === "weekly") {
    intervalMs = WEEK_MS;
  } else if (schedule === "monthly") {
    intervalMs = MONTH_MS;
  } else {
    return false; // off / unknown → never
  }
  if (typeof lastAutoImportMs !== "number") return true; // never run yet
  return nowMs - lastAutoImportMs > intervalMs;
}

module.exports = {isImportDue, SCHEDULE_VALUES};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd functions && npx jest wave/__tests__/import_schedule.test.js`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add functions/wave/import_schedule.js functions/wave/__tests__/import_schedule.test.js
git commit -m "feat(wave): add isImportDue cadence helper"
```

---

### Task 2: Backend wiring — scheduler, get-connection extension, set-schedule callable

**Files:**
- Modify: `functions/wave/callables.js`
- Modify: `functions/index.js:34` (add two exports)

- [ ] **Step 1: Add requires + the schedule constant near the top of `callables.js`**

After the existing `const {classifyWaveError} = require("./errors");` line (line 17), add:

```js
const {isImportDue, SCHEDULE_VALUES} = require("./import_schedule");
```

After the existing `const {assertPayloadShape, assertAdmin, enforceDurableRateLimit} = require("../security");` block, add:

```js
// Accepted automatic-import cadences (mirrors the app's WaveImportSchedule enum
// and firestore field). "off" is the default when the field is absent.
const IMPORT_SCHEDULE_SET = new Set(SCHEDULE_VALUES);
```

- [ ] **Step 2: Extend `waveGetConnection` to return `importSchedule`**

In `waveGetConnection` replace the return block:

```js
      const snap = await getFirestore()
          .collection("wave").doc("connection").get();
      const data = snap.exists ? snap.data() : null;
      const businessId = data && typeof data.businessId === "string" ?
        data.businessId : "";
      const businessName = data && typeof data.businessName === "string" ?
        data.businessName : "";
      return {connected: Boolean(businessId), businessId, businessName};
```

with:

```js
      const snap = await getFirestore()
          .collection("wave").doc("connection").get();
      const data = snap.exists ? snap.data() : null;
      const businessId = data && typeof data.businessId === "string" ?
        data.businessId : "";
      const businessName = data && typeof data.businessName === "string" ?
        data.businessName : "";
      const rawSchedule = data && typeof data.importSchedule === "string" ?
        data.importSchedule : "off";
      const importSchedule =
        IMPORT_SCHEDULE_SET.has(rawSchedule) ? rawSchedule : "off";
      return {
        connected: Boolean(businessId),
        businessId,
        businessName,
        importSchedule,
      };
```

- [ ] **Step 3: Add the `waveSetImportSchedule` callable**

Immediately after the `waveGetConnection` definition (after its closing `);`), add:

```js
// 2b) waveSetImportSchedule — admin-only setter for the automatic-import
// cadence. Writes the `importSchedule` field on the single wave/connection doc.
// No secret, no rate limit (a cheap Firestore write); App Check + admin only.
const waveSetImportSchedule = onCall(
    {enforceAppCheck: true},
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      assertPayloadShape(req.data, new Set(["schedule"]));
      await assertAdmin(req.auth.uid);

      const schedule = req.data && req.data.schedule;
      if (typeof schedule !== "string" || !IMPORT_SCHEDULE_SET.has(schedule)) {
        throw new HttpsError("invalid-argument", "wave/invalid-schedule");
      }

      const ref = getFirestore().collection("wave").doc("connection");
      const snap = await ref.get();
      const data = snap.exists ? snap.data() : null;
      if (!data || typeof data.businessId !== "string" || !data.businessId) {
        throw new HttpsError("failed-precondition", "wave/not-bootstrapped");
      }

      await ref.update({importSchedule: schedule});
      logger.info("WAVE-SCHED set", {uid: req.auth.uid, schedule});
      return {schedule};
    },
);
```

- [ ] **Step 4: Add the `waveScheduledImport` scheduled function**

Immediately before the final `module.exports = {` block, add:

```js
// 5) waveScheduledImport — daily Wave → App auto-import. Runs importCustomers()
// only when the configured cadence is due (see isImportDue). Server-triggered,
// so no App Check / rate limit. Idempotent import path; a per-run failure is
// logged (there is no user to surface it to) and retried on the next day's run.
const waveScheduledImport = onSchedule(
    {
      schedule: "every 24 hours",
      secrets: [WAVE_FULL_ACCESS_TOKEN],
      maxInstances: 1,
      timeoutSeconds: 300,
    },
    async () => {
      const snap = await getFirestore()
          .collection("wave").doc("connection").get();
      const data = snap.exists ? snap.data() : null;
      const businessId = data && typeof data.businessId === "string" ?
        data.businessId : "";
      if (!businessId) {
        logger.debug("waveScheduledImport: not connected — nothing to do");
        return;
      }
      const schedule = data && typeof data.importSchedule === "string" ?
        data.importSchedule : "off";
      const lastAt = data && data.lastAutoImportAt &&
        typeof data.lastAutoImportAt.toMillis === "function" ?
        data.lastAutoImportAt.toMillis() : null;
      if (!isImportDue(schedule, lastAt, Date.now())) {
        logger.debug("waveScheduledImport: not due", {schedule});
        return;
      }

      logger.info("WAVE-SCHED import starting", {businessId, schedule});
      let summary;
      try {
        summary = await importCustomers({businessId, graphql});
      } catch (e) {
        const {code, message} = classifyWaveError(e);
        logger.warn("WAVE-SCHED import failed", {code, message});
        return; // leave lastAutoImportAt unchanged → retried next run
      }

      await getFirestore().collection("wave").doc("connection").update({
        lastAutoImportAt: FieldValue.serverTimestamp(),
      });
      logger.info("WAVE-SCHED import done", {
        imported: summary.imported,
        updated: summary.updated,
        skippedArchived: summary.skippedArchived,
        pages: summary.pages,
      });
    },
);
```

- [ ] **Step 5: Add both to the `module.exports` block in `callables.js`**

Replace the exports block:

```js
module.exports = {
  selectBusiness,
  waveBootstrap,
  waveGetConnection,
  waveImportCustomers,
  waveUpsertCustomer,
  waveSyncWorker,
};
```

with:

```js
module.exports = {
  selectBusiness,
  waveBootstrap,
  waveGetConnection,
  waveSetImportSchedule,
  waveImportCustomers,
  waveUpsertCustomer,
  waveScheduledImport,
  waveSyncWorker,
};
```

- [ ] **Step 6: Re-export from `functions/index.js`**

After line 34 (`exports.waveImportCustomers = waveCallables.waveImportCustomers;`) add:

```js
exports.waveSetImportSchedule = waveCallables.waveSetImportSchedule;
exports.waveScheduledImport = waveCallables.waveScheduledImport;
```

- [ ] **Step 7: Lint**

Run: `cd functions && npm run lint`
Expected: no errors (Google ESLint, 80-char lines).

- [ ] **Step 8: Run the Wave jest suite (ensure nothing broke)**

Run: `cd functions && npx jest wave`
Expected: PASS (existing Wave tests + Task 1).

- [ ] **Step 9: Commit**

```bash
git add functions/wave/callables.js functions/index.js
git commit -m "feat(wave): scheduled auto-import + get/set import schedule callables"
```

---

### Task 3: `WaveImportSchedule` enum (Dart domain)

**Files:**
- Create: `lib/features/wave/domain/models/wave_import_schedule.dart`
- Test: `test/features/wave/wave_import_schedule_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/wave/domain/models/wave_import_schedule.dart';

void main() {
  group('WaveImportSchedule.fromRaw', () {
    test('maps known wire strings', () {
      expect(WaveImportSchedule.fromRaw('weekly'), WaveImportSchedule.weekly);
      expect(WaveImportSchedule.fromRaw('monthly'), WaveImportSchedule.monthly);
      expect(WaveImportSchedule.fromRaw('off'), WaveImportSchedule.off);
    });

    test('null/empty/unknown fall to off', () {
      expect(WaveImportSchedule.fromRaw(null), WaveImportSchedule.off);
      expect(WaveImportSchedule.fromRaw(''), WaveImportSchedule.off);
      expect(WaveImportSchedule.fromRaw('yearly'), WaveImportSchedule.off);
    });

    test('raw round-trips for every value', () {
      for (final s in WaveImportSchedule.values) {
        expect(WaveImportSchedule.fromRaw(s.raw), s);
      }
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/wave/wave_import_schedule_test.dart`
Expected: FAIL — target of URI doesn't exist (file not created yet).

- [ ] **Step 3: Write minimal implementation**

```dart
/// The automatic Wave-import cadence, stored on `wave/connection` and chosen in
/// Settings. `fromRaw` pins the accepted wire strings explicitly (rather than
/// trusting `.name`) so the cross-boundary contract — also validated in the
/// `waveSetImportSchedule` function and switched on in `isImportDue` — can't be
/// silently changed by an enum-constant rename. Any null/empty/unknown value
/// falls to [off], the fail-safe default (never accidentally enables imports).
enum WaveImportSchedule {
  off,
  weekly,
  monthly;

  static WaveImportSchedule fromRaw(String? raw) => switch (raw) {
    'weekly' => weekly,
    'monthly' => monthly,
    _ => off,
  };

  /// The stored/wire string. Safe as `.name` here because the enum names
  /// already equal the accepted wire values.
  String get raw => name;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/wave/wave_import_schedule_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/wave/domain/models/wave_import_schedule.dart test/features/wave/wave_import_schedule_test.dart
git commit -m "feat(wave): add WaveImportSchedule enum"
```

---

### Task 4: `WaveConnection.importSchedule` + `WaveService.setImportSchedule`

**Files:**
- Modify: `lib/features/wave/domain/models/wave_connection.dart`
- Modify: `lib/features/wave/data/wave_service.dart`
- Test: `test/features/wave/wave_test.dart` (add cases)

- [ ] **Step 1: Add `importSchedule` to `WaveConnection`**

At the top of `wave_connection.dart`, after the existing `import`, add:

```dart
import 'package:scheduling/features/wave/domain/models/wave_import_schedule.dart';
```

Replace the constructor, factory, and fields:

```dart
  const WaveConnection({required this.businessId, required this.businessName});

  factory WaveConnection.fromMap(Map<String, dynamic> map) {
    return WaveConnection(
      businessId: (map['businessId'] as String?) ?? '',
      businessName: (map['businessName'] as String?) ?? '',
    );
  }

  final String businessId;
  final String businessName;
```

with:

```dart
  const WaveConnection({
    required this.businessId,
    required this.businessName,
    this.importSchedule = WaveImportSchedule.off,
  });

  factory WaveConnection.fromMap(Map<String, dynamic> map) {
    return WaveConnection(
      businessId: (map['businessId'] as String?) ?? '',
      businessName: (map['businessName'] as String?) ?? '',
      importSchedule: WaveImportSchedule.fromRaw(
        map['importSchedule'] as String?,
      ),
    );
  }

  final String businessId;
  final String businessName;
  final WaveImportSchedule importSchedule;
```

Replace the `==` and `hashCode`:

```dart
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WaveConnection &&
          runtimeType == other.runtimeType &&
          businessId == other.businessId &&
          businessName == other.businessName;

  @override
  int get hashCode => Object.hash(businessId, businessName);
```

with:

```dart
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WaveConnection &&
          runtimeType == other.runtimeType &&
          businessId == other.businessId &&
          businessName == other.businessName &&
          importSchedule == other.importSchedule;

  @override
  int get hashCode => Object.hash(businessId, businessName, importSchedule);
```

- [ ] **Step 2: Add `setImportSchedule` to `WaveService`**

At the top of `wave_service.dart`, after the existing model import, add:

```dart
import 'package:scheduling/features/wave/domain/models/wave_import_schedule.dart';
```

After the `importCustomers()` method (before the closing class brace), add:

```dart
  /// Sets the automatic-import cadence via the admin-only
  /// `waveSetImportSchedule` callable.
  Future<void> setImportSchedule(WaveImportSchedule schedule) async {
    try {
      await _functions
          .httpsCallable('waveSetImportSchedule')
          .call(<String, dynamic>{'schedule': schedule.raw});
    } catch (e, st) {
      _logger.warn('WAVE-SCHED waveSetImportSchedule callable failed', e, st);
      throw WaveErrorMapper.map(e);
    }
  }
```

- [ ] **Step 3: Write failing tests**

Open `test/features/wave/wave_test.dart` and add these tests inside the existing `main()` (append a new group at the end of `main`). First read the file's existing imports; ensure it imports `wave_connection.dart` and `wave_import_schedule.dart` (add the schedule import if absent). Add:

```dart
  group('WaveConnection.fromMap importSchedule', () {
    test('parses a known schedule', () {
      final conn = WaveConnection.fromMap(const {
        'businessId': 'b1',
        'businessName': 'Biz',
        'importSchedule': 'weekly',
      });
      expect(conn.importSchedule, WaveImportSchedule.weekly);
    });

    test('defaults to off when absent or unknown', () {
      final absent = WaveConnection.fromMap(const {
        'businessId': 'b1',
        'businessName': 'Biz',
      });
      final unknown = WaveConnection.fromMap(const {
        'businessId': 'b1',
        'businessName': 'Biz',
        'importSchedule': 'yearly',
      });
      expect(absent.importSchedule, WaveImportSchedule.off);
      expect(unknown.importSchedule, WaveImportSchedule.off);
    });
  });
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/wave/wave_test.dart`
Expected: PASS (existing + 2 new).

- [ ] **Step 5: Commit**

```bash
git add lib/features/wave/domain/models/wave_connection.dart lib/features/wave/data/wave_service.dart test/features/wave/wave_test.dart
git commit -m "feat(wave): connection carries importSchedule + setImportSchedule service"
```

---

### Task 5: Localization keys

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_fr.arb`

- [ ] **Step 1: Add keys to `app_en.arb`**

Find an existing `wave_` key block (e.g. `wave_importCustomers`) and add after it:

```json
  "wave_autoImportLabel": "Automatic import",
  "@wave_autoImportLabel": {
    "description": "Settings label for the Wave automatic-import cadence picker."
  },
  "wave_autoImportOff": "Off",
  "@wave_autoImportOff": {
    "description": "Wave automatic-import cadence: disabled."
  },
  "wave_autoImportWeekly": "Weekly",
  "@wave_autoImportWeekly": {
    "description": "Wave automatic-import cadence: once a week."
  },
  "wave_autoImportMonthly": "Monthly",
  "@wave_autoImportMonthly": {
    "description": "Wave automatic-import cadence: once a month."
  },
  "wave_autoImportUpdated": "Automatic import updated.",
  "@wave_autoImportUpdated": {
    "description": "Success notice after changing the Wave automatic-import cadence."
  },
```

- [ ] **Step 2: Add matching keys to `app_fr.arb`** (no `@` metadata in FR)

```json
  "wave_autoImportLabel": "Importation automatique",
  "wave_autoImportOff": "Désactivée",
  "wave_autoImportWeekly": "Chaque semaine",
  "wave_autoImportMonthly": "Chaque mois",
  "wave_autoImportUpdated": "Importation automatique mise à jour.",
```

- [ ] **Step 3: Generate localizations**

The ARB-edit hook regenerates automatically. If needed manually:
Run: `flutter gen-l10n`
Expected: no errors; `lib/l10n/.gen/untranslated.json` shows no drift for these keys.

- [ ] **Step 4: Verify analyzer sees the new getters**

Run: `flutter analyze lib/l10n`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_fr.arb
git commit -m "feat(wave): l10n keys for automatic-import cadence"
```

---

### Task 6: Settings cadence picker UI

**Files:**
- Modify: `lib/features/wave/widgets/wave_settings_section.dart`
- Test: `test/features/wave/wave_settings_section_test.dart` (add cases)

- [ ] **Step 1: Add imports + label helper to the section file**

At the top of `wave_settings_section.dart`, after the existing wave imports, add:

```dart
import 'package:scheduling/core/adaptive/adaptive_action_sheet.dart';
import 'package:scheduling/features/wave/domain/models/wave_import_schedule.dart';
```

Add a top-level label helper below the imports (before the class):

```dart
/// Localized label for an automatic-import cadence — used by the picker row and
/// the action sheet.
String _scheduleLabel(BuildContext context, WaveImportSchedule schedule) =>
    switch (schedule) {
      WaveImportSchedule.off => context.l10n.wave_autoImportOff,
      WaveImportSchedule.weekly => context.l10n.wave_autoImportWeekly,
      WaveImportSchedule.monthly => context.l10n.wave_autoImportMonthly,
    };
```

- [ ] **Step 2: Add busy flag + the change handler to `_WaveSettingsSectionState`**

After the existing `bool _importBusy = false;` field add:

```dart
  bool _scheduleBusy = false;
```

After the `_import()` method add:

```dart
  Future<void> _pickSchedule(WaveImportSchedule current) async {
    final choice = await showAdaptiveActionSheet<WaveImportSchedule>(
      context,
      title: context.l10n.wave_autoImportLabel,
      actions: [
        for (final s in WaveImportSchedule.values)
          AdaptiveSheetAction(value: s, label: _scheduleLabel(context, s)),
      ],
    );
    if (choice == null || choice == current) return;

    setState(() => _scheduleBusy = true);
    try {
      await ref.read(waveServiceProvider).setImportSchedule(choice);
      if (!mounted) return;
      // Reflect the new cadence locally; the connection provider is invalidated
      // so a later Settings mount re-reads the persisted value.
      final base = _connection ?? ref.read(waveConnectionProvider).value;
      if (base != null) {
        setState(() {
          _connection = WaveConnection(
            businessId: base.businessId,
            businessName: base.businessName,
            importSchedule: choice,
          );
        });
      }
      ref.invalidate(waveConnectionProvider);
      ref
          .read(noticeServiceProvider)
          .success(context.l10n.wave_autoImportUpdated);
    } on WaveFailure catch (e) {
      if (!mounted) return;
      ref.read(noticeServiceProvider).error(e.toLocalizedMessage(context));
    } finally {
      if (mounted) setState(() => _scheduleBusy = false);
    }
  }
```

- [ ] **Step 3: Render the cadence row in `build()` (connected branch only)**

In `build()`, inside the `if (connected) ...[` block, after the business-name `Padding(...)` widget (before the closing `],` of that collection-if), add:

```dart
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sync_rounded),
            title: Text(context.l10n.wave_autoImportLabel),
            trailing: _scheduleBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: AdaptiveProgressIndicator(),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _scheduleLabel(context, connection.importSchedule),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
            onTap: _connectBusy || _importBusy || _scheduleBusy
                ? null
                : () => _pickSchedule(connection.importSchedule),
          ),
```

(`connection` and `scheme` are already in scope in `build()`. `AdaptiveProgressIndicator` is already imported.)

- [ ] **Step 4: Write failing widget test**

In `test/features/wave/wave_settings_section_test.dart`, add these imports at the top if absent:

```dart
import 'package:scheduling/features/wave/domain/models/wave_import_schedule.dart';
```

Add inside the `group('WaveSettingsSection', ...)` block:

```dart
    testWidgets('picking a cadence calls setImportSchedule and notices', (
      tester,
    ) async {
      final service = _mockService();
      final notices = NoticeService();
      final emitted = <String>[];
      notices.stream.listen((n) => emitted.add(n.message));

      when(service.getConnection).thenAnswer(
        (_) async => const WaveConnection(
          businessId: 'biz-1',
          businessName: 'Test Biz',
        ),
      );
      when(() => service.setImportSchedule(any())).thenAnswer((_) async {});

      await tester.pumpWidget(_wrapSection(service, noticeService: notices));
      await tester.pumpAndSettle();

      // Open the cadence picker (row shows the current 'Off' value).
      await tester.tap(find.text('Automatic import'));
      await tester.pumpAndSettle();

      // Choose Weekly from the sheet.
      await tester.tap(find.text('Weekly').last);
      await tester.pumpAndSettle();

      verify(
        () => service.setImportSchedule(WaveImportSchedule.weekly),
      ).called(1);
      expect(emitted.last, contains('Automatic import updated'));
      expect(tester.takeException(), isNull);
    });
```

Register a fallback value for the mocktail `any()` matcher — add to the top of `main()` (inside `setUpAll`):

```dart
    registerFallbackValue(WaveImportSchedule.off);
```

- [ ] **Step 5: Run the test to verify it fails, then passes**

Run: `flutter test test/features/wave/wave_settings_section_test.dart`
Expected first: FAIL (no "Automatic import" text / method missing).
After Steps 1-3 are in place: PASS (existing + new).

- [ ] **Step 6: Analyze**

Run: `flutter analyze lib/features/wave test/features/wave`
Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add lib/features/wave/widgets/wave_settings_section.dart test/features/wave/wave_settings_section_test.dart
git commit -m "feat(wave): Settings automatic-import cadence picker"
```

---

### Task 7: Full-suite verification

- [ ] **Step 1: Flutter analyze (whole project)**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"`
Expected: no output (no errors/warnings introduced).

- [ ] **Step 2: Flutter Wave tests**

Run: `flutter test test/features/wave`
Expected: PASS.

- [ ] **Step 3: Functions lint + Wave jest**

Run: `cd functions && npm run lint && npx jest wave`
Expected: lint clean, jest PASS.

- [ ] **Step 4: Final commit if anything is uncommitted**

```bash
git status
```

---

## Deploy (manual, after review — not part of the coding tasks)

`cd functions && npm run lint` then `firebase deploy --only functions`
(rules unchanged — the app never touches `wave/` directly). The new
`waveScheduledImport` schedule registers on deploy.
