# Animated + debuggable error handling

**Date:** 2026-06-06
**Status:** Approved (brainstormed with visual companion; user picked animation style A and approaches 1A + 2A)

## Context

Error surfaces in the app are inconsistent. Top notices and auth-screen fields already animate (slide+fade notices; `AnimatedFormFieldWrapper` shake), but field errors in every other form pop in instantly, and several catch sites surface the generic "Something went wrong", which testers can't usefully report and the developer can't trace to a log line.

Two goals:

1. **Animate field errors app-wide** — shake the field and fade-slide the error row in, consistently, for every form (clients, calendar, employees), not just auth.
2. **Make generic errors debuggable** — replace bare "Something went wrong" with a sanitized cause plus a short operation tag that matches the Crashlytics log label.

## Decisions made during brainstorming

- **Scope:** field error rows (all forms) + field shake (app-wide) + cause/tag for generic error notices. Stream-error views get the improved *message*; no animation required there.
- **Animation style (user choice A):** shake + fade-slide. Error text fades in while sliding down ~4px; the same 320ms / 3Hz / 6px shake the auth screens already use.
- **Architecture 1A:** animation baked into the shared `LabeledTextField`, not wrapped at call sites.
- **Architecture 2A:** one core cause-mapper + per-call-site operation tags, not new typed-Failure subclasses.
- **Message format (user-approved preview):** `Couldn't delete employee — you appear to be offline. (EMP-DEL)`.

## Design

### 1. Field animation (inside `LabeledTextField`)

`lib/shared/widgets/fields/labeled_text_field.dart`:

- Wrap the internal `TextField` in the existing `AnimatedFormFieldWrapper` (`lib/core/animations/animated_form_field_wrapper.dart`) with `hasError: errorText != null`. Every `LabeledTextField` call site gains the shake with zero call-site changes; new forms get it for free.
- **Required fix in the wrapper (pre-existing bug, explicit work item):** `flutter_animate`'s `.animate()` autoplays on first build, so a field that mounts with `_shakeTick == 0` plays a shake at mount. Guard it: return the bare child until the first error *transition* (`_shakeTick > 0`). Auth screens (the wrapper's existing users) get the fix too; covered by the no-shake-on-first-build widget test below.
- `_FieldError` (and `_MaxLengthWarning`, which reuses it) animates per style A:
  - Entrance: fade 0→1 + translateY(-4px → 0), `AppAnimationDurations.quick` (180ms), `AppAnimationCurves.entrance`.
  - Exit: same reversed.
  - The error slot is wrapped in `AnimatedSize` (also `quick`) so fields below glide instead of jumping. The perceived motion is the fade-slide; the size change is just smoothing.
- Shake replays when `errorText` transitions null → non-null (existing wrapper semantics); it does not replay while the message merely changes text.

### 2. Accessibility (reduced motion)

When `MediaQuery.disableAnimations` is true, both the shake and the fade-slide collapse to instant appearance (duration zero / bare child). Mirrors the existing `accessibleNavigation` handling in `NoticeListener`.

### 3. Error cause + tag (`lib/core/errors/error_cause.dart`, new)

A core helper used by exception-driven catch sites:

- `ErrorCause classifyError(Object error)` → enum `{offline, permissionDenied, notFound, unknown}`:
  - `offline`: `FirebaseException` codes `unavailable`, `network-request-failed`, `deadline-exceeded`; `SocketException`; `TimeoutException`.
  - `permissionDenied`: `FirebaseException` code `permission-denied`.
  - `notFound`: `FirebaseException` code `not-found`.
  - everything else: `unknown`.
- `String composeErrorNotice(BuildContext context, {required String intro, required String tag, required Object error})` → fills the l10n template `error_noticeWithCause` (`"{intro} — {cause}. ({tag})"`) so FR can reorder. `unknown` cause renders the template with the generic cause string.
- **Security rule respected:** only the four sanitized cause strings ever reach UI; raw Firebase codes and stack traces never do. Full detail still goes to Crashlytics via the existing `logger.warn`.
- At each tagged catch site, prepend the tag to the existing log label: `logger.warn('EMP-DEL deleteEmployee failed', e, st)` — a tester's screenshot then matches a Crashlytics line exactly.

### 4. Tagged call sites (13)

| Tag | File | Operation |
|---|---|---|
| EMP-DEL | `employee_details_view.dart` (delete catch) | delete employee |
| EMP-STATUS | `employee_details_view.dart` (disable/enable catch) | toggle employee status |
| EMP-CREATE | `employee_form_sheet.dart` | create employee account |
| APPT-CREATE | `add_appointment_sheet.dart` | create appointment |
| APPT-SAVE | `details_edit_body.dart` (`EventDetailsFailed`) | save appointment changes |
| APPT-DEL | `details_edit_body.dart` (delete catch) | delete appointment |
| APPT-LOAD | `main_calendar_screen.dart` (stream `ref.listen`) | appointments stream error |
| ACCT-DEL | `settings_screen.dart` (generic catch) | delete account |
| CLI-ADD | `add_client_sheet.dart` | add client |
| CLI-SAVE | `client_detail_view.dart` (save catch) | update client |
| CLI-DEL | `client_detail_view.dart` (delete catch) | delete client |
| HIST-LOAD | `appointment_history_view.dart` (error branch) | history stream error |
| CLI-LIST | `clients_list_view.dart` (first-page error state) | clients page load error |

Untouched: typed-failure paths that already produce specific messages (e.g. `AuthFailure.toLocalizedMessage` flows, `employee_form_sheet`'s email-specific error), and non-exception notices (`error_colorAlreadyUsed`, `settings_appLockUnavailable`).

**Required controller change (APPT-SAVE):** the save-changes view receives an `EventDetailsFailed` outcome object, not the exception. Add the original error to `EventDetailsFailed` (e.g. an `Object error` field set in the controller's catch block) so the view can run `composeErrorNotice` on it. This is an explicit work item, not an optional note.

### 5. Localization

New keys in **both** `app_en.arb` and `app_fr.arb` (lockstep, each with `@key` metadata, prefix buckets per convention):

- `error_noticeWithCause` — template with `intro`, `cause`, `tag` placeholders.
- `error_causeOffline`, `error_causePermissionDenied`, `error_causeNotFound`, `error_causeUnknown`.
- Short intro keys (`error_intro*`) for the 13 operations. Where an existing key already reads as a clean intro, reuse it; where the existing text embeds "please try again" (which would double up with the cause sentence), add a trimmed intro key instead. Existing keys stay (other call sites may use them).

Run `flutter gen-l10n`; check `untranslated.json` stays empty.

## Testing

- Plain `test()`s for `classifyError` (each Firebase code, `SocketException`, `TimeoutException`, unknown fallback) and for `composeErrorNotice` formatting via `lookupAppLocalizations`.
- Controller test: a failing save produces an `EventDetailsFailed` carrying the original error.
- Widget tests for `LabeledTextField`: error row appears after animation settles; errorText null→set triggers exactly one shake; no shake on first build with a pre-set error; `disableAnimations: true` renders instantly; `tester.takeException()` null throughout (l10n delegates per testing.md harness rules).
- Full `flutter test` + `flutter analyze` (must stay 0 issues) before completion.

## Out of scope

- Top notices and SnackBars (already animated).
- Auth screens' Material `errorText` styling (they keep their existing wrapper + decoration).
- Dialog animations (Material default).
- Any retry/offline-queue behavior — this is presentation + diagnostics only.
