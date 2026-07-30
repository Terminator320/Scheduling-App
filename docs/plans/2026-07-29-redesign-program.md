# Navigation redesign — program design

**Date:** 2026-07-29 · **Branch:** `redesgin` · **Status:** approved design, pre-implementation

Source handoff: `C:\Users\GeorgeVogas\Downloads\Scheduling app navigation redesign\design_handoff_scheduling_app\`
(docs `01`–`10`, clickable prototype `design/Scheduling App.dc.html`, screenshots partially stale —
trust the prototype and the docs). The handoff is high-fidelity on visuals; every real gap is
data-model or backend. This document is the program-level spec: what ships, in what order, and every
decision made where the handoff and the codebase disagree. Each sub-project below gets its own
implementation plan when its turn comes.

## Program decisions (settled with the owner)

1. **Scope: everything, sequenced** — all seven projects plus the Wave invoice read path (P7b).
2. **Client fields: fast New, full Edit** — the New client sheet ships as designed (fast capture
   only); the Edit sheet is a superset keeping every existing field plus the new ones.
3. **Archive AND delete** — Archive is the primary removal action; hard delete stays as a second
   destructive row behind a `showConfirmDialog(destructive: true)`.
4. **Wide screens: drawer everywhere, keep two-pane** — the `AdaptiveShell` nav rail is deleted at
   every size; `isTwoPane` master-detail panes and the calendar month|agenda split survive, restyled.
5. **Typography: adopt both new fonts** — Instrument Sans for UI, IBM Plex Mono for data
   (times, counts, section labels). Sans-for-UI / mono-for-data becomes a theme convention.

## Deviations from the handoff (deliberate, don't "fix")

| Handoff says | We ship | Why |
| --- | --- | --- |
| Live-map staleness red at ~10 min | **25 min**, text-only | Location is foreground-only since the App Store 2.5.4 rejection; 10 min would mark nearly everyone stale. Must stay in sync with `PRESENCE_STALE_MINUTES` (`functions/travel_utils.js`) via `presenceStaleAfter`. Markers are never dimmed. |
| Client `SINCE` editable in Edit sheet | Rendered from read-only `createdAt` | `createdAt` is server-stamped and drives dashboard trends and list order; never client-editable. |
| Email editable on My details | **Read-only** | Email is the Firebase Auth identity; changing it is an auth flow (verify + token), not a profile edit. Deferred. |
| Photo pill on the My details profile card | Not shipped this pass | No avatar-photo storage exists (avatars are initials-on-colour); adding one is its own small project. |
| Density as a user setting | Fixed at **Balanced** | YAGNI; the tokens keep the three values so a setting can come later. |
| Role-preview segmented control on My details | Not shipped | The handoff itself marks it review-only. Role comes from auth. |
| `+ ADD` photo tile in the detail sheet for everyone | **Admin-only** | Assignee rules only allow `status`/`updatedAt` writes; an employee add would be `permission-denied`. |
| Instrument Sans / IBM Plex Mono "or equivalents" | Exactly those two, **bundled as assets** | google_fonts runtime-fetch is already on the audit backlog; bundling closes it. |

## Build order

```
P1 foundation → P2 calendar → P3 clients → P4 team → P5 settings/my-details → P6 time off → P7 dashboard/history
                                                                                P7b Wave invoices (parallel, unblocks P7 money sections)
```

P3/P4 model+rules work has no P1 dependency and may land early if de-risking is preferred.

---

## P1 — Foundation: tokens, fonts, drawer, header pair, toast

**Tokens.** Fold the `01-tokens.md` palette, radii, shadows, and motion into
`core/theme/design_tokens.dart` + `ColorScheme` + the existing `ThemeExtension`s
(`AppStatusColors`, `AppCardStyle`). Dark palette per `09-dark-theme.md`: separation by surface
stepping not shadow, status chips move to 16%-alpha fills, avatar text flips to near-black tints of
the avatar hue, buttons stay saturated (`#1D6BE8`), scrim deepens. **Never branch on
`isDark`/brightness** — every light↔dark divergence is a new extension field set in both `.light`
and `.dark`.

**Fonts.** Instrument Sans (UI) + IBM Plex Mono (data) bundled as assets. New type ramp from
`01-tokens.md` (display 26/700 −0.025em … micro mono 9px floor). Add a theme-level accessor for the
mono data style so call sites don't hand-build `GoogleFonts.ibmPlexMono(...)`.

**Header pair.** One reusable widget: Calendar pill (blue-tint pill, 38px tall) + hamburger icon
button (38×38, radius 12, blue tint), with a back-chevron variant for pushed pages. Replaces
`AppTopBar`'s current action area on every screen. The Calendar pill routes through
`HubTabSelector.select(AdaptiveDestination.calendar)` — clears pushed pages, closes sheets/drawer;
no screen is a dead end. The Live map floats the pair top-right on white shadowed surfaces.

**Drawer.** New right-anchored 284px grouped end drawer replacing both the current
`SettingsDrawer` nav list and the `AdaptiveShell` rail (rail deleted; `endDrawerFor` no longer
returns null on split layouts). Groups and dot colours per `02-navigation.md`:
TODAY (Calendar · Day route · Live map) / PEOPLE (Team · Time off · Clients) /
THE BUSINESS (Dashboard · History) / ACCOUNT (My details · Settings). Header = avatar + name +
`"Owner · Espro Plumbing"`-style line; version string pinned at the bottom. Counts wired live:
Calendar = today's job count, Live map = crew-on-the-clock count, Time off = pending count
(red when > 0; provider arrives in P6, renders nothing before that). **Employee drawer is scoped:**
TODAY (Calendar, Day route) + ACCOUNT only.

**Toast.** Restyle `NoticeListener`'s notice to the dark pill (`#0B1A33`/dark `#1A2436`, radius 16,
status dot, 2600 ms in-hold-out, 56px from top). Architecture, `noticeServiceProvider` API, and the
per-kind haptic are unchanged. Dot colours: mint success · `#7FCBFF` info · `#F0C36A` request sent ·
`#FF9AA8` declined/error.

**Hub restructure.** Hub tabs shrink to **Calendar · Clients · Team · Live map** (persistent
`IndexedStack`). **History and Settings become pushed routes** alongside Dashboard, Day route,
Time off, My details, client detail, employee detail. Handled consequences:

- Feature tours: History and Settings lose their hub-tab tour scopes; their tours re-host on the
  pushed screens (or retire for this pass — decide per-screen in the P1 plan). `tourStepsFor`
  catalogs and key wiring updated for any moved/removed target.
- `PrimaryScrollScope` re-checked for every simultaneously-mounted scrollable that remains.
- FAB `heroTag`s stay unique per mounted surface (`addFab`, `todayFab`, `clientsAddFab`,
  `employeesAddFab`, `liveMapRosterFab`, `liveMapRecenterFab` — renames tracked in the plan).
- `HubTabRedirectRoute` mappings updated for the new tab set; Android back / iOS edge swipe still
  return to Calendar.
- Stacking order per `02-navigation.md`: pushed page below status bar; sheets above; dropdown menu
  sheet above sheets; drawer above that; notice on top.

## P2 — Calendar

- Fixed header block (never scrolls): mono `SCHEDULE` label, tappable month name + year + chevron →
  **month/year picker** (not the prototype's tap-to-cycle), route icon button, hamburger.
- Month grid: **42 cells always** (35 drops the end of months like August 2026), 2px gap, 46px
  cells, **32×32 day circle carries the selected fill** (not the cell), max-3 crew dots (5px)
  coloured by who works that day, off-month cells blank and untappable.
- Sticky collapse: grid is the first thing inside the scroll view; past 80px it unmounts and a week
  strip (56px cells, 30×30 circles, one 4.5px dot) rises into the fixed header; a **150px spacer**
  keeps scroll extent stable; re-expand arms past 44px and fires below 6px (anti-thrash).
- Agenda header: date title + mono `N JOBS` count.
- **Appointment card** (single shared widget — agenda, history, client detail, employee detail,
  day route, review sheet): white radius 15, 4px full-height crew bar, title + status chip row, mono
  time range, 19px crew avatar + `"Crew · Client"` line (`Theo +1` for multi-crew). Cancelled =
  strikethrough at 0.6 opacity. Keep the `IntrinsicHeight` constraint — title stays plain `Text`.
- FAB (58×58, radius 20) + "Today" pill (popIn, only off-month). Status model unchanged: `overdue`
  stays display-only and derived; `pending` renders as **"Scheduled"** (label change only, EN+FR).

## P3 — Clients (the flagged gap)

**Model.** `ClientRecord` and `isValidClientData` (firestore.rules) gain, in lockstep:

| Field | Type | Rules cap |
| --- | --- | --- |
| `type` | string enum `residential` · `commercial` · `property_mgmt` (empty = unset) | `size() <= 32` |
| `tags` | list of strings | list `size() <= 10`; UI caps each tag via `TextLimits` |
| `accessNotes` | string | `size() <= 500` |
| `onSiteManager` | string | `size() <= 200` |
| `billingTerms` | string | `size() <= 200` |
| `autoInvoice` | bool | `is bool` |
| `archived` | bool | `is bool` |
| `jobCount` | int, **function-owned** | rejected on client writes, like `wave` |

`toMap` emits all user-owned new fields (so docs self-heal `archived: false` on first edit) and
still **never** emits `waveCustomerId`/`wave`/`jobCount`.

**Archived hazard (the trap).** Existing docs lack the field and Firestore excludes docs missing a
filter field — so **no `where('archived' == false)` anywhere**. The list page and search already
match in Dart; archived filtering happens there too. Archived clients: hidden from the client list
by default and from the appointment client picker; reachable via an "Archived" list filter; job
history and past appointments untouched. `propagateClientEdits` behaviour unchanged (archived
clients rarely get edits; if they do, propagation to future visits is correct anyway since
archiving doesn't cancel anything).

**Delete** keeps its repository path and gains a confirm dialog; sits under Archive in the Edit
sheet footer. Deleting orphans `clientName` on past appointments — the confirm copy says so.

**New client sheet** (form sheet, 88%): exactly as designed — WHO (name-or-business, type chips),
REACH THEM (phone, email · optional), SITE (address + **Map** pill → existing autocomplete,
access notes · optional), caption "Billing terms and tags can wait…". Primary verb **Add**.
Secondary **Add and book a job**: saves (existing `addClient` returns the record with its doc id),
pops, then opens the add-appointment sheet with the client pre-seeded — sequential sheets, not
stacked; double-tap-guarded with the `InlineAddClientHost` pattern (in-flight flag set before the
first await). The existing appointment-side inline add-client flow keeps working unchanged.

**Edit client sheet** (form sheet, 92%): superset in the new chrome (Cancel / title / Save bar,
white field panels, split rows) — CLIENT (name, first/last, type, since = read-only `createdAt`,
tags), CONTACT (phone, mobile, email, on-site manager), SITE (address grid incl. apt/city/
province/postal, `noFixedAddress` toggle, access notes), BILLING (terms, **Wave customer read-only
mono**, auto-invoice toggle), then Archive + Delete. Additional `contacts[]` editor stays.

**Client detail** (pushed on phones, detail pane under `isTwoPane` — decision 4): Edit pill →
edit sheet; action tiles **Call · Directions · Book job** (Book job opens the add-appointment sheet pre-seeded with this client; admin-only surface);
info panel `PHONE · ADDRESS · MANAGER · BILLING` (empty rows omitted); `JOB HISTORY` panel via the
existing `clientJobHistoryProvider`.

**Job count.** Server-maintained `jobCount` on the client doc, updated by a small addition to the
appointment write trigger (`FieldValue.increment` on create/delete/client-reassignment; idempotency
consistent with the trigger's existing retry semantics — exact mechanics in the P3 plan). Feeds the
list row's mono count and the archive caption ("keeps the N past jobs"). Rows render no count until
the field exists (empty-omitted rule). A one-time backfill script counts existing appointments.

## P4 — Team

**Model.** `role` today is the ACCESS flag (`admin`/`employee`) — it keeps that meaning; the ACCESS
toggle in the Edit person sheet maps to it. The design's role chips (Lead tech · Technician ·
Apprentice · Dispatcher) become a **new `jobTitle` field**. Also new on the user doc, all
rules-capped: `workingDays` (7 bools), `workStartMinutes`/`workEndMinutes`, `maxJobsPerDay`,
`onCall` (bool), `emergencyContact` (string). Write access splits two ways: `jobTitle`,
`maxJobsPerDay`, colour, `role`, and `status` are **admin-only**; the availability family
(`workingDays`, hours, `onCall`, `emergencyContact`, `phone`) is admin-writable **and**
self-service-writable (the P5 own-doc clause). The users-doc rules keep their four read clauses.

**Screens.** Team list (40px colour avatar, `"<jobTitle> · <n> jobs today"`, Active/Invited chip);
employee detail goes **read-only** (pushed on phones, pane under `isTwoPane`; profile card + Edit
pill, info panel `COLOUR · PHONE · HOURS · ACCESS`, `TODAY` panel of their stops); **Edit person sheet** owns all editing — details, role
chips, colour swatch grid (taken colours hidden, current selection always visible — matches
`EmployeeColorGrid` behaviour today), availability (7 toggle cells + start/end + max jobs), ACCESS
group (admin toggle + time-to-leave alerts), Disable account with the reassign-count caption.
**Invite sheet** restyled (first/last, work email, role chips, colour grid with "N colours left"
caption, admin toggle off by default, amber invited note); the signup-code flow
(`createEmployeeInvite` → copy dialog) is unchanged.

## P5 — Settings + My details

**Settings** (pushed): profile row → My details; grouped panels APPEARANCE (theme, text size,
language) · SECURITY (app lock, change password) · INTEGRATIONS (Wave, admin-only) ·
NOTIFICATIONS; version footer. Existing rows/providers restyled, not rebuilt.

**My details** (pushed, everyone): profile card (photo pill deferred with email — see deviations);
YOU CAN CHANGE THESE (phone, emergency contact; email shown read-only); MY AVAILABILITY (7 day
toggles, start/end, on-call) — **applies immediately**, with the inline amber conflict warning when
a turned-off day has booked work ("…the jobs stay until someone moves them"); TIME OFF section
(P6); NOTIFICATIONS (existing toggles). For admins the SET BY YOUR ADMIN panel appears as an
editable SCHEDULING panel; for technicians it is **hidden entirely**.

**Rules.** A user may update **only** the self-service keys on their own doc —
`affectedKeys().hasOnly(['phone', 'emergencyContact', 'workingDays', 'workStartMinutes',
'workEndMinutes', 'onCall', 'updatedAt'])` under `uid == request.auth.uid` — scheduling fields
(role, jobTitle, colour, maxJobsPerDay, status) stay admin-only. Nothing is ever auto-unassigned:
availability changes notify (inline warning + P7 dashboard flag), a human moves the jobs.

## P6 — Time off (new feature)

**Collection `timeOff`:** `{employeeDocId, uid, from, to, kind: holiday|sick|unpaid, note, status:
pending|approved|declined, declineReason, decidedBy, decidedAt, createdAt, updatedAt}`. Allowance:
`allowanceDays` on the user doc (admin-set, default 15); used-count derived from approved requests
in the current year. **Rules:** employee creates own request only with `status == 'pending'` and
`uid == request.auth.uid` (payload shape validated); employee reads own; admin reads all; admin
updates status pending→approved / pending→declined, **decline requires a non-empty
`declineReason`**; no client deletes. Server timestamps on create/decide.

**Surfaces.**
- **Request sheet** (employee, from My details): From/To, kind chips, note; derived mono summary
  (`4 DAYS · 2 WORKING DAYS` — working days from their own `workingDays`); derived **jobs in this
  window** panel with the caption "Nothing is cancelled by asking"; footer "Send request to
  <admin>".
- **Review sheet** (admin): request header + note; `N JOBS TO REASSIGN` — each job with crew chips;
  a chosen chip **reassigns through the existing appointment edit path** so
  `mergeRetainedAssignees` and the notification diff hold; decline-reason chips; Decline / Approve
  (label tracks: "Approve" / "Approve and reassign").
- **Board** (pushed, admin): Waiting / Upcoming / History segmented tabs per `05-screens-business.md`
  — request cards with age chip and coverage warning; month-grouped upcoming; allowance-used bars +
  decided list **with the decline reason quoted**. Declines always carry their reason, here and on
  the employee's page.
- **Dashboard card** + drawer pending count (red when > 0).
- **Calendar context:** approved days block the employee's calendar visually (rendering decided in
  the P6 plan).
- **Pushes:** request-created (to admins) and decision (to the employee) ride the existing FCM
  pipeline in `notifications.js`, with per-recipient idempotency ledgers like the existing kinds.

## P7 — Dashboard + History

**Dashboard** (pushed, admin): hero gradient card (today's count + completed / in progress); period
segmented control **wired** (Today · Week · Month · Year re-filter the aggregator); KPI grid
(only the tiles with data — see P7b); Time off card (P6); employee workload bars; New clients
(from `createdAt`, tappable rows → client detail); Jobs booked per day (7 bars, over-capacity red
using `maxJobsPerDay`); Needs attention (existing flags + pending time-off + availability-conflict
+ stale invites). **Chart rule everywhere:** bars live in their own fixed-height track; value and
axis labels are siblings outside it — labels sharing the flex column silently clip tall bars.

**Money sections do not ship in P7.** Revenue trend, Avg ticket, Unpaid invoices, Top clients by
revenue, Quotes won, First-time fix are **omitted** (not stubbed — empty-omitted rule) until P7b.

**History** (pushed): search field with clear button; **Year / Crew dropdowns opening as
dropdown-menu sheets** (the reusable single-select sheet pattern from `06-sheets-and-dialogs.md`);
quick-filter chips; mono result count; day-grouped panels; cancelled struck through. Filtering
stays the existing bounded Dart-side search (`historySearchProvider`); no new server queries.

## P7b — Wave invoice read path (independent project)

Unblocks the six dashboard money sections. Server-side only: scheduled function queries Wave
(GraphQL, `WAVE_FULL_ACCESS_TOKEN` from Secret Manager) for invoices; projects the minimal fields
(totals, status, age buckets, customer id) into a rules-locked `waveInvoices` (or aggregate doc)
collection readable by admins via a callable, mirroring the `waveGetConnection` pattern — the app
never talks to Wave directly and no client-side reads of the raw collection. Scoped and specced
separately when it starts.

## Cross-cutting requirements

- **Localisation:** every new string = paired EN+FR ARB keys with `@key` blocks; `flutter gen-l10n`
  (auto-hook on ARB edits). Chip labels, mono captions, notices, decline reasons — all of it.
- **Accessibility:** text-scale sweeps 0.8–2.0 at 375×667 per screen touched; every new animation
  collapses under `disableAnimationsOf`; `Semantics` on icon-only controls (header pair, day cells).
- **Load-bearing invariants unchanged:** `showActions` required + false default · unique FAB
  `heroTag`s · `PrimaryScrollScope` on simultaneously-mounted scrollables · `isSplitLayout` vs
  `isTwoPane` not conflated (rail dies but the two-pane gate lives) · no `LayoutBuilder` under
  `IntrinsicHeight` · success ≠ `tertiary` · offline fail-fast on entity writes · notices not
  SnackBars.
- **Rules discipline:** every new client-writable field gets a type/length cap in the same commit;
  new callables follow guard order auth → `assertAdmin` → shape → rate limit → work; no new client
  `runTransaction` call sites.
- **Testing:** policy/domain logic as pure classes with `test()`; widget tests per the harness
  requirements; jest for any function changes (pure logic extracted into plain modules).

## Sequencing note

Each project gets its own implementation plan (superpowers:writing-plans) and its own
verify-and-ship cycle on this branch. P1 is first unless the owner asks to front-load the P3/P4
model + rules work.
