# Active plans — index and outstanding work

Swept 2026-08-11. Everything left in this directory is either **live work** or a
reference a live plan depends on; ten documents whose work has shipped moved to
`docs/archive/` in that sweep (see its README for what and why). Dated audit
snapshots live in `docs/audits/` until they are superseded, then they move to
the archive too.

**Current state of the code is `CLAUDE.md`, `docs/ARCHITECTURE.md` and
`docs/CLOUD_FUNCTIONS.md` — never a plan doc.** A plan records how something was
decided and built; several here have unticked checkboxes for work that shipped
weeks ago, because they were executed without ticking. Trust the status banner
at the top of each file, not its boxes.

---

## Index

| Doc | State |
|---|---|
| `2026-07-29-redesign-program.md` | **P1–P5 and P7 shipped.** What it still owes is **P6** (deferred, skippable) and **P7b**. The binding spec for both. |
| `redesign-subdocs/` | The build record for P1 through P7 — see the README in there. P4b is **withdrawn**. |
| `redesign-subdocs/2026-07-30-p1-p2-DEVICE-TEST.md` | **§0–§10 closed 2026-08-11**, owner-reported passing. The **P5 block (18 checks) is still unrun** — no longer blocked (the deploy landed 2026-08-11), but it needs a technician account. |
| `2026-07-10-siri-app-intents-design.md` | Design, 6 phases. Phases 5–6 unscoped. |
| `2026-07-19-siri-app-intents-implementation.md` | Phases 1–3 built; **no device pass ever run**. |
| `2026-07-20-siri-phase4-write-actions.md` | **NOT STARTED.** Mac + Apple-portal session. |
| `APP_STORE_SUBMISSION.md` | **The live release runbook.** 26 items open. |

---

## What has not been done

### 1. ~~The backend deploy~~ — DONE 2026-08-11, and it was the biggest item here

Deployed at `70579d22` (release 1.45.0+72), targets **functions, rules,
storage**, 25 functions live — no export change, so no deletion prompt and none
of the 2026-08-08 abort. The full row is in `docs/DEPLOYMENT.md`, which is the
only reliable record of what production runs; read it rather than this
paragraph. What went live: P5's `changeEmployeeEmail` self branch with its
`assertFreshReauth` gate and 20/h → 5/h budget, the
`isSelf() && isAvailabilityOnlyChange()` clause on `/users`,
`isValidAppointmentSpan` with its +2h DST allowance, the multi-day Live Activity
skip, and the `day_slice_utils.js` day-scoping behind the widget payload and
push text. `firestore:indexes` was deliberately omitted, which is also what
leaves the surviving `signupCodes` TTL policy alone — never `--force` it away.

**What this unblocks:** the P5 device block in §4, and shipping an app build
carrying the P5 UI (which was the ordering hazard — the rules clause had to be
live first, or every self save fails `permission-denied`).

### 2. Redesign — P6 and P7b remain

- **P5 — SHIPPED AND DEPLOYED 2026-08-11**
  (`redesign-subdocs/2026-08-10-p5-my-details.md`). All three phases built and
  live: the rules clause is called and `updateSelfDetails` exists (A); an
  employee moves their own sign-in email through `changeEmployeeEmail`'s new
  `self` branch, with re-auth, confirm-twice and an active-admins fan-out (B);
  and the P4-parked time-to-leave toggle is live end to end (C). **Still not
  device-verified** — the whole self-service path is unreachable as an admin, so
  it needs a **technician** pass, and that is now the only thing outstanding on
  it. Deliberate deviations from the spec, all recorded in the
  plan's decisions section: no duplicate NOTIFICATIONS block (Settings already
  owns it), no duplicate profile card, SCHEDULING scoped to `maxJobsPerDay`, and
  the identity fields explicitly saved behind a Save/Discard bar (owner call)
  while availability keeps apply-immediately.
- **P6 Time off — NOT STARTED, and DEFERRED (owner call 2026-08-10). Skippable.**
  No `timeOff` collection, no rules, no surfaces; the only trace in the code is
  two comments reserving the `PushedDestination.timeOff` slot. It was never a
  prerequisite for P7, and P7 shipped without it — the three places P7 reaches
  into P6 (the Time off card, the drawer pending count, the pending-time-off
  Attention entry) are **omitted, not stubbed**, per the spec's own
  empty-omitted rule. The design is kept intact in the program spec for whenever
  it is picked up; its four backend requirements were re-verified 2026-08-10 and
  all still hold (an active-admins fan-out query, the EN+FR `_MESSAGES` rows, a
  `kind`-aware `_handlePushTap`, and a new ledger + TTL). The fan-out is no
  longer new work — P5 built and shipped `sendToActiveAdmins`.
- **P7 — BUILT 2026-08-11, both halves**
  (`redesign-subdocs/2026-08-11-p7-dashboard-history.md`, phases A–D). App-side
  only; nothing to deploy. Dashboard: the period control ships as **Today ·
  Week · Month; Year is dropped** — `fetchInRange` caps at 1000 docs and a year
  is ~1,825 jobs even at 5/day, so Year could only have reported a silent
  prefix, and it needs P7b's aggregate read path first. Also
  jobs-booked-per-day with an over-capacity line, New clients as tappable rows
  (archived now excluded — a behaviour change), and two new Attention flags
  (accounts never set up, booked-outside-availability). History: the date rail
  under a sticky month bar, which cost mostly the re-owned pagination a sticky
  header cannot share with `PagedListView`. **Not device-verified.**
- **P7b Wave invoice read path — not started.** It is what unblocks P7's six
  money sections, which the spec deliberately omits until then, and the
  dashboard's dropped **Year** period.

### 3. Siri

Phases 1–3 are code-complete and have **never been run on a device** — that is
the whole of what stands between them and done. Phase 4 (voice write actions)
is specified end to end but nothing is landed: it needs one Mac session doing
the Apple-portal keychain-sharing capability, a second Firebase app for the
extension's App Attest, and the entitlement XML, in that order — landing the
XML first breaks signed builds.

### 4. Device verification — §0–§10 closed, the rest still open

`redesign-subdocs/2026-07-30-p1-p2-DEVICE-TEST.md` is the runbook. **Its §0–§10
were closed 2026-08-11 on the owner's report** that he had run them on hardware
— recorded on his word, with no console capture or screenshot behind any
individual box, so a later contradiction means "re-run that check", not "a
regression against a known-good baseline". Read the banner in its Results
section before relying on a specific box.

**Still unrun:** the **P5 block (18 checks)**, which is now **unblocked** — the
deploy in §1 landed 2026-08-11, so a `permission-denied` there is no longer the
expected symptom of a missing deploy and should be read as a real finding. It
needs a **technician** account; the path is unreachable as an admin. Also never
exercised on a device:
every P3/P4/P4c surface, the drawer icons + the 43 tour steps, the closed-jobs
agenda, the photo cue, the restyled History, and the P7 dashboard — none of
those has a runbook at all, which is now the real gap here. The Swift halves of
the multi-day mirrors (widget decoder + Siri snapshot v3) are likewise
Xcode/device-unverified; Swift has no test harness.

If a pass is ever driven from the repo, read §0.7 first: `main()` routes
`FlutterError.onError` to Crashlytics, so overflows never reach `flutter run`
stdout and about a third of the checks are meaningless without the temporary
`dumpErrorToConsole` patch.

One loose end from the P4 device pass is still undiagnosed: a `RawScrollbar`
assertion ("provided ScrollController is attached to more than one
ScrollPosition") seen in the console, with no screen attributed to it.

### 5. One deferred design question — Live Activities for a multi-day job

Carried forward from the multi-day design doc (now
`docs/archive/2026-08-02-multi-day-appointments.md` §10) so it isn't lost with
it. A card counting down to an end four days out would sit on the Lock Screen
for the entire job, so **`resolveReminderForAssignee` skips multi-day jobs
outright** (`dayCountOf(c) > 1`, built 2026-08-11) — the `leaveNow` push still
goes out on day 1, which is the only day with a departure time. That skip is the
containment, not the answer: what a multi-day card should actually be (a per-day
card? a countdown to today's window end?) is an unanswered design question.

### 6. Data and ops

- **The client phone backfill RAN against prod on 2026-08-08, and was REVERSED
  on 2026-08-14. Never run it again.**
  `functions/scripts/backfill-client-phone-from-name.js` lifted the phone number
  out of `clients/{id}.name` and renamed `name` to "First Last". That was correct
  for the app but wrong for Wave: `name` is synced VERBATIM as the Wave customer
  name (`toWaveCustomerInput`), and the invoicing workflow identifies customers
  by number — so it renamed every one of those customers on real Wave invoices.
  Owner call 2026-08-14 reversed it: the number goes back in the stored `name`
  and the APP strips it for display (`ClientNamePolicy.displayName`).
  **The live script is now `backfill-client-name-with-phone.js`** (idempotent,
  `--dry-run`, `--since` defaulting to 2026-08-08 so recently-added clients are
  skipped). Run it when the Wave queue is quiet — it fires `propagateClientEdits`
  and `waveUpsertCustomer`, and the latter now drains inline, so a few hundred
  Wave mutations land within seconds of the last batch against Wave's
  60-calls/min ceiling.
  The read-only damage audit for the 2026-08-08 run is
  `docs/audits/audit-client-phone-backfill-damage.js` (note: its `require` path
  for the superseded script is stale — it points at the repo root rather than
  `functions/scripts/`).
- **The `signupCodes` collection and its TTL policy remain in prod**,
  deliberately — the collection was verified empty and rules now deny all
  access. Never `--force` the policy away.
- **A hard budget cap for Google Maps Platform is still unset** —
  `docs/audits/AUDIT_FOLLOWUPS.md` §2, the one item in that file still open. It
  needs GCP billing access, so it cannot be done from here.

### 7. App Store — SHIPPED. The runbook is now a release checklist, not a launch one

**ES Pro was accepted by Apple and is live**; 1.45.0+72 is the **4th update**
(owner-reported 2026-08-11). `APP_STORE_SUBMISSION.md` still reads in places
like a pre-launch document and **its unticked boxes have never been reconciled
against four shipped submissions** — the app record, pricing, the FR
localization, screenshots and "attach the build and submit" were evidently done
during the first release and simply never ticked. Treat an unticked box there as
*unknown*, not *outstanding*; the count is not a work list.

What is genuinely still open, as far as the repo can tell: the **on-device Part 6
checks** (iPad pass, live map + Routes API, push deep link, home-screen widget,
wake-on-push refresh, Live Activity card, Siri phrases), the **Time Sensitive
Notifications entitlement**, and ASC App Privacy needing **Precise Location**
added. One is blocked by Firestore itself: the `liveActivityCards` TTL policy
cannot be created yet. **A reconciliation pass over Part 13 is worth doing
once** — it is the difference between a checklist and a list of ghosts.

**The legal pages are NOT on that list — they are published and correct.** All
four (`terms-of-service`, `accessibility`, `support`, and the privacy policy
served as the repo's `index`) return HTTP 200 from `gvogas.github.io/es-pro-legal`
and were verified **byte-identical** to `docs/legal/` on 2026-08-11. Keep it that
way: republishing is part of any edit to those files, not a follow-up task, or
the consent checkbox stamps `termsAcceptedAt` against text nobody has read.

### 8. Function SDK downgrade — found and FIXED 2026-08-10, keep it from recurring

`functions/package.json` had been **downgraded** on 2026-08-08 (commit
`11e1db9b`, "updating") from `firebase-admin ^13.6.0` / `firebase-functions
^7.3.2` to `^10.3.0` / `^4.9.0`, with `node_modules` and the lockfile to match.
Production was unaffected — it runs the tree that declared 13.6/7.3.2 — but the
next `firebase deploy` would have installed from that file, and under those
versions `Query.prototype.count` **does not exist** (`@google-cloud/firestore`
4.15.1). Three production paths call `.count()`: `deleteClient`'s
client-has-history gate (`clients.js`), `recountClientJobs`
(`client_job_count.js`) and the Wave outbox depth (`wave/worker.js`) — so a
deploy would have silently broken the one guarantee stopping a client with job
history from being deleted.

`package.json` + `package-lock.json` were restored from the deployed tree
(`5a42743e`) and reinstalled: firebase-functions 7.3.2, firebase-admin 13.10.0,
`@google-cloud/firestore` 7.11.6, `Query.prototype.count` present. `npm run
lint` clean.

**The jest suite cannot catch this class of regression** — it mocks
firebase-admin, so it passed on the broken versions too. Note also that
`firebase-admin ^14` is a known break against firebase-functions 7.x; do not
"fix" a future audit warning by bumping to it. After any dependency change
here, check the installed versions directly rather than trusting green tests.
