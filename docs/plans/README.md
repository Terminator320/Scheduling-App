# Active plans — index and outstanding work

Swept 2026-08-11, re-swept 2026-08-15, **re-swept 2026-09-06** against what the
code, `git log` and the deploy log actually say. The 2026-09-06 pass moved
fourteen documents to `docs/archive/` (the simplified-auth pair, four August
calendar/day-off designs, the per-day appointments pair, client-building
grouping, calendar holidays, the superseded clients address filter, the
feature-tour 1.57 pair and the 2026-09-03 mobile audit) and rebuilt the index
below, which had gone **21 files behind** — every plan written after 2026-08-15
was missing from it. Everything left in this directory is either **live work**
or a reference a live plan depends on. Dated audit snapshots live in
`docs/audits/` until they are superseded, then they move to the archive too.

**Current state of the code is `CLAUDE.md`, `docs/ARCHITECTURE.md` and
`docs/CLOUD_FUNCTIONS.md` — never a plan doc.** A plan records how something was
decided and built; several here have unticked checkboxes for work that shipped
weeks ago, because they were executed without ticking. Trust the status banner
at the top of each file, not its boxes.

---

## Index

| Doc | State |
|---|---|
| `2026-07-29-redesign-program.md` | **COMPLETE.** P1–P5 and P7 shipped; **P6 and P7b CANCELLED by owner call 2026-09-06.** Owes nothing further — kept as the program record. |
| `redesign-subdocs/` | The build record for P1 through P7 — see the README in there. P4b is **withdrawn**; P6 and P7b are **cancelled**. |
| `redesign-subdocs/2026-07-30-p1-p2-DEVICE-TEST.md` | **§0–§10 closed 2026-08-11**, owner-reported passing. The **P5 block (18 checks) is still unrun** — no longer blocked (the deploy landed 2026-08-11), but it needs a technician account. |
| `2026-07-10-siri-app-intents-design.md` | Design, 6 phases. Phases 5–6 unscoped. |
| `2026-07-19-siri-app-intents-implementation.md` | Phases 1–3 built; **no device pass ever run**. |
| `2026-07-20-siri-phase4-write-actions.md` | **NOT STARTED.** Mac + Apple-portal session. |
| `2026-08-28-address-street-locality-split.md` | **Shipped and deployed; the prod backfill's LIVE run is the one thing open.** `backfill-client-address-street.js` has only dry-run against prod (2026-08-28: 714 scanned, 114 reduced). Cleanup, not a defect — the app renders both stored shapes. |
| `2026-08-30-wave-validated-contract-design.md` | **Phase 1 built and deployed 2026-08-30** (`485c88cb`, report-only). Phases 2–4 deliberately unwritten until the prod replay lands. |
| `2026-08-30-wave-validated-contract-implementation.md` | Phase 1's task list. Its last step — `functions/scripts/audit-wave-contract.js` against prod — **has never run**; this box has no ADC. |
| `2026-09-04-carplay-driving-task.md` | **PLAN, not started.** Written 2026-09-04, awaiting owner review. |
| `2026-09-04-clients-page-search-first.md` | **Implemented 2026-09-05** (`68ae7d37` + `d84cae53`), released 1.58.0+87. **Backend undeployed** — two `clients` composites must be READY and `backfill-client-sort-fields.js` must run before the sorts work. Supersedes the archived address-filter doc. |
| `2026-09-04-clients-page-search-first-implementation.md` | Its task list. Same deploy gate. |
| `2026-09-05-add-job-client-picker.md` | **Built and released the same day** as 1.58.0+87 (`d7e8294f`). Its banner claimed "no code written" until this sweep. **Not usable in prod** until `searchClients` deploys. |
| `2026-09-05-add-job-client-picker-implementation.md` | Its task list, boxes ticked in `f884e120`. Same deploy gate. |
| `APP_STORE_SUBMISSION.md` | **The live release runbook**, now for updates rather than a launch — the app shipped. Its unticked boxes have never been reconciled against four shipped submissions, so read one as *unknown*, not *outstanding* (§7). |

---

## What has not been done

### 1. The backend deploy — a THREE-RELEASE DEBT is open again

The P5/multi-day deploy this section was written for landed 2026-08-11 at
`70579d22` (release 1.45.0+72), which unblocked the P5 device block in §4 and
shipping an app build carrying the P5 UI — the ordering hazard was that the
rules clause had to be live first, or every self save fails `permission-denied`.

**Nothing about deploy state should be read from this file** —
**`docs/DEPLOYMENT.md` is the only reliable record of what production runs**;
read its log rather than any paragraph here. As of the 2026-09-06 sweep that
log's last row is **2026-09-03**, and prod is running **25 functions while the
repo declares 29**. So the debt spans 1.56/1.57/1.58, and its ordering matters:

- The three `indexed_search.js` callables (`searchClients`, `searchHistory`,
  `findAppointmentConflicts`) plus `restoreAppointmentStatus` are undeployed.
- Their composite indexes must be READY **and**
  `functions/scripts/backfill-search-tokens.js` must have run before the app
  build that calls them ships — an unbackfilled document is invisible to the
  search that replaced the client-side scan.
- The search-first clients work adds two more `clients` composites and
  `backfill-client-sort-fields.js` on top of that.
- Until this deploys, Wave clients keep arriving with an empty phone field, and
  the 1.58 phone-first client picker cannot work at all.

`docs/DEPLOYMENT.md` §"TODO 1.57.0+86" holds the ordering runbook.

### 2. Redesign — COMPLETE. P6 and P7b were CANCELLED 2026-09-06

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
- **P6 Time off — CANCELLED (owner call 2026-09-06).** It had been deferred
  since 2026-08-10; this closes it and it will not be built. Nothing was ever
  built for it — no `timeOff` collection, no rules, no surfaces — and the last
  trace in the code, a comment reserving the `PushedDestination.timeOff` slot in
  `drawer_catalog.dart`, was deleted with the cancellation. **What stands in its
  place is permanent, not a stopgap:** a personal block / day off makes someone
  read as unavailable because `findBusyEmployees` deliberately does not filter
  it. There is no request/approve flow, no allowance, and there will not be one.
  The design is kept intact in the program spec as the record of what was
  decided.
- **P7b Wave invoice read path — CANCELLED (owner call 2026-09-06).** Never
  started, and will not be. Two consequences are now permanent rather than
  pending, and are documented at their sites: P7's **six money sections** stay
  omitted (empty-omitted rule, not stubbed), and the dashboard's **Year** period
  stays absent — P7b was the aggregate read path that would have served it. Do
  not "add Year back" by widening `fetchInRange`; a year is ~1,825 jobs even at
  5/day against a 1000-doc cap, so it would report a prefix as a total. See
  `lib/features/dashboard/domain/dashboard_period.dart`.

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

**The backfills in the bullet list below have all RUN against prod; each is
listed so nobody re-runs one. THREE OTHERS HAVE NOT RUN and are real work
items** (corrected 2026-09-06 — this heading said "every backfill named here"
and read as though nothing was outstanding):

- `backfill-search-tokens.js` — **a prerequisite for the 1.57/1.58 release, not
  a follow-up.** Until it runs, `searchClients` / `searchHistory` return nothing
  for every client and closed job written before 2026-09-04.
- `backfill-client-sort-fields.js` — gates the search-first clients screen's
  Most jobs / Recently added sorts.
- `backfill-client-address-street.js` — the live run. Only ever dry-run against
  prod (2026-08-28: 714 scanned, 114 reduced, 600 left alone). Optional cleanup:
  the app renders both stored address shapes correctly.

- **The client name/phone rewrite — ran, reversed, re-ran, and destroyed data on
  the way through.** `backfill-client-phone-from-name.js` ran 2026-08-08: it
  lifted the phone number out of `clients/{id}.name` and renamed `name` to
  "First Last". Correct for the app, wrong for Wave — `name` is synced VERBATIM
  as the Wave customer name (`toWaveCustomerInput`) and the invoicing workflow
  identifies customers by number, so it renamed those customers on real Wave
  invoices. **Never run it again.** Owner call 2026-08-14 reversed the rule: the
  number goes back in the stored `name` and the APP strips it for display
  (`ClientNamePolicy.displayName`). `backfill-client-name-with-phone.js` ran
  against prod the same day (**504 renamed**), and
  `backfill-client-phone-formatting.js` with it (**142 reformatted**).
- **That 2026-08-14 run predated the first/last split and DESTROYED the stored
  name on docs that had no `firstName`/`lastName`** — those clients render as a
  bare number. The only surviving copy is `clientName` on the client's SETTLED
  appointments. `restore-client-name-halves.js` writes those back into the two
  halves and never touches `name` (Wave's identity);
  `docs/audits/audit-renamed-client-names.js` is its read-only twin, and the two
  are kept deliberately in step — reading one rule's report and running another
  rule's repair is the failure mode. `restore-business-client-names.js` covers
  the businesses the heuristic caught. The read-only damage audit for the
  2026-08-08 run is `docs/audits/audit-client-phone-backfill-damage.js`.
- **The appointment-images backfill RAN, and was RE-RUN at the CONTRACT step
  2026-08-22** — the current figure is `copied 14 photos across 11
  appointments`, not the superseded `13 / 10` from the 2026-08-15 run. Copy-only
  and idempotent; `pictures` is untouched. **TWO steps of that migration are
  still outstanding, not one**: step 3 (ship the app build) and then step 4 (the
  irreversible clear script, gated on the fleet ageing off builds that still
  write the array). See the deploy log in `docs/DEPLOYMENT.md`, which is the
  authority here; the full audit history is in `docs/archive/`.
- **The three "orphaned Cloud Scheduler jobs" NEVER EXISTED — RESOLVED
  2026-08-23.** Checking found exactly the 3 expected scheduled jobs and no
  orphans; this bullet claimed otherwise for nine days. What the check DID turn
  up is worth keeping: `purgeExpiredHistory` was sitting **PAUSED** with no
  record why (resumed 2026-08-23). Only the Cloud **Scheduler** page shows a
  job's STATE — `functions:list` and Cloud Run both render a paused job
  identically to a healthy one — so check it there after any deploy that
  touches a scheduled function.
- **The `signupCodes` collection and its TTL policy remain in prod**,
  deliberately — the collection was verified empty and rules now deny all
  access. Never `--force` the policy away.
- **One accepted risk is live in the rules:** the 500-char cap added to
  `clients.addressLine2` on 2026-08-15 sits over docs the already-deployed Wave
  import wrote uncapped, and prod could not be inspected (this box's clock skew
  breaks the Firebase MCP's Firestore reads). If an opaque `permission-denied`
  ever appears on an ordinary client save, check that field first.
- **A hard budget cap for Google Maps Platform is still unset** —
  `docs/audits/AUDIT_FOLLOWUPS.md`, the one item in that file still open. It
  needs GCP billing access, so it cannot be done from here.

### 7. App Store — SHIPPED. The runbook is now a release checklist, not a launch one

**ES Pro was accepted by Apple and is live**; 1.45.0+72 was the **4th update**
(owner-reported 2026-08-11). The repo has moved on twice since — 1.46.0+73
(2026-08-14) and 1.46.1+74 (2026-08-15) are cut in `CHANGELOG.md`, and nothing
here records whether either has been submitted; the photo migration's step 3 is
waiting on an app build either way. `APP_STORE_SUBMISSION.md` still reads in places
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
firebase-admin, so it passed on the broken versions too. After any dependency
change here, check the installed versions directly rather than trusting green
tests.

**The "do not bump to `firebase-admin ^14`" warning this section used to carry
is RETIRED (corrected 2026-09-06).** It is in, and has been since the 2026-09-04
maintenance pass: `functions/package.json` declares `^14.3.0` against
`firebase-functions ^7.3.2`, and that is what is installed. The blocker was
never the SDK pairing — it was jest/ESM, and a CommonJS `jose` mock unblocked
it. `npm audit` is clean. See the archived
`docs/archive/MOBILE_APP_AUDIT_2026-09-03.md` for the upgrade record.
