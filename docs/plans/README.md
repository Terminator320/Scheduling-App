# Active plans — index and outstanding work

Swept 2026-08-10, and every open plan **reconciled against the code the same
day** — each one carries a dated banner or inline block saying what moved under
it. Four owner calls came out of that pass and are recorded in
`2026-07-29-redesign-program.md`: employees will edit their own phone **and
email** in My details; the dashboard's Attention list gains **accounts never set
up**; **New clients hides archived**; and **P6 Time off is deferred and
skippable**, so the remaining order is **P5 → P7**, with P6 and P7b parallel and
optional. Everything in this directory is either **live work** or a reference a
live plan depends on. Completed plans move to `docs/archive/`
(see its README); dated audit snapshots live in `docs/audits/`.

**Current state of the code is `CLAUDE.md`, `docs/ARCHITECTURE.md` and
`docs/CLOUD_FUNCTIONS.md` — never a plan doc.** A plan records how something was
decided and built; several here have unticked checkboxes for work that shipped
months ago, because they were executed without ticking. Trust the status banner
at the top of each file, not its boxes.

---

## Index

| Doc | State |
|---|---|
| `2026-07-29-redesign-program.md` | **P1–P4c shipped (+P2b).** Remaining order **P5 → P7**; **P6 deferred/skippable**, P7b parallel. The binding spec for the rest. |
| `redesign-subdocs/` | Complete history for P1–P4c — see the README in there. P4b is **withdrawn**. |
| `redesign-subdocs/2026-07-30-p1-p2-DEVICE-TEST.md` | **Open runbook.** ~87 of 95 checks never run. |
| `2026-08-02-multi-day-appointments.md` | Design. Shipped in the app; §10 open items stand. |
| `2026-08-02-multi-day-appointments-PLAN-1-app.md` | **DONE** (`140fc92`). |
| `2026-08-03-multi-day-appointments-PLAN-2-mirrors.md` | **NOT STARTED.** The off-screen mirrors. |
| `2026-07-10-siri-app-intents-design.md` | Design, 6 phases. Phases 5–6 unscoped. |
| `2026-07-19-siri-app-intents-implementation.md` | Phases 1–3 built; **no device pass ever run**. |
| `2026-07-20-siri-phase4-write-actions.md` | **NOT STARTED.** Mac + Apple-portal session. |
| `2026-08-08-completed-jobs-agenda.md` | Built. Its companion **phone backfill has not been run for real**. |
| `2026-08-10-photo-cue-and-day-count.md` | Built. Not device-verified. |
| `APP_STORE_SUBMISSION.md` | **The live release runbook.** 26 items open. |

---

## What has not been done

### 1. Redesign — three projects and a half remain

- **P5 — Phase A BUILT 2026-08-10** (`docs/plans/redesign-subdocs/2026-08-10-p5-my-details.md`).
  The rules clause is called, `updateSelfDetails` exists, and My details now
  carries the identity section (explicit Save/Discard bar — owner call), MY
  AVAILABILITY with the amber conflict warning, and the admin-only SCHEDULING
  panel. 1779 flutter green. **The rules are NOT deployed yet, and must go
  before any app build carrying this UI**, or every self save fails
  `permission-denied`. Phase B (self-service email via a `self` branch on
  `changeEmployeeEmail` + the active-admins fan-out) and Phase C (the
  time-to-leave toggle) are not started. Original scope notes follow:
- **P5 — smaller than the spec says. The Settings half is already built**;
  what remains is My details. `settings_screen.dart` renders the profile card, a
  My-details row, APPEARANCE / SECURITY / NOTIFICATIONS / INTEGRATIONS (Wave) /
  LEGAL / HELP. `MyDetailsScreen` exists but carries **only the emergency-contact
  section**; the self-service phone edit, MY AVAILABILITY (7 day toggles + hours
  + on-call, applying immediately with the amber conflict warning), the
  notifications block and the admin-only SCHEDULING panel are unbuilt. The rules
  half is written and **still uncalled**: P5's job is to add
  `|| (isSelf() && isAvailabilityOnlyChange())` to `allow update` on `/users`,
  not to invent a key list. Two spec corrections made 2026-08-10:
  `emergencyContact` must **not** join that list (it lives in the
  `private/emergency` subcollection and rules now refuse it on the parent doc),
  and the `allow create` loophole the spec flagged was **closed on 2026-08-08**.
  Also parked here from P4: the **time-to-leave alerts toggle**, which needs a
  user-doc flag plus a `runTravelAwareReminderSweep` change.
- **P6 Time off — NOT STARTED, and DEFERRED (owner call 2026-08-10). Skippable.**
  No `timeOff` collection, no rules, no surfaces; the only trace in the code is
  two comments reserving the `PushedDestination.timeOff` slot. **It is not a
  prerequisite for P7** — the build order now runs P5 → P7, with P6 parallel and
  optional like P7b. P7 must **omit, not stub**, the three places it reaches into
  P6 (the Time off card, the drawer pending count, the pending-time-off Attention
  entry), per the spec's own empty-omitted rule. The design is kept intact for
  whenever it is picked up; its four backend requirements were re-verified
  2026-08-10 and all still hold (an active-admins fan-out query, the EN+FR
  `_MESSAGES` rows, a `kind`-aware `_handlePushTap`, and a new ledger + TTL). The
  fan-out is now shared work: P5's self-service email notice needs it too.
- **P7 Dashboard + History — the redesign pass, not the features.** Both
  screens exist from July and work; what is missing is P7's scope. Verified
  absent: the period segmented control (Today · Week · Month · Year) is not
  wired anywhere in `lib/features/dashboard/`. History has year/crew dropdown
  chips already, so its gap is the restyle, not the filtering.
- **P7b Wave invoice read path — not started.** It is what unblocks P7's six
  money sections, which the spec deliberately omits until then.

### 2. Multi-day appointments — Plan 2, the off-screen mirrors

Days 2+ of a run are still invisible outside the app. Verified: no
`functions/day_slice_utils.js`, and neither `widget_sync_service.dart` nor
`functions/widget_payload_utils.js` knows about day slicing; the Siri snapshot
is still schema v2. `CLAUDE.md`, `docs/ARCHITECTURE.md`,
`functions/travel_utils.js` and `functions/notification_policy.js` all carry
"owed by Plan 2" pointers. The design doc's own §10 also stands:

- **Live Activities for a multi-day job** — deferred on purpose (a card
  counting down to an end four days out would sit on the Lock Screen for the
  whole job). Unsolved, not forgotten.
- Whether the 14-day cap deserves a `firestore.rules` bound. Today the cap is
  client-side only, so a console/Admin-SDK write can exceed it.

### 3. Siri

Phases 1–3 are code-complete and have **never been run on a device** — that is
the whole of what stands between them and done. Phase 4 (voice write actions)
is specified end to end but nothing is landed: it needs one Mac session doing
the Apple-portal keychain-sharing capability, a second Firebase app for the
extension's App Attest, and the entitlement XML, in that order — landing the
XML first breaks signed builds.

### 4. Device verification — the largest single gap

Nothing in the redesign has been systematically exercised on hardware.
`redesign-subdocs/2026-07-30-p1-p2-DEVICE-TEST.md` is the runbook (~95 checks,
8 ticked). Read its §0.7 first: `main()` routes `FlutterError.onError` to
Crashlytics, so overflows never reach `flutter run` stdout and about a third of
the checks are meaningless without the temporary `dumpErrorToConsole` patch.
Also unverified on a device: every P3/P4/P4c surface, the drawer icons + the 43
tour steps, the closed-jobs agenda, and the photo cue.

One loose end from the P4 device pass is still undiagnosed: a `RawScrollbar`
assertion ("provided ScrollController is attached to more than one
ScrollPosition") seen in the console, with no screen attributed to it.

### 5. Data and ops

- **The client phone backfill has not been run for real.**
  `functions/scripts/backfill-client-phone-from-name.js`. The dry run against
  prod on 2026-08-08 reported 684 scanned / 347 to patch; the 14 ambiguous docs
  were reviewed and are deliberately left alone. Note it fires
  `propagateClientEdits` and `waveUpsertCustomer`.
- **The `signupCodes` collection and its TTL policy remain in prod**,
  deliberately — the collection was verified empty and rules now deny all
  access. Never `--force` the policy away.
- ~~P4c's production migration of `invited` users~~ — **closed**, not open. The
  2026-08-08 deploy queried prod first and found **zero** `invited` users, so
  there was nobody to strand. The migration section in the P4c handoff is
  history.

### 6. App Store submission — 26 open items

`APP_STORE_SUBMISSION.md` is the runbook. The clusters: the on-device Part 6
checks (iPad pass, live map + Routes API, push deep link, home-screen widget,
wake-on-push refresh, Live Activity card, Siri phrases), the **Time Sensitive
Notifications entitlement**, ASC App Privacy needing **Precise Location**
added, **publishing `docs/legal/terms-of-service.html` to the `es-pro-legal`
Pages repo**, the FR localization, screenshots, and then archive → TestFlight →
submit. One is blocked by Firestore itself: the `liveActivityCards` TTL policy
cannot be created yet.

### 7. Function SDK downgrade — found and FIXED 2026-08-10, keep it from recurring

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
lint` clean, **820 jest passing**.

**The jest suite cannot catch this class of regression** — it mocks
firebase-admin, so it passed on the broken versions too. Note also that
`firebase-admin ^14` is a known break against firebase-functions 7.x; do not
"fix" a future audit warning by bumping to it. After any dependency change
here, check the installed versions directly rather than trusting green tests.
