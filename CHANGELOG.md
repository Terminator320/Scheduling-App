# Changelog

All notable changes to this project are documented here.


- **MAJOR** (`x.0.0`) — incompatible / breaking changes.
- **MINOR** (`1.x.0`) — new functionality, backward-compatible.
- **PATCH** (`1.0.x`) — backward-compatible bug fixes only.

The `+N` build number after the version (e.g. `1.1.0+5`) is the store version
code; it increments by one on every store upload regardless of the semver part.

## [1.15.0+25] - 2026-06-11
### Added
- **Password strength checklist when creating an account.** The create-account
  password field now shows its five requirements — at least 8 characters, an
  uppercase letter, a lowercase letter, a number, and a symbol — as a live
  checklist where each circle turns into a green checkmark as you type. New
  passwords must meet all five; existing sign-ins are unaffected.

### Changed
- **Success messages are now green.** The "account created" and "check your
  inbox" screens, the success banners, and the slide-in success notices all use
  a consistent green instead of yellow or blue accents.
- **Saving a client to contacts without the permission now still links it.**
  Declining the Contacts permission falls back to the system new-contact screen
  as before, but the saved contact is now linked to the client, so later edits
  sync to it too (contacts plugin upgraded).

## [1.14.0+24] - 2026-06-11
### Added
- **Password managers can now save your sign-in.** The sign-in and
  create-account forms are linked into the OS autofill context, so Google /
  iCloud password managers fill both fields together and offer to save the
  credentials after a successful sign-in or account creation.
- **Haptic feedback on notices.** Success, info, and error notices now come
  with a matching tactile cue.
- **One-tap clear on text fields.** Every editable text field across the app
  now shows a small "x" while it holds text, so emptying a field is one tap
  instead of holding backspace.
- **Clear address button.** The client add/edit form's address block has a
  "Clear address" action that empties the street, apt/unit, city, province,
  postal code, and country fields all at once.

### Changed
- **Easier employee color picker.** Colors already taken by another employee
  are hidden instead of greyed out, so everything shown is pickable. Swatches
  are bigger and easier to tap, picking gives a small haptic tick, and the
  custom picker is now a tap-a-swatch palette with shades — no more color
  wheel or hex code.
- **Android predictive back.** The app opts into Android 13+ predictive back,
  so the system back gesture previews where you'll land before you commit.
- Firebase Performance's Logcat mirroring is now debug-only, so release builds
  no longer carry the extra logging.

### Fixed
- Deleting a client now also removes its device-local phone-contact link, so a
  stale link can't linger after the client is gone.
- Dismissing the edit sheet while the "this visit or all visits" prompt was
  open could leave the appointment editor stuck in its busy state.
- A failed employee enable/disable from the edit sheet now shows an error
  notice instead of failing silently.
- Invited-employee activation re-reads the verification flag after the auth
  reload instead of trusting a possibly stale user snapshot.

## [1.13.0+23] - 2026-06-11
### Added
- **Save a client to your phone contacts.** The client detail view has a new
  **Save** quick action that adds the client (name, business, phone, email,
  address) to your phone contacts in one tap.
- **Edited clients sync back to your phone contacts.** Once a client has been
  saved to contacts, editing their details updates that same contact
  automatically. Saving and syncing ask for the Contacts permission the first
  time; if you decline, Save still works through the OS new-contact screen but
  edits won't sync. The link is per-device — a client saved on one phone only
  syncs on that phone.

### Changed
- **Client search now starts from the first character.** Typing a single letter
  or digit begins searching your clients — you no longer have to type at least
  two characters (or three for a phone number) before results appear.

## [1.12.0+22] - 2026-06-11
### Added
- **Edit a repeating appointment for this visit only or all of them.** Saving a
  change to a recurring appointment now asks whether to apply it to just this
  visit or to this and all future visits — mirroring the delete prompt. Applying
  to all updates the shared details and the start/end time on every future visit
  while keeping each visit's own date and its own status.

### Changed
- **Repeating appointments now book five years ahead instead of one.** A
  recurring job appears across all upcoming years, not just the current one.
- **The repeating-appointment edit/delete prompt now spells out its scope** —
  it says whether the choice affects only this visit or every future visit in
  the series, and the destructive delete option carries an icon so its intent
  isn't conveyed by colour alone.

### Fixed
- **Editing "this and future visits" no longer fails if one future visit was
  deleted in the meantime.** The series update now skips a visit that was
  removed concurrently instead of aborting the whole save.
- **The "Resend verification email" button now reports when it can't send** (no
  active session) instead of doing nothing silently.

## [1.11.1+21] - 2026-06-11
### Added
Performance tracking

## [1.11.0+20] - 2026-06-11

### Added
- **Didn't get your verification email? You can resend it.** The "Account
  created" screen now has a **Resend verification email** button, and signing in
  before you've verified your email automatically sends a fresh link — both
  remind you to check your inbox **and** spam folder.

### Fixed
- **Signing up no longer gets stuck.** If an earlier attempt left a half-created
  account, the app now recovers it automatically on the next try instead of
  blocking that email with an "already in use" dead-end — and it can never
  remove a real, active account while doing so.

### Changed
- **Clearer sign-up guidance** — the account-created and "verify your email"
  messages now remind you to check your spam folder.

## [1.10.0+19] - 2026-06-10

### Added
- **Appointment details now tuck extra contacts behind a tap.** When a client
  has additional business contacts, the appointment view shows a collapsible
  **Contacts (N)** header — tap to reveal the full contact cards, tap again to
  hide them. The key info (client, phone, address) stays visible up top.

### Changed
- **Switching between the main screens** (Calendar, Clients, History, Employees,
  Settings) now uses a clean cross-fade, so the top bar and nav rail stay put
  and only the page content changes.
- The **back arrow** in the top bar now animates on tap — the arrow nudges back
  and springs into place — for clearer touch feedback. (Respects the system
  reduce-motion setting.)

## [1.9.1+18] - 2026-06-10

### Changed
- The **edit appointment** form now lists **Notes before Materials**, matching
  the new-appointment form and the appointment details view — the same fields in
  the same order everywhere.

## [1.9.0+17] - 2026-06-10

### Changed
- **History now loads in pages.** The history list shows the most recent
  appointments first and loads more as you scroll, so it stays fast even with
  years of history. Filters and search apply to the appointments already loaded;
  pull down to refresh.

### Fixed
- History could **hide the most recent appointments** once there were more than
  500 past appointments — the full history is now reachable.
- Searching history no longer **lags while you type** on large histories.
- While editing an appointment, picking a different client no longer briefly
  reverts to the original client.
- Editing an appointment for a client with **no fixed address** now opens the
  address field ready to type, instead of showing an empty address row.

### Security
- With the biometric **app lock** on, the app now hides your data in the phone's
  app-switcher preview, not only once it's fully in the background.
- Hardened an internal sign-up lookup so repeated retries can't lock you out of
  it.

## [1.8.0+16] - 2026-06-09

### Added
- **History is now its own screen with filters.** Narrow appointment history by
  **year** or by **assigned staff** with the new filter chips, and the list is
  grouped under clear **year** headers — so the year is visible, not just the
  month and day.
- History search now also matches a **client's phone number** (on top of client
  and employee name); formatting doesn't matter — `5550199` finds
  `(514) 555-0199`.
- The appointment details screen now shows the client's **phone number** and
  **address** as tappable rows (tap to call or open directions), alongside the
  existing quick-action buttons.
- **Automatic history cleanup.** Done and cancelled appointments stay in history
  for **2 years**, then are removed automatically — the appointment **and its
  photos** — once that period has passed. Nothing is deleted before the full two
  years elapse. (Runs server-side, daily.)

### Fixed
- Deleting an appointment now also deletes its **photos** from storage. Photos
  were previously left behind, accumulating as orphaned files. For a recurring
  series, only the photos of the visits actually being deleted are removed —
  past and completed/cancelled visits keep theirs.

## [1.7.0+15] - 2026-06-08

### Added
- The appointment details screen now shows a **status badge** (Pending,
  Confirmed, Done, etc.) right under the title, and **Call** and **Directions**
  quick-action buttons — tap to phone the client or open the address in a map.

### Changed
- The appointment details screen is cleaner: the client is shown by name (call
  and directions now live in the buttons above), and empty sections — notes,
  materials, employees, pictures — are hidden instead of showing "None" rows.

## [1.6.0+14] - 2026-06-08

### Added
- Clients can now be marked **No fixed address** when adding or editing them —
  useful for a city or a client with many locations. The address requirement is
  skipped, and the address is entered per appointment instead. Booking an
  appointment for such a client opens the address field ready for a custom
  address rather than showing the client's (empty) address.

### Changed
- A client's address is now required unless **No fixed address** is set.
  Previously, entering a business name silently skipped the address requirement;
  that shortcut is gone — use the toggle instead.
- **Phone** and **email** are now optional on clients — a client only needs a
  name (and an address, unless **No fixed address** is set). A typed email is
  still checked for a valid format.

### Fixed
- The optional **Business name** field no longer turns red with a required
  error when both name fields are left empty — the "business name or contact
  name is required" message now appears only on the **Contact name** field.

## [1.5.0+13] - 2026-06-08

### Added
- Client details now show **Call**, **Email**, and **Directions** quick-action
  buttons right under the name, and the phone, email, and address rows are
  tappable.
- Tapping **Email** lets you pick which app to send from — your default mail
  app, Gmail, or Outlook — the same way addresses already let you choose a map
  app.

### Changed
- Refreshed the look of the client details screen: tinted icon chips and
  clearer section headers. The primary contact is no longer repeated in the
  **Contacts** list — only the additional business contacts appear there.

### Fixed
- Editing a business client: clearing the business name now correctly removes
  its extra business contacts when you save, instead of a previously removed
  contact reappearing.

## [1.4.2+12] - 2026-06-08

### Changed
- Internal refactor/cleanup pass — no change to how the app behaves. Recurring
  UI was consolidated into shared, reusable pieces so screens stay thin and
  consistent:
  - The three auth screens (sign-in, create-account, forgot-password) now share
    one set of form building blocks — scaffold, header, email/password fields,
    status banner, and entrance animation — instead of each re-rolling its own.
  - The add-appointment, add-client, and employee forms share one bottom-sheet
    frame (`FormSheetScaffold`); the add- and edit-client forms also share the
    street-address block and a common form-state mixin.
  - One shared error toast (`errorSnackBar`), one destructive-button style, and
    one avatar-and-name form header replace copies scattered across screens.
  - Form spacing now uses the design-system spacing tokens.

## [1.4.1+11] - 2026-06-07

### Changed
- Internal refactor and optimization pass — no change to how the app behaves:
  - **Snappier detail screens.** Opening a client or an appointment no longer
    builds the edit form's text fields up front — they're created only when you
    tap Edit, so a view-only open does no edit-form work.
  - **Less duplicated UI code.** The client detail screen was split into a
    read-only view and a separate edit form, and recurring pieces were pulled
    into shared widgets reused across screens: a busy/loading button icon
    (`BusyButtonIcon`), the standard detail-sheet scroll shell
    (`DetailSheetListView`), and the auth-screen logo and error banner
    (`AuthLogo`, `AuthErrorBanner`).

## [1.4.0+10] - 2026-06-07

### Added
- **Landscape and tablet layout.** Rotating a phone to landscape — and on
  tablets in any orientation — the app now shows a side navigation rail in place
  of the hamburger menu, and the calendar lays out side by side (the month grid
  next to the selected day's appointments) instead of stacked. Portrait phones
  are unchanged.

### Changed
- The month/year date picker's year list now spans a few years back through
  several years ahead and shifts automatically with the calendar each year,
  instead of a fixed range that would eventually go out of date.
- App headers take up less vertical space in landscape, giving the calendar and
  lists more room.
- On tablets the calendar now opens an appointment's details in a sheet (the same
  as landscape) rather than a separate side pane.
- The search fields on Clients, History, and Employees now all share one
  consistent style.

## [1.3.1+9] - 2026-06-07

### Changed
- New team members are always invited as employees. Admin access is now granted
  by editing a person after they've joined the team, instead of at invite time —
  an account invited directly as an admin previously couldn't finish signing up.
- Searching clients and appointment history is now accent-insensitive everywhere
  (searching "jose" matches "José"), and phone search matches on the digits you
  type, so "(514) 555" finds a number saved as 5145551234.
- Search and long appointment lists are smoother — date formatting is cached,
  search patterns are compiled once, and the calendar drops some redundant
  rebuilds.
- Large internal cleanup/refactor pass: one consistent animated save button
  across the add/edit appointment, client, and employee forms; shared status
  labels and a single navigation route table; dead code removed. No change to
  what the app does.

### Fixed
- Repeating appointments that span a daylight-saving change now keep their
  correct start and end times. Previously a series crossing the spring/autumn
  switch could store a visit an hour off.
- An overnight appointment ending after midnight on a daylight-saving change
  night now saves the correct end time.
- Re-authenticating to delete your account no longer counts the "please log in
  again" prompt against the attempt limit, so retrying after re-login can't lock
  you out of deleting the account.
- The abuse limit on account deletion and invite lookups is now a true rolling
  15-minute window; a caller could previously slip a few extra attempts in right
  at the window boundary.
- Address lookups that return an unexpected or garbled response now fail cleanly
  (and are logged for diagnosis) instead of showing a generic error.

## [1.3.0+8] - 2026-06-07

### Added
- The edit-appointment sheet now handles the address like the add sheet: the
  client's address shows as a pill with a Change button, and a "Use client's
  address" link switches back from a custom address. An appointment saved with
  a custom address opens in custom mode showing that address.

### Changed
- Tapping Change on the client-address pill clears the address field so a new
  address can be typed straight away, instead of having to delete the client's
  address by hand first.

### Fixed
- Editing an appointment no longer lets a save go through after the client was
  removed — the client field now shows the same "client is required" error as
  the add flow. Previously the save silently kept the old client.

## [1.2.0+7] - 2026-06-07

### Added
- Repeating appointments: the add and edit sheets have a Repeat dropdown
  (every 4 months / every 6 months / every year). Picking one pre-books the
  future visits up to a year ahead as their own appointments — same details,
  status "pending", each one can be marked done on its day like any other
  booking. Every visit in a series shows its rule next to the date and time.
- Changing a repeating appointment's Repeat option rewrites the series like a
  real calendar: the previously booked future visits are deleted and the new
  cadence is booked from the edited date, in one atomic batch. Past visits and
  visits already marked done or cancelled are never touched.
- Deleting a repeating appointment now asks whether to delete this visit only
  or this and all future visits in the series.
- Form fields now shake and their error messages animate in when validation
  fails, across every form in the app (respects the OS reduced-motion setting).
- Error messages now say what failed and why — e.g. "Couldn't delete the
  client — you appear to be offline. (CLI-DEL)" — instead of a generic
  "Something went wrong". The short tag matches the Crashlytics log entry so
  tester reports can be traced directly to logs.

### Changed
- Internal cleanup pass: shared confirm dialog, shared section labels and
  client-form validation, avatar initials now auto-contrast against light
  employee colors, and one canonical appointment-status mapper.

### Fixed
- Several failure paths that silently swallowed errors (client delete,
  employee save, appointment delete) now log to Crashlytics.
- Calendar no longer re-sorts and regroups all appointments on every tap;
  the history tab no longer re-sorts on every search keystroke; the busy-
  employee conflict check now runs its queries in parallel.
- Auth-screen fields no longer play a stray shake animation on first build.

## [1.1.1+6] - 2026-06-02

### Fixed
- Login no longer fails with a false "this account has been disabled" crash or a
  generic "something went wrong please try again" banner. The deleted-account
  watcher mistook the transient empty placeholder doc — surfaced while the
  `authStateChanges()` uid stream lags `FirebaseAuth.currentUser` right after
  sign-in — for a real deletion. It now fires only for a settled, non-loading
  empty doc with a resolved uid (`isAccountDeletionSignal`).
- The account-exit handler can no longer wedge the root navigator. It previously
  pushed a route while the navigator was mid-transition, throwing `!_debugLocked`
  and permanently locking navigation — which cascaded into the login "something
  went wrong" banner and dead Create-account / Forgot-password links. Navigation
  is now deferred to a post-frame callback (idle navigator) and guarded against
  re-entrancy across the three account listeners.
- Login failures are now logged (`login.sign_in`) instead of being silently
  swallowed, so post-authentication errors surface in the debug console.

## [1.1.0+5] - 2026-06-02

### Added
- First-launch onboarding carousel, shown once and gated by an encrypted
  `onboardingSeen` flag (`smooth_page_indicator`).
- Biometric app-lock that gates the whole app on cold start and resume
  (`local_auth`), toggled from Settings and stored as an encrypted flag.
- Appointment image carousel and in-app camera capture, with runtime camera
  permission handling (`permission_handler`).
- Paginated clients list with infinite scroll (`infinite_scroll_pagination`).
- Encrypted at-rest secure storage for cached identity and remembered login
  email (`flutter_secure_storage`).
- App version display in Settings.

### Changed
- Performance and security hardening pass across the codebase (durable
  Firestore-backed rate limiting on auth callables, callable payload
  sanitization, and related cleanup).
- Code-structure simplification and documentation of plugin features in
  `docs/ARCHITECTURE.md`.

### Fixed
- Appointment card no longer crashes when viewing events on other days. The
  card's `IntrinsicHeight` (which stretches the employee-color bar) could not
  compute intrinsic dimensions through `AutoSizeText`'s internal `LayoutBuilder`,
  which surfaced in release builds as a paint-time `Null check operator used on
  a null value`. The title is now a plain `Text`.

## [1.0.3+4] - 2026-05-23

### Fixed
- Account deletion reliability and an accompanying Firestore security-rules
  update.

## [1.0.2+3] - 2026-05-21

### Added
- Adaptive / responsive layout, native splash screen, and app launcher icons.
- Full English/French localization via `gen_l10n` with `@key` metadata.

### Changed
- Hardcoded values refactored into design tokens and localized strings.

### Fixed
- Sign-up errors no longer collapse into a generic message in release builds.

## [1.0.0+1] - 2026-03-26

### Added
- Initial release: appointment scheduling, client records, employee management,
  and photo documentation, backed by Firebase (Auth, Firestore, Storage,
  App Check).
