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
 * credentials — a function that doesn't bind the secrets must not read them.
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
 * [liveDeps] plus the APNs credentials, for the two functions that bind
 * [APNS_SECRETS] and actually push Live Activity cards.
 * @return {!Object}
 */
function liveActivityDeps() {
  return {...liveDeps(), apnsAuth: apnsAuth()};
}

/**
 * APNs provider credentials for the Live Activity path, or null when the
 * secrets aren't bound — every Live Activity verb just no-ops in that case.
 * Read lazily since `.value()` throws outside a secret-bound invocation.
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

// Travel-aware "time to leave" reminders, every 5 minutes. Drive time comes
// from the Routes API, and every failure path degrades to a fixed 30-min
// reminder. A per-recipient ledger makes sure each occurrence fires exactly
// once, and a missed run just self-heals on the next sweep.
const sendUpcomingJobReminders = onSchedule(
    {
      schedule: "every 5 minutes",
      timeZone: "America/Toronto",
      maxInstances: 1,
      secrets: [GOOGLE_MAP_API_KEY, ...APNS_SECRETS],
      // Pairs run concurrently, each with up to one Routes round-trip.
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
        // Log rather than rethrow — the next 5-min run self-heals anyway.
        logger.error("sendUpcomingJobReminders failed", {err});
      }
    },
);

// Nightly digest at 18:00 America/Toronto — one push per employee with >=1
// job tomorrow. No ledger here; it only runs once daily, so we accept the
// occasional rare duplicate.
const sendDailyJobDigest = onSchedule(
    {
      schedule: "0 18 * * *",
      timeZone: "America/Toronto",
      maxInstances: 1,
    },
    async () => {
      const deps = liveDeps();
      try {
        await runDailyDigest(deps);
      } catch (err) {
        // Log rather than rethrow, matching the reminder sweep: the digest
        // fans out with Promise.all, so one bad appointment rejecting the
        // batch must not also skip the TTL prune below it.
        logger.error("sendDailyJobDigest failed", {err});
      }
      // Rides the digest rather than adding a whole new scheduler for it.
      // Isolated in its own try so a failed prune can't fail the digest,
      // which has already sent by this point.
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

// Overdue "job finished?" prompts, every 15 minutes. A job whose endTime
// passed within the last 24h while still pending/in_progress earns one
// nudge, tracked via an endTime-keyed ledger that re-arms on reschedule.
const sendOverdueJobPrompts = onSchedule(
    {
      schedule: "every 15 minutes",
      timeZone: "America/Toronto",
      maxInstances: 1,
      // Well over the default 60s so a backlog can't leave the newest
      // overdue jobs unprompted.
      timeoutSeconds: 300,
    },
    async () => {
      try {
        await runOverduePromptSweep(liveDeps());
      } catch (err) {
        // Log rather than rethrow, matching the two sibling schedulers: the
        // next 15-min run self-heals, and a throw here would surface as a
        // failed invocation for something already retried by the clock.
        logger.error("sendOverdueJobPrompts failed", {err});
      }
    },
);

module.exports = {
  notifyAppointmentChanges,
  sendUpcomingJobReminders,
  sendDailyJobDigest,
  sendOverdueJobPrompts,
};
