"use strict";

/**
 * Tests for `ledgerBody` — the shape every claim-ledger doc is written with.
 *
 * Zero direct coverage across three call sites, and its docstring names a
 * coupling that lives in a DIFFERENT file and in a different language:
 * *"`expiresAt` is the ABSOLUTE deletion instant, so the Firestore TTL policy
 * on these collections must use expiration offset 0."*
 *
 * Both halves fail silently. Write a RELATIVE duration into `expiresAt` and
 * Firestore's reaper reads it as an instant in 1970 and deletes every claim
 * immediately — every suppressed duplicate push starts sending again. Drop the
 * TTL policy and nothing is deleted at all, and the ledgers grow forever. The
 * only visible symptom either way is a notification behaving oddly weeks
 * later.
 */

const fs = require("fs");
const path = require("path");

const {ledgerBody} = require("../notification_policy");

/** The three collections `ledgerBody` is written into. */
const LEDGER_COLLECTIONS = [
  "appointmentReminders",
  "appointmentOverduePrompts",
  "appointmentSeriesNotices",
];

const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;

describe("ledgerBody", () => {
  test("stamps createdAt with the instant it was handed", () => {
    const now = new Date("2026-08-31T12:00:00Z");
    expect(ledgerBody(now).createdAt).toEqual(now);
  });

  test("expiresAt is an ABSOLUTE instant, not a duration", () => {
    // The failure this pins: a relative value here reads to Firestore's TTL
    // reaper as a 1970 timestamp, so every claim is deleted on sight and the
    // duplicate-suppression this ledger exists for stops working entirely.
    const now = new Date("2026-08-31T12:00:00Z");
    const {expiresAt} = ledgerBody(now);

    expect(expiresAt).toBeInstanceOf(Date);
    expect(expiresAt.getTime()).toBe(now.getTime() + SEVEN_DAYS_MS);
    expect(expiresAt.toISOString()).toBe("2026-09-07T12:00:00.000Z");
  });

  test("expiresAt always trails createdAt by the same window", () => {
    for (const iso of ["2026-01-01T00:00:00Z", "2026-12-31T23:59:59Z"]) {
      const body = ledgerBody(new Date(iso));
      expect(body.expiresAt.getTime() - body.createdAt.getTime())
          .toBe(SEVEN_DAYS_MS);
    }
  });

  test("carries only the two fields, so a create cannot smuggle state",
      () => {
        expect(Object.keys(ledgerBody(new Date())).sort())
            .toEqual(["createdAt", "expiresAt"]);
      });
});

describe("the TTL policy this shape depends on", () => {
  const manifest = JSON.parse(fs.readFileSync(
      path.join(__dirname, "..", "..", "firestore.indexes.json"), "utf8"));

  test.each(LEDGER_COLLECTIONS)(
      "%s has a TTL policy on expiresAt",
      (collectionGroup) => {
        // The other half of the coupling, and the half no JS test could
        // otherwise reach: without this entry nothing reaps the ledgers and
        // they grow without bound. `.claude/rules/firestore-indexes.md` also
        // warns a redeploy cannot DELETE a policy, so losing one from here is
        // a silent divergence from prod rather than an error.
        const override = (manifest.fieldOverrides || []).find(
            (f) => f.collectionGroup === collectionGroup &&
              f.fieldPath === "expiresAt");

        expect(override).toBeDefined();
        expect(override.ttl).toBe(true);
      });
});
