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
  runDailyDigest,
  runOverduePromptSweep,
} = require("./notification_utils");
const {runTravelAwareReminderSweep} = require("./travel_utils");
const {
  pruneExpiredActivityTokens,
  pruneExpiredCardMarkers,
} = require("./live_activity_registry");
const {
  GOOGLE_MAP_API_KEY,
  APNS_AUTH_KEY,
  APNS_KEY_ID,
  APNS_TEAM_ID,
} = require("./params");

/**
 * Real injected deps for the orchestration functions. Carries NO APNs
 * credentials — a function that doesn't bind the secrets must not read them,
 * or firebase-functions logs a "No value found for secret parameter" warning
 * on every invocation.
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

/**
 * [liveDeps] plus the APNs credentials. ONLY for the two functions that bind
 * [APNS_SECRETS] and actually push Live Activity cards — the digest's TTL
 * prune and the overdue sweep are Firestore-only and use [liveDeps].
 * @return {!Object}
 */
function liveActivityDeps() {
  return {...liveDeps(), apnsAuth: apnsAuth()};
}

/**
 * APNs provider credentials for the Live Activity path, or null when the
 * secrets aren't bound to this function — in which case every Live Activity
 * verb no-ops and only the plain push is sent. Read lazily: `.value()` throws
 * outside a secret-bound invocation.
 * @return {?{authKey: string, keyId: string, teamId: string}}
 */
function apnsAuth() {
  try {
    const authKey = APNS_AUTH_KEY.value();
    const keyId = APNS_KEY_ID.value();
    const teamId = APNS_TEAM_ID.value();
    if (!authKey || !keyId || !teamId) return null;
    return {authKey, keyId: keyId.trim(), teamId: teamId.trim()};
  } catch (err) {
    return null;
  }
}

// Secrets every Live-Activity-capable function must bind.
const APNS_SECRETS = [APNS_AUTH_KEY, APNS_KEY_ID, APNS_TEAM_ID];

// Assignment / reschedule / cancel / removal alerts. No `retry: true` — a
// duplicate push is worse than a rare missed one.
const notifyAppointmentChanges = onDocumentWritten(
    {
      document: "appointments/{appointmentId}",
      // Bound for the Live Activity update/end hooks in handleAppointmentWrite.
      secrets: APNS_SECRETS,
    },
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
          liveActivityDeps(),
      );
    },
);

// Travel-aware "time to leave" reminders (was: fixed 30-minute reminders).
// Runs every 5 minutes; the `(status, startTime)` composite index covers the
// candidate query and `(employeeIds CONTAINS, endTime ASC, startTime ASC)`
// covers the per-employee origin-context query — no new index. Drive time
// comes from Routes API computeRoutes (TRAFFIC_AWARE); every failure path
// degrades to the original fixed 30-min reminder. The per-recipient ledger
// makes each (occurrence, employee) fire exactly once, and a missed run
// self-heals without double-sending.
const sendUpcomingJobReminders = onSchedule(
    {
      schedule: "every 5 minutes",
      timeZone: "America/Toronto",
      maxInstances: 1,
      secrets: [GOOGLE_MAP_API_KEY, ...APNS_SECRETS],
      // Serial pairs, each with up to one Routes round-trip.
      timeoutSeconds: 120,
    },
    async () => {
      try {
        await runTravelAwareReminderSweep({
          ...liveActivityDeps(),
          fetchImpl: fetch,
          apiKey: GOOGLE_MAP_API_KEY.value().trim(),
        });
      } catch (err) {
        // Log rather than rethrow: a retried sweep would re-pay Routes for
        // pairs already claimed; the next 5-min run self-heals anyway.
        logger.error("sendUpcomingJobReminders failed", {err});
      }
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
      const deps = liveDeps();
      await runDailyDigest(deps);
      // Rides the digest rather than adding a scheduler: a card the server
      // never got to end would otherwise leak its token row and card marker
      // indefinitely. Both TTLs are measured in days, so daily is ample.
      // Isolated — a failed prune must not fail the digest that already sent.
      try {
        const tokens = await pruneExpiredActivityTokens(deps);
        const cards = await pruneExpiredCardMarkers(deps);
        if (tokens.pruned > 0 || cards.pruned > 0) {
          logger.info("liveActivity: TTL prune", {
            tokens: tokens.pruned,
            cards: cards.pruned,
          });
        }
      } catch (err) {
        logger.warn("liveActivity: TTL prune failed", {err});
      }
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
