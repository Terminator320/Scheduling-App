# Codebase Audit - current action list

This is the cleaned-up live audit review. The full 2026-09-01 audit snapshot is
archived at `docs/archive/CODEBASE_AUDIT_2026-09-01.md`; it keeps the original
findings, implementation notes and verification record.

Closed implementation findings were removed from this rolling file so the audit
only reads as work still left to do.

## Still open

### Owner-only / console work

- **Maps Platform hard budget cap.** Still open from S3. This needs GCP billing
  admin access and cannot be completed from the local repo. The runbook is in
  `docs/audits/AUDIT_FOLLOWUPS.md`.
- **Functions log exclusion for external scanner noise.** The code-side I17 work
  is done; only the GCP log-based exclusion for callable-protocol/CORS scanner
  noise remains.
- **Crashlytics follow-up.** Confirm the two Places-related Crashlytics issues
  stay gone once build 1.55.0+84 has real fleet time.
- **Wave settings check.** Open the Wave settings screen and retry failed jobs
  only if the app still reports parked Wave work.

### Product decisions / feature work

These were deliberately left out of the cleanup because each needs product
shape, UI and tests rather than a narrow audit patch.

- Week view.
- Per-technician calendar filter.
- "Running late" / "on my way" status.
- Duplicate / "book again" action.
- Technician search.
- A job time record using `startedAt` / `completedAt`.

### Release/manual wiring

- Add `ios/Runner/en.lproj/InfoPlist.strings` and
  `ios/Runner/fr.lproj/InfoPlist.strings` to the Runner target in Xcode before
  relying on the localized permission prompts in a shipped build.

### Remaining refactors

- Extract the duplicated debounced-search-over-`PagingController` block shared
  by `clients_list_view.dart` and `appointment_history_view.dart`.
- Collapse the two `_onAddClient` implementations in `clients_screen.dart` and
  `clients_list_view.dart` into one owner.
- Extract the repeated appointment-form error-key clearing logic currently
  spelled across the add/edit controllers.

## Closed in the 2026-09-01 cleanup

Security findings S1, S2, S4, S5 and S6 are closed. Bug findings B1-B7 are
closed. Improvements I1-I17 are closed except for the owner-only log exclusion
noted above. I18's mark-done haptic and localized iOS permission prompt work are
closed; the rest of I18 is listed above as product work.

The closed details remain in the archived snapshot for historical review, but
they are no longer active audit work.
