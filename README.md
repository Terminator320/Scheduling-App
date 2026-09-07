# Scheduling App

> A private, client-commissioned mobile application for managing appointments, field employees, and client records in a service-based business.

This repository is proprietary. The source code, architecture, and configuration details contained here are confidential and intended solely for the development team and the commissioning client.

---

## Overview

The Scheduling App is a mobile application for iPhone, built with Flutter. It provides a centralized platform for business owners and their field teams to coordinate service appointments in real time — replacing manual scheduling, paper records, and fragmented communication.

The application is backed by Google Firebase, giving it a secure, cloud-based foundation with offline-capable data sync, enterprise-grade authentication, and scalable storage for appointment photos and client files.

---

## Setup

1. **Build config** — copy `dev/firebase.local.example.json` to `dev/firebase.local.json`, fill in the Firebase and iOS Maps client values, and pass it with `--dart-define-from-file`. Required keys are `IOS_API_KEY`, `IOS_APP_ID`, `MESSAGING_SENDER_ID`, `PROJECT_ID`, `STORAGE_BUCKET`, and `IOS_MAPS_API_KEY`. The app fails fast on startup naming any missing Firebase key.
2. **Dependencies** — run `flutter pub get`. Localizations are generated automatically (`generate: true` in `pubspec.yaml`); run `flutter gen-l10n` manually if needed.
3. **Run** — `flutter run --dart-define-from-file=dev/firebase.local.json`, or pass the same keys individually with repeated `--dart-define=KEY=value` arguments.
4. **Local Firebase emulators (optional)** — start them with `firebase emulators:start`, then run the app with:

   ```bash
   flutter run --dart-define=USE_FIREBASE_EMULATOR=true
   # Host defaults to 127.0.0.1, which is what the iOS Simulator needs.
   # Override it when running on a physical device on the same network:
   flutter run --dart-define=USE_FIREBASE_EMULATOR=true --dart-define=EMULATOR_HOST=192.168.x.x
   ```

5. **Analytics (optional in development)** — Firebase Analytics collection is **off in debug builds** so `flutter run` never files events against the production property. To watch events in Firebase DebugView, turn collection on *and* add the launch argument:

   ```bash
   flutter run --dart-define-from-file=dev/firebase.local.json --dart-define=ANALYTICS_DEBUG=true
   ```

   The `-FIRDebugEnabled` launch argument also has to be on the Xcode scheme — see [docs/IOS_MAC_BUILD.md](docs/IOS_MAC_BUILD.md). Release builds always collect.

6. **Release builds should drop the advertising identifier** — the app sells no ads and needs no attribution, so build with `FIREBASE_ANALYTICS_WITHOUT_ADID=true` in the environment. That swaps `FirebaseAnalytics` for `FirebaseAnalyticsCore` in the plugin's SPM package, which removes IDFA collection and the App Store privacy disclosure that comes with it:

   ```bash
   FIREBASE_ANALYTICS_WITHOUT_ADID=true flutter build ios --release --dart-define-from-file=dev/firebase.local.json
   ```

The app targets **iOS only** and building it requires a Mac — see [docs/IOS_MAC_BUILD.md](docs/IOS_MAC_BUILD.md).

---

## Key Capabilities

### Appointment Scheduling
A full-featured monthly calendar lets administrators plan, assign, and manage service appointments. Each appointment captures everything needed in the field: client details, service address, assigned employees, time window, materials required, internal notes, and status. Administrators have a complete view of all scheduled work; employees see only the appointments assigned to them.

A job is not limited to a single day. An appointment can be booked across a run of up to two weeks, and its start and end times are read as a **daily working window** — 9 to 5 across a five-day run means 9 to 5 on each of those days, not one unbroken stretch through the nights. Each day of the run appears on the calendar in its own right, labelled with its position ("Day 3 of 5"), and an overnight shift is expressed simply by ending earlier in the clock than it starts.

Not every entry on the calendar is a client visit. A **personal job** blocks out time for the crew itself — an appointment, a day off, a training morning — with no client and no address, and can cover a whole day rather than a time window. It still names who the time belongs to, so it shows up on their schedule and counts against their availability, and the system knows not to treat it as work in progress: it is never chased for completion and never triggers a "time to leave" alert.

### Admin Dashboard
A single overview screen gives administrators the day at a glance: today's visits broken down by status, how many are still unassigned, each employee's workload for today and the week, an eight-week trend of completed versus cancelled jobs and new clients, the busiest weekday, and an attention list flagging jobs starting soon or already running overdue.

### Live Staff Map
Administrators can see their field team on a live map — each employee who is sharing location appears as a colored pin, with a roster that orders staff by proximity and shows how recently each position was reported. Location is captured while the app is in the foreground on the employee's device (foreground-only since 2026-07-27, for App Store guideline 2.5.4) and is only ever visible to administrators, giving dispatch a picture of who is where without any manual check-ins.

### Push Notifications
Field employees are kept in the loop automatically — they receive a push when they're assigned to, rescheduled on, or removed from a visit, a reminder shortly before a job is due to start, a nudge to close out a job once it runs past its end time, and an end-of-day summary of the next day's work. On iPhone, a home-screen widget shows an employee's remaining jobs for the day and their next upcoming visit.

Reminders are **travel-aware**: rather than a fixed countdown, the system estimates live, traffic-aware drive time from where the employee is (or their previous job) to the next stop and sends a "time to leave" alert at the right moment to arrive on schedule. On a recent iPhone, this surfaces as a Lock Screen Live Activity card that counts down to the job — and if drive time can't be determined, it safely falls back to a standard fixed reminder.

### Client Records
A searchable directory of clients, listed alphabetically by name — including customer name, optional first/last name, service address, billing contacts, and phone number. Records update in real time across all devices. The search engine matches customer name, first name, last name and phone, handling accent characters and partial matches to keep lookups fast even with large client bases.

A client is never deleted out from under their own history. Clients that are no longer active are **archived**: they drop out of the main list and the type filter, but stay searchable and bookable, and every past appointment keeps its link to them. Archiving is reversible, and a client can still be removed outright only while they have no appointments at all — the server checks, and refuses otherwise.

### Wave Accounting Sync
Administrators can connect the business's [Wave](https://www.waveapps.com) account and keep the two customer lists in step. Every client added or edited is synced to Wave automatically in the background, and each client carries a small status badge — *synced*, *sync pending*, or *sync error*. A single **Sync with Wave** action runs both directions on demand: it sends whatever is still waiting to reach Wave, then pulls Wave's customers back into the app. It reports what actually moved and in which direction, and says plainly when a run didn't finish or a customer was rejected, rather than reporting a clean result. Customer imports can also be scheduled to run automatically on a weekly or monthly cadence (or left off). The sync runs entirely server-side, so it never slows the app down, and a Wave outage simply leaves a client "pending" rather than failing the save. The target Wave business is selected server-side, so nothing about the account is configured in the app.

### Employee Management
Administrators onboard employees directly: the admin creates the account and hands over the sign-in email and a starting password, and the employee then signs in and sets their own password. There is no self-registration path. Each employee is assigned a distinct display color that appears on the calendar, making workload distribution and scheduling conflicts immediately visible.

### Photo Documentation
Employees can attach photos directly to any appointment from their device camera or photo library. Images are compressed automatically and uploaded to secure cloud storage in the background, keeping the app responsive while files transfer.

### Route Planning
Employees get a timeline view of their day's stops in order, and can hand the whole route off to Google Maps as a single multi-stop trip for turn-by-turn navigation between jobs — or open directions to any individual address. This turns a list of appointments into an efficient driving plan for the day.

### Hands-Free with Siri
On iPhone, employees and administrators can ask Siri about their schedule without opening the app — how many appointments they have, what's on today, their next visit, or the plan for a specific day. Answers are drawn from an on-device snapshot, so they work quickly and only ever expose the schedule details the question needs.

### Guided Tours
The first time a user opens each main screen, a short, role-aware walkthrough highlights the key actions available there. Tours only run once, respect what each role can actually do, and can be replayed at any time from Settings.

### Access Control
Two distinct roles — **Admin** and **Employee** — enforce data boundaries at every layer of the application. Admins have full read/write access across all records. Employees operate within a scoped view limited to their own assigned work.

### Personalization & Accessibility
Users can switch between light and dark display modes, adjust text scaling for readability, and select their preferred language. All preferences are persisted across sessions. Status labels, text-size option names, and in-app notices are fully localized in English and French.

---

## Technical Foundation

| Concern | Solution |
|---|---|
| Mobile framework | Flutter — iOS |
| Authentication | Firebase Authentication |
| Data store | Cloud Firestore (real-time sync) |
| File storage | Firebase Storage |
| Application security | Firebase App Check |
| Push & background delivery | Firebase Cloud Messaging + APNs (iOS Live Activities) |
| Address lookup | Google Places API |
| Mapping, live location & routing | Google Maps SDK, Google Routes API, device GPS |
| Voice queries | Siri App Intents (iOS) |
| Accounting sync | Wave Accounting (server-side) |
| Offline support | Firestore local cache |

---

## Application Architecture

The codebase follows a feature-first structure. Each domain area — authentication, calendar, clients, employees, dashboard, notifications, live location, and settings among them — is self-contained with its own screens, data models, business logic, and UI components. Shared utilities and design primitives are promoted to common layers only when used across multiple features.

All navigation is centralized through a single route handler, ensuring consistent screen construction and argument passing throughout the application. Data access is strictly mediated through per-feature service classes; no screen ever queries the database directly.

---

## Data Model

Three primary collections form the application's data backbone:

**Users** — employee and admin accounts, including role, account status, and a display color used on the calendar.

**Appointments** — the complete record of a scheduled service visit, including a client snapshot, assigned employee list, time range, location, status, and attached photos.

**Clients** — business and contact information, including a full address, primary phone, email, and any number of additional named contacts.

---

## Security & Privacy

- All authentication is handled by Firebase Authentication. No passwords are stored in application code or the database.
- Role boundaries are enforced at the data layer. Employee-scoped queries filter records server-side, not just in the UI.
- Sensitive configuration — API keys, project identifiers — is managed through environment variables and is never committed to version control.
- Firebase App Check prevents unauthorized API access from outside the application binary.
- Sensitive account actions and server endpoints are rate-limited to deter abuse and brute-force attempts.
- All requests to server functions are validated and size-limited; malformed or oversized payloads are rejected before processing.

---

## Roadmap

### Wave Billing Integration
The first stage of the [Wave](https://www.waveapps.com) integration — **client record sync** — is live: clients created or updated in the Scheduling App are reflected in Wave's customer directory, keeping both systems consistent (see *Wave Accounting Sync* above).

The next milestone extends this to full billing, bridging the gap between scheduling and invoicing so that once a service appointment is completed in the app, the relevant data flows directly into Wave without any manual re-entry.

Planned scope includes:

- **Automatic invoice generation** — completed appointments trigger draft invoices in Wave, pre-populated with client details, service description, and time-based or flat-rate billing.
- **Payment status visibility** — invoice and payment status from Wave surfaced within the app so administrators can see outstanding balances alongside their scheduling view.
- **Appointment-to-invoice traceability** — each appointment will carry a reference to its corresponding Wave invoice, creating a clear audit trail from booking to payment.

This integration will position the application as an end-to-end operations platform — from the moment a job is scheduled to the moment it is invoiced and paid.

---

## Confidentiality Notice

This application and all associated source code, documentation, and configuration are the exclusive property of the commissioning client. Unauthorized access, reproduction, distribution, or use of any part of this repository is strictly prohibited.

&copy; 2026 — All rights reserved.
