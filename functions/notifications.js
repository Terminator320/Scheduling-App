"use strict";

/**
 * @fileoverview Push-notification trigger registrations (thin wrappers). All
 * logic lives in notification_utils.js, driven here with the real Firestore +
 * Messaging so notification_utils.js stays require()-able by jest without a
 * Storage/scheduler bucket resolving at load.
 *
 * @module notifications
 */

const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const {getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

const {
  handleAppointmentWrite,
  runReminderSweep,
  runDailyDigest,
  runOverduePromptSweep,
} = require("./notification_utils");

/**
 * Real injected deps for the orchestration functions.
 * @return {{db: !Object, messaging: !Object, now: !Date, logger: !Object}}
 */
function liveDeps() {
  return {
    db: getFirestore(),
    messaging: getMessaging(),
    now: new Date(),
    logger,
  };
}

// Assignment / reschedule / cancel / removal alerts. No `retry: true` — a
// duplicate push is worse than a rare missed one.
const notifyAppointmentChanges = onDocumentWritten(
    "appointments/{appointmentId}",
    async (event) => {
      const before = event.data?.before?.exists ?
        event.data.before.data() : null;
      const after = event.data?.after?.exists ?
        event.data.after.data() : null;
      if (!before && !after) return;
      await handleAppointmentWrite(
          event.params.appointmentId,
          before,
          after,
          liveDeps(),
      );
    },
);

// 30-minute reminders. Runs every 5 minutes; the `(status, startTime)`
// composite index already covers the query — no new index. First run after a
// job enters the window fires (~25-30 min out); the ledger makes it fire
// exactly once, and a missed run self-heals without double-sending.
const sendUpcomingJobReminders = onSchedule(
    {
      schedule: "every 5 minutes",
      timeZone: "America/Toronto",
      maxInstances: 1,
    },
    async () => {
      await runReminderSweep(liveDeps());
    },
);

// Nightly digest at 18:00 America/Toronto: one push per employee with >=1 job
// tomorrow. No ledger (runs once daily; a rare crash-retry duplicate is
// accepted).
const sendDailyJobDigest = onSchedule(
    {
      schedule: "0 18 * * *",
      timeZone: "America/Toronto",
      maxInstances: 1,
    },
    async () => {
      await runDailyDigest(liveDeps());
    },
);

// Overdue "job finished?" prompts every 15 minutes: a job whose endTime
// passed within the last 24h while still pending/in_progress earns one nudge
// per occurrence (the endTime-keyed ledger re-arms on reschedule; a
// zero-delivery claim is released for retry). Queries by startTime over the
// last 48h — eligibility plus the <24h max booking — so the existing
// `(status, startTime)` index covers it.
const sendOverdueJobPrompts = onSchedule(
    {
      schedule: "every 15 minutes",
      timeZone: "America/Toronto",
      maxInstances: 1,
      // The sweep processes candidates serially; give it well over the default
      // 60s so a backlog can't leave the newest overdue jobs unprompted.
      timeoutSeconds: 300,
    },
    async () => {
      await runOverduePromptSweep(liveDeps());
    },
);

module.exports = {
  notifyAppointmentChanges,
  sendUpcomingJobReminders,
  sendDailyJobDigest,
  sendOverdueJobPrompts,
};
