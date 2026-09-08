# Firebase Analytics — remaining work

**State: code COMPLETE and verified; every item below is off-repo** — a
Firebase Console setting, an Xcode/App Store Connect action, or a device pass.
Nothing here is a code change, and nothing here blocks development. Items 1, 6
and 7 **do** block a useful reporting window or an App Store submission.

Built 2026-09-07. Implementation notes live in `.claude/rules/analytics.md` and
the Analytics section of `docs/ARCHITECTURE.md`; the current state of the code
is those two, never this file.

**Verified at build time:** `flutter analyze` → `No issues found!`;
`flutter test` → **3547 passed**, exit 0.

---

## What already exists, so nobody re-does it

- `firebase_analytics ^12.5.0` is in `pubspec.yaml`, and it is **SPM-safe**
  (`ios/firebase_analytics/Package.swift`) — no Podfile was introduced and none
  is needed.
- `ios/GoogleService-Info.plist` already exists at the `ios/` **root** and is
  already bundled into Runner's resources (`project.pbxproj:462`). Firebase is
  still configured from `--dart-define` through `lib/firebase_options.dart`.
  **`flutterfire configure` was NOT run and must not be** — it rewrites that
  file into the literal-values style and breaks the define-based setup.
- `ios/Runner/PrivacyInfo.xcprivacy` already declares **Product Interaction**
  (added with this work). Item 6 is about App Store Connect, which is a
  *separate* declaration that has to agree with it.
- `ANALYTICS_DEBUG` is in `dev/firebase.local.example.json`. Copy it into your
  own `dev/firebase.local.json` (gitignored) if you want it there rather than
  spelled on the command line.

---

## 1. Enable Google Analytics on the Firebase project — DO THIS FIRST

Firebase Console → *Project settings → Integrations → Google Analytics*, and
confirm the iOS app (`net.vogas.scheduling`) is linked to a GA4 property.

**Without this the SDK ships, runs, and reports nothing.** There is no error
and no warning anywhere — in the app, in the console or in the logs. It looks
exactly like an app nobody is using, which is the one failure mode that could
survive a whole release unnoticed.

- [ ] Google Analytics enabled on `schedulingapp-88727`
- [ ] The iOS app appears under the linked GA4 property's data streams

## 2. Register custom dimensions (or the parameters are invisible in reports)

Firebase Console → *Admin → Custom definitions → Create custom dimension*.

Custom **event parameters are collected immediately but are not queryable in
reports until registered.** They will show in DebugView and in the raw event
count either way, so this is easy to assume is working when it is not.

Register as **event-scoped** dimensions:

| Parameter | Answers |
|---|---|
| `source` | "how do people actually reach a job / a client?" |
| `surface` | splits search, filters and photos by which list they happened on |
| `filter_name` | which filter controls are used and which are dead |
| `direction` | how the calendar is navigated (swipe vs Today vs picker) |
| `view_mode` | day vs week agenda |
| `status` | which job states get opened most |
| `scope` | single vs series edits and deletes |
| `setting_name` | which settings people actually change |
| `action` | call vs email vs directions |
| `period` | which dashboard window admins live in |

Register as a **user-scoped** dimension:

| Property | Answers |
|---|---|
| `user_role` | **the admin-vs-employee comparison — the headline ask.** Without it, every "which features do admins use?" question is unanswerable in the console even though the data is being collected. |
| `app_locale` | EN vs FR usage |
| `build_env` | lets you EXCLUDE debug traffic from reports |

There is a limit of 50 event-scoped and 25 user-scoped custom dimensions, so
this uses a small fraction of the budget.

- [ ] 10 event-scoped dimensions registered
- [ ] 3 user-scoped dimensions registered

## 3. Mark key events as conversions (optional)

Firebase Console → *Analytics → Events → toggle "Mark as key event"*.
Candidates: `appointment_created`, `job_completed`, `client_created`. This only
changes how prominently they are reported; nothing in the app depends on it.

- [ ] Decided (fine to skip)

## 4. Verify events on a device or simulator (Mac-gated)

Both halves are needed. Only having one is why "DebugView shows nothing" is the
usual first result — the define decides whether events are **collected**, the
launch argument decides whether they **stream live**.

```bash
flutter run --dart-define-from-file=dev/firebase.local.json --dart-define=ANALYTICS_DEBUG=true
```

…and in Xcode: *Product → Scheme → Edit Scheme… → Run → Arguments → Arguments
Passed On Launch* → add `-FIRDebugEnabled`.

Then Firebase Console → *Analytics → DebugView*, pick the device top-left.

Verify one of each shape rather than every event — if these four work, the
plumbing is right and the rest is the same code path:

- [ ] A **screen view**: switch hub tabs, confirm exactly ONE `screen_view` per
      tab arrival. Then reach Clients from the drawer instead — still one.
      (This is the observer/hub-shell split; a double here is the one real
      regression risk in the design.)
- [ ] A **parameterised custom event**: create an appointment, confirm
      `appointment_created` carries `repeat`, `assignee_count`, `has_photos` etc.
- [ ] A **user property**: DebugView → the device card → *User properties* →
      `user_role` reads `admin` or `employee`.
- [ ] **No PII anywhere** in the DebugView payloads — spot-check
      `search_used` (no query text), `note_added` (no note), `photo_added` (no
      filename), `contact_action` (no phone number).

**Turn it back off when finished** — remove `-FIRDebugEnabled` from the scheme,
or that device keeps streaming every session into DebugView.

- [ ] `-FIRDebugEnabled` removed from the scheme after testing

## 5. Confirm the debug/production split actually holds

Cheap, and it is the thing that protects the numbers for the rest of the
product's life:

- [ ] Run **without** `ANALYTICS_DEBUG` and confirm DebugView shows nothing
      (collection is off in debug builds by default)
- [ ] After a real release, confirm `build_env` reports `release` for the fleet

## 6. App Store Connect privacy labels — SUBMISSION BLOCKER

`ios/Runner/PrivacyInfo.xcprivacy` now declares **Product Interaction** (Usage
Data), `Linked: false`, `Tracking: false`. **The App Store Connect answers are a
separate declaration and must agree with it.**

App Store Connect → the app → *App Privacy* → add **Usage Data → Product
Interaction**, purpose *Analytics*, not linked to identity, not used for
tracking.

The "not linked" answer rests on two facts about the code, both worth
re-reading before you sign it: `setUserId` is never called anywhere, and no
analytics parameter carries a name, email, phone, address, note or filename —
enforced by the allowlist in `AnalyticsParams.allParams`, not by convention.

- [ ] **Owner has read and agreed** with the `PrivacyInfo.xcprivacy` entry
- [ ] App Store Connect labels updated to match

## 7. Build releases with the ad-id dropped — RELEASE STEP

```bash
FIREBASE_ANALYTICS_WITHOUT_ADID=true flutter build ios --release --dart-define-from-file=dev/firebase.local.json
```

The plugin's `Package.swift` reads that env var and links `FirebaseAnalyticsCore`
instead of `FirebaseAnalytics`, which removes IDFA / advertising-identifier
collection. This app sells no ads and needs no attribution, so the ad id buys
nothing and costs a heavier privacy disclosure and a possible ATT prompt.

**Dropping this flag is what would put App Tracking Transparency back on the
table** — that is why it is a documented release step and not a preference.
Recorded in `docs/IOS_MAC_BUILD.md` Phase G step 2.

- [ ] Release build uses the flag
- [ ] `PrivacyInfo.xcprivacy` still declares `NSPrivacyTracking: false`

## 8. Wait for the reporting window before judging anything

Custom events appear in **DebugView within seconds** but in **standard reports
after ~24 hours**, and Retention/Cohort reports need days of data. An empty
Events page on release day is expected, not a bug — check DebugView instead.

- [ ] Re-check the Events page ~48h after the release

---

## Open decisions (no action needed, recorded so they aren't re-litigated)

- **`app_version` is deliberately NOT a user property.** Firebase reports app
  version, device model and OS version as automatic dimensions, so declaring one
  would spend a slot on data the console already has. Ask if you want it anyway.
- **Sign-out does not call `resetAnalyticsData`.** That would mint a new app
  instance id and destroy retention measurement, which is an explicit goal. The
  accepted cost: two people signing in on one handed-over device share an
  instance id. Nothing identifying is attached to it, and `user_role` is cleared
  on sign-out.
- **`search_used` carries no result count.** The only place that knows a search
  ran is the debounce commit, and the results have not been fetched there; a
  count reported later would be a second event for one search.
- **`job_completed` carries no `has_notes`.** The parent `fieldNotes` string is
  the legacy write path (crew notes live in a subcollection since 2026-09-06),
  so reading it would under-report to near zero. `note_added` already answers
  how often notes are written.
- **`logFeatureUsed()` has no call site.** It exists because the spec asked for
  it, and it is the extension point for the next feature; every meaningful
  action today got a named event instead. A two-line delete if you would rather
  not carry an uncalled method.
