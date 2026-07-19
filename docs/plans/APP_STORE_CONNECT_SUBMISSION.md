# App Store Connect Submission Materials — ES Pro

Prepared 2026-07-19 · app version **1.33.0+52** · bundle `net.vogas.scheduling`
· team **H5XWLU87AX** · launch scope **App Store only** (iPhone + iPad).

This doc holds everything that gets **typed into App Store Connect (ASC) or
added in Xcode** so submission is turnkey once the owner is on a Mac. It
**complements** the Mac build runbook in `docs/plans/IOS_APP_STORE_HANDOFF.md`
(clone, SPM, App Attest, archive, upload) — it does **not** repeat those steps.
Where the two overlap (privacy questionnaire, screenshots, demo account), the
runbook has the one-line checkbox and this doc has the actual content to paste.

Cross-references used throughout:
- Privacy policy (live): `https://gvogas.github.io/es-pro-legal/`
  (source `docs/legal/privacy-policy.html`; linked in-app via
  `AppUrls.privacyPolicy`).
- Person in charge of personal information: George Vogas — george@vogas.net.
- The app is bilingual; ASC needs **English (Canada)** as primary and
  **French (Canada)** as a localization. Provide both for every text field.

---

## 0. What the app actually collects (ground truth for everything below)

Confirmed by reading `lib/`, `functions/`, `ios/Runner/Info.plist`, and
`pubspec.yaml`. Everything is stored in **Firebase (Firestore / Storage /
Crashlytics / Cloud Messaging)**. There are **no advertising or analytics SDKs**
(no `firebase_analytics`, no AdMob, no third-party trackers) — verified against
`pubspec.yaml`. `NSPrivacyTracking = false` is correct.

| What | Where in code | Sent off device? |
|---|---|---|
| Account email, display name, phone, role | `users/{id}` Firestore doc | Yes (Firestore) |
| Firebase auth UID / users-doc id | `users/{id}`, `usersByUid/{uid}` | Yes |
| Client contact records (name, business, phone, mobile, email, street/city/province/postal/country, contacts array) | `clients/{id}` Firestore doc, entered by admins | Yes |
| Appointment content (date/time, assignees, status, notes, address) | `appointments/{id}` | Yes |
| Appointment photos | Firebase Storage `appointments/*/images/*` (JPEG/PNG, validated) | Yes |
| **Precise background location** of active staff + assigned admins | `users/{docId}/presence/location` (`geolocator` background stream) | Yes |
| FCM push token + per-device locale | `users/{docId}/fcmTokens/{token}` | Yes |
| Crash diagnostics | Firebase Crashlytics | Yes |

**Contacts is NOT a collected data type.** `flutter_contacts`
(`contact_export_launcher.dart`) only **writes** a client the admin already has
into the device address book, and reads back **only the single contact it
created** to keep it in sync. It never harvests the address book and never
uploads device contacts to a server. So the app **accesses** the Contacts API
(needs `NSContactsUsageDescription`, already present) but does **not collect**
Contacts for App Privacy purposes. Do not declare Contacts on the nutrition
label.

**No** financial info, health, browsing history, search history, or purchases
leave the app. Wave Accounting runs entirely server-side (Cloud Functions); the
app never reads Wave client-side, so no accounting/financial data is collected
by the app itself.

---

## 1. App Privacy nutrition labels (ASC → App Privacy)

Answer the ASC flow as: **Yes, we collect data.** Then declare exactly these
types. For **every** type below: **Used for tracking = No** (there is no
tracking across apps or websites). "Linked to identity" is Yes wherever the data
sits under a signed-in user's account.

| Data type (Apple category) | Collected | Linked to identity | Tracking | Purpose | Notes |
|---|---|---|---|---|---|
| **Name** (Contact Info) | Yes | Yes | No | App Functionality | Account display name + client names entered by admins |
| **Email Address** (Contact Info) | Yes | Yes | No | App Functionality | Sign-in email + client emails |
| **Phone Number** (Contact Info) | Yes | Yes | No | App Functionality | Account phone + client phone/mobile |
| **Physical Address** (Contact Info) | Yes | Yes | No | App Functionality | Client street/city/postal + job addresses |
| **Precise Location** (Location) | Yes | Yes | No | App Functionality | Background GPS for time-to-leave reminders + admin live staff map; active staff and assigned admins only |
| **Photos or Videos** (User Content) | Yes | Yes | No | App Functionality | Photos attached to appointments |
| **Other User Content** (User Content) | Yes | Yes | No | App Functionality | Appointment notes / job details |
| **User ID** (Identifiers) | Yes | Yes | No | App Functionality | Firebase auth UID / users-doc id |
| **Device ID** (Identifiers) | Yes | Yes | No | App Functionality | FCM push token (per-device, for job notifications) |
| **Crash Data** (Diagnostics) | Yes | No | No | App Functionality | Firebase Crashlytics |

Notes for the reviewer-facing questionnaire wording:
- Precise Location is the one type most likely to draw a follow-up. It is
  **App Functionality**, **not** tracking or advertising. It is background
  location (the app has `UIBackgroundModes: location`). Justification lives in
  §5 App Review notes.
- Crash Data (Diagnostics) is declared **not linked to identity** — the app
  does not call Crashlytics `setUserId` with PII; crash reports are not tied to
  a customer's account in the console. (No Performance Data is declared — the
  app ships no Firebase Performance Monitoring SDK.)
- If ASC asks whether any collected data is **required** vs optional: account
  and client data are required to use the app; location is optional (the app
  degrades gracefully when a user denies or grants only "while using").

---

## 2. iOS Privacy Manifest (`PrivacyInfo.xcprivacy`)

The repo already tracks two manifests. The main app's
`ios/Runner/PrivacyInfo.xcprivacy` has **already been updated** to the version
below (verified 2026-07-19) — its `NSPrivacyCollectedDataTypes` array is fully
populated and matches the nutrition labels in §1, so **no code change is
required**. The block below is the authoritative reference; diff it against the
on-disk file if you need to confirm. The required-reason API entries (UserDefaults
`CA92.1` for `shared_preferences`, File Timestamp `C617.1` for `path_provider` /
`flutter_cache_manager` file access, System Boot Time `35F9.1`) are present and
correct — keep them.

### `ios/Runner/PrivacyInfo.xcprivacy` (complete file)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSPrivacyTracking</key>
	<false/>
	<key>NSPrivacyTrackingDomains</key>
	<array/>
	<key>NSPrivacyCollectedDataTypes</key>
	<array>
		<!-- Contact Info: Name -->
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeName</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<!-- Contact Info: Email Address -->
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeEmailAddress</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<!-- Contact Info: Phone Number -->
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypePhoneNumber</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<!-- Contact Info: Physical Address -->
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypePhysicalAddress</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<!-- Location: Precise Location -->
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypePreciseLocation</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<!-- User Content: Photos or Videos -->
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypePhotosorVideos</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<!-- User Content: Other User Content (appointment notes/details) -->
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeOtherUserContent</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<!-- Identifiers: User ID -->
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeUserID</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<!-- Identifiers: Device ID (FCM push token) -->
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeDeviceID</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<!-- Diagnostics: Crash Data -->
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeCrashData</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<false/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
	</array>
	<key>NSPrivacyAccessedAPITypes</key>
	<array>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>CA92.1</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>C617.1</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategorySystemBootTime</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>35F9.1</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
```

**Widget manifest** (`ios/ScheduleWidget/PrivacyInfo.xcprivacy`): leave as-is.
The widget only reads the shared App Group payload via `UserDefaults` (already
declared with `CA92.1`) and collects nothing of its own. No change needed.

Note: `NSPrivacyCollectedDataTypePhotosorVideos` is Apple's exact spelling (no
camel-case on "or") — do not "correct" it or the manifest validation fails.

---

## 3. Store metadata (paste into ASC)

Character limits are Apple's hard caps: App Name 30, Subtitle 30, Promotional
Text 170, Keywords 100, "What's New" 4000, Description 4000. **Counts below are
my count — re-verify in the ASC field before saving; ASC rejects an over-limit
value.**

### English (Canada) — primary

**App Name** (≤30)
```
ES Pro
```

**Subtitle** (≤30) — 29 chars
```
Schedule plumbing jobs & crew
```

**Promotional Text** (≤170) — 158 chars; editable any time without a new build
```
Book a job, send it to the right plumber, and the whole crew sees the change on their phone. Photos, client history, and traffic-timed reminders come with it.
```

**Keywords** (≤100, comma-separated, no spaces) — 99 chars
```
plumber,plumbing,scheduler,appointments,dispatch,crew,jobs,fieldservice,technician,calendar,clients
```

**Description** (≤4000)
```
ES Pro runs a plumbing business from one screen. Book a job, assign the right plumber, and everyone on the crew sees their day the moment it changes.

Made for the field:
- See your appointments by day, week, or month.
- Put one or more plumbers on a job. Each person sees only the work that is theirs.
- Keep every client's name, phone, address, and past visits in one place, and add a new client without leaving the booking screen.
- Snap photos on a job straight from the camera so the office sees the work that was done.
- Get a reminder when it is time to leave, timed to the real traffic between your last stop and the next one.
- Open a live map of where the crew is during the day.
- Mark jobs in progress and complete, and get a nudge when one runs past its end time.

Works where plumbers work:
- Book and edit jobs in a basement with no signal. Changes sync once you are back online.
- Get a push the moment a job is assigned, moved, or cancelled, even with the app closed.
- Add today's jobs to your home screen and see your next stop without opening the app.

In French and English:
- Switch languages any time. Every screen, notification, and reminder is bilingual.

ES Pro is built for a plumbing crew by the company that runs one. Sign-in is by invitation from your administrator, so the whole team stays on one shared schedule.
```

**What's New in This Version** (first App Store release)
```
First release of ES Pro on the App Store.

- Day, week, and month schedule for the whole crew
- Assign plumbers to jobs and keep client history in one place
- Job photos from the camera
- Traffic-timed "time to leave" reminders and a live crew map
- Push notifications when a job changes, plus a home-screen widget
- Works offline and syncs when you reconnect
- Full French and English
```

**Support URL** (required) — placeholder, owner to confirm
```
https://gvogas.github.io/es-pro-legal/
```
> Owner: ASC requires a reachable support page. The privacy-policy host works as
> a stopgap, but a page that shows a support email (george@vogas.net) is better.
> If you add a `support.html` beside the privacy policy, put its URL here.

**Marketing URL** (optional) — leave blank or reuse the support URL.

**Privacy Policy URL** (required)
```
https://gvogas.github.io/es-pro-legal/
```

**Primary Category:** Business. **Secondary Category:** Productivity.

**Copyright:** `2026 Plombier Eau Secours`

---

### French (Canada) — localization

**Nom de l'app** (≤30)
```
ES Pro
```

**Sous-titre** (≤30) — 29 chars
```
Planifiez chantiers et équipe
```

**Texte promotionnel** (≤170) — 169 chars (the earlier "et rappels" wording was 171, over the cap)
```
Créez un rendez-vous, envoyez-le au bon plombier, et toute l'équipe voit le changement sur son téléphone. Photos, historique client, rappels selon la circulation inclus.
```

**Mots-clés** (≤100, séparés par des virgules, sans espaces) — vérifier le compte
```
plombier,plomberie,horaire,rendezvous,repartition,equipe,chantier,technicien,calendrier,clients
```

**Description** (≤4000)
```
ES Pro gère une entreprise de plomberie à partir d'un seul écran. Créez un rendez-vous, assignez le bon plombier, et toute l'équipe voit sa journée dès qu'elle change.

Pensé pour le terrain :
- Consultez vos rendez-vous par jour, par semaine ou par mois.
- Assignez un ou plusieurs plombiers à un chantier. Chacun ne voit que ses propres tâches.
- Gardez le nom, le téléphone, l'adresse et les visites passées de chaque client au même endroit, et ajoutez un nouveau client sans quitter l'écran de réservation.
- Prenez des photos sur le chantier directement avec l'appareil photo pour que le bureau voie le travail réalisé.
- Recevez un rappel au moment de partir, calculé selon la circulation réelle entre votre dernier arrêt et le suivant.
- Ouvrez une carte en direct de la position de l'équipe pendant la journée.
- Marquez les chantiers en cours et terminés, et recevez un rappel lorsqu'un chantier dépasse son heure de fin.

Fonctionne là où travaillent les plombiers :
- Créez et modifiez des chantiers dans un sous-sol sans réseau. Les changements se synchronisent une fois de retour en ligne.
- Recevez une notification dès qu'un chantier est assigné, déplacé ou annulé, même l'app fermée.
- Ajoutez les chantiers du jour à votre écran d'accueil et voyez votre prochain arrêt sans ouvrir l'app.

En français et en anglais :
- Changez de langue à tout moment. Chaque écran, notification et rappel est bilingue.

ES Pro est conçu pour une équipe de plomberie par l'entreprise qui en exploite une. La connexion se fait sur invitation de votre administrateur, pour que toute l'équipe partage le même horaire.
```

**Nouveautés de cette version** (première sortie)
```
Première version d'ES Pro sur l'App Store.

- Horaire par jour, semaine et mois pour toute l'équipe
- Assignation des plombiers aux chantiers et historique client centralisé
- Photos de chantier depuis l'appareil photo
- Rappels « heure de partir » selon la circulation et carte de l'équipe en direct
- Notifications quand un chantier change, plus un widget d'écran d'accueil
- Fonctionne hors ligne et se synchronise au retour du réseau
- Entièrement en français et en anglais
```

---

## 4. Screenshot plan

### Required sizes (iPhone + iPad, since iPad target is kept)

| Device slot | Pixel size (portrait) | Required? |
|---|---|---|
| iPhone 6.9" (16 Pro Max / 15 Pro Max) | 1320 × 2868 | **Required** — ASC's baseline iPhone set |
| iPhone 6.5" (11 Pro Max / XS Max) | 1242 × 2688 | Optional; ASC can reuse the 6.9" set. Provide if you have a 6.5" simulator handy, else skip. |
| iPad 13" (iPad Pro M4) | 2064 × 2752 | **Required** — the app ships for iPad (`TARGETED_DEVICE_FAMILY = "1,2"`) |

Landscape variants are optional; portrait is enough for approval. Capture from a
device/simulator signed into the **demo account** (§5) so no real customer data
shows. Localize: capture each shot **twice**, once with the device in English,
once in French, and upload to the matching ASC localization.

Up to 10 screenshots per size. Recommended set of 7 (order = story):

| # | Screen to capture | EN caption | FR caption |
|---|---|---|---|
| 1 | Calendar — month grid + day agenda (tablet/landscape split shows both) | Your whole crew's day, week, and month | La journée, la semaine et le mois de votre équipe |
| 2 | Appointment detail sheet (client, address, assignees, photos) | Every job detail in one place | Tous les détails d'un chantier au même endroit |
| 3 | Add / edit appointment with employee picker | Assign the right plumber in seconds | Assignez le bon plombier en quelques secondes |
| 4 | Live staff map with pins + roster sheet | See where the crew is, live | Voyez où est l'équipe, en direct |
| 5 | Admin dashboard (counts / charts) | Know the day at a glance | Ayez un aperçu de la journée |
| 6 | Client list / search | Client history, always at hand | L'historique client, toujours à portée |
| 7 | A "time to leave" push / reminder (or notifications settings) | A reminder timed to real traffic | Un rappel calculé selon la circulation |

Login screen is optional as a shot; it shows little and reviewers reach it
anyway. If you want an 8th, use the home-screen widget showing today's jobs
("Today's jobs on your home screen" / "Les chantiers du jour sur l'écran
d'accueil"). Avoid the App Attest / permission dialogs in shots.

---

## 5. Age rating + App Review notes

### Age rating questionnaire (ASC → Age Rating)

Answer **None / No** to every content question. Target result: **4+**.

| Question | Answer |
|---|---|
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Prolonged Graphic or Sadistic Realistic Violence | None |
| Profanity or Crude Humor | None |
| Mature/Suggestive Themes | None |
| Horror/Fear Themes | None |
| Medical/Treatment Information | None |
| Alcohol, Tobacco, or Drug Use or References | None |
| Simulated Gambling | None |
| Sexual Content or Nudity | None |
| Graphic Sexual Content and Nudity | None |
| Contests | None |
| Unrestricted Web Access | No |
| Gambling (real) | No |
| Made for Kids | No |
| Age Assurance / age verification used | No |
| In-app purchases | No |

Expected rating: **4+**. (Location collection and account sign-in do not raise
the content rating.)

### App Review Information (ASC → App Review Information)

- **Sign-in required:** Yes. Provide the demo credentials below.
- **Contact:** George Vogas · george@vogas.net · (phone as required by ASC).

**Demo accounts** — create before submitting (signup is invite-only via one-time
codes, so Review cannot self-register). Fill in real values:

```
Admin demo:
  Email:    demo-admin@vogas.net        (OWNER: create + confirm)
  Password: __________________________

Employee demo (optional, shows the field-worker view):
  Email:    demo-employee@vogas.net     (OWNER: create + confirm)
  Password: __________________________
```
Seed the demo admin's tenant with a few fake clients/appointments so the app is
not empty and no real customer data is exposed. The admin account shows the full
app (dashboard, live map, Wave section, client management); if you only give one
account, give the admin.

**Review notes (paste into the Notes field):**
```
ES Pro is a private scheduling tool for a Quebec plumbing company and its
employees. Accounts are created by invitation only (one-time codes issued by an
administrator), so there is no public self-registration. Please use the demo
credentials above.

Roles: an "admin" account manages the schedule, clients, employees, the live
staff map, and dashboard. An "employee" account sees only the jobs assigned to
them. The demo admin account shows the full app.

Background location: the app collects the signed-in staff member's location in
the background for two features only: (1) timing a "time to leave" reminder
using live traffic to the next job, and (2) an admin-only live map of where the
crew currently is. It is App Functionality, not tracking or advertising, and is
tied to the user's own account. Location can be denied or limited to "while
using" and the app still works (it falls back to a fixed 30-minute reminder).

App Check uses Apple App Attest, which only produces valid tokens on real
hardware. On the Simulator, network calls to our Cloud Functions may fail. Please
test on a physical device (this is a TestFlight/store-signed build, so App Attest
works there).

Account deletion is available in-app: Settings has a delete-account action that
removes the user's account and data server-side.

Notifications and the home-screen widget: the app requests notification
permission to alert staff when a job is assigned, moved, or cancelled, and for
reminders. These are optional.
```

---

## 6. Pre-submission checklist (owner-only, Mac / ASC)

These are the steps only the owner can do, and that are **not** already covered
as build steps in `IOS_APP_STORE_HANDOFF.md`. (Build/archive/App Attest/upload
live in that runbook; this is the ASC content side.)

**In Xcode:**
- [x] `ios/Runner/PrivacyInfo.xcprivacy` **already matches** the §2 version
      (`NSPrivacyCollectedDataTypes` populated, verified 2026-07-19). No change
      needed — just confirm it's committed. Widget manifest unchanged.

**In App Store Connect — app record + metadata:**
- [ ] Confirm the app record: **ES Pro**, `net.vogas.scheduling`, Business /
      Productivity categories, copyright.
- [ ] Add **French (Canada)** localization; paste EN + FR name, subtitle,
      promo text, keywords, description, What's New from §3.
- [ ] Verify every field's character count in-field (name/subtitle/keywords are
      the tight ones).
- [ ] Support URL + Privacy Policy URL set (§3). Consider a dedicated support
      page showing george@vogas.net.

**In ASC — App Privacy (§1):**
- [ ] Declare all 10 data types with Linked/Tracking/Purpose exactly as the
      table. Tracking = No everywhere. Precise Location = App Functionality.
- [ ] Confirm the labels match the §2 manifest (Apple cross-checks them).

**In ASC — Age Rating (§5):**
- [ ] Complete the questionnaire (all None/No) → expect 4+.

**In ASC — App Review Information (§5):**
- [ ] Create the demo admin (and optional employee) accounts; seed fake data.
- [ ] Paste the review notes; fill in demo credentials + contact phone.

**In ASC — Screenshots (§4):**
- [ ] Upload the iPhone 6.9" set (EN + FR). iPad 13" set (EN + FR). Optional
      6.5" if available.

**In ASC — build + release:**
- [ ] After TestFlight upload (runbook §6), attach the build to the version.
- [ ] Export Compliance: `ITSAppUsesNonExemptEncryption = false` is in
      `Info.plist`, so no upload prompt; confirm no compliance question blocks
      submission.
- [ ] Pricing = Free; availability = Canada (at minimum), plus any other
      regions you want.
- [ ] Submit for review.

---

## Assumptions the owner must verify

1. **Character counts** were re-verified 2026-07-19 with `wc -m`: App Name 6,
   EN subtitle 29, EN promo 158, EN keywords 99, FR subtitle 29, FR promo 169
   (fixed down from an over-cap 171), FR keywords 95 — all within Apple's caps.
   Long Description/What's-New fields (4000-cap) were not machine-counted; they
   are well under. Still worth a glance in-field, since ASC hard-rejects
   over-limit values.
2. **Support URL** currently points at the privacy-policy host as a placeholder.
   ASC wants a reachable support page; a page listing george@vogas.net is
   ideal. Decide before submitting.
3. **Demo account credentials** are placeholders — the accounts must be created
   (invite-only flow) and seeded with fake data, and the passwords filled in.
4. **Category choice** (Business primary, Productivity secondary) is my
   recommendation for a field-service scheduling tool; change if you prefer.
5. **Diagnostics not linked to identity** assumes Crashlytics is not configured
   with `setUserId` carrying PII. I did not find such a call, but confirm before
   ticking "not linked" if you later add user-scoped crash reporting.
6. **Copyright holder / seller name** shown as "Plombier Eau Secours" from the
   privacy policy — confirm it matches the legal entity on the Apple Developer
   account.
7. **Region availability / pricing** is a business decision not derivable from
   code; Canada-at-minimum is assumed given the Quebec audience.
```
