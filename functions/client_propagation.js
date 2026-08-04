"use strict";

/**
 * @fileoverview Propagates client-doc edits (name/phone/address) onto that
 * client's FUTURE denormalized appointment copies, so an edit doesn't leave
 * the calendar showing stale data (client-side finding C8).
 *
 * Semantics (mirrors the app's own rules):
 *   - `clientName` / `clientPhone` are always overwritten with the client's
 *     current values.
 *   - `address` follows the client only when the appointment's stored address
 *     still equals the client's previous (non-empty) address — a differing
 *     or empty address is treated as custom/none and left untouched.
 *   - Only appointments with WORK LEFT are rewritten — history records what
 *     was true at the time of the visit. That is `endTime >= now`, NOT
 *     `startTime >= now`: under the daily-window model a run started up to
 *     MAX_APPOINTMENT_SPAN_DAYS ago can still have days of work left, and
 *     gating on the start meant a client's corrected phone or suite number
 *     never reached a crew that was already on site. Firestore can only take
 *     the one inequality that matches the index, so the QUERY floor is widened
 *     by the span and the real endTime test is applied in code below.
 *
 * Every write is an absolute value, so this is idempotent and the trigger
 * runs with `retry: true`. Updates go out in WriteBatches of ≤500 (the
 * Firestore hard limit).
 *
 * Requires the composite index `(clientId ASC, startTime ASC)` on
 * `appointments` (declared in firestore.indexes.json).
 *
 * @module client_propagation
 */

const {onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {MAX_APPOINTMENT_SPAN_MS, toMillis} = require("./time_utils");

/** Firestore WriteBatch hard limit. */
const BATCH_LIMIT = 500;

/** Page size for the future-appointments query (one batch per page). */
const PAGE_SIZE = BATCH_LIMIT;

/**
 * Lazily resolves firebase-admin/firestore so unit tests that inject deps
 * never touch it.
 * @return {{getFirestore: !Function, FieldValue: !Object}}
 */
function adminFirestore() {
  // eslint-disable-next-line global-require
  return require("firebase-admin/firestore");
}

/**
 * Display name for a client doc, mirroring the Flutter model's fallback:
 * `name` when non-blank, else the legacy `businessName`.
 * @param {!Object} data Client document fields.
 * @return {string}
 */
function clientDisplayName(data) {
  const d = data || {};
  const name = typeof d.name === "string" ? d.name.trim() : "";
  if (name) return name;
  return typeof d.businessName === "string" ? d.businessName.trim() : "";
}

/**
 * Computes what (if anything) a client edit must propagate to appointments.
 * Pure — unit-testable without Firestore.
 *
 * @param {!Object} before Pre-edit client document fields.
 * @param {!Object} after Post-edit client document fields.
 * @return {?{clientName: (string|undefined), clientPhone: (string|undefined),
 *   address: (?{from: string, to: string})}} Null when nothing changed.
 *   `address` is set only when the client's address changed from a
 *   non-empty value — matching appointments get `to`.
 */
function relevantClientChange(before, after) {
  const b = before || {};
  const a = after || {};

  const change = {};
  let any = false;

  const nameBefore = clientDisplayName(b);
  const nameAfter = clientDisplayName(a);
  if (nameAfter !== nameBefore) {
    change.clientName = nameAfter;
    any = true;
  }

  const phoneBefore = typeof b.phone === "string" ? b.phone.trim() : "";
  const phoneAfter = typeof a.phone === "string" ? a.phone.trim() : "";
  if (phoneAfter !== phoneBefore) {
    change.clientPhone = phoneAfter;
    any = true;
  }

  const addrBefore = typeof b.address === "string" ? b.address.trim() : "";
  const addrAfter = typeof a.address === "string" ? a.address.trim() : "";
  // Only propagate when the OLD address was non-empty — appointments with
  // an empty address are custom/none, and matching against "" would clobber
  // them.
  if (addrAfter !== addrBefore && addrBefore !== "") {
    change.address = {from: addrBefore, to: addrAfter};
    any = true;
  } else {
    change.address = null;
  }

  return any ? change : null;
}

/**
 * Builds the update patch for one appointment doc given a relevant change.
 * Pure — unit-testable without Firestore.
 * @param {!Object} change Result of `relevantClientChange` (non-null).
 * @param {!Object} apptData The appointment document fields.
 * @return {?Object} Field patch, or null when this appointment needs nothing.
 */
function buildAppointmentPatch(change, apptData) {
  const d = apptData || {};
  const patch = {};

  if (change.clientName !== undefined &&
      d.clientName !== change.clientName) {
    patch.clientName = change.clientName;
  }
  if (change.clientPhone !== undefined &&
      d.clientPhone !== change.clientPhone) {
    patch.clientPhone = change.clientPhone;
  }
  if (change.address) {
    const current = typeof d.address === "string" ? d.address.trim() : "";
    // This follows the client: only an address still equal to the client's
    // previous value gets updated. A differing address is custom and stays
    // untouched, and an already-propagated doc matches nothing so it's
    // skipped on retry.
    if (current === change.address.from) {
      patch.address = change.address.to;
    }
  }

  return Object.keys(patch).length > 0 ? patch : null;
}

/**
 * Fans a relevant client change out to that client's FUTURE appointments.
 * Injectable core (unit-testable); the trigger below is a thin wrapper.
 *
 * @param {string} clientId The client document id.
 * @param {Object} before Pre-edit client fields.
 * @param {Object} after Post-edit client fields.
 * @param {Object=} deps Injectable: `db` (default getFirestore()), `now`
 *   (Date for the startTime cutoff; default `new Date()`), `logger`.
 * @return {!Promise<{updated: number}>}
 */
async function propagateClientChange(clientId, before, after, deps = {}) {
  const db = deps.db || adminFirestore().getFirestore();
  // eslint-disable-next-line global-require
  const logger = deps.logger || require("firebase-functions/logger");
  const now = deps.now || new Date();

  const change = relevantClientChange(before, after);
  if (!change) return {updated: 0};

  const nowMs = now.getTime();
  const queryFloor = new Date(nowMs - MAX_APPOINTMENT_SPAN_MS);
  // "Is there still work left on this job?" — mirrors `hasWorkLeft` in
  // notification_policy.js. Falls back to the start when endTime is missing.
  const hasWorkLeft = (d) => {
    const ms = toMillis(d.endTime) ?? toMillis(d.startTime);
    return ms != null && ms >= nowMs;
  };

  let updated = 0;
  let cursor = null;
  for (;;) {
    let query = db.collection("appointments")
        .where("clientId", "==", clientId)
        .where("startTime", ">=", queryFloor)
        .orderBy("startTime")
        .limit(PAGE_SIZE);
    if (cursor) query = query.startAfter(cursor);
    const snap = await query.get();
    const docs = snap && Array.isArray(snap.docs) ? snap.docs : [];
    if (docs.length === 0) break;

    const batch = db.batch();
    let ops = 0;
    for (const doc of docs) {
      const data = doc.data() || {};
      // The widened floor pulls in runs that already finished; drop those.
      if (!hasWorkLeft(data)) continue;
      const patch = buildAppointmentPatch(change, data);
      if (!patch) continue;
      batch.update(doc.ref, patch);
      ops += 1;
    }
    if (ops > 0) await batch.commit();
    updated += ops;

    if (docs.length < PAGE_SIZE) break;
    cursor = docs[docs.length - 1];
  }

  if (updated > 0) {
    logger.info("propagateClientEdits: appointments updated", {
      clientId,
      updated,
      fields: Object.keys(change).filter((k) =>
        change[k] !== null && change[k] !== undefined),
    });
  }
  return {updated};
}

// This trigger fans client edits out to future appointments. It fires only
// on UPDATE, since creates have no appointments yet and deletes intentionally
// leave history intact. (`retry: true` is safe — see the idempotency note in
// the fileoverview.)
const propagateClientEdits = onDocumentUpdated(
    {document: "clients/{clientId}", retry: true},
    async (event) => {
      const before = event.data?.before?.exists ?
        event.data.before.data() : null;
      const after = event.data?.after?.exists ?
        event.data.after.data() : null;
      if (!before || !after) return;
      await propagateClientChange(event.params.clientId, before, after);
    },
);

module.exports = {
  propagateClientEdits,
  // Exported so the orchestrator can be driven with injected {db, logger,
  // now} — that injection is what makes the has-work-left gate testable
  // without touching firebase-admin.
  propagateClientChange,
  relevantClientChange,
  buildAppointmentPatch,
  clientDisplayName,
};
