# Wave-integration branch — ultra code review

Scope: `git diff main...HEAD` on `wave-integration` (merge-base `7e642aa`), 28 commits,
132 files. Reviewed by an 11-area multi-agent fan-out (security / correctness / performance /
convention lenses), every finding adversarially verified against the actual source, plus a
manual cross-cutting pass. Binary icon/splash assets excluded (nothing to review).

**Verdict:** the integration is well-built. The Cloud Functions are genuinely well-hardened
(secret only from Secret Manager, GraphQL injection-safe, sanitized errors, no PII logged), the
Firestore rules correctly lock the Wave fields/collections, and the Flutter layer follows the
project conventions. **No critical issues.** The findings below are the real ones that survived
verification, ordered by severity.

Result counts: **3 high · 2 medium · 6 low · 7 nit · 4 dismissed.**

---

## Status — fixes applied 2026-06-21 (uncommitted on `wave-integration`)

- **HIGH #1 (legacy business-only docs) — FIXED.** `ClientRecord.fromMap` now falls
  back `name ← businessName` when `name` is empty, and the repository search index
  includes `businessName`. This restores the display name, search, and (via the
  prefilled Name field) editability for legacy docs. Covered by two new
  `client_record_test.dart` cases. Repo `searchableText` re-indexes `businessName`.
- **HIGH #2 (committed iOS plist) — FIXED (tracking).** `git rm --cached
  ios/GoogleService-Info.plist`; the file stays on disk for native builds. The
  existing `.gitignore` rule `**/GoogleService-Info.plist` already covers the path
  (verified with `git check-ignore` — the earlier "rule doesn't match" claim was a
  verification error; `git check-ignore` only skipped it because it was *tracked*),
  so no `.gitignore` change was needed. **Still pending (user/console):** the key is
  in git history — restrict/rotate the iOS API key in the GCP console (App Check +
  bundle-id restriction). History rewrite was intentionally NOT done (rewrites shared
  history; your call).
- **MEDIUM #3 (worker lost-update race) — FIXED.** Outcome writes now go through
  `commitOutcome`, a transaction that re-reads the job and applies `done`/`queued`/
  `dead` only while it is still `inflight` with the same `claimedAt`. A concurrent
  re-enqueue is left intact so the newer edit still syncs. New regression test +
  full functions suite green (134/134), ESLint clean.
**Second pass 2026-06-21 — remaining findings fixed (uncommitted):**
- **MEDIUM #4 — FIXED:** the two dispatch retry tests now inject a real numeric
  clock and assert `nextAttemptAt` is a valid future Date (not Invalid), closing
  the vacuous-assertion gap.
- **LOW #5 — FIXED:** `listBusinesses` (client.js) coerces a null/non-string Wave
  business name to `""`, so `selectBusiness` can't throw a raw TypeError. New
  client.test.js coercion test.
- **LOW #6 — FIXED:** added not-connected tests for `upsertCustomer` and
  `importCustomers` (customers.test.js); fixed the `importDb` fake so an explicit
  empty `businessId` reaches `readBusinessId`.
- **LOW #7 — FIXED (documented):** added a NOTE on `_connection` explaining it is
  session-only by design (rules block client reads of `wave`). No read-on-mount
  added (would need a new callable or a rules relax — out of proportion).
- **LOW #8 — FIXED:** `wave/business-ambiguous` now maps to a dedicated
  `WaveValidation(reason: 'businessAmbiguous')` with a truthful EN/FR message
  (`wave_errorBusinessAmbiguous`) instead of the generic "try again". Mapper +
  failure + l10n + tests updated.
- **LOW #9 — FIXED:** removed the duplicate person-name `InfoCardRow`; the name
  now shows once, as the detail header subtitle.
- **LOW #10 — FIXED:** `docs/ARCHITECTURE.md` no longer references the deleted
  `ImageCompressService`.
- **Nits — FIXED:** `waveBootstrap` now rate-limited (`wave-bootstrap`, 10/hr) on
  its pre-connection Wave-calling path; "OAuth" wording removed from the
  `app_en.arb` `@key` descriptions and the `firestore.rules` `wave` comment;
  redundant French `app_name` override removed (it duplicated the default).

**Deliberately deferred (nits, with reason):**
- Done/dead job purge in `waveSyncQueue` — bounded one-per-client (~650), benign;
  would be a behavior change with test churn for no real gain at this scale.
- Client-search per-row memoization — verifier downgraded to nit (regexes already
  precompiled, active-search path doesn't accumulate pages); would need cached
  fields on `ClientRecord` — premature.
- `drainDb` reclaim-query isolation in tests — reclaim is already isolated by a
  separate `reclaimDb` fake; pure test-fixture nit.

Verification: functions `137/137` jest + ESLint clean; Flutter `507/507`; l10n
`gen-l10n` clean with no EN/FR drift.

---

## HIGH

### 1. Legacy business-only client docs break after the `ClientRecord` reshape (no migration)
Files: `lib/features/clients/domain/models/client_record.dart`,
`lib/features/clients/domain/policies/client_form_validator.dart`,
`lib/features/clients/data/firebase_clients_repository.dart`,
`lib/features/clients/widgets/views/client_detail_view.dart`

On `main` the model had `businessName`, `displayName => businessName.isNotEmpty ? businessName : name`,
and a validator requiring *businessName OR name*. So production may contain business-type client
docs: `businessName` set, `name` empty. After the reshape:
- `fromMap` no longer reads `businessName`; `displayName => name`; search no longer indexes
  `businessName`. → such docs render **nameless** (empty title/avatar) and **drop out of search**.
- The validator now requires `name`. The edit form prefills `name` from `c.name` (empty for these
  docs), so the admin **cannot save any edit** (e.g. a phone change) without retyping a name.

There is no migration/backfill on the branch. This is silent data invisibility + an edit lockout
on existing data.

**Key question for you:** do production Firestore client docs with a populated `businessName` and
empty `name` actually exist? (The reviewers can't tell from the repo.) If yes, this must be fixed
before deploy. If the app never shipped business-only clients, the path is unreachable and this
drops to low.

**Fix:** defensive fallback in `fromMap` — `name: (data['name'] ?? data['businessName'] ?? '')`
— and re-index `data['businessName']` in `searchableText`, OR a one-time backfill copying
`businessName → name` where `name` is empty. The `fromMap` fallback also fixes the edit-lockout
(the Name field prefills and the validator passes).

### 2. `ios/GoogleService-Info.plist` committed despite being gitignored — iOS Firebase key in history
File: `ios/GoogleService-Info.plist` (added by commit `c089978`)

The branch force-adds the iOS plist, putting the iOS API key, `GCM_SENDER_ID`, `GOOGLE_APP_ID`,
`PROJECT_ID`, `STORAGE_BUCKET` in plaintext git history — violating the project's secret-hygiene
convention (Android `google-services.json` and `dev/.env` are correctly excluded). The same iOS
values are already injected via the gitignored `dev/.env` and consumed in `lib/firebase_options.dart`.

> Note from verification: the existing `.gitignore` rule is `**/GoogleService-Info.plist`, which
> matches `ios/Runner/GoogleService-Info.plist` but **NOT** the committed top-level
> `ios/GoogleService-Info.plist`. So a plain `git rm --cached` leaves it re-addable — the
> `.gitignore` pattern must also be broadened (e.g. add `ios/GoogleService-Info.plist` or
> `**/GoogleService-Info.plist` → `GoogleService-Info.plist`).

**Fix:** `git rm --cached ios/GoogleService-Info.plist`, broaden the ignore rule, keep the file
locally for native builds. Treat the key as exposed — restrict it in the Google Cloud console
(App Check + iOS bundle-id restriction), and rotate if policy requires. (An iOS API key in a
plist is lower-risk than a server secret — it's client config — but it breaks the stated
convention and should be locked down.)

---

## MEDIUM

### 3. Worker outcome writes aren't guarded against a concurrent re-enqueue (lost Wave sync)
File: `functions/wave/worker.js:474-527`

The job *claim* is transactional, but the outcome writes (`status:'done'/'queued'/'dead'`) are
plain non-transactional `doc.ref.update()` with no re-check that the job is still `inflight`.
If a client is edited again while the worker is mid-dispatch (the Wave call takes seconds), the
`onDocumentWritten` trigger re-enqueues the same deterministic jobId (`status:'queued'`); when the
in-flight call finishes it unconditionally writes `status:'done'`, clobbering the re-enqueue.
Because `upsertCustomer` read the client doc near dispatch start, the *second* edit is never synced
— Wave is left stale while `wave.syncState` reads `'synced'` and no pending job exists. Narrow
window (two rapid saves of one client) but a real lost-update.

**Fix:** wrap the outcome write in a transaction that re-reads the job and only applies the
done/dead/retry transition when `status==='inflight'` AND `claimedAt` matches the claim-time value;
otherwise leave the new `'queued'` job alone.

### 4. Retry-path tests inject a non-numeric clock — "nextAttemptAt advanced" is never verified
File: `functions/wave/__tests__/worker.test.js:17-19, 415-488`

The dispatch tests use `now = () => {__serverTimestamp:true}`, so `nowMs = +nowValue` is `NaN` and
`nextAttemptAt = new Date(NaN)` = Invalid Date. The assertions only check `toBeInstanceOf(Date)`
(an Invalid Date passes), so the named "advanced" behavior is never tested. A regression that wrote
an Invalid Date would strand the job forever (the `nextAttemptAt <= now` query never re-matches) and
these tests would stay green. Not a live bug (production never injects `deps.now`), but a real blind
spot. The reclaim tests already use a real `nowFn` — mirror that and assert
`Number.isNaN(nextAttemptAt.getTime()) === false` and `> nowMs`.

---

## LOW

5. **`selectBusiness` raw TypeError on a null Wave business name** (`functions/index.js:962`;
   `client.js:306` maps `name` uncoerced). A null name throws → misclassified as a generic
   `internal` error instead of a clean not-found/ambiguous. Currently unreachable from the UI
   (bootstrap is called with no `businessName`), becomes live with a future business-picker. Guard:
   `typeof b.name === 'string'`. *(Two reviewers found this independently.)*

6. **No test for the deliberate "not connected" path** (`functions/wave/__tests__/customers.test.js`).
   `readBusinessId` throws when `wave/connection.businessId` is missing — a shipped feature
   ("clear not-connected error") with zero coverage. (The `importDb` fake's `opts.businessId || 'biz-1'`
   collapses empty string back to a value, so it needs adjusting for the test too.)

7. **Connected-state UI resets on every Settings rebuild** (`wave_settings_section.dart:26,72,108`).
   `_connection` is session-only ephemeral state with no read-on-mount, so an already-connected admin
   always sees the filled "Connect to Wave" button and no connected-business row. Consistent with the
   "app never reads Wave" design, but the indicator is effectively useless across sessions — either
   drop the connected visual or add a thin read path.

8. **Ambiguous/not-found business error dead-ends with a generic "try again"**
   (`wave_error_mapper.dart:40-42`). With multiple Wave businesses and no picker, the user gets
   "Something went wrong… Please try again" and retrying reproduces it. Add a dedicated
   `businessAmbiguous` reason + l10n string (or defer with the picker, but track it).

9. **Person name rendered twice on the client detail screen** (`client_view_body.dart:104-110` +
   `client_detail_view.dart:173-182`). Same `fullName` with the same guard shows as both the header
   subtitle and an `InfoCardRow`. Show it in one place. *(Borderline nit — purely cosmetic.)*

10. **`docs/ARCHITECTURE.md` still references the deleted `ImageCompressService`**. Stale checked-in
    doc. *(Verification note: the finding's line numbers were partly wrong — the real stale refs are
    `ARCHITECTURE.md:18` and `:110`, both bare name-drops; the "two-stage pipeline" wording is in the
    gitignored CLAUDE.md, not this file.)*

---

## NIT (incl. items verifiers downgraded from low)

- `waveBootstrap` has no `enforceDurableRateLimit` on its pre-connection Wave calls, unlike its
  sibling `waveImportCustomers` (`functions/index.js:865-936`). Bounded by admin auth + idempotent
  short-circuit. Defensive consistency only.
- Done/dead jobs are never purged from `waveSyncQueue` (`worker.js`). Bounded to one-per-client by
  deterministic jobIds (~650 at planned scale) — benign; optionally delete on `done`.
- `drainDb` test fake doesn't isolate the reclaim query from the main query
  (`worker.test.js:122-161`). Harmless today; the reclaim pass is already isolated by a separate
  `reclaimDb` fake elsewhere.
- `@key` descriptions in `app_en.arb` say "Wave OAuth" — the integration uses a Full Access Token,
  no OAuth. Dev-facing metadata only (not user-visible).
- `firestore.rules:201-208` comment says the `wave` collection holds "OAuth tokens" — it holds
  `businessId`/sync metadata; no tokens in Firestore. Rule body (`if false`) is correct.
- `values-fr/strings.xml` `app_name` changed to "Scheduling App" — now byte-identical to the default,
  so the French override no longer localizes. Delete the override or restore a French name.
- Client list search re-normalizes every loaded row on every keystroke; this diff widened it to 3
  name + 2 phone fields (`clients_list_view.dart:157-167`). Regexes are already precompiled and the
  active-search path doesn't accumulate pages, so impact is negligible — optional memoization.

---

## Dismissed (checked, not real)

- *Mapper tests omit accented names* — the mapper has no accent-specific branch (strings are treated
  opaquely), so ASCII tests already exercise the same path. Speculative coverage, not a defect.
- *Hardcoded spacing/icon-size in Wave widgets* — `width:6` has no matching `AppSpacing` token (only
  4/8/12/16/24/32), there is no icon-size token, and the pattern is the established house style.
- *`flutter_image_compress` removal "skips compression"* — **false.** `image_picker` resizes +
  JPEG-compresses natively (`maxWidth/Height:1600`, `imageQuality:70`). Only a redundant *second*
  compression pass was removed; documented in `CHANGELOG.md`. Magic-byte validation is untouched.
- *Contact export "always sets an Organization"* — **false** (manually re-verified; its automated
  verifier died on an API overload). `clientToContact` sets `Organization` *conditionally*
  (`if (displayName.isNotEmpty)`) to the customer/display `name`, which is the documented intent of
  the Wave-aligned model (`contact_export_launcher.dart:121-123,167-169`).

---

## Process notes
- One verify agent (contact-export) died on an API overload and one completeness-critic died on a
  session limit. Both gaps were closed manually: the contact-export finding was re-read and dismissed
  (above), and a manual cross-cutting pass confirmed no uncovered seam (l10n EN/FR lockstep; every
  function-written Wave field locked in rules; both new composite indexes present matching the worker
  queries; both new callables auth+payload+rate-limit guarded).
- The Cloud Functions test suite runs 133 tests green. `flutter analyze` on `lib/features/clients` is
  clean per the clients-UI reviewer.
