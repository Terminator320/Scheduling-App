# Client-Facing SMS + Email Appointment Reminders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status: PLANNED — approved design 2026-07-13, not started.**

**Goal:** Text (Twilio) and email (SendGrid) each CLIENT a reminder ~24 h
before their appointment, with per-client opt-out toggles and an FR/EN
language preference (FR default — Quebec business).

**Architecture:** A new scheduled Cloud Function `sendClientAppointmentReminders`
(every 15 min) mirrors the employee-push sweep pattern: query the existing
`(status, startTime)` index for appointments starting within 24 h, join client
contact data from `clients` by `clientId`, claim a per-appointment idempotency
ledger doc with `create()`, then send SMS/email over plain HTTPS. All logic
lives in a pure jest-testable module (`client_reminder_utils.js`); the trigger
wrapper stays thin. Secrets live in Secret Manager only.

**Tech Stack:** Firebase Cloud Functions v2 (Node), Twilio REST API, SendGrid
v3 API, Jest, Flutter/Dart (client form fields), `gen_l10n`, Firestore rules.

---

## Context

### Decisions made with the user (2026-07-13)

- **Both channels**: SMS (Twilio) AND email (SendGrid) — SMS is the
  time-sensitive channel, email the backup/receipt.
- **Timing:** one reminder per appointment occurrence, sent on the first sweep
  after the visit enters the 24 h window. A same-day booking therefore gets its
  reminder right away — accepted (the template states the explicit date/time,
  never "tomorrow").
- **Language:** per-client `language` field, `'fr'` default, `'en'` option.
- **Out of scope v1:** booking confirmations, "on my way" texts, two-way SMS.
  Twilio's built-in Advanced Opt-Out handles STOP/ARRET replies.

### Key design findings (from codebase research)

- Appointment docs already carry `clientId`, `clientName`, `clientPhone` —
  but **NOT `clientEmail`**. The sweep joins `clients/{clientId}` via one
  batched `db.getAll()` per sweep; the client doc is also the fresher source
  for phone (falls back to the denormalized `clientPhone` if the client doc is
  gone).
- The sweep query reuses the existing `(status ASC, startTime ASC)` composite
  index (`firestore.indexes.json:43-49`) — **no new index**.
- Ledger pattern to copy: `_deliverRecipientOnce`
  (`functions/notification_utils.js:812-856`) — atomic `create()` claim,
  `isAlreadyExists` → skip, `delete()` release when nothing was delivered,
  `expiresAt` +7 d for a console TTL policy.
- Ledger id: `${appointmentId}_${startTimeMillis}` (ONE client per
  appointment — no recipient dimension needed; a reschedule changes
  `startTimeMillis` and naturally re-arms).
- Status filter: `status in ['pending', 'confirmed']` — legacy `confirmed`
  docs still exist (retired 2026-07-09, no migration); `in_progress`, `done`,
  `cancelled` excluded.
- Secret + fetch discipline to copy: `functions/places.js:16,73,103-147`
  (`defineSecret` → `secrets: [...]` → `.value().trim()`; try/catch fetch,
  non-200 → 200-char body preview at `warn`, try/catch `.json()`).
  `wave/callables.js:388-394` proves `secrets` works on `onSchedule`.
- New-toggle template: `noFixedAddress` end-to-end
  (`client_record.dart:48/90/115` → `client_form_state.dart:17-25` →
  `add_client_sheet.dart:212-222` + `client_edit_form.dart` →
  `firestore.rules` `isValidClientData` → `app_en.arb` label+hint pair).
- No E.164 formatter exists — add one (pure, both sides only need it
  server-side).
- **PII discipline:** never log phone numbers or emails — log
  `appointmentId`/`clientId` only.

### New client-doc fields (all optional, absent = default)

| Field | Type | Default | Meaning |
|---|---|---|---|
| `smsReminders` | bool | `true` | client receives reminder SMS |
| `emailReminders` | bool | `true` | client receives reminder email |
| `language` | string | `'fr'` | reminder language, `'fr'` or `'en'` |

---

### Task 1: Pure helpers — `functions/client_reminder_utils.js` (jest, TDD)

**Files:**
- Create: `functions/client_reminder_utils.js`
- Test: `functions/__tests__/client_reminder_utils.test.js`

- [ ] **Step 1: Write the failing tests**

```js
"use strict";

const {
  toE164Canada,
  clientReminderLedgerId,
  selectClientReminderCandidates,
  resolveClientChannels,
  buildClientReminderSms,
  buildClientReminderEmail,
} = require("../client_reminder_utils");

const NOW = new Date("2026-07-13T12:00:00.000Z");
const HOUR = 60 * 60 * 1000;
const future = (ms) => new Date(NOW.getTime() + ms);

describe("toE164Canada", () => {
  test("formats a bare 10-digit number", () => {
    expect(toE164Canada("514-555-0134")).toBe("+15145550134");
  });
  test("accepts a leading 1", () => {
    expect(toE164Canada("1 (514) 555-0134")).toBe("+15145550134");
  });
  test("rejects short, long, and empty input", () => {
    expect(toE164Canada("555-0134")).toBeNull();
    expect(toE164Canada("2514555013455")).toBeNull();
    expect(toE164Canada("")).toBeNull();
    expect(toE164Canada(null)).toBeNull();
  });
});

describe("clientReminderLedgerId", () => {
  test("keys on appointment id + startTime millis", () => {
    expect(clientReminderLedgerId("a1", 1234)).toBe("a1_1234");
  });
});

describe("selectClientReminderCandidates", () => {
  const doc = (over) => ({
    id: "a1", status: "pending", clientId: "c1",
    startTime: future(4 * HOUR), ...over,
  });
  test("keeps pending and legacy confirmed inside 24h", () => {
    const docs = [doc({}), doc({id: "a2", status: "confirmed"})];
    expect(selectClientReminderCandidates(docs, NOW).map((d) => d.id))
        .toEqual(["a1", "a2"]);
  });
  test("drops terminal statuses and past/beyond-window starts", () => {
    const docs = [
      doc({id: "done", status: "done"}),
      doc({id: "cancelled", status: "cancelled"}),
      doc({id: "past", startTime: future(-1 * HOUR)}),
      doc({id: "far", startTime: future(25 * HOUR)}),
      doc({id: "noclient", clientId: ""}),
    ];
    expect(selectClientReminderCandidates(docs, NOW)).toEqual([]);
  });
});

describe("resolveClientChannels", () => {
  const appt = {clientPhone: "514-555-0000"};
  test("defaults: both channels on, fr, mobile preferred", () => {
    const r = resolveClientChannels(
        {mobile: "514-555-0134", phone: "514-555-9999",
          email: "a@b.ca"}, appt);
    expect(r).toEqual({
      language: "fr",
      smsTo: "+15145550134",
      emailTo: "a@b.ca",
    });
  });
  test("explicit opt-outs disable a channel", () => {
    const r = resolveClientChannels(
        {mobile: "514-555-0134", email: "a@b.ca",
          smsReminders: false, emailReminders: false}, appt);
    expect(r.smsTo).toBeNull();
    expect(r.emailTo).toBeNull();
  });
  test("missing client doc falls back to appointment clientPhone", () => {
    const r = resolveClientChannels(null, appt);
    expect(r.smsTo).toBe("+15145550000");
    expect(r.emailTo).toBeNull();
    expect(r.language).toBe("fr");
  });
  test("en language is honored; junk falls back to fr", () => {
    expect(resolveClientChannels({language: "en"}, appt).language).toBe("en");
    expect(resolveClientChannels({language: "es"}, appt).language).toBe("fr");
  });
});

describe("templates", () => {
  const ctx = {
    clientName: "Marie",
    startTime: new Date("2026-07-14T13:00:00.000Z"), // 9:00 Toronto
    address: "12 Rue Principale, Gatineau",
  };
  test("fr SMS includes date, Toronto time, and address", () => {
    const s = buildClientReminderSms(ctx, "fr");
    expect(s).toContain("Rappel");
    expect(s).toContain("9");
    expect(s).toContain("12 Rue Principale");
  });
  test("en SMS variant", () => {
    const s = buildClientReminderSms(ctx, "en");
    expect(s).toContain("Reminder");
  });
  test("address is omitted cleanly when empty", () => {
    const s = buildClientReminderSms({...ctx, address: " "}, "fr");
    expect(s).not.toContain("Adresse");
  });
  test("email has subject and body in both languages", () => {
    const fr = buildClientReminderEmail(ctx, "fr");
    expect(fr.subject).toContain("Rappel");
    expect(fr.text).toContain("12 Rue Principale");
    const en = buildClientReminderEmail(ctx, "en");
    expect(en.subject).toContain("Reminder");
  });
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd functions && npx jest __tests__/client_reminder_utils.test.js`
Expected: FAIL (module not found).

- [ ] **Step 3: Implement the pure module**

```js
"use strict";

/**
 * Client-facing reminder logic — pure and dependency-injected so jest can
 * require() it without an admin/scheduler runtime (same convention as
 * notification_utils.js / signup_code_utils.js).
 */

const CLIENT_REMINDER_LEAD_MS = 24 * 60 * 60 * 1000;
const LEDGER_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const CLIENT_REMINDER_SWEEP_MAX = 500;
const LEDGER_COLLECTION = "clientAppointmentReminders";
const REMINDER_FROM_EMAIL = "rappels@vogas.net"; // must be a SendGrid-verified sender
const REMINDER_FROM_NAME = "Plombier Eau Secours!";

function toE164Canada(raw) {
  const digits = String(raw || "").replace(/\D/g, "");
  if (digits.length === 10) return "+1" + digits;
  if (digits.length === 11 && digits.startsWith("1")) return "+" + digits;
  return null;
}

function clientReminderLedgerId(appointmentId, startTimeMillis) {
  return `${appointmentId}_${startTimeMillis}`;
}

function selectClientReminderCandidates(docs, now) {
  const nowMs = now.getTime();
  return docs.filter((d) => {
    if (d.status !== "pending" && d.status !== "confirmed") return false;
    if (!d.clientId) return false;
    const startMs = d.startTime instanceof Date ?
      d.startTime.getTime() : d.startTime.toMillis();
    return startMs > nowMs && startMs <= nowMs + CLIENT_REMINDER_LEAD_MS;
  });
}

function resolveClientChannels(clientData, appointment) {
  const c = clientData || {};
  const language = c.language === "en" ? "en" : "fr";
  const smsEnabled = c.smsReminders !== false;
  const emailEnabled = c.emailReminders !== false;
  const rawPhone = [c.mobile, c.phone, appointment.clientPhone]
      .map((v) => String(v || "").trim())
      .find((v) => v) || "";
  const phone = toE164Canada(rawPhone);
  const email = String(c.email || "").trim();
  return {
    language,
    smsTo: smsEnabled && phone ? phone : null,
    emailTo: emailEnabled && email ? email : null,
  };
}

function _formatWhen(startTime, language) {
  const date = startTime instanceof Date ? startTime : startTime.toDate();
  return new Intl.DateTimeFormat(language === "fr" ? "fr-CA" : "en-CA", {
    timeZone: "America/Toronto",
    weekday: "long", day: "numeric", month: "long",
    hour: "numeric", minute: "2-digit",
  }).format(date);
}

function buildClientReminderSms(ctx, language) {
  const when = _formatWhen(ctx.startTime, language);
  const addr = String(ctx.address || "").trim();
  if (language === "fr") {
    const base = `Rappel ${REMINDER_FROM_NAME} : rendez-vous le ${when}.`;
    return addr ? `${base} Adresse : ${addr}.` : base;
  }
  const base = `Reminder from ${REMINDER_FROM_NAME}: appointment on ${when}.`;
  return addr ? `${base} Address: ${addr}.` : base;
}

function buildClientReminderEmail(ctx, language) {
  const when = _formatWhen(ctx.startTime, language);
  const addr = String(ctx.address || "").trim();
  const name = String(ctx.clientName || "").trim();
  if (language === "fr") {
    return {
      subject: `Rappel de rendez-vous — ${REMINDER_FROM_NAME}`,
      text: [
        name ? `Bonjour ${name},` : "Bonjour,",
        "",
        `Petit rappel : votre rendez-vous avec ${REMINDER_FROM_NAME} est ` +
          `prévu le ${when}.`,
        addr ? `Adresse : ${addr}` : "",
        "",
        "À bientôt!",
      ].filter((l) => l !== null).join("\n"),
    };
  }
  return {
    subject: `Appointment reminder — ${REMINDER_FROM_NAME}`,
    text: [
      name ? `Hello ${name},` : "Hello,",
      "",
      `A quick reminder: your appointment with ${REMINDER_FROM_NAME} is ` +
        `scheduled for ${when}.`,
      addr ? `Address: ${addr}` : "",
      "",
      "See you soon!",
    ].filter((l) => l !== null).join("\n"),
  };
}

module.exports = {
  CLIENT_REMINDER_LEAD_MS,
  LEDGER_TTL_MS,
  CLIENT_REMINDER_SWEEP_MAX,
  LEDGER_COLLECTION,
  REMINDER_FROM_EMAIL,
  REMINDER_FROM_NAME,
  toE164Canada,
  clientReminderLedgerId,
  selectClientReminderCandidates,
  resolveClientChannels,
  buildClientReminderSms,
  buildClientReminderEmail,
};
```

(Note: French accents push SMS into UCS-2 encoding — 70 chars/segment, so a
reminder is typically 2 segments ≈ US$0.02–0.03. Accepted.)

- [ ] **Step 4: Run tests + lint**

Run: `cd functions && npx jest __tests__/client_reminder_utils.test.js && npm run lint`
Expected: PASS / clean (80-char lines — Google ESLint).

- [ ] **Step 5: Commit**

```bash
git add functions/client_reminder_utils.js functions/__tests__/client_reminder_utils.test.js
git commit -m "feat: pure client reminder helpers"
```

---

### Task 2: HTTPS senders (Twilio + SendGrid) with injected fetch

**Files:**
- Modify: `functions/client_reminder_utils.js`
- Test: `functions/__tests__/client_reminder_utils.test.js` (append)

- [ ] **Step 1: Failing tests (fake fetchImpl)**

```js
const {sendTwilioSms, sendSendgridEmail} = require("../client_reminder_utils");

const silentLogger = {warn: () => {}, info: () => {}, error: () => {}};

describe("sendTwilioSms", () => {
  const args = (fetchImpl) => ({
    fetchImpl, logger: silentLogger,
    accountSid: "AC123", authToken: "tok", from: "+15550001111",
    to: "+15145550134", body: "hi",
  });
  test("201 -> true, posts form-encoded to the account URL", async () => {
    let captured;
    const ok = await sendTwilioSms(args(async (url, init) => {
      captured = {url, init};
      return {status: 201, text: async () => ""};
    }));
    expect(ok).toBe(true);
    expect(captured.url).toContain("/Accounts/AC123/Messages.json");
    expect(captured.init.headers["Authorization"]).toMatch(/^Basic /);
    expect(captured.init.body).toContain("To=%2B15145550134");
  });
  test("non-201 -> false", async () => {
    const ok = await sendTwilioSms(args(async () => (
      {status: 400, text: async () => "bad"})));
    expect(ok).toBe(false);
  });
  test("transport throw -> false", async () => {
    const ok = await sendTwilioSms(args(async () => {
      throw new Error("boom");
    }));
    expect(ok).toBe(false);
  });
});

describe("sendSendgridEmail", () => {
  const args = (fetchImpl) => ({
    fetchImpl, logger: silentLogger, apiKey: "SG.x",
    to: "a@b.ca", subject: "s", text: "t",
  });
  test("202 -> true with bearer auth", async () => {
    let captured;
    const ok = await sendSendgridEmail(args(async (url, init) => {
      captured = {url, init};
      return {status: 202, text: async () => ""};
    }));
    expect(ok).toBe(true);
    expect(captured.url).toBe("https://api.sendgrid.com/v3/mail/send");
    expect(captured.init.headers["Authorization"]).toBe("Bearer SG.x");
  });
  test("non-202 -> false; transport throw -> false", async () => {
    expect(await sendSendgridEmail(args(async () => (
      {status: 401, text: async () => "no"})))).toBe(false);
    expect(await sendSendgridEmail(args(async () => {
      throw new Error("x");
    }))).toBe(false);
  });
});
```

- [ ] **Step 2: Run to verify failure, then implement**

Both senders follow the `places.js` error discipline — try/catch transport →
warn → false; non-2xx → 200-char body preview at warn → false. **Never log
`to`** (PII) — log only status.

```js
async function sendTwilioSms(opts) {
  const {fetchImpl, accountSid, authToken, from, to, body, logger} = opts;
  let response;
  try {
    response = await fetchImpl(
        `https://api.twilio.com/2010-04-01/Accounts/${accountSid}` +
          "/Messages.json",
        {
          method: "POST",
          headers: {
            "Authorization": "Basic " + Buffer.from(
                `${accountSid}:${authToken}`).toString("base64"),
            "Content-Type": "application/x-www-form-urlencoded",
          },
          body: new URLSearchParams({To: to, From: from, Body: body})
              .toString(),
        });
  } catch (err) {
    logger.warn("clientReminder: twilio transport error", {err: err.message});
    return false;
  }
  if (response.status !== 201) {
    const preview = (await response.text()).slice(0, 200);
    logger.warn("clientReminder: twilio non-201", {
      status: response.status, body: preview,
    });
    return false;
  }
  return true;
}

async function sendSendgridEmail(opts) {
  const {fetchImpl, apiKey, to, subject, text, logger} = opts;
  let response;
  try {
    response = await fetchImpl("https://api.sendgrid.com/v3/mail/send", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        personalizations: [{to: [{email: to}]}],
        from: {email: REMINDER_FROM_EMAIL, name: REMINDER_FROM_NAME},
        subject,
        content: [{type: "text/plain", value: text}],
      }),
    });
  } catch (err) {
    logger.warn("clientReminder: sendgrid transport error",
        {err: err.message});
    return false;
  }
  if (response.status !== 202) {
    const preview = (await response.text()).slice(0, 200);
    logger.warn("clientReminder: sendgrid non-202", {
      status: response.status, body: preview,
    });
    return false;
  }
  return true;
}
```

Add both to `module.exports`.

- [ ] **Step 3: Run + commit**

Run: `cd functions && npx jest __tests__/client_reminder_utils.test.js && npm run lint` → PASS.

```bash
git add functions/client_reminder_utils.js functions/__tests__/client_reminder_utils.test.js
git commit -m "feat: twilio and sendgrid senders"
```

---

### Task 3: `runClientReminderSweep` orchestrator

**Files:**
- Modify: `functions/client_reminder_utils.js`
- Test: `functions/__tests__/client_reminder_utils.test.js` (append; build a
  small `makeDb` mock modeled on `notification_utils.test.js:349-427` —
  appointments query + `getAll` for clients + ledger create/delete recording,
  `err.code = 6` on pre-existing ledger keys)

- [ ] **Step 1: Failing tests**

Cover, at minimum:
- happy path: pending appointment 4 h out + client doc with mobile+email →
  ledger create, one SMS + one email sent, `res.reminded === 1`;
- existing ledger doc → no sends, no release;
- both channels fail → ledger released (`delete()` recorded) for retry;
- one channel succeeds, one fails → claim kept (client was reached);
- client with `smsReminders:false, emailReminders:false` → skipped, **no
  ledger write** (nothing to retry, avoids create/delete churn every sweep);
- client doc missing → falls back to appointment `clientPhone` (SMS only);
- one candidate throwing does not stop the others;
- `language:'en'` client gets the English template (assert body content).

- [ ] **Step 2: Implement**

```js
async function runClientReminderSweep(deps) {
  const {db, now, logger} = deps;
  const nowMs = now.getTime();
  const windowEnd = new Date(nowMs + CLIENT_REMINDER_LEAD_MS);
  const snap = await db.collection("appointments")
      .where("status", "in", ["pending", "confirmed"])
      .where("startTime", ">", now)
      .where("startTime", "<=", windowEnd)
      .limit(CLIENT_REMINDER_SWEEP_MAX)
      .get();
  const docs = snap.docs.map((d) => ({id: d.id, ...d.data()}));
  if (docs.length >= CLIENT_REMINDER_SWEEP_MAX) {
    logger.warn("clientReminder: sweep cap hit", {cap: CLIENT_REMINDER_SWEEP_MAX});
  }
  const candidates = selectClientReminderCandidates(docs, now);
  const clientIds = [...new Set(candidates.map((c) => c.clientId))];
  const clientById = new Map();
  if (clientIds.length) {
    const refs = clientIds.map((id) => db.collection("clients").doc(id));
    for (const doc of await db.getAll(...refs)) {
      if (doc.exists) clientById.set(doc.id, doc.data());
    }
  }
  let reminded = 0;
  for (const appt of candidates) {
    try {
      reminded += await _remindClientOnce(deps, appt,
          clientById.get(appt.clientId) || null);
    } catch (err) {
      logger.warn("clientReminder: candidate failed", {id: appt.id, err});
    }
  }
  return {reminded};
}

async function _remindClientOnce(deps, appt, clientData) {
  const {db, fetchImpl, now, logger, twilio, sendgrid} = deps;
  const channels = resolveClientChannels(clientData, appt);
  if (!channels.smsTo && !channels.emailTo) {
    logger.info("clientReminder: no reachable channel", {id: appt.id});
    return 0;
  }
  const startMs = appt.startTime instanceof Date ?
    appt.startTime.getTime() : appt.startTime.toMillis();
  const ledgerRef = db.collection(LEDGER_COLLECTION)
      .doc(clientReminderLedgerId(appt.id, startMs));
  try {
    await ledgerRef.create({
      createdAt: now,
      expiresAt: new Date(now.getTime() + LEDGER_TTL_MS),
    });
  } catch (err) {
    if (err.code === 6 || err.code === "already-exists") return 0;
    logger.warn("clientReminder: ledger create failed", {id: appt.id, err});
    return 0;
  }
  const ctx = {
    clientName: appt.clientName,
    startTime: appt.startTime instanceof Date ?
      appt.startTime : appt.startTime.toDate(),
    address: appt.address,
  };
  let delivered = 0;
  if (channels.smsTo) {
    const ok = await sendTwilioSms({
      fetchImpl, logger,
      accountSid: twilio.accountSid, authToken: twilio.authToken,
      from: twilio.from, to: channels.smsTo,
      body: buildClientReminderSms(ctx, channels.language),
    });
    if (ok) delivered++;
  }
  if (channels.emailTo) {
    const {subject, text} =
        buildClientReminderEmail(ctx, channels.language);
    const ok = await sendSendgridEmail({
      fetchImpl, logger, apiKey: sendgrid.apiKey,
      to: channels.emailTo, subject, text,
    });
    if (ok) delivered++;
  }
  if (delivered === 0) {
    try {
      await ledgerRef.delete(); // release the claim so the next sweep retries
    } catch (err) {
      logger.warn("clientReminder: ledger release failed", {id: appt.id, err});
    }
  }
  return delivered > 0 ? 1 : 0;
}
```

Export `runClientReminderSweep` (keep `_remindClientOnce` private).

- [ ] **Step 3: Run + commit**

Run: `cd functions && npx jest __tests__/client_reminder_utils.test.js && npm run lint` → PASS.

```bash
git add functions/client_reminder_utils.js functions/__tests__/client_reminder_utils.test.js
git commit -m "feat: client reminder sweep orchestrator"
```

---

### Task 4: Trigger wiring + export

**Files:**
- Modify: `functions/notifications.js`
- Modify: `functions/index.js`

- [ ] **Step 1: Add the scheduled wrapper**

In `notifications.js` (thin, mirroring `sendOverdueJobPrompts` at lines 92-104;
`liveDeps()` at lines 29-36 supplies `db`/`now`/`logger` — messaging unused):

```js
const {defineSecret} = require("firebase-functions/params");
const {runClientReminderSweep} = require("./client_reminder_utils");

const TWILIO_ACCOUNT_SID = defineSecret("TWILIO_ACCOUNT_SID");
const TWILIO_AUTH_TOKEN = defineSecret("TWILIO_AUTH_TOKEN");
const TWILIO_FROM_NUMBER = defineSecret("TWILIO_FROM_NUMBER");
const SENDGRID_API_KEY = defineSecret("SENDGRID_API_KEY");

const sendClientAppointmentReminders = onSchedule(
    {
      schedule: "every 15 minutes",
      timeZone: "America/Toronto",
      maxInstances: 1,
      timeoutSeconds: 300,
      secrets: [TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN,
        TWILIO_FROM_NUMBER, SENDGRID_API_KEY],
    },
    async () => {
      await runClientReminderSweep({
        ...liveDeps(),
        fetchImpl: fetch,
        twilio: {
          accountSid: TWILIO_ACCOUNT_SID.value().trim(),
          authToken: TWILIO_AUTH_TOKEN.value().trim(),
          from: TWILIO_FROM_NUMBER.value().trim(),
        },
        sendgrid: {apiKey: SENDGRID_API_KEY.value().trim()},
      });
    },
);
```

Add `sendClientAppointmentReminders` to `notifications.js`'s exports and
re-export it from `functions/index.js` beside the other notification
functions. Like the other sweeps: deliberately **no `retry: true`** — a
duplicate client text is worse than a 15-min-late one.

- [ ] **Step 2: Lint + commit**

Run: `cd functions && npm run lint && npm test` → clean, all green.

```bash
git add functions/notifications.js functions/index.js
git commit -m "feat: sendClientAppointmentReminders scheduled function"
```

---

### Task 5: Firestore rules

**Files:**
- Modify: `firestore.rules`

- [ ] **Step 1: Ledger deny-all block**

Beside `appointmentOverduePrompts` (firestore.rules:89-94):

```
    // clientAppointmentReminders is the Admin-SDK-only idempotency ledger for
    // the client-facing SMS/email reminder sweep (one doc per appointment
    // occurrence). Same posture as appointmentReminders.
    match /clientAppointmentReminders/{id} {
      allow read, write: if false;
    }
```

- [ ] **Step 2: Validate the three new client fields**

In `isValidClientData` (firestore.rules:218-227) add:

```
        && (!('smsReminders' in data) || data.smsReminders is bool)
        && (!('emailReminders' in data) || data.emailReminders is bool)
        && (!('language' in data) || (data.language is string && data.language.size() <= 5))
```

- [ ] **Step 3: Commit**

```bash
git add firestore.rules
git commit -m "feat: client reminder ledger rules and client field validation"
```

---

### Task 6: Flutter — `ClientRecord` fields (TDD)

**Files:**
- Modify: `lib/features/clients/domain/models/client_record.dart`
- Test: `test/features/clients/domain/models/client_record_test.dart`
  (extend the existing file if present, else create)

- [ ] **Step 1: Failing tests**

```dart
test('reminder fields default on and fr', () {
  final c = ClientRecord.fromMap('id1', {'name': 'A'});
  expect(c.smsReminders, isTrue);
  expect(c.emailReminders, isTrue);
  expect(c.language, 'fr');
});

test('reminder fields round-trip through toMap', () {
  const c = ClientRecord(
    id: 'id1', name: 'A',
    smsReminders: false, emailReminders: false, language: 'en',
  );
  final map = c.toMap();
  expect(map['smsReminders'], isFalse);
  expect(map['emailReminders'], isFalse);
  expect(map['language'], 'en');
  expect(map.containsKey('waveCustomerId'), isFalse);
});
```

- [ ] **Step 2: Implement**

Factory additions (after `noFixedAddress`):

```dart
@Default(true) bool smsReminders,
@Default(true) bool emailReminders,
@Default('fr') String language,
```

`fromMap`:

```dart
smsReminders: (data['smsReminders'] as bool?) ?? true,
emailReminders: (data['emailReminders'] as bool?) ?? true,
language: (data['language'] ?? '').toString() == 'en' ? 'en' : 'fr',
```

`toMap` (before the wave-fields omission comment):

```dart
'smsReminders': smsReminders,
'emailReminders': emailReminders,
'language': language,
```

Then regenerate freezed: `dart run build_runner build --delete-conflicting-outputs`.

- [ ] **Step 3: Run + commit**

Run: `flutter test test/features/clients/domain` → PASS.

```bash
git add lib/features/clients/domain/models test/features/clients/domain
git commit -m "feat: client reminder preference fields on ClientRecord"
```

---

### Task 7: Flutter — form UI + l10n

**Files:**
- Modify: `lib/features/clients/widgets/client_form_state.dart`
- Modify: `lib/features/clients/widgets/sheets/add_client_sheet.dart`
- Modify: `lib/features/clients/widgets/views/client_edit_form.dart`
- Modify: `lib/l10n/app_en.arb` + `lib/l10n/app_fr.arb`

- [ ] **Step 1: l10n keys (both ARBs in lockstep; the on-save hook runs gen-l10n)**

`app_en.arb`:

```json
"clients_reminders": "Reminders",
"@clients_reminders": {
  "description": "Section label above the client reminder preferences"
},
"clients_smsReminders": "SMS reminders",
"@clients_smsReminders": {
  "description": "Toggle label for sending this client SMS appointment reminders"
},
"clients_smsRemindersHint": "Text a reminder the day before each appointment",
"@clients_smsRemindersHint": {
  "description": "Subtitle explaining the SMS reminders toggle"
},
"clients_emailReminders": "Email reminders",
"@clients_emailReminders": {
  "description": "Toggle label for sending this client email appointment reminders"
},
"clients_emailRemindersHint": "Email a reminder the day before each appointment",
"@clients_emailRemindersHint": {
  "description": "Subtitle explaining the email reminders toggle"
},
"clients_reminderLanguage": "Reminder language",
"@clients_reminderLanguage": {
  "description": "Label for the FR/EN reminder language choice"
}
```

`app_fr.arb`: "Rappels", "Rappels par texto", "Envoyer un rappel par texto la
veille de chaque rendez-vous", "Rappels par courriel", "Envoyer un rappel par
courriel la veille de chaque rendez-vous", "Langue des rappels".

- [ ] **Step 2: Form state mixin**

In `client_form_state.dart`, beside `noFixedAddress` (lines 17-25):

```dart
bool smsReminders = true;
bool emailReminders = true;
String reminderLanguage = 'fr';

void setSmsReminders({required bool value}) =>
    setState(() => smsReminders = value);
void setEmailReminders({required bool value}) =>
    setState(() => emailReminders = value);
void setReminderLanguage(String value) =>
    setState(() => reminderLanguage = value == 'en' ? 'en' : 'fr');
```

- [ ] **Step 3: UI in BOTH the add sheet and the edit form**

Below the existing `noFixedAddress` `SwitchListTile` block
(`add_client_sheet.dart:212-222` and the edit form's mirror):

```dart
SectionLabel(context.l10n.clients_reminders),
SwitchListTile.adaptive(
  title: Text(context.l10n.clients_smsReminders),
  subtitle: Text(context.l10n.clients_smsRemindersHint),
  value: smsReminders,
  activeTrackColor: Theme.of(context).colorScheme.primary,
  onChanged: (value) => setSmsReminders(value: value),
),
SwitchListTile.adaptive(
  title: Text(context.l10n.clients_emailReminders),
  subtitle: Text(context.l10n.clients_emailRemindersHint),
  value: emailReminders,
  activeTrackColor: Theme.of(context).colorScheme.primary,
  onChanged: (value) => setEmailReminders(value: value),
),
Padding(
  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sp8),
  child: Row(
    children: [
      Expanded(child: Text(context.l10n.clients_reminderLanguage)),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'fr', label: Text('FR')),
          ButtonSegment(value: 'en', label: Text('EN')),
        ],
        selected: {reminderLanguage},
        onSelectionChanged: (s) => setReminderLanguage(s.first),
      ),
    ],
  ),
),
```

Wire into the record assembly (add sheet ~line 141-157 and the edit form's
save): `smsReminders: smsReminders, emailReminders: emailReminders,
language: reminderLanguage`, and seed the mixin fields from the existing
record when the edit form opens.

- [ ] **Step 4: Verify + commit**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"` and
`flutter test test/features/clients` → clean / PASS.

```bash
git add -A lib/features/clients lib/l10n
git commit -m "feat: client reminder preference toggles in the client forms"
```

---

### Task 8: Console / account setup (manual, one-time)

No code. Project `schedulingapp-88727`:

- [ ] Create a Twilio account; buy a Canadian long-code number (~US$1-5/mo);
  enable **Advanced Opt-Out** (STOP/ARRET handling) on its Messaging Service.
- [ ] `firebase functions:secrets:set TWILIO_ACCOUNT_SID` (repeat for
  `TWILIO_AUTH_TOKEN`, `TWILIO_FROM_NUMBER` — E.164, e.g. `+1819XXXXXXX`).
- [ ] Create a SendGrid account (free tier, 100/day is ample); verify the
  sender identity/domain matching `REMINDER_FROM_EMAIL` in
  `client_reminder_utils.js` (adjust that constant to the verified address);
  `firebase functions:secrets:set SENDGRID_API_KEY`.
- [ ] Firestore console → TTL policy on `clientAppointmentReminders.expiresAt`
  (same as the two existing ledgers).

---

### Task 9: Deploy + verification

- [ ] `cd functions && npm run lint && npm test` → green.
- [ ] `flutter analyze` + `flutter test` → green.
- [ ] `firebase deploy --only functions:sendClientAppointmentReminders,firestore:rules`
- [ ] Seed a test appointment ~2 h out whose client has YOUR mobile + email →
  SMS and email arrive within 15 min; ledger doc appears; a second sweep sends
  nothing.
- [ ] Reschedule that appointment → a second reminder arrives (new
  `startTimeMillis` key).
- [ ] Toggle the client's SMS reminders off, new appointment → email only.
- [ ] `language: en` client → English text.
- [ ] Cancel an appointment inside the window before the sweep → no reminder.
- [ ] Function logs contain no phone numbers or emails (PII check).

## Failure guarantees

| Failure | Behavior |
|---|---|
| Twilio/SendGrid transport or non-2xx | Channel returns false; if BOTH fail, ledger released → next sweep retries |
| One channel delivers, other fails | Claim kept — client was reached once |
| Client has no phone/email or opted out of both | Skipped, no ledger write, info log only |
| Client doc deleted | Falls back to denormalized `clientPhone` (SMS only) |
| Reschedule inside the window | New `startTimeMillis` → fresh ledger key → fresh reminder |
| Cancelled/done before sweep | Status filter excludes it |
| Sweep instance crash mid-run | Unclaimed candidates retried next sweep; claimed-but-undelivered released by the zero-delivery delete |
| >500 candidates | Cap logged (`sweep cap hit`) — bounded blast radius |
