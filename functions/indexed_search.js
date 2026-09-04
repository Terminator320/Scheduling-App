"use strict";

/**
 * @fileoverview Indexed search and conflict callables used by the mobile app.
 * These replace capped client-side scans for high-cardinality paths.
 */

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const {getFirestore} = require("firebase-admin/firestore");

const {clientDisplayName} = require("./client_name_utils");
const {
  APP_CHECK,
  assertAdminCall,
  assertPayloadShape,
  optionalString,
  requireNumberInRange,
  shortHash,
} = require("./security");
const {
  recordMatchesQuery,
  searchQueryTokens,
} = require("./search_tokens");
const {
  isTerminalStatus,
  toMillis,
} = require("./time_utils");

const SEARCH_QUERY_MAX = 80;
const SEARCH_READ_LIMIT = 50;
const SEARCH_RESULT_LIMIT = 25;
const CONFLICT_READ_LIMIT = 500;
const CONFLICT_EMPLOYEE_LIMIT = 500;
const APPOINTMENT_ID_MAX = 128;
const MIN_SEARCHABLE_MILLIS = Date.UTC(2020, 0, 1);
const MAX_SEARCHABLE_MILLIS = Date.UTC(2100, 0, 1);

/**
 * Reads and validates the active caller profile from usersByUid.
 * @param {!Object} req Callable request.
 * @param {!Set<string>} allowedKeys Allowed payload keys.
 * @return {!Promise<!Object>}
 */
async function requireActiveCaller(req, allowedKeys) {
  if (!req.auth || !req.auth.uid) {
    throw new HttpsError("unauthenticated", "auth-required");
  }
  assertPayloadShape(req.data, allowedKeys);
  const db = getFirestore();
  const snap = await db.collection("usersByUid").doc(req.auth.uid).get();
  const data = snap.exists ? snap.data() : null;
  if (!data || data.status !== "active") {
    logger.warn("indexed callable: inactive caller", {
      uidHash: shortHash(req.auth.uid),
      status: data ? data.status : null,
    });
    throw new HttpsError("permission-denied", "inactive-user");
  }
  return {uid: req.auth.uid, ...data};
}

/**
 * Converts Firestore values to JSON values the Flutter callable SDK can parse.
 * @param {*} value Raw Firestore/Admin SDK value.
 * @return {*}
 */
function serializeValue(value) {
  if (value == null) return value;
  if (typeof value.toMillis === "function") {
    return {millisecondsSinceEpoch: value.toMillis()};
  }
  if (value instanceof Date) {
    return {millisecondsSinceEpoch: value.getTime()};
  }
  if (Array.isArray(value)) return value.map(serializeValue);
  if (typeof value === "object") {
    return Object.fromEntries(
        Object.entries(value).map(([k, v]) => [k, serializeValue(v)]),
    );
  }
  return value;
}

/**
 * @param {!Object} doc Query document.
 * @return {{id: string, data: !Object}}
 */
function callableRecord(doc) {
  return {id: doc.id, data: serializeValue(doc.data() || {})};
}

/**
 * Server-side client search, admin-only because clients are PII.
 */
const searchClients = onCall(APP_CHECK, async (req) => {
  await assertAdminCall(req, new Set(["query"]));
  const query = optionalString(req.data, "query", SEARCH_QUERY_MAX);
  const tokens = searchQueryTokens(query);
  if (tokens.length === 0) return {clients: []};

  const snap = await getFirestore()
      .collection("clients")
      .where("searchTokens", "array-contains-any", tokens)
      .orderBy("name")
      .limit(SEARCH_READ_LIMIT)
      .get();
  const scored = [];
  for (const doc of snap.docs) {
    const data = doc.data() || {};
    if (!recordMatchesQuery(data, query)) continue;
    scored.push({
      sortKey: clientDisplayName(data).toLowerCase(),
      record: callableRecord(doc),
    });
  }
  scored.sort((a, b) => a.sortKey.localeCompare(b.sortKey));
  return {
    clients: scored.slice(0, SEARCH_RESULT_LIMIT).map((e) => e.record),
  };
});

/**
 * Chooses the history-search token scope allowed for the caller.
 * @param {!Object} profile usersByUid row.
 * @param {string} requestedEmployeeId Optional employeeId payload.
 * @return {string}
 */
function historyScope(profile, requestedEmployeeId) {
  const callerDocId = String(profile.docId || "");
  if (profile.role === "admin") {
    return requestedEmployeeId ? `emp:${requestedEmployeeId}` : "all";
  }
  if (profile.role === "employee" && callerDocId) {
    if (requestedEmployeeId && requestedEmployeeId !== callerDocId) {
      throw new HttpsError("permission-denied", "scope-denied");
    }
    return `emp:${callerDocId}`;
  }
  throw new HttpsError("permission-denied", "role-denied");
}

/**
 * Server-side terminal-appointment search, scoped by caller role.
 */
const searchHistory = onCall(APP_CHECK, async (req) => {
  const profile = await requireActiveCaller(
      req, new Set(["query", "employeeId"]));
  const query = optionalString(req.data, "query", SEARCH_QUERY_MAX);
  const employeeId = optionalString(req.data, "employeeId", APPOINTMENT_ID_MAX);
  const tokens = searchQueryTokens(query);
  if (tokens.length === 0) return {appointments: []};

  const scope = historyScope(profile, employeeId);
  const scoped = tokens.map((token) => `${scope}:${token}`);
  const snap = await getFirestore()
      .collection("appointments")
      .where("historySearchScopes", "array-contains-any", scoped)
      .where("status", "in", ["done", "completed", "cancelled"])
      .orderBy("startTime", "desc")
      .limit(SEARCH_READ_LIMIT)
      .get();
  const appointments = snap.docs
      .filter((doc) => recordMatchesQuery(doc.data() || {}, query))
      .slice(0, SEARCH_RESULT_LIMIT)
      .map(callableRecord);
  return {appointments};
});

/**
 * Validates employee id payloads.
 * @param {*} raw Raw payload value.
 * @return {!Array<string>}
 */
function readEmployeeIds(raw) {
  if (!Array.isArray(raw) || raw.length > CONFLICT_EMPLOYEE_LIMIT) {
    throw new HttpsError("invalid-argument", "invalid-employeeIds");
  }
  const out = [];
  const seen = new Set();
  for (const value of raw) {
    const id = String(value || "").trim();
    if (!id || id.includes("/") || id.length > APPOINTMENT_ID_MAX) {
      throw new HttpsError("invalid-argument", "invalid-employeeIds");
    }
    if (!seen.has(id)) {
      seen.add(id);
      out.push(id);
    }
  }
  return out;
}

/**
 * True when two instants overlap.
 * @param {?number} startA
 * @param {?number} endA
 * @param {number} startB
 * @param {number} endB
 * @return {boolean}
 */
function overlaps(startA, endA, startB, endB) {
  if (startA == null || endA == null) return true;
  return startA < endB && endA > startB;
}

/**
 * Server-side conflict validation for appointment writes.
 */
const findAppointmentConflicts = onCall(APP_CHECK, async (req) => {
  const profile = await requireActiveCaller(req, new Set([
    "employeeIds",
    "startMillis",
    "endMillis",
    "excludeAppointmentId",
    "clientJobsOnly",
  ]));
  const startMillis = requireNumberInRange(
      req.data.startMillis, "startMillis",
      MIN_SEARCHABLE_MILLIS, MAX_SEARCHABLE_MILLIS);
  const endMillis = requireNumberInRange(
      req.data.endMillis, "endMillis",
      MIN_SEARCHABLE_MILLIS, MAX_SEARCHABLE_MILLIS);
  if (endMillis <= startMillis) {
    throw new HttpsError("invalid-argument", "invalid-endMillis");
  }
  const excludeId = optionalString(
      req.data, "excludeAppointmentId", APPOINTMENT_ID_MAX);
  const clientJobsOnly = req.data.clientJobsOnly === true;
  let employeeIds = readEmployeeIds(req.data.employeeIds);
  if (employeeIds.length === 0) return {appointments: []};

  if (profile.role !== "admin") {
    const callerDocId = String(profile.docId || "");
    if (!callerDocId || employeeIds.some((id) => id !== callerDocId)) {
      throw new HttpsError("permission-denied", "scope-denied");
    }
    employeeIds = [callerDocId];
  }

  const db = getFirestore();
  const found = new Map();
  for (let i = 0; i < employeeIds.length; i += 30) {
    const batch = employeeIds.slice(i, i + 30);
    const snap = await db.collection("appointments")
        .where("employeeIds", "array-contains-any", batch)
        .where("startTime", "<", new Date(endMillis))
        .where("endTime", ">", new Date(startMillis))
        .limit(CONFLICT_READ_LIMIT)
        .get();
    if (snap.docs.length >= CONFLICT_READ_LIMIT) {
      logger.warn("findAppointmentConflicts: read cap hit", {
        uidHash: shortHash(profile.uid),
        count: snap.docs.length,
      });
    }
    for (const doc of snap.docs) found.set(doc.id, doc);
  }

  const appointments = [...found.values()].filter((doc) => {
    const data = doc.data() || {};
    if (doc.id === excludeId) return false;
    if (isTerminalStatus(data.status)) return false;
    if (clientJobsOnly && data.isPersonal === true) return false;
    return overlaps(
        toMillis(data.startTime),
        toMillis(data.endTime),
        startMillis,
        endMillis,
    );
  }).map(callableRecord);

  return {appointments};
});

module.exports = {
  searchClients,
  searchHistory,
  findAppointmentConflicts,
  historyScope,
  overlaps,
  serializeValue,
};
