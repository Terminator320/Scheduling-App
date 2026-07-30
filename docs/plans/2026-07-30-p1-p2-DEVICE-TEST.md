# P1 + P2 device test — one check at a time

**Branch:** `redesgin` @ `d4b487f` · **Written:** 2026-07-30 · **Target:** real iPhone, not the Simulator

Neither P1 (foundation/navigation) nor P2 (calendar) has ever run on hardware.
This is the single pass that covers both.

**How to use this:** work top to bottom. Each check is self-contained — do the
action, compare against **Expect**, and mark the box. If something differs,
record it under **Result** in §9 and keep going unless the check says STOP.
Every check names the file that owns the behaviour, so the Claude session on the
Mac can go straight there.

---

## 0. Before the first launch (do these in order)

- [ ] **0.1 — Pull the branch.**
      `git fetch && git checkout redesgin && git pull` → HEAD should be `d4b487f`.
- [ ] **0.2 — Copy the two gitignored files across.** Neither is in git:
      - `dev/.env` — 8 keys. Bundled as an asset; **the app will not start without it.**
      - `ios/GoogleService-Info.plist` — note it lives at the **`ios/` root, NOT `ios/Runner/`.**
- [ ] **0.3 — Do NOT run `flutterfire configure`.** It rewrites
      `lib/firebase_options.dart` into literal-values style and breaks the
      env-based iOS setup. If someone already ran it, `git checkout
      lib/firebase_options.dart` before building.
- [ ] **0.4 — Do NOT look for a Podfile.** This project is **SPM-only**. Xcode
      resolves `firebase-ios-sdk` on first open; `pod install` is not part of
      this repo and never will be.
- [ ] **0.5 — Real device, not Simulator.** App Check uses **App Attest**, which
      fails on the Simulator. On the Simulator every Firestore read/write returns
      `permission-denied`, which will look exactly like a P2 bug and is not one.
- [ ] **0.6 — `flutter pub get`, then build.** Deployment target is iOS 18.0.

### 0.7 — Make UI errors visible (IMPORTANT, and revert after)

`main()` sets `FlutterError.onError = crashlytics.recordFlutterFatalError`, so
**overflow and layout errors go silently to Crashlytics and never appear in
`flutter run` output.** Half the checks below are looking for overflow. Before
testing, temporarily add the console dump in `lib/main.dart`'s handler:

```dart
FlutterError.onError = (details) {
  FlutterError.dumpErrorToConsole(details); // TODO(pre-ship): remove after device test
  crashlytics.recordFlutterFatalError(details);
};
```

- [ ] 0.7 patch applied
- [ ] **0.7b — revert it when the pass is done** (last line of §9)

---

## 1. Launch and shell (P1)

- [ ] **1.1 — Cold launch to the calendar.**
      Expect: splash → calendar. No stall on a static frame.
      *Owner:* `splash`, `routes/hub_shell.dart`
- [ ] **1.2 — The header pair is on every screen.**
      Tap the hamburger (top right) → drawer slides in **from the right**, 284px,
      grouped Today / People / The Business / Account.
      Expect: today's job count and on-shift staff count render on their rows.
      *Owner:* `features/navigation/widgets/app_nav_drawer.dart`
- [ ] **1.3 — The Calendar pill goes home from anywhere.**
      Drawer → Settings → then tap the **Calendar** pill in the header.
      Expect: lands on the calendar tab with the pushed stack collapsed — not
      Settings-with-a-calendar-behind-it.
      *Owner:* `goHomeToCalendar` in `core/navigation/`
- [ ] **1.4 — Back means back.**
      From Settings, use the back arrow (not the pill).
      Expect: returns to whatever pushed it, one level.
- [ ] **1.5 — A notice renders as a dark pill at the TOP.**
      Trigger any success (e.g. mark a job complete).
      Expect: compact dark pill, coloured status dot, top of screen, auto-clears.
      Swipe up dismisses early.
      **STOP if no notice appears at all** — that means `NoticeListener` lost its
      `navigatorKey` and every notice in the app is suppressed.
      *Owner:* `core/notices/`, `main.dart`

## 2. Calendar month grid (P2)

- [ ] **2.1 — Six rows, always.** Navigate to **August 2026** (31 days starting
      Saturday — the month that breaks a 5-row grid).
      Expect: 42 cells / 6 rows, and the 31st is visible. Nothing clipped.
      *Owner:* `calendar/widgets/views/calendar_month_grid.dart`
- [ ] **2.2 — Off-month cells.** Look at the leading/trailing greyed days.
      Expect: faint day number **and crew dots if someone works that day**, but
      tapping does nothing. This is deliberate — see handoff deviation #5.
- [ ] **2.3 — Swipe between months.** Swipe left, then right, several times fast.
      Expect: smooth paging, no crash, the focused day doesn't jump to the 1st.
      **Known past bug:** a `PageView` echoes programmatic jumps back through
      `onPageChanged`; if the selected day resets when you swipe, that guard broke.
      *Owner:* `calendar_month_pager.dart`
- [ ] **2.4 — The month picker still opens.** Tap the month name in the header.
      Expect: bottom sheet with **two wheels** — every month, and years −5/+15.
      Pick a distant month; the grid and agenda follow.
- [ ] **2.5 — Today's circle.** Confirm today is ringed/bold and the dots under
      days match who's actually working.

## 3. The collapse — P2's headline interaction

This is the single most important thing to exercise. Do it slowly first.

- [ ] **3.1 — Slow scroll down.** On a day with enough jobs to scroll, drag the
      agenda up slowly.
      Expect: past ~80px the month grid **unmounts** and a one-week strip rises
      inside the fixed header. The first card must **not** jump position at the
      moment of collapse.
- [ ] **3.2 — Scroll back to the top.**
      Expect: the full month grid returns.
      **STOP-worthy failure:** stays collapsed forever. That means the re-arm
      direction is inverted (arms *below* 44px, fires *below* 6px).
      *Owner:* `calendar/domain/collapse_state.dart`
- [ ] **3.3 — Hover the threshold.** Scroll down ~100px, then back up ~40px, then
      down again, repeatedly.
      Expect: **no flicker.** The grid must not thrash in and out. That 44/6
      two-stage arm exists precisely for this.
- [ ] **3.4 — Fling to the top.** Hard fling upward from deep in the list.
      Expect: re-expands. (A fling skips intermediate frames; both stages are
      evaluated in one pass so it still fires.)
- [ ] **3.5 — Tap a day in the week strip while collapsed.**
      Expect: selects that day, agenda updates, strip stays collapsed.
- [ ] **3.6 — The Today pill.** Select a day that isn't today.
      Expect: a white **pill** (not a round FAB) appears bottom-left. Tap → back
      to today, pill disappears.

## 4. The appointment card (P2)

- [ ] **4.1 — One card everywhere.** Compare a job as it appears on: the calendar
      agenda · Day route · a client's Job history · the Dashboard · History.
      Expect: identical card design in all five.
- [ ] **4.2 — Multi-crew job.** Find/create a job with 2+ assignees.
      Expect: crew line reads **"Theo +1"**, and the left colour bar is the
      **first** assignee's colour — **not grey**. Grey here is the old bug.
- [ ] **4.3 — Unassigned job.** Expect: renders fine, faint bar, no crash.
- [ ] **4.4 — Cancelled job in History.** Expect: struck-through title, dimmed
      (0.6). On the calendar agenda a cancelled job is **not** dimmed — that
      asymmetry is intentional.
- [ ] **4.5 — Overdue job** (past end time, still open).
      Expect: amber warning glyph before the title, "Overdue" chip.

## 5. Detail sheet (P2)

- [ ] **5.1 — Open a job.** Expect: title + status chip on one row, then a single
      mono line like `TUE 4 AUG · 10:30 – 12:00`. No separate calendar/clock icon rows.
- [ ] **5.2 — The info panel.** Expect: `CLIENT / PHONE / ADDRESS / NOTES` in a
      mono key column at left, values right. Phone and address are blue and tappable.
- [ ] **5.3 — Empty sections are absent.** Open a job with no notes.
      Expect: **no** `NOTES` row at all — not "None".
- [ ] **5.4 — Tap the phone** → dialer. **Tap the address** → map chooser.
- [ ] **5.5 — Mark as complete** is a **filled green** button (not blue, not grey).
- [ ] **5.6 — A repeating job** shows its repeat line under the when-line.
- [ ] **5.7 — Employee account:** sign in as an employee and open a job.
      Expect: **no** Edit / Cancel / Delete affordances anywhere.
      **STOP if they appear** — that is a permissions-surface regression.

## 6. Form sheets (P2)

- [ ] **6.1 — Tap + to book a job.** Expect: a bar across the top with
      **Cancel · New Appointment · Save**. No big Save button at the bottom.
- [ ] **6.2 — Save is reachable with the keyboard up.** Tap into Notes so the
      keyboard covers the lower half.
      Expect: the top bar (and Save) stays put and visible. This is the whole
      point of the fixed bar.
- [ ] **6.3 — Sections.** Expect mono headers: `TEMPLATES`, `WHO`, `SCHEDULE`,
      `DETAILS`.
- [ ] **6.4 — The schedule panel.** Expect: Date on its own row, then **Start and
      End side by side** with a divider between, values in blue mono.
- [ ] **6.5 — Pickers work.** Tap Date → date picker. Tap Start → time picker;
      End should auto-advance if you haven't set it manually.
- [ ] **6.6 — Validation.** Hit Save with the form empty.
      Expect: inline errors under the offending rows (e.g. "Please select a date"),
      no crash, Save re-enables.
- [ ] **6.7 — Edit an existing job.** Tap Edit on a job.
      Expect: the same bar chrome, title "Edit Appointment", primary "Save changes",
      and **Delete at the bottom of the scroll** — never in the top bar.
- [ ] **6.8 — Double-tap Save.** Expect: one save, not two. The bar's verb
      disables and shows a spinner while in flight.

## 7. The two dialogs (P2)

- [ ] **7.1 — Scheduling conflict on EDIT.** Take an existing job, edit only its
      **notes**, and save.
      Expect: **NO conflict dialog.** The job must not collide with itself.
      **This is the bug C3 fixed — if the dialog appears here, report it.**
- [ ] **7.2 — A real conflict on edit.** Move a job onto a slot where its assignee
      already has another job.
      Expect: the conflict dialog *does* appear, naming the busy person.
      Tap Cancel → returns to the form, **Save is usable again** (not stuck spinning).
      Tap Schedule anyway → saves.
- [ ] **7.3 — Repeat scope dialog.** Save a change to a repeating job.
      Expect: two radio options **with real numbers** — e.g. "12 remaining visits
      through 26 Jan" — and the button label changes between **"Save this visit"**
      and **"Save 12 visits"** as you switch. Defaults to this-visit-only.
- [ ] **7.4 — Delete a repeating job.** Expect: same dialog shape, and the confirm
      button is a **readable solid red** (check this again in dark mode, §8).

## 8. Dark mode

Switch to dark (Settings, or system) and re-check:

- [ ] **8.1 — Calendar** — header, grid, dots, week strip.
- [ ] **8.2 — Cards** — crew colour bars must still be distinguishable.
- [ ] **8.3 — Detail sheet** — the green "Mark as complete" must be readable.
- [ ] **8.4 — The delete confirm button.** Expect: solid readable red.
      **This is the specific thing C4 fixed** — it used to use the lifted
      foreground red as a fill and was unreadable in dark.
- [ ] **8.5 — Status bar icons** on the calendar. Expect: correct contrast
      against the header. The calendar has no app bar, so it sets this itself —
      if the icons vanish into the background, `AnnotatedRegion` is wrong.
- [ ] **8.6 — Notices** in dark.

## 9. Large text (2×) and landscape

- [ ] **9.1 — Set text size to max** (iOS Settings → Display → Text Size, or
      Accessibility for the larger range).
- [ ] **9.2 — Calendar header at 2×.** Expect: the month title and the
      route/Calendar/menu controls **stack onto two rows**. No yellow-black
      overflow stripes. (Unstacked, this overflowed by 138px.)
- [ ] **9.3 — Month grid at 2×.** Expect: taller rows, no clipping. Note: column
      width can drop under 48px on a narrow phone — accepted, a 7-column week
      can't do better.
- [ ] **9.4 — Job form at 2×.** Expect: Start/End stack vertically instead of
      sharing a row.
- [ ] **9.5 — Detail sheet at 2×.** Expect: the key/value panel stacks label
      above value.
- [ ] **9.6 — Rotate to landscape.** Expect: month grid and agenda **side by
      side**, and **NO collapse behaviour at all** — collapse is portrait-only.
- [ ] **9.7 — Rotate back.** Expect: collapse works again, nothing wedged.
- [ ] **9.8 — Reset text size** before continuing.

## 10. Device-only paths (no test coverage — look carefully)

- [ ] **10.1 — Camera capture.** Job form → photos → Camera. Take a shot.
      Expect: permission prompt first time, image lands in the strip.
- [ ] **10.2 — Gallery pick.** Expect: OS photo picker, no permission prompt.
- [ ] **10.3 — Photo upload survives backgrounding.** Add photos, save, background
      the app immediately, return.
      Expect: upload completes or retries; no duplicate photos on the job.
- [ ] **10.4 — Notification deep link.** Trigger a push (assign yourself a job
      from another account) and tap the notification.
      Expect: opens **that job's** detail sheet, not just the app.
- [ ] **10.5 — Home-screen widget tap.** Add the widget, tap a job row.
      Expect: same — the appointment sheet opens.
      *If it merely launches the app,* the `homeWidget` query param was dropped
      from the deep-link URL (see CLAUDE.md — three Swift producers must append it).
- [ ] **10.6 — Offline save.** Turn on Airplane mode, try to save a job.
      Expect: a fast, clear offline notice — **not** a spinner that hangs.

---

## Results

| # | Check | Pass? | Notes |
|---|---|---|---|
| | | | |

Record anything that differs from **Expect** here, with the check number. For a
visual issue a screenshot is worth more than a description. For a crash or a
silent failure, grab the `flutter run` console output — with the §0.7 patch in
place, overflow errors will actually print.

- [ ] **Final: revert the §0.7 `dumpErrorToConsole` patch** before committing anything.

---

## Notes for the Claude session on the Mac

- Start from `docs/plans/2026-07-30-p2-HANDOFF.md` §2 — it lists **14 deviations
  with their reasons**. Several checks here (2.2 off-month dots, 4.4 the dim
  asymmetry, 9.3 sub-48px columns, 9.6 no landscape collapse) will *look* wrong
  to a fresh reader and are deliberate. Read that before "fixing" one.
- The behaviour is on `redesgin` @ `d4b487f`. Static gates are already green
  (analyze 0 issues, 1173 tests) — a failure here is a device/integration issue,
  not something the suite would have caught.
- **Do not fix and push from the Mac without re-running `flutter analyze` and
  `flutter test`.** The repo's standard is a 0-issue analyzer baseline.
- If a check fails, the fastest triage is usually: which of the three is it —
  a layout/overflow issue (§0.7 console will show it), a permissions/rules issue
  (`permission-denied` in the console → check `firestore.rules`, and confirm it's
  not §0.5 Simulator/App Attest), or a genuine logic bug (reproduce, then find
  the owning file named in the check).
