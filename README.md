# Scheduling App

> A private, client-commissioned mobile application for managing appointments, field employees, and client records in a service-based business.

This repository is proprietary. The source code, architecture, and configuration details contained here are confidential and intended solely for the development team and the commissioning client.

---

## Overview

The Scheduling App is a native Android application built with Flutter. It provides a centralized platform for business owners and their field teams to coordinate service appointments in real time — replacing manual scheduling, paper records, and fragmented communication.

The application is backed by Google Firebase, giving it a secure, cloud-based foundation with offline-capable data sync, enterprise-grade authentication, and scalable storage for appointment photos and client files.

---

## Key Capabilities

### Appointment Scheduling
A full-featured monthly calendar lets administrators plan, assign, and manage service appointments. Each appointment captures everything needed in the field: client details, service address, assigned employees, time window, materials required, internal notes, and status. Administrators have a complete view of all scheduled work; employees see only the appointments assigned to them.

### Client Records
A searchable, paginated directory of clients — including business name, service address, billing contacts, and phone numbers. Records update in real time across all devices. The search engine handles accent characters and partial matches to keep lookups fast even with large client bases.

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
| Mobile framework | Flutter — Android |
| Authentication | Firebase Authentication |
| Data store | Cloud Firestore (real-time sync) |
| File storage | Firebase Storage |
| Application security | Firebase App Check |
| Address lookup | Google Places API |
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
The next major milestone is a full integration with [Wave](https://www.waveapps.com), a cloud-based accounting and invoicing platform. The goal is to bridge the gap between scheduling and billing — once a service appointment is completed in the app, the relevant data will flow directly into Wave to generate invoices, track payments, and maintain accurate financial records without any manual re-entry.

Planned scope includes:

- **Automatic invoice generation** — completed appointments trigger draft invoices in Wave, pre-populated with client details, service description, and time-based or flat-rate billing.
- **Client record sync** — clients created or updated in the Scheduling App will be reflected in Wave's customer directory, keeping both systems consistent.
- **Payment status visibility** — invoice and payment status from Wave surfaced within the app so administrators can see outstanding balances alongside their scheduling view.
- **Appointment-to-invoice traceability** — each appointment will carry a reference to its corresponding Wave invoice, creating a clear audit trail from booking to payment.

This integration will position the application as an end-to-end operations platform — from the moment a job is scheduled to the moment it is invoiced and paid.

---

## Confidentiality Notice

This application and all associated source code, documentation, and configuration are the exclusive property of the commissioning client. Unauthorized access, reproduction, distribution, or use of any part of this repository is strictly prohibited.

&copy; 2026 — All rights reserved.
