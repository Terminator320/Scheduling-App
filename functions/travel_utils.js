"use strict";

/**
 * @fileoverview Travel-time "leave now" logic for the reminder sweep: pure
 * helpers plus an orchestrator, with injected
 * `{db, messaging, fetchImpl, apiKey, now, logger}` deps so jest can drive it
 * with mocks, mirroring notification_utils.js.
 *
 * For each employee/candidate-appointment pair, we decide an origin in this
 * order: an intervening appointment's address first (they'll depart from
 * that job), then a fresh background-GPS presence doc (updatedAt <= 25 min),
 * then a recently-ended previous appointment's address (<= 4 h, not
 * cancelled), and finally null — which falls back to the fixed 30-min
 * reminder with the plain reminder text.
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
const {
  startLiveActivity,
  updateLiveActivity,
  endLiveActivity,
} = require("./live_activity_dispatch");
const {
  listCardsDueForOnSite,
  clearCardMarker,
} = require("./live_activity_registry");

const MINUTE_MS = 60 * 1000;

// Extra lead on top of the computed drive time.
const BUFFER_MINUTES = 10;

// Lead cap; a >80-min drive fires at the first sweep inside the 90-min
// window (accepted).
const MAX_LEAD_MINUTES = 90;

// Lead when no origin / no address / Routes failed — matches the push plan's
// original fixed reminder.
const FALLBACK_LEAD_MINUTES = 30;

// A presence doc older than this means tracking died (force-quit, permission
// revoked); fall back to the address chain.
const PRESENCE_STALE_MINUTES = 25;

// How far back a previous appointment's address still counts as "where the
// employee just was".
const PREV_APPOINTMENT_LOOKBACK_HOURS = 4;

// Caps the per-employee context read. Ordered by endTime ASC, so the cap
// keeps the earliest-ending jobs decideOrigin actually needs, instead of
// every future appointment in a pre-booked series.
const CONTEXT_QUERY_MAX = 50;

// Longest bookable visit (24h cap). The context query's upper bound has to
// clear the travel window plus one full visit, or a long intervening job
// drops out of decideOrigin.
const MAX_BOOKING_MS = 24 * 60 * MINUTE_MS;

// Sweep candidate window: MAX_LEAD_MINUTES ahead, so the longest computable
// lead is already in range when it becomes due.
const TRAVEL_WINDOW_MS = MAX_LEAD_MINUTES * MINUTE_MS;

// A recent cached estimate lets a clearly-not-due pair skip the metered
// Routes call. This can only DEFER a send, never trigger one — the fire
// decision always uses a fresh Routes response.
const ESTIMATE_TTL_MS = 10 * MINUTE_MS;
const SKIP_MARGIN_MS = 15 * MINUTE_MS;
const _estimateCache = new Map();

/**
 * Drops every expired entry. Read-triggered eviction alone can't reclaim a
 * pair that stopped being swept, so the sweep also prunes the whole map
 * once per run to keep the warm instance bounded.
 * @param {!Map} cache
 * @param {number} nowMs
 * @return {void}
 */
function pruneEstimates(cache, nowMs) {
  for (const [key, hit] of cache) {
    if (nowMs - hit.atMs > ESTIMATE_TTL_MS) cache.delete(key);
  }
}

/**
 * Cached drive-time estimate for a (candidate, employee) pair, or null when
 * absent/stale; expired entries are dropped on read so the map self-prunes.
 * @param {!Map} cache
 * @param {string} key
 * @param {number} nowMs
 * @return {?number} seconds, or null.
 */
function readEstimate(cache, key, nowMs) {
  const hit = cache.get(key);
  if (!hit) return null;
  if (nowMs - hit.atMs > ESTIMATE_TTL_MS) {
    cache.delete(key);
    return null;
  }
  return hit.seconds;
}

/**
 * True when a cached estimate conservatively (by SKIP_MARGIN_MS) proves the
 * pair cannot be due yet, so the Routes call can be skipped this sweep.
 * @param {{seconds: ?number, startTimeMillis: number, nowMillis: number}} args
 * @return {boolean}
 */
function canDeferRoutes({seconds, startTimeMillis, nowMillis}) {
  if (seconds == null) return false;
  const leadMs = computeLeadMinutes(seconds) * MINUTE_MS;
  return nowMillis < startTimeMillis - leadMs - SKIP_MARGIN_MS;
}

// Statuses that still expect the visit to happen. `confirmed` is the
// retired legacy alias, kept so pre-retirement docs still earn reminders.
const PENDING_LIKE = new Set(["pending", "confirmed"]);

// Same allowlist as an array for the candidate query's `where("status", "in",
// ...)`; deliberately narrower than notification_utils' OPEN_STATUSES since
// `in_progress` has no "time to leave" left to remind about.
const PENDING_STATUSES = [...PENDING_LIKE];

// A job in one of these no longer occupies the employee. Legacy `completed`
// is the retired alias of `done`.
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

  // Intervening appointment — they'll depart from THAT job's address, not
  // from wherever they are now. Marking it done promotes GPS below.
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

  // Fresh background-GPS fix.
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

  // Recently-ended previous appointment, any status except cancelled since
  // a cancelled visit never happened. Newest endTime wins.
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
 * Routes API computeRoutes request body — Routes accepts raw address strings
 * as waypoints, so no geocoding is needed. Pure — unit-testable.
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
 * failure — never throws (same error discipline as places.js). `fetchImpl`
 * is injected for jest.
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
    // Log status only — the request carries staff GPS/address data and
    // Google's INVALID_ARGUMENT echoes the offending field back (same reason
    // placesReverseGeocode sets logResponsePreview: false).
    if (logger) {
      logger.warn("travel: routes upstream non-200", {
        status: response.status,
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
 * Ledger doc id — same `${id}_${startMs}_${employeeDocId}` shape as the
 * push plan's reminderLedgerId, so claims made before the travel upgrade
 * still get honored and the deploy doesn't cause double reminders.
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
 * Resolves ONE (candidate, assignee) pair: ledger short-circuit, then
 * decideOrigin, then Routes (deferred when a recent estimate already proves
 * it isn't due), then the due-check, then claim/send/release, then an
 * optional Live Activity start.
 *
 * The Live Activity start hangs off `deliverRecipientOnce`'s claim, so a
 * racing collision can't double-fire a card. Every failure path degrades to
 * the fixed 30-minute `reminder` kind.
 * @param {!Object} deps
 * @param {!Object} args
 * @return {!Promise<{reminded: number, started: number}>}
 */
async function resolveReminderForAssignee(deps, args) {
  const {db, fetchImpl, apiKey, logger} = deps;
  const {candidate: c, employeeDocId, startMs, nowDate, nowMs,
    presence, employeeAppointments, estimates, cache} = args;
  const none = {reminded: 0, started: 0};

  const ledgerId = travelReminderLedgerId(
      String(c.id), startMs, employeeDocId);
  // Cheap pre-check before any Routes spend — the atomic create() inside
  // deliverRecipientOnce is still the real exactly-once guard.
  const existing = await db
      .collection("appointmentReminders").doc(ledgerId).get();
  if (existing && existing.exists) return none;

  const origin = decideOrigin({
    presence,
    employeeAppointments,
    candidate: c,
    now: nowDate,
  });
  const destinationAddress = _address(c);
  let travelSeconds = null;
  if (origin && destinationAddress !== "") {
    // A recent estimate that leaves this pair well short of its leave
    // instant defers the (billable) Routes call to a later sweep.
    const key = `${c.id}|${employeeDocId}`;
    const cached = readEstimate(estimates, key, nowMs);
    if (canDeferRoutes({
      seconds: cached, startTimeMillis: startMs, nowMillis: nowMs,
    })) {
      return none;
    }
    travelSeconds = await computeTravelSeconds({
      fetchImpl,
      apiKey,
      origin,
      destinationAddress,
      now: nowDate,
      logger,
    });
    if (travelSeconds != null) {
      estimates.set(key, {seconds: travelSeconds, atMs: nowMs});
    }
  }
  const leadMinutes = computeLeadMinutes(travelSeconds);
  if (!isDue({startTimeMillis: startMs, leadMinutes, nowMillis: nowMs})) {
    return none;
  }
  const kind = travelSeconds == null ? "reminder" : "leaveNow";
  const ctx = {
    clientName: c.clientName,
    startTime: c.startTime,
    endTime: c.endTime,
    address: c.address,
    travelMinutes: travelSeconds == null ?
        null : Math.ceil(travelSeconds / 60),
  };
  const delivered = await deliverRecipientOnce(deps, {
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
  let started = 0;
  if (kind === "leaveNow" && delivered > 0) {
    // Best-effort — a Live Activity failure must not change `reminded` or
    // abort the sweep. No card just leaves the plain leaveNow push
    // unchanged.
    started = await startLiveActivity(deps, {
      appointmentId: String(c.id),
      employeeDocId,
      ctx: {
        ...ctx,
        leaveAt: new Date(
            startMs - computeLeadMinutes(travelSeconds) * MINUTE_MS),
      },
      nowDate,
    });
  }
  return {reminded: delivered, started};
}

/**
 * The travel-aware reminder sweep — one notification per (appointment,
 * employee) pair, replacing the fixed 30-min runReminderSweep. Any pair
 * failure is caught and logged without stopping the rest of the sweep.
 * Injectable deps `{db, messaging, fetchImpl, apiKey, now, logger}`.
 * @param {!Object} deps
 * @return {!Promise<{reminded: number}>}
 */
async function runTravelAwareReminderSweep(deps) {
  // fetchImpl/apiKey are consumed by resolveReminderForAssignee off `deps`.
  const {db, now, logger} = deps;
  const nowDate = now || new Date();
  const nowMs = nowMillis(nowDate);
  const windowEnd = new Date(nowMs + TRAVEL_WINDOW_MS);
  const snap = await db
      .collection("appointments")
      .where("status", "in", PENDING_STATUSES)
      .where("startTime", ">", nowDate)
      .where("startTime", "<=", windowEnd)
      .get();
  const candidates = selectTravelCandidates(
      (((snap && snap.docs) || [])).map(
          (doc) => ({id: doc.id, ...(doc.data() || {})})),
      nowDate,
  );
  // The flip pass must run even with no upcoming candidates. A job stops
  // being a candidate the moment it starts, so without this, the sweep
  // right after a tech begins their only job would never flip that card to
  // `onSite`.
  if (candidates.length === 0) {
    return {
      reminded: 0,
      liveActivitiesStarted: 0,
      liveActivitiesFlipped: await runOnSiteFlipPass(deps),
    };
  }

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
  // The per-employee context queries are independent, so issue them
  // concurrently rather than blocking on each in turn. One employee's query
  // throwing just falls back to [] for them, without failing the others.
  const contextByEmployee = new Map();
  const lookbackStart = new Date(
      nowMs - PREV_APPOINTMENT_LOOKBACK_HOURS * 60 * MINUTE_MS);
  const contextEnd = new Date(nowMs + TRAVEL_WINDOW_MS + MAX_BOOKING_MS);
  await Promise.all(employeeIds.map(async (employeeDocId) => {
    try {
      // Upper-bounded on the same field. Without that bound the query would
      // match every future appointment, and a pre-booked series would
      // saturate CONTEXT_QUERY_MAX. The bound clears the window by
      // MAX_BOOKING_MS since an intervening job can run a full day past it.
      const ctxSnap = await db
          .collection("appointments")
          .where("employeeIds", "array-contains", employeeDocId)
          .where("endTime", ">", lookbackStart)
          .where("endTime", "<=", contextEnd)
          .orderBy("endTime")
          .limit(CONTEXT_QUERY_MAX)
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
  let started = 0;
  const cache = new Map();
  // Warm-instance memo, injectable so tests get a clean map per run.
  const estimates = deps.estimateCache || _estimateCache;
  pruneEstimates(estimates, nowMs);
  for (const c of candidates) {
    const startMs = toMillis(c.startTime);
    if (startMs == null) continue;
    for (const employeeDocId of toIdList(c.employeeIds)) {
      try {
        const outcome = await resolveReminderForAssignee(deps, {
          candidate: c,
          employeeDocId,
          startMs,
          nowDate,
          nowMs,
          presence: presenceByEmployee.get(employeeDocId) || null,
          employeeAppointments: contextByEmployee.get(employeeDocId) || [],
          estimates,
          cache,
        });
        reminded += outcome.reminded;
        started += outcome.started;
      } catch (err) {
        // One failing pair must not stop the sweep.
        if (logger) {
          logger.warn("travel: pair failed", {id: c.id, employeeDocId, err});
        }
      }
    }
  }
  const flipped = await runOnSiteFlipPass(deps);
  return {reminded, liveActivitiesStarted: started, liveActivitiesFlipped:
    flipped};
}

/**
 * Backstop that pushes one update per started job to flip its Lock Screen
 * card from `travel` to `onSite`, riding the existing 5-minute sweep with no
 * new scheduler.
 *
 * Driven off the card markers, not an appointments query, since they're the
 * only record of which techs have a card. Best-effort — failures are
 * swallowed without affecting the reminder sweep.
 * @param {!Object} deps `{db, now, logger, apnsAuth}`.
 * @return {!Promise<number>} Cards updated.
 */
async function runOnSiteFlipPass(deps) {
  const {db, now, logger} = deps;
  const nowDate = now || new Date();
  const markers = await listCardsDueForOnSite(deps);
  let flipped = 0;
  for (const marker of markers) {
    try {
      const snap = await db
          .collection("appointments").doc(marker.appointmentId).get();
      const record = snap && snap.exists ? (snap.data() || {}) : null;
      // A deleted/terminal job has to call endLiveActivity, not just drop
      // the marker, since the Lock Screen card outlives the Firestore doc.
      // We also clear the marker here so this doesn't retry every sweep.
      if (!record ||
          TERMINAL.has(String(record.status || "").toLowerCase())) {
        await endLiveActivity(deps, {
          appointmentId: String(marker.appointmentId),
          employeeDocId: marker.employeeDocId,
          ctx: record ? {
            clientName: record.clientName,
            address: _address(record),
            startTime: record.startTime,
            endTime: record.endTime,
            leaveAt: null,
            travelMinutes: null,
          } : {},
          nowDate,
        });
        await clearCardMarker(deps, {employeeDocId: marker.employeeDocId});
        continue;
      }
      flipped += await updateLiveActivity(deps, {
        appointmentId: String(marker.appointmentId),
        employeeDocId: marker.employeeDocId,
        ctx: {
          clientName: record.clientName,
          address: _address(record),
          startTime: record.startTime,
          endTime: record.endTime,
          leaveAt: null,
          travelMinutes: null,
        },
        nowDate,
      });
    } catch (err) {
      // One failing card must not stop the pass.
      if (logger) {
        logger.warn("liveActivity: on-site flip failed",
            {employeeDocId: marker.employeeDocId, err});
      }
    }
  }
  return flipped;
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
  canDeferRoutes,
  buildRoutesRequestBody,
  parseRoutesDurationSeconds,
  computeTravelSeconds,
  travelReminderLedgerId,
  runTravelAwareReminderSweep,
  runOnSiteFlipPass,
};
