# Scheduling App

> A private, client-commissioned mobile application for managing appointments, field employees, and client records in a service-based business.

This repository is proprietary. The source code, architecture, and configuration details contained here are confidential and intended solely for the development team and the commissioning client.

---

## Overview

The Scheduling App is a cross-platform mobile application built with Flutter, targeting Android and iOS from a single codebase. It provides a centralized platform for business owners and their field teams to coordinate service appointments in real time — replacing manual scheduling, paper records, and fragmented communication.

The application is backed by Google Firebase, giving it a secure, cloud-based foundation with offline-capable data sync, enterprise-grade authentication, and scalable storage for appointment photos and client files.

---

## Setup

1. **Environment file** — copy `dev/.env.example` to `dev/.env` and fill in the Firebase client values (Firebase console → *Project settings* → *General* → *Your apps*, or the output of `flutterfire configure`). `dev/.env` is gitignored and bundled as an asset at build time; the app fails fast on startup naming any missing key.
2. **Dependencies** — run `flutter pub get`. Localizations are generated automatically (`generate: true` in `pubspec.yaml`); run `flutter gen-l10n` manually if needed.
3. **Run** — `flutter run`.
4. **Local Firebase emulators (optional)** — start them with `firebase emulators:start`, then run the app with:

   ```bash
   flutter run --dart-define=USE_FIREBASE_EMULATOR=true
   # Override the emulator host if not on the Android emulator (default 10.0.2.2):
   flutter run --dart-define=USE_FIREBASE_EMULATOR=true --dart-define=EMULATOR_HOST=127.0.0.1
   ```

Building for iOS requires a Mac — see [docs/IOS_MAC_BUILD.md](docs/IOS_MAC_BUILD.md).

---

## Key Capabilities

### Appointment Scheduling
A full-featured monthly calendar lets administrators plan, assign, and manage service appointments. Each appointment captures everything needed in the field: client details, service address, assigned employees, time window, materials required, internal notes, and status. Administrators have a complete view of all scheduled work; employees see only the appointments assigned to them.

### Client Records
A searchable directory of clients, listed alphabetically by name — including customer name, optional first/last name, service address, billing contacts, phone, and mobile numbers. Records update in real time across all devices. The search engine matches customer name, first name, last name, phone, and mobile, handling accent characters and partial matches to keep lookups fast even with large client bases.

### Wave Accounting Sync
Administrators can connect the business's [Wave](https://www.waveapps.com) account and import its existing customers into the app. From then on, every client added or edited is synced to Wave automatically in the background, and each client carries a small status badge — *synced*, *sync pending*, or *sync error*. The sync runs entirely server-side, so it never slows the app down, and a Wave outage simply leaves a client "pending" rather than failing the save. The target Wave business is selected server-side, so nothing about the account is configured in the app.

### Employee Management
Administrators onboard employees through a controlled invite flow: an employee account is created by the admin first, and only pre-invited email addresses are permitted to self-register. Each employee is assigned a distinct display color that appears on the calendar, making workload distribution and scheduling conflicts immediately visible.

### Photo Documentation
Employees can attach photos directly to any appointment from their device camera or photo library. Images are compressed automatically and uploaded to secure cloud storage in the background, keeping the app responsive while files transfer.

### Access Control
Two distinct roles — **Admin** and **Employee** — enforce data boundaries at every layer of the application. Admins have full read/write access across all records. Employees operate within a scoped view limited to their own assigned work.

### Personalization & Accessibility
Users can switch between light and dark display modes, adjust text scaling for readability, and select their preferred language. All preferences are persisted across sessions. Status labels, text-size option names, and in-app notices are fully localized in English and French.

---

## Technical Foundation

| Concern | Solution |
|---|---|
| Mobile framework | Flutter — Android & iOS |
| Authentication | Firebase Authentication |
| Data store | Cloud Firestore (real-time sync) |
| File storage | Firebase Storage |
| Application security | Firebase App Check |
| Address lookup | Google Places API |
| Accounting sync | Wave Accounting (server-side) |
| Offline support | Firestore local cache |

---

## Application Architecture

The codebase follows a feature-first structure. Each domain area — authentication, calendar, clients, employees, and settings — is self-contained with its own screens, data models, business logic, and UI components. Shared utilities and design primitives are promoted to common layers only when used across multiple features.

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
