"use strict";

/**
 * @fileoverview Appointment action callables whose authorization is richer
 * than Firestore rules can safely express from the client.
 */

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

const {
  APP_CHECK,
  assertPayloadShape,
  optionalString,
  shortHash,
} = require("./security");
const {
  isCompletedStatus,
  isTerminalStatus,
} = require("./time_utils");

const DOC_ID_MAX = 128;
const RESTORABLE_STATUSES = new Set(["pending", "in_progress"]);

/**
 * Reads the active caller profile.
 * @param {!Object} db Firestore instance.
 * @param {!Object} req Callable request.
 * @return {!Promise<!Object>}
 */
async function activeCaller(db, req) {
  if (!req.auth || !req.auth.uid) {
    throw new HttpsError("unauthenticated", "auth-required");
  }
  const snap = await db.collection("usersByUid").doc(req.auth.uid).get();
  const data = snap.exists ? snap.data() : null;
  if (!data || data.status !== "active") {
    throw new HttpsError("permission-denied", "inactive-user");
  }
  return {uid: req.auth.uid, ...data};
}

/**
 * True when caller may operate on this appointment.
 * @param {!Object} caller usersByUid profile.
 * @param {!Object} appointment Appointment fields.
 * @return {boolean}
 */
function mayRestore(caller, appointment) {
  if (caller.role === "admin") return true;
  const callerDocId = String(caller.docId || "");
  const ids = Array.isArray(appointment.employeeIds) ?
    appointment.employeeIds.map((id) => String(id)) : [];
  return caller.role === "employee" &&
      callerDocId !== "" &&
      ids.includes(callerDocId);
}

/**
 * Undo for the mobile "mark complete" action.
 */
const restoreAppointmentStatus = onCall(APP_CHECK, async (req) => {
  const db = getFirestore();
  const caller = await activeCaller(db, req);
  assertPayloadShape(req.data, new Set(["appointmentId", "previousStatus"]));
  const appointmentId = optionalString(req.data, "appointmentId", DOC_ID_MAX);
  const previousStatus = optionalString(
      req.data, "previousStatus", DOC_ID_MAX);
  if (!appointmentId || appointmentId.includes("/")) {
    throw new HttpsError("invalid-argument", "invalid-appointmentId");
  }
  if (!RESTORABLE_STATUSES.has(previousStatus)) {
    throw new HttpsError("invalid-argument", "invalid-previousStatus");
  }

  const ref = db.collection("appointments").doc(appointmentId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new HttpsError("not-found", "appointment-not-found");
    }
    const data = snap.data() || {};
    if (!mayRestore(caller, data)) {
      throw new HttpsError("permission-denied", "scope-denied");
    }
    if (!isCompletedStatus(data.status)) {
      throw new HttpsError("failed-precondition", "not-completed");
    }
    if (isTerminalStatus(previousStatus)) {
      throw new HttpsError("invalid-argument", "invalid-previousStatus");
    }

    tx.update(ref, {
      status: previousStatus,
      completedAt: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  logger.info("restoreAppointmentStatus: restored", {
    uidHash: shortHash(caller.uid),
    appointmentId,
    previousStatus,
  });
});

module.exports = {
  mayRestore,
  restoreAppointmentStatus,
};
