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
  is done; only the GCP log-based exclusion remains. **Lower value than when
  filed** — a check on 2026-09-02 found ZERO error-severity function log entries
  in the preceding ~31 hours, so the noise this exclusion was written for is not
  currently arriving. Re-check before spending console time on it.
- **Wave settings check.** Open the Wave settings screen and press "Retry
  failed" only if the app still reports parked Wave work. Still unverified from
  here: `firestore_query_collection` fails reproducibly with
  `'read_time' cannot be in the future`, which is the same MCP tool error the
  2026-09-01 audit hit, and `firestore_list_documents` silently ignores
  `orderBy`, so the `status == 'dead'` count cannot be read without paging the
  whole queue. Indirect evidence is good: no dead-letter log line since
  2026-08-29, and the blank-client-name doc was repaired 2026-08-30.

### Blocked, not merely waiting

- **Crashlytics follow-up — the premise changed.** The two open issues both
  report `lastSeenVersion: 1.54.0`, which reads as "fixed in 1.55.0". It is not:
  a `topVersions` report on 2026-09-02 shows **1.55.0 (84) is absent from the
  fleet entirely** — every event in the trailing week came from 1.54.0 (83). The
  Dart half of 1.55.0 was never shipped, so the silence is absence of fleet, not
  absence of the bug. This cannot be closed by waiting; it reopens as a check
  *after* an app build actually ships. (Same shape as the index-prefix lesson:
  a thing that looks confirmed because the evidence that would contradict it
  cannot arrive.)

  The two issues, for that later check:
  - `cloud_firestore/permission-denied` in `messages.pigeon.dart` — NON_FATAL,
    first seen 1.26.0, 12 events / 2 users in the trailing week.
  - `GooglePlacesRepository.getPlaceDetails` / `MapsFailureRateLimit` —
    NON_FATAL, first seen 1.54.0, 4 events / 2 users.

### Product decisions / feature work

All of I18's product half is now closed. Week view, the per-technician calendar
filter, "on my way" / "running late" crew status, technician search and the
server-owned `startedAt`/`completedAt` job time record landed on 2026-09-01;
**"Book again" landed 2026-09-02** (see below).

### Release/manual wiring

- **`InfoPlist.strings` target membership — DONE in the repo, unverified on the
  Mac.** `ios/Runner.xcodeproj/project.pbxproj` was hand-edited on 2026-09-02 to
  add both file references, the `InfoPlist.strings` variant group, `fr` to
  `knownRegions`, and the build-file entry in Runner's Resources phase. It was
  validated structurally (balanced braces/parens, no undefined UUID references,
  no duplicate object ids, CRLF preserved, entries in sorted position so Xcode
  will not churn the file). **Open the project in Xcode once before relying on
  it**: confirm `InfoPlist.strings` appears under Runner with en/fr children and
  in Build Phases → Copy Bundle Resources. "The file parses" and "Xcode agrees"
  are different claims and only the first was checked.

## Closed since the 2026-09-01 cleanup

- **The `firestore.rules` comment removal was DELIBERATE** (owner call,
  2026-09-03), and the same trim was then applied across the release scope. The
  release review had raised the ~450 deleted rationale lines as a possible
  documentation regression; it is not one, and it is not an audit finding.
  `.claude/rules/code-quality.md` now records the policy: one line max, the
  "why" lives in the rules files rather than in the source. Don't re-file this,
  and don't restore a deleted block — if a fact it carried is missing from the
  rules files, add it there.

- **Five defects found by the 1.56.0+85 release review**, all fixed in that
  release. Two were user-visible: **"Start job" dismissed the sheet** (it shared
  the closing actions' outcome handler, so the crew was thrown out of the one
  screen holding the notes box, the photo picker and the "Started …" line the
  tap had just created), and **the crew-status push could name the wrong
  person** (`toIdList` FILTERS `employeeIds` while `employeeNames` was indexed
  raw, so one droppable entry ahead of the sender shifted the two lists apart;
  the name now has one pure owner, `crewStatusSenderName`). The other three:
  a stored-blank assignee name rendered " is running late" rather than the
  fallback; a thin `{'status':'done'}` patch on a doc the history scan window
  had never seen inserted a blank row dated `now()` into the admin window and
  was dropped outright from a scoped one (so a technician could not find the
  job they had just completed); and `_scopeKey` mapped `null` and `''` to the
  same window, which would have served an admin an empty history search.
  All five are pinned.

- **"Book again"** (`AppointmentPrefill`, 2026-09-02) — the last I18 product
  item. An admin-only outlined action, last in `DetailsActionBar` because it is
  the one action that does not change the job it is on, offered on any client
  job including a closed one (a repeat callback usually follows a finished
  visit) and never on a personal block, a read-only surface, or to a technician.
  It opens the ordinary add sheet pre-filled with client, address, title, brief,
  materials, crew and job length, and deliberately **no date or time** — the
  admin picks when, and the job saves `pending` like any other. The
  carries-over / stays-behind contract lives in the pure
  `AppointmentPrefill.bookAgain` and is pinned from both sides, so a field added
  to `AppointmentRecord` that leaks into a duplicate fails a test.
  `usesCustomAddress` was extracted to
  `calendar/domain/policies/custom_address_policy.dart` so the prefill and the
  edit form cannot disagree about the address pill, and
  `JobTemplate.endMinutesOfDay` was folded into
  `AppointmentDraftDefaults.endTimeFor` so a template chip and a book-again seed
  the end time through one owner.
- **l10n prefix buckets** — `CLAUDE.md` listed 12 buckets, four of which do not
  exist. It now lists the real 17, records that `app_` has zero keys, and warns
  that `liveMap_` is the one lowerCamel prefix.
- The three code-quality refactors (the debounced-search block, `_onAddClient`,
  the error-key clearing) all landed on 2026-09-01 as `DebouncedPagedSearch`,
  `runAddClientFlow` and `AppointmentFormConcerns`.

## Closed in the 2026-09-01 cleanup

Security findings S1, S2, S4, S5 and S6 are closed. Bug findings B1-B7 are
closed. Improvements I1-I17 are closed except for the owner-only log exclusion
noted above.

The closed details remain in the archived snapshot for historical review, but
they are no longer active audit work.

## Found on 2026-09-02 while closing the list — the branch was NOT green

The 2026-09-01 work was recorded as "3141 flutter, green". It was not: HEAD
(`74f71aa6`) carried **two failing tests** in
`test/features/calendar/screens/main_calendar_screen_test.dart`, both introduced
with the week-view / crew-filter commits, and reproduced in a clean worktree at
HEAD with none of the 2026-09-02 work applied. One was a real product bug.

- **The crew filter offered an EMPTY roster — real bug, would have shipped.**
  `CrewFilterButton._pick` did `ref.read(assignableEmployeesProvider)` inside
  the tap handler. That provider derives from the `autoDispose`
  `employeesStreamProvider`, and nothing else on the calendar screen subscribes
  to it — so the read built it cold, got `AsyncLoading` back, took the
  `?? []` branch and disposed it again. The sheet showed "All crew" and nobody
  else, **every** time, not just the first. Fixed by watching the roster in
  `build` (the add-appointment sheet already does) and passing the resolved
  list into `_pick`.
- **The week test's failure was a date-dependent TEST bug**, the same class as
  the `DateFormat.MMMM()` one. `_wrap` handed the same single-subscription
  `Stream.value` to every key of the range-keyed `appointmentsInRangeProvider`
  family. Tapping a week bar that belongs to the previous month moves the
  focused month, so Riverpod builds a second family instance and listens
  **again** — getting nothing, and the agenda reads "0 JOBS" rather than
  throwing. It only bites on dates where a day tap crosses a month boundary,
  which 2026-09-02 (Wednesday, week starting Sunday 2026-08-30) is. The
  override now replays the first event per listener.
- Three pre-existing analyzer `info`s from the same commits were fixed, so
  `flutter analyze` is back to the documented `No issues found!` baseline. The
  `employeeId: null` one is `// ignore`d rather than deleted: it is the
  unscoped twin of `employeeId: 'e1'` and dropping it would make the
  admin/technician split assert nothing.

**Lesson worth keeping:** a subagent reported the baseline as 3215/2 failing
rather than the recorded 3141/green, and it was right. Re-measure the baseline
before attributing a failure to your own diff — and treat a recorded green as a
claim, not a fact.

## Not an audit finding, recorded so it is not re-diagnosed

`notifyappointmentchanges` crash-looped on 2026-09-01 between 17:22 and 17:24
UTC — "Could not load the function, shutting down", `exit(1)`, failed startup
probes — during the `02f540eb` deploy rollout. It recovered at 17:25 and every
instance start since has succeeded. A bad revision during rollout, not a
standing fault; no action.
