"use strict";

/**
 * @fileoverview Travel-time "leave now" logic for the reminder sweep. Pure
 * helpers plus an orchestrator that takes injected
 * `{db, messaging, fetchImpl, apiKey, now, logger}` so jest can drive it with
 * mocks (no admin/scheduler requires here — mirrors notification_utils.js).
 *
 * Origin decision (per employee, per candidate appointment):
 *   1. intervening appointment's address (they'll depart from that job)
 *   2. fresh background-GPS presence doc (updatedAt <= 25 min)
 *   3. recently-ended previous appointment's address (<= 4 h, not cancelled)
 *   4. null -> fixed 30-min fallback with the plain reminder text
 *
 * @module travel_utils
 */

const {
  buildNotificationMessage,
  deliverRecipientOnce,
  toMillis,
  nowMillis,
  toIdList,
  TIMED_RECIPIENT_ROLES,
} = require("./notification_utils");

const MINUTE_MS = 60 * 1000;

// Extra lead on top of the computed drive time.
const BUFFER_MINUTES = 10;

// Lead cap; a >80-min drive fires at the first sweep inside the 90-min
// window (accepted).
const MAX_LEAD_MINUTES = 90;

// Lead when no origin / no address / Routes failed — matches the push plan's
// original fixed reminder.
const FALLBACK_LEAD_MINUTES = 30;

// Presence freshness. The client's background stream heartbeats every 10 min
// while tracking is alive, so a doc older than two missed heartbeats (+slack)
// reliably means tracking is dead (force-quit, permission revoked) — fall
// back to the address chain.
const PRESENCE_STALE_MINUTES = 25;

// How far back a previous appointment's address still counts as "where the
// employee just was".
const PREV_APPOINTMENT_LOOKBACK_HOURS = 4;

// Sweep candidate window: MAX_LEAD_MINUTES ahead, so the longest computable
// lead is already in range when it becomes due.
const TRAVEL_WINDOW_MS = MAX_LEAD_MINUTES * MINUTE_MS;

// Statuses that still expect the visit to happen. `confirmed` is the retired
// legacy alias (treated as pending; new writes rejected since 2026-07-09),
// kept so pre-retirement docs still earn reminders.
const PENDING_LIKE = new Set(["pending", "confirmed"]);

// A job in one of these no longer occupies the employee (intervening prong).
// Legacy `completed` is the retired alias of `done`.
const TERMINAL = new Set(["done", "completed", "cancelled"]);

/**
 * Trimmed address or "".
 * @param {*} record
 * @return {string}
 */
function _address(record) {
  return String((record && record.address) || "").trim();
}

/**
 * Decides where the employee will depart from. Pure — unit-testable.
 *
 * @param {{presence: ?Object, employeeAppointments: !Array<!Object>,
 *   candidate: !Object, now: (Date|number)}} args `presence` is the
 *   `users/{docId}/presence/location` doc data (or null);
 *   `employeeAppointments` is this employee's context-query result (endTime
 *   within the lookback or in the future).
 * @return {?{kind: string, lat: (number|undefined), lng: (number|undefined),
 *   address: (string|undefined)}} `{kind:'gps'}` | `{kind:'address'}` | null.
 */
function decideOrigin({presence, employeeAppointments, candidate, now}) {
  const nowMs = nowMillis(now);
  const candidateStartMs = toMillis(candidate && candidate.startTime);
  const apps = employeeAppointments || [];

  // 1. Intervening appointment: still occupies the employee when the
  // candidate's leave time comes — they'll depart from THAT job's address,
  // not from wherever they are now (critical for back-to-back bookings).
  // Marking it done makes it terminal, which promotes GPS below.
  let intervening = null;
  for (const r of apps) {
    if (candidate && r.id === candidate.id) continue;
    if (TERMINAL.has(String(r.status || "").toLowerCase())) continue;
    const startMs = toMillis(r.startTime);
    const endMs = toMillis(r.endTime);
    if (startMs == null || endMs == null) continue;
    if (candidateStartMs != null && startMs >= candidateStartMs) continue;
    if (endMs <= nowMs) continue;
    if (_address(r) === "") continue;
    // Latest-starting current job wins (the one they're actually at).
    if (!intervening || startMs > toMillis(intervening.startTime)) {
      intervening = r;
    }
  }
  if (intervening) return {kind: "address", address: _address(intervening)};

  // 2. Fresh background-GPS fix.
  if (presence) {
    const updatedMs = toMillis(presence.updatedAt);
    const lat = presence.lat;
    const lng = presence.lng;
    const fresh = updatedMs != null &&
        nowMs - updatedMs <= PRESENCE_STALE_MINUTES * MINUTE_MS;
    if (fresh && typeof lat === "number" && typeof lng === "number") {
      return {kind: "gps", lat, lng};
    }
  }

  // 3. Recently-ended previous appointment. Any status except cancelled — a
  // cancelled visit never happened, but a done one did (the employee was
  // physically there). Newest endTime wins.
  let previous = null;
  const floorMs = nowMs - PREV_APPOINTMENT_LOOKBACK_HOURS * 60 * MINUTE_MS;
  for (const r of apps) {
    if (candidate && r.id === candidate.id) continue;
    if (String(r.status || "").toLowerCase() === "cancelled") continue;
    const endMs = toMillis(r.endTime);
    if (endMs == null || endMs > nowMs || endMs <= floorMs) continue;
    if (_address(r) === "") continue;
    if (!previous || endMs > toMillis(previous.endTime)) previous = r;
  }
  if (previous) return {kind: "address", address: _address(previous)};

  return null;
}

/**
 * Filters appointment records to travel-reminder candidates: pending-like and
 * starting within (now, now + TRAVEL_WINDOW_MS]. `in_progress` is excluded
 * (visit already started). Pure — unit-testable.
 * @param {!Array<!Object>} records
 * @param {(Date|number)} now
 * @return {!Array<!Object>}
 */
function selectTravelCandidates(records, now) {
  const nowMs = nowMillis(now);
  const cutoff = nowMs + TRAVEL_WINDOW_MS;
  return (records || []).filter((r) => {
    if (!PENDING_LIKE.has(String(r.status || "").toLowerCase())) return false;
    const ms = toMillis(r.startTime);
    return ms != null && ms > nowMs && ms <= cutoff;
  });
}

/**
 * Lead minutes for a computed drive time; the fixed fallback when null.
 * Pure — unit-testable.
 * @param {?number} travelSeconds
 * @return {number}
 */
function computeLeadMinutes(travelSeconds) {
  if (travelSeconds == null || !isFinite(travelSeconds) ||
      travelSeconds < 0) {
    return FALLBACK_LEAD_MINUTES;
  }
  return Math.min(
      Math.ceil(travelSeconds / 60) + BUFFER_MINUTES,
      MAX_LEAD_MINUTES,
  );
}

/**
 * True once `now` has reached the leave-now instant. Pure — unit-testable.
 * @param {{startTimeMillis: number, leadMinutes: number, nowMillis: number}}
 *   args
 * @return {boolean}
 */
function isDue(args) {
  return args.nowMillis >= args.startTimeMillis -
      args.leadMinutes * MINUTE_MS;
}

/**
 * Routes API computeRoutes request body. Routes accepts raw address strings
 * as waypoints, so the fallback origin and the destination need no geocoding.
 * Pure — unit-testable.
 * @param {{origin: !Object, destinationAddress: string,
 *   departureTimeIso: string}} args
 * @return {!Object}
 */
function buildRoutesRequestBody({origin, destinationAddress,
  departureTimeIso}) {
  const originWaypoint = origin.kind === "gps" ?
      {location: {latLng: {latitude: origin.lat, longitude: origin.lng}}} :
      {address: origin.address};
  return {
    origin: originWaypoint,
    destination: {address: destinationAddress},
    travelMode: "DRIVE",
    routingPreference: "TRAFFIC_AWARE",
    departureTime: departureTimeIso,
  };
}

/**
 * Parses `routes[0].duration` ("1234s") out of a computeRoutes response;
 * null on any malformed shape. Pure — unit-testable.
 * @param {*} json
 * @return {?number}
 */
function parseRoutesDurationSeconds(json) {
  const route = json && Array.isArray(json.routes) ? json.routes[0] : null;
  const duration = route && route.duration;
  if (typeof duration !== "string") return null;
  const match = /^(\d+(?:\.\d+)?)s$/.exec(duration.trim());
  if (!match) return null;
  return Math.round(Number(match[1]));
}

/**
 * Calls Routes API computeRoutes and returns drive seconds, or null on ANY
 * failure (transport, non-200, bad JSON, malformed shape) — never throws
 * (places.js error discipline). Injected `fetchImpl` for jest.
 * @param {{fetchImpl: !Function, apiKey: string, origin: !Object,
 *   destinationAddress: string, now: (Date|number), logger: ?Object}} args
 * @return {!Promise<?number>}
 */
async function computeTravelSeconds({fetchImpl, apiKey, origin,
  destinationAddress, now, logger}) {
  // Routes rejects departure times in the past; nudge just ahead of now.
  const departureTimeIso =
      new Date(nowMillis(now) + 60 * 1000).toISOString();
  const body = buildRoutesRequestBody(
      {origin, destinationAddress, departureTimeIso});
  let response;
  try {
    response = await fetchImpl(
        "https://routes.googleapis.com/directions/v2:computeRoutes",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": apiKey,
            "X-Goog-FieldMask": "routes.duration",
          },
          body: JSON.stringify(body),
        },
    );
  } catch (err) {
    if (logger) {
      logger.warn("travel: routes transport error", {err: err.message});
    }
    return null;
  }
  if (!response.ok) {
    let preview = "";
    try {
      preview = (await response.text()).slice(0, 200);
    } catch (err) {
      preview = "<unreadable>";
    }
    if (logger) {
      logger.warn("travel: routes upstream non-200", {
        status: response.status,
        body: preview,
      });
    }
    return null;
  }
  let data;
  try {
    data = await response.json();
  } catch (err) {
    if (logger) {
      logger.warn("travel: invalid JSON in 200 response", {err: err.message});
    }
    return null;
  }
  return parseRoutesDurationSeconds(data);
}

/**
 * Ledger doc id — same `${id}_${startMs}_${employeeDocId}` shape as the push
 * plan's reminderLedgerId, so claims made before the travel upgrade stay
 * honored (no double reminders across the deploy).
 * @param {string} appointmentId
 * @param {number} startTimeMillis
 * @param {string} employeeDocId
 * @return {string}
 */
function travelReminderLedgerId(appointmentId, startTimeMillis,
    employeeDocId) {
  return `${appointmentId}_${startTimeMillis}_${employeeDocId}`;
}

/**
 * The travel-aware reminder sweep: one sweep, one notification per
 * (appointment, employee), replacing the fixed 30-min runReminderSweep.
 * Per pair: ledger short-circuit -> decideOrigin -> Routes ->
 * due-check -> claim/send/release (see deliverRecipientOnce). Any pair
 * failure is caught and logged; the sweep continues. Injectable deps
 * `{db, messaging, fetchImpl, apiKey, now, logger}`.
 * @param {!Object} deps
 * @return {!Promise<{reminded: number}>}
 */
async function runTravelAwareReminderSweep(deps) {
  const {db, fetchImpl, apiKey, now, logger} = deps;
  const nowDate = now || new Date();
  const nowMs = nowMillis(nowDate);
  const windowEnd = new Date(nowMs + TRAVEL_WINDOW_MS);
  const snap = await db
      .collection("appointments")
      .where("status", "in", ["pending", "confirmed"])
      .where("startTime", ">", nowDate)
      .where("startTime", "<=", windowEnd)
      .get();
  const candidates = selectTravelCandidates(
      (((snap && snap.docs) || [])).map(
          (doc) => ({id: doc.id, ...(doc.data() || {})})),
      nowDate,
  );
  if (candidates.length === 0) return {reminded: 0};

  // Per-sweep batching: presence docs in one getAll, and ONE context query
  // per distinct employee, reused across all of that employee's candidates.
  const employeeIds = [...new Set(
      candidates.flatMap((c) => toIdList(c.employeeIds)))];
  const presenceByEmployee = new Map();
  if (employeeIds.length > 0) {
    try {
      const refs = employeeIds.map((id) => db
          .collection("users").doc(id)
          .collection("presence").doc("location"));
      const snaps = await db.getAll(...refs);
      snaps.forEach((s, i) => {
        presenceByEmployee.set(
            employeeIds[i], s && s.exists ? (s.data() || null) : null);
      });
    } catch (err) {
      // No presence just demotes every origin to the address chain.
      if (logger) logger.warn("travel: presence getAll failed", {err});
    }
  }
  // The per-employee context queries are independent — issue them
  // concurrently (one throwing employee falls back to [] without failing the
  // others) rather than blocking on each in turn.
  const contextByEmployee = new Map();
  const lookbackStart = new Date(
      nowMs - PREV_APPOINTMENT_LOOKBACK_HOURS * 60 * MINUTE_MS);
  await Promise.all(employeeIds.map(async (employeeDocId) => {
    try {
      const ctxSnap = await db
          .collection("appointments")
          .where("employeeIds", "array-contains", employeeDocId)
          .where("endTime", ">", lookbackStart)
          .orderBy("endTime")
          .get();
      contextByEmployee.set(
          employeeDocId,
          ((ctxSnap && ctxSnap.docs) || []).map(
              (doc) => ({id: doc.id, ...(doc.data() || {})})));
    } catch (err) {
      if (logger) {
        logger.warn("travel: context query failed", {employeeDocId, err});
      }
      contextByEmployee.set(employeeDocId, []);
    }
  }));

  let reminded = 0;
  const cache = new Map();
  for (const c of candidates) {
    const startMs = toMillis(c.startTime);
    if (startMs == null) continue;
    const destinationAddress = _address(c);
    for (const employeeDocId of toIdList(c.employeeIds)) {
      try {
        const ledgerId = travelReminderLedgerId(
            String(c.id), startMs, employeeDocId);
        // Cheap pre-check before any Routes spend; the atomic create() inside
        // deliverRecipientOnce remains the real exactly-once guard.
        const existing = await db
            .collection("appointmentReminders").doc(ledgerId).get();
        if (existing && existing.exists) continue;

        const origin = decideOrigin({
          presence: presenceByEmployee.get(employeeDocId) || null,
          employeeAppointments: contextByEmployee.get(employeeDocId) || [],
          candidate: c,
          now: nowDate,
        });
        let travelSeconds = null;
        if (origin && destinationAddress !== "") {
          travelSeconds = await computeTravelSeconds({
            fetchImpl,
            apiKey,
            origin,
            destinationAddress,
            now: nowDate,
            logger,
          });
        }
        const leadMinutes = computeLeadMinutes(travelSeconds);
        if (!isDue({startTimeMillis: startMs, leadMinutes,
          nowMillis: nowMs})) {
          continue;
        }
        const kind = travelSeconds == null ? "reminder" : "leaveNow";
        const ctx = {
          clientName: c.clientName,
          startTime: c.startTime,
          address: c.address,
          travelMinutes: travelSeconds == null ?
              null : Math.ceil(travelSeconds / 60),
        };
        reminded += await deliverRecipientOnce(deps, {
          collection: "appointmentReminders",
          ledgerId,
          appointmentId: String(c.id),
          employeeDocId,
          kind,
          buildMsg: (locale) => buildNotificationMessage(kind, ctx, locale),
          nowDate,
          label: "reminder",
          roles: TIMED_RECIPIENT_ROLES,
          cache,
        });
      } catch (err) {
        // One failing pair must not stop the sweep.
        if (logger) {
          logger.warn("travel: pair failed", {id: c.id, employeeDocId, err});
        }
      }
    }
  }
  return {reminded};
}

module.exports = {
  BUFFER_MINUTES,
  MAX_LEAD_MINUTES,
  FALLBACK_LEAD_MINUTES,
  PRESENCE_STALE_MINUTES,
  PREV_APPOINTMENT_LOOKBACK_HOURS,
  TRAVEL_WINDOW_MS,
  decideOrigin,
  selectTravelCandidates,
  computeLeadMinutes,
  isDue,
  buildRoutesRequestBody,
  parseRoutesDurationSeconds,
  computeTravelSeconds,
  travelReminderLedgerId,
  runTravelAwareReminderSweep,
};
