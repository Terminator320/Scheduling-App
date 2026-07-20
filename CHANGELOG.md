# Changelog

All notable changes to this project are documented here.


- **MAJOR** (`x.0.0`) — incompatible / breaking changes.
- **MINOR** (`1.x.0`) — new functionality, backward-compatible.
- **PATCH** (`1.0.x`) — backward-compatible bug fixes only.

The `+N` build number after the version (e.g. `1.1.0+5`) is the store version
code; it increments by one on every store upload regardless of the semver part.

## [1.34.1+55] - 2026-07-19
### Changed
- **Removing a team member now cuts off access immediately.** Setting someone
  to disabled signs them out of every device, blocks them from signing back in,
  and stops all notifications and live cards for them. Previously a removed
  technician could still see the jobs they had been assigned — including client
  names, phone numbers, addresses, notes, and job photos. Re-enabling them
  restores access as before.
### Fixed
- **The live job card now actually appears.** A missing database index meant
  every Lock Screen card silently failed to start, update, or clear, falling
  back to the plain "time to leave" notification.
- **The live card switches to "On site" and clears itself reliably.** On a quiet
  day with nobody else scheduled, the card used to sit on "On the way" for the
  whole visit and linger after the job was done.
- **Turning the live job card off always works.** Switching it off in Settings
  now removes this device from live cards even if no card had appeared yet in
  that session — before, the server could keep starting cards on a phone that
  had opted out.
- **Completing one job no longer clears another job's live card.** Marking a
  visit complete used to dismiss the card for whatever job you were actually
  driving to.
- **Siri and the home-screen widget roll over at midnight.** Leaving the app
  open overnight made Siri answer "no appointments today" and the widget show
  the previous day's jobs until the app was reopened.
- **Re-enabling Live Activities in iOS Settings takes effect right away.** The
  "Live job card" row no longer stays hidden until you relaunch the app.
- **A busy schedule no longer swallows a notification.** An oversized widget
  refresh attached to a push could make the whole notification fail to send.

## [1.34.0+54] - 2026-07-19
### Added
- **Ask Siri about your day.** On iPhone you can now ask Siri "what's my next
  appointment", "what's on my schedule today", or how many jobs you have left,
  and hear the answer without opening the app. Admins hear the whole business,
  technicians hear only their own assigned visits.
- **A live job card when it's time to leave.** When the app tells you to head
  to a job, a card now appears on the Lock Screen and in the Dynamic Island
  showing the client, the address, the drive time, and when to leave — with a
  Directions button that opens your maps app. It switches to "On site" once the
  job's start time arrives and clears itself when the job is complete.
- **Turn the live job card off.** Settings has a new "Live job card" switch for
  anyone who would rather not have jobs on their Lock Screen. It's on by
  default, and switching it off clears any card already showing. The row only
  appears on iPhones that support the card.
### Changed
- **The dashboard has the menu button again.** Opening the dashboard on a phone
  now shows the same menu as every other screen, so you can reach settings
  without going back first.
- **Staff pins stay readable on the live map.** A team member whose location
  hasn't updated recently no longer has their map pin greyed out — how long ago
  they updated is still spelled out in the info card and the staff list.
- **Booking an empty day goes through the + button.** The "New appointment"
  button inside an empty day's schedule was removed; use the + button, which is
  always in the same place.
### Fixed
- **The "today" button disappears when you're already on this month.** Swiping
  back to the current month used to leave the jump-to-today button on screen.

## [1.33.0+52] - 2026-07-19
### Added
- **Book common jobs in a couple of taps.** The add-appointment form now has a
  row of quick-fill chips for the usual job types — leak diagnostic, drain
  cleaning, faucet or valve, toilet repair, emergency call, water heater.
  Tapping one fills in the service title and a typical duration; everything
  stays editable afterwards.
- **See a client's whole job history.** Opening a client now shows a "Job
  history" section listing that client's appointments newest-first — tap any one
  to open its details.
- **Book straight from an empty day.** An empty day's schedule now shows a "New
  appointment" button, so you can start a booking without hunting for the plus
  button.
- **See everyone on the live map as a sortable list.** The staff map now has a
  "show staff list" button that opens a roster of every team member sharing
  their location, ordered nearest-to-farthest from you — each row showing the
  distance, their nearest town, and how long ago they updated, with your own row
  marked "You". Tap a name to jump straight to that person on the map.
### Changed
- **Jump to any day on the day route.** The day-route screen's date is now
  tappable to pick any day from a calendar, with a one-tap "today" button to
  return, and the employee switcher opens as a tidy picker sheet.
- **Overdue jobs stand out at a glance.** A job that has run past its end time
  now shows a warning icon on its card, so it's easy to spot in a busy day.
### Fixed
- **The staff list says "No location" when a spot can't be pinned.** A roster
  row whose position can't be resolved to a place now reads "No location"
  instead of showing "Locating…" indefinitely.
- **Location sharing stays fresher for on-time "leave now" alerts.** A dropped
  location update no longer briefly pauses the next one, so your position — and
  the drive-time reminders that depend on it — stay current.

## [1.32.0+51] - 2026-07-18
### Added
- **See where your staff are on a live map.** Admins get a new Staff map that
  plots every team member sharing their location, each pin coloured to the
  employee and stamped with how long ago it updated ("Just now", "5 min ago").
  Tap a pin to see who it is, their nearest street address, and a one-tap
  handoff to open that spot in Maps. Anyone whose location has gone stale is
  shown as offline with a last-seen time. Toggle live traffic or a satellite
  view, and recenter the map on the whole team with one button.
- **"Time to leave" reminders that account for real drive time.** Instead of a
  fixed 30-minute heads-up, you now get a departure alert timed to when you
  actually need to leave for your next job — calculated from live traffic
  between where you are and the job's address, plus a 10-minute buffer. A short
  hop across town nudges you later; a cross-city drive nudges you sooner. The
  alert names the client, the start time, and the estimated drive, and (on
  iPhone) is marked time-sensitive so it breaks through Focus modes. If your
  location or a route can't be determined, it quietly falls back to the usual
  30-minute reminder.
- **The app can share your location in the background to time those alerts.**
  Field staff (and admins assigned to jobs) are asked once for location
  permission; with it granted, the app keeps your last position current even
  while it's in the background so the leave-now timing stays accurate. Your
  location is visible only to the reminder system and to admins on the staff
  map — never to coworkers — and is dropped the moment you sign out. Granting
  only "while using the app," or denying location entirely, still works:
  reminders just fall back to timing from your previous job's address or the
  fixed 30-minute heads-up.
- **Drive a whole day's jobs as one route.** Open a day's schedule to see every
  stop numbered in start-time order, then hand the full run off to Google Maps
  as a multi-stop driving route with one tap. Admins can switch between the
  employees who have jobs that day; each person sees their own route.
- **Save a job photo to your camera roll or share it.** The full-screen photo
  viewer now has Save and Share buttons, working for both photos you just took
  and ones already stored on the job.

### Changed
- **Cancelled visits can be edited again.** A cancelled appointment is no longer
  locked read-only — an admin can fix its details or re-activate it from the
  status picker, instead of having to recreate it.
- **The app now handles going offline gracefully.** Photos you attach to a
  visit no longer vanish if you lose signal mid-upload — they're kept and
  uploaded automatically the moment you reconnect or next sign in. Saving an
  appointment or client while offline now tells you right away instead of
  leaving the Save button spinning.

### Fixed
- **Notices no longer hide under the notch.** In landscape, the banner that
  slides in from the top now shifts toward the open side of the screen so it
  stays clear of the camera notch.
- **Text no longer overflows at large text sizes.** The calendar's month bar
  and the employee and status chips stay tidy when you crank up the system
  font size.
- **The text-size preview reads in French.** The sample text on the text-size
  screen now follows your app language instead of always showing English.
- **The home-screen widget no longer flickers empty after sign-in.** A brief
  hiccup right after signing in can no longer momentarily blank the iPhone
  widget.

## [1.30.0+49] - 2026-07-13
### Added
- **Manage notifications from Settings.** Settings now has a Notifications row
  that shows whether notifications are On or Off. If they're off — or you
  dismissed the first-time prompt — tapping it either asks again or opens your
  system settings so you can turn them back on and start receiving job alerts.

### Changed
- **The iPhone home-screen widget now shows today and tomorrow.** It lists your
  remaining jobs for today and, once the day's work is done, rolls over to
  tomorrow's schedule on its own — no app launch needed.
- **Dashboard job lists are now full appointment cards.** The "starting soon /
  overdue" and "today" lists on the Dashboard show the same tappable,
  colour-coded cards as the calendar, so you can open a visit straight from
  there.

### Fixed
- **The home-screen widget stays current even when the app is closed.** Being
  assigned to, rescheduled on, or removed from a job now refreshes the widget in
  the background, so it no longer shows a stale schedule until you next open the
  app.

## [1.29.0+48] - 2026-07-11
### Added
- **An admin Dashboard gives you the day at a glance.** A new Dashboard screen
  (from the menu and Settings) shows today's visits by status, who's unassigned,
  each employee's workload for today and this week, an eight-week trend of
  completed vs. cancelled jobs and new clients, your busiest weekday, and an
  attention list of jobs starting soon or already overdue.
- **Push notifications keep your team on top of every job.** Employees now get
  alerts when they're assigned to, rescheduled on, or removed from a visit,
  a reminder 30 minutes before a job starts, a "job finished?" nudge once a
  visit runs past its end time, and a 6 PM summary of the next day's work.
- **See your schedule on your iPhone home screen.** A new home-screen widget
  shows an employee's remaining jobs for today and their next upcoming visit;
  tapping it opens that appointment.
- **Wave can import your customers automatically.** Settings → Wave now has an
  automatic-import cadence you can set to Off, Weekly, or Monthly, so new Wave
  customers flow into the app without a manual import.

## [1.28.0+47] - 2026-07-10
### Added
- **Jobs that run past their end time now show "Overdue".** An appointment
  reads **In progress** while it's underway and flips to **Overdue** once its
  end time passes without being marked Complete or Cancelled — so it's obvious
  at a glance which visits still need closing out.

### Fixed
- **An appointment's status now matches everywhere you look.** A visit whose
  time had passed could show "In progress" on the calendar card while its edit
  screen still read "Pending"; the card, the details view, and the editor now
  agree.

## [1.27.0+46] - 2026-07-09
### Changed
- **Appointment statuses are simpler: Pending → In progress → Complete.** The
  status picker now offers just these three stages, and "Done" is called
  **"Complete"** everywhere (the button now reads **"Mark as complete"**).
  Cancelling a visit is still its own separate action.
- **A completed visit no longer offers a Cancel button.** Once a job is marked
  complete, the Cancel action is hidden — completing it is the end of its
  lifecycle.

### Fixed
- **Editing an older appointment saves reliably again.** Changing the time,
  notes, or assignees on a visit created before the status change no longer
  fails to save.
- **An invited employee now reads "Invited" everywhere.** The employee details
  view previously showed a not-yet-activated employee as "Active"; it now
  matches the "Invited" badge shown in the list.

## [1.26.0+45] - 2026-07-08
### Added
- **Read the privacy policy from inside the app.** Settings now has a **Legal**
  section with a **Privacy Policy** link that opens the policy in your browser.

## [1.25.1+44] - 2026-07-08
### Security
- **Hardened the app's connection to its backend.** Sensitive actions —
  deleting your account, sending employee invites, and the Wave accounting sync
  — now require requests to come from a verified copy of the app, blocking
  tampered or automated clients.

## [1.25.0+43] - 2026-07-07
### Changed
- **The app now shows as "ES Pro" on your home screen.** The app icon's label
  was renamed; the branding inside the app is unchanged.
- **Appointment cards list everyone assigned to a job.** When a visit has more
  than one person on it, the calendar and history cards now show all of their
  names instead of only the first.

### Fixed
- **Re-enabling a disabled employee now updates immediately.** On tablets and in
  landscape, an employee you just re-enabled no longer keeps showing as
  "Disabled" in the details pane — it flips to active right away.
- **The light/dark switch works on the first tap.** If your phone was set to
  dark mode, the toggle used to start in the wrong position and needed two taps
  to switch back to light; one tap now does it.

## [1.24.0+42] - 2026-07-07
### Added
- **Add a new client without leaving the appointment.** When you search for a
  client while booking (or editing) an appointment and no one matches, you can
  now tap **Add "<name>" as a new client** right from the results. The new-client
  form opens with the name already filled in, and once you save it, the client is
  selected on the appointment automatically — no more backing out to the Clients
  tab and starting over.

## [1.23.1+41] - 2026-07-05
### Changed
- **Moving between sections feels smoother.** Switching tabs and typing with the
  keyboard open no longer cause background screens to redraw, so the app stays
  responsive.

### Fixed
- **The month calendar no longer crowds out the day's appointments.** On smaller
  phones — or with the keyboard open, large text turned on, or in split-screen —
  the month grid now sizes itself to the space available instead of pushing the
  appointment list off the bottom.
- **No more crashes on tablets, in landscape, or when moving between sections.**
  A scrolling error that could blank the screen when two lists were visible at
  once (calendar split view, client/appointment side-by-side panes, or a kept-
  alive tab) is resolved, and the add buttons on the Clients and Employees tabs
  no longer conflict with each other.
- **Marking a job done or cancelling it now tells you if it fails.** Previously a
  failed status change was silent; you now get a clear message with the reason.
- **Adding a client on a tablet no longer jams the next add or edit.** The add
  form's Save button could stay stuck after a client was added in the two-pane
  layout; it now resets correctly.
- **Creating an account is more reliable.** A hiccup reading your profile right
  after sign-up no longer leaves you stuck with no message — you're guided to
  sign in normally, which completes the setup.
- **Client search in the appointment form no longer flashes stale results.** A
  slow earlier search can no longer overwrite the results of what you just typed.
- **Search fields no longer get cut off at large text sizes,** and the clear
  button on the appointment client picker now has a spoken label for screen
  readers.

### Security
- **Employee invitations are rate-limited.** Invite creation is now capped per
  admin, a safeguard against a compromised admin session mass-creating invites.

## [1.23.0+40] - 2026-07-02
### Added
- **The app works sensibly offline.** A slim banner appears whenever the
  connection drops, so nobody wonders why a change hasn't shown up yet.
- **Failed lists can be retried in place.** When clients, history, or a search
  can't load, the screen now shows a clear message with a Retry button instead
  of bare error text.
- **Screen-reader and large-text support took a big step.** Calendar days
  announce their date and appointment count, every icon-only button has a
  spoken name, the in-app text size now stacks on top of the phone's
  accessibility font size, and small tap targets (banner dismiss, EN/FR
  switch) were enlarged to comfortable sizes.

### Changed
- **Switching sections no longer restarts them.** Calendar, Clients,
  Employees, History, and Settings stay alive in the background: no more
  loading flashes, and the Android back button now returns to the calendar
  instead of exiting the app. On iPhone, swiping back works on pushed screens.
- **Date and time pickers match the platform.** Android gets Material pickers,
  iPhone gets the native-style wheels, and the time wheel follows the device's
  12/24-hour preference.
- **Searching clients and history is far cheaper and faster.** Searches share
  one cached read window, match off the main thread, and results update
  immediately after adding, editing, or deleting a record.
- **App start is quicker.** The first frame no longer waits on analytics
  setup, and the app's fonts ship inside the binary instead of being fetched
  from the internet on first launch.

### Fixed
- **Appointment photos can no longer vanish.** Saving an edit while photos
  were still uploading in the background could silently erase them; photo
  changes are now applied additively so concurrent activity can't clobber them.
- **Editing a repeating visit right after opening it no longer drops the
  original assignees**, and picking the same start and end time now shows a
  validation message instead of silently booking a 24-hour appointment.
- **Cancelled visits no longer block staff as "busy"** when booking new work.
- **Client edits reach existing appointments.** Changing a client's name,
  phone, or address now updates their future appointments automatically.
- **Deleted or just-edited records no longer linger in search results.**
- **Account safety nets.** An account deleted while the app was closed now
  signs out with a clear message instead of a broken calendar; a rare start-up
  hiccup can no longer disable the admin role or account-status detection for
  the whole session.
- **Wave sync is more robust.** Stuck jobs now surface an error badge instead
  of staying "pending" forever, temporary Wave outages retry instead of giving
  up, a crash mid-sync can no longer create duplicate Wave customers, and
  second address lines (e.g. "Suite 5") survive the round trip.
- **Security hardening.** Staff-directory reads now require an active account
  — a merely signed-up account can no longer list employee contact details —
  and client-side updates can never rewrite a user's account link.

## [1.22.0+39] - 2026-07-01
### Added
- **On iPhone, the app now feels native.** Confirmation dialogs, the
  camera/gallery and map/email choosers, the "just this appointment or the whole
  series" prompt, on/off switches, loading spinners, and pull-to-refresh all
  follow iOS conventions, with an iOS-style scrollbar on long lists and an iOS
  back arrow. On Android, everything looks and works exactly as before.

### Changed
- **The Text Size screen now matches the rest of the app.** Its header uses the
  same standard top bar as every other screen, so the title, back button, and
  landscape behaviour stay consistent.

### Fixed
- **No more false "account disabled" message just after signing up.** A rare
  timing issue that could briefly flash the account-disabled screen while a
  newly invited account was still finishing activation is resolved.

## [1.21.0+38] - 2026-06-28
### Added
- **The first-launch walkthrough now has a Back button.** You can step back to a
  slide you moved past instead of only going forward or skipping.

### Changed
- **A refreshed, on-brand welcome.** The sign-in, create-account, password-reset,
  and intro screens now lead with the Plombier Eau Secours logo and a cleaner,
  centered layout that also looks right on tablets and in landscape.
- **Sign-in is easier to scan.** "Forgot password?" now sits directly under the
  password field, and creating an account is a clear prompt at the bottom of the
  screen.
- **Calmer screen transitions.** The sign-in and account screens now ease in
  smoothly as a whole rather than animating each field one at a time, and the
  loading splash shows the company name beneath the logo.

## [1.20.0+37] - 2026-06-28
### Added
- **Inviting a staff member now gives you a one-time code to share with them.**
  When you invite someone, the app shows a code you can copy and pass on however
  you like — they use it to set up their own login. Re-inviting a person who
  hasn't signed up yet hands you a fresh code, so a lost or expired one is easy
  to replace.

### Changed
- **Joining as an invited staff member is simpler and works right away.** New
  staff create their account with their email, a password, and the code from
  their admin — there's no separate email-verification step, and the account is
  ready to use the moment they finish.

### Fixed
- **Signing up with the wrong email now gives a clear message.** If the email
  you enter doesn't match the one your admin invited, the app tells you to use
  the exact invited email instead of a confusing "invalid code".
- **A failed sign-up no longer leaves a broken half-made account behind.** If
  setting up the account doesn't go through, the partially-created login is
  cleaned up so you can simply try again.
- **Too many wrong-code attempts are now blocked for a short while**, so an
  invite can't be guessed at.
- **Your appointments load reliably right after you sign in.** A timing hiccup
  that could briefly stop the calendar from loading on the very first try after
  signing in now sorts itself out automatically.

## [1.19.4+36] - 2026-06-27
### Changed
- **Risky actions now confirm before they happen.** Cancelling an appointment
  and disabling or re-enabling a staff member ask for confirmation first, and
  deleting your account shows a full-screen progress overlay so it can't be
  triggered twice.
- **Forms are quicker to fill in.** Name fields capitalise automatically, the
  keyboard's "next" key moves you through a form field by field, and the status
  and staff-member chips are bigger, with clearer labels for screen readers.

### Fixed
- **Saving an appointment can't accidentally book it twice.** Quickly
  double-tapping Save when adding or editing an appointment no longer creates a
  duplicate visit (or duplicate repeats), even on a slow connection.
- **Buttons no longer get stuck after a failure.** If checking for scheduling
  conflicts or changing a staff member's status failed, the button could stay
  greyed-out and spinning; it now resets so you can try again.
- **Search no longer shows clients or appointments that were just changed or
  deleted.** Client and appointment-history search results stay in sync after an
  edit or deletion.
- **Removing a client on a tablet clears the side panel.** Deleting a client in
  the two-pane layout no longer leaves their details on screen with a frozen
  button.

## [1.19.3+35] - 2026-06-26
### Changed
- **The app now adapts to small phones and large text sizes.** Appointment
  cards, the appointment and client detail views, the add/edit forms, the
  employee screens, and Settings now rearrange their contents — stacking
  titles, buttons, and fields vertically — when the screen is narrow or you've
  turned up the system text size, so everything stays readable and tappable.
- **The slide-out menu now scrolls and never cuts off.** On shorter screens
  (including phones held sideways) the navigation menu scrolls instead of
  pushing items off-screen, and add/edit panels open taller so more of the form
  is visible at once.

### Fixed
- **Long names, times, and labels no longer run off the edge.** Text that could
  overflow or get clipped on appointment cards, list rows, and the top bar now
  wraps or trims cleanly.

## [1.19.2+34] - 2026-06-25
### Changed
- **Searching and scrolling the clients and appointment-history lists is now
  faster and smoother.** Repeating a recent search reuses its results, and
  typing in the search box no longer rebuilds the surrounding screen, so large
  lists stay responsive.

### Fixed
- **Editing an appointment now keeps everyone assigned to it.** Staff who were
  disabled or removed after being assigned to a visit were silently dropped when
  you saved an edit; they now keep their assignment — and their access to that
  appointment.
- **Client search finds clients that were previously missing.** Older client
  records that never showed up in search results are now included.
- **The Save button can't submit a client edit twice.** It now disables while a
  save is in progress, so a quick double-tap can't create duplicate updates.
- **The app no longer gets stuck on the coloured launch screen.** If a saved
  setting can't be read at startup, the app now continues to the normal screen
  instead of hanging.

## [1.19.1+33] - 2026-06-24
### Fixed
- **Wave customer sync no longer risks dropping an edit.** If a client was
  changed while an earlier sync to Wave was still being retried after an
  interruption, that newer edit could be overwritten; syncs are now reconciled
  so your most recent change always reaches Wave.

## [1.19.0+32] - 2026-06-23
### Added
- **Appointment history search now covers your entire history.** Searching past
  appointments by client name, phone, or staff member finds matches across all
  of your history — not just the appointments already scrolled into view — while
  still showing instant results as you type.

### Changed
- **Client search matches more of a client's details.** Typing in the clients
  list now finds people by business name, email, address, extra contacts, and
  mobile or contact phone numbers, on top of their name and main phone.
- **Every client suggestion on the appointment form is now reachable.** The
  client picker used to show only the first five matches; the list now scrolls
  so you can reach every one.
- **Employee search now matches accented names and formatted phone numbers.**
  Searching "Jose" finds "José", and a run of digits like "5145550199" finds a
  staff member whose number is saved as "(514) 555-0199".

## [1.18.1+31] - 2026-06-23
### Fixed
- **Appointment details show the right client contacts.** The appointment view
  was dropping a client's first extra contact (and showed none when the client
  had only one); every extra contact now appears.
- **Clients identified only by a business name sort correctly in the A–Z list.**
  After the switch to alphabetical ordering, clients whose name came from the
  old "Business name" field clustered at the very top of the list; a one-time
  repair files them under their actual name so they appear in the right place.
- **Connecting to Wave fails cleanly when no business is configured.** Instead
  of showing a blank "Connected to" status, Connect now reports the problem and
  stays on the Connect button.
- **Wave customers imported without a name get a usable label.** Such customers
  now fall back to their first/last name or email instead of importing as a
  blank, unsortable row.

## [1.18.0+30] - 2026-06-23
### Added
- **The Wave section now shows you're connected.** Once an admin connects the
  business's Wave account, Settings shows a "Connected to <business>" status
  every time you open it — on any device, not just right after connecting.

### Changed
- **Connecting to Wave is now a single tap.** Connect links the business's Wave
  account directly, with no business to choose. Once connected, the Connect
  button is replaced by the connected status, leaving just "Import customers
  from Wave."

## [1.17.0+29] - 2026-06-23
### Changed
- **Clients are now listed alphabetically by name.** The client list is sorted
  A–Z instead of newest-first, making it easier to scan and find someone.

### Fixed
- **Imported Wave customers now appear in your client list.** Customers brought
  in from Wave were saved but didn't show up when browsing or searching clients.
  They now appear immediately. Re-running the import once repairs any customers
  imported earlier so they show up too.

## [1.16.1+28] - 2026-06-21
### Fixed
- **Clients identified only by a business name stay visible.** A client created
  before the recent details reshape — one whose only name was the old "Business
  name" — keeps that name on its card and detail screen, stays findable in
  search, and can still be opened and saved. Previously such clients could show
  up blank and refuse to save.
- **A quick second edit to a client is no longer lost during Wave sync.** If you
  edited a client again while its previous change was still syncing to Wave, the
  newer edit could be silently dropped; both edits now reach Wave.
- **Clearer message when your Wave account has more than one business.** Instead
  of a generic "something went wrong, try again," connecting now explains that
  choosing a specific business isn't supported yet.
- **The client detail screen no longer shows the contact's name twice.**

## [1.16.0+27] - 2026-06-21
### Added
- **Wave Accounting customer sync (admins).** Settings has a new Wave section
  (admins only) to connect the business's Wave account and import its existing
  customers into the app. From then on, every client you add or edit is synced
  to Wave automatically in the background, and each client shows a small Wave
  badge — *synced*, *sync pending*, or *sync error* — so you can see its status
  at a glance. The sync runs entirely server-side: it never slows the app down
  and a Wave outage just leaves a client "pending," never a failed save. The app
  always reads clients from its own database, so browsing and searching are as
  fast as before.

### Changed
- **Client details reshaped to match Wave.** A client now has a **Customer
  name** plus optional **First name** / **Last name**, and a separate **Mobile**
  field alongside Phone. The old single "Business name" field is gone — the
  customer name covers both people and businesses. Client search now also
  matches first name, last name, and mobile number.

## [1.15.1+26] - 2026-06-21
### Changed
- **iOS build now uses Swift Package Manager; CocoaPods removed.** All native
  iOS plugins are resolved through Swift Package Manager and the CocoaPods
  integration (Podfile, Pods project, and xcconfig includes) has been removed,
  which speeds up iOS builds. No change to app behavior. The custom
  permission-handler setup is no longer needed — only the permissions the app
  actually declares in Info.plist (camera, photos, contacts) are compiled in.
- **Image uploads no longer double-compress.** Picked images were being resized
  and JPEG-compressed once by the image picker and then a second time by a
  separate compression step. The redundant pass and its plugin
  (`flutter_image_compress`) were removed; the picker now produces the upload
  image directly at the same target size and quality. Uploads look the same and
  stay well under the size limit.

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
