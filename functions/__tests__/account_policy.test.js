"use strict";

/**
 * Tests for the account-deletion orchestration.
 *
 * `deleteAccount` is the user-facing IRREVERSIBLE deletion and had only its
 * pure `isReauthStale` helper covered — the whole sequence was untested. This
 * follows the `maintenance_policy` precedent: the decisions moved to an
 * injectable policy module and are pinned here.
 *
 * The three rules that make a partial run safe:
 *   1. the users doc is resolved BEFORE anything destructive;
 *   2. Auth is deleted BEFORE the doc;
 *   3. a doc failure after Auth is gone still reports success.
 */

const {resolveUserDocId, runAccountDeletion} = require("../account_policy");

/** @return {!Object} A logger double that records nothing but the calls. */
function makeLogger() {
  return {info: jest.fn(), warn: jest.fn(), error: jest.fn()};
}

/**
 * Firestore double.
 * @param {!Object} opts Behaviour overrides.
 * @param {!Array<string>} trace Shared ordered call log.
 * @return {!Object}
 */
function makeDb(opts, trace) {
  return {
    collection: (name) => ({
      doc: (id) => ({
        id,
        get: async () => {
          trace.push(`db.get:${name}`);
          if (opts.bridgeError) throw new Error(opts.bridgeError);
          return {
            exists: opts.bridgeDocId !== undefined,
            data: () => ({docId: opts.bridgeDocId}),
          };
        },
      }),
      where: () => ({
        limit: () => ({
          get: async () => {
            trace.push("db.query:users");
            if (opts.queryError) throw new Error(opts.queryError);
            return opts.queryDocId ?
              {empty: false, docs: [{id: opts.queryDocId}]} :
              {empty: true, docs: []};
          },
        }),
      }),
    }),
    recursiveDelete: jest.fn(async () => {
      trace.push("db.recursiveDelete");
      if (opts.deleteDocError) throw new Error(opts.deleteDocError);
    }),
  };
}

/**
 * Auth double.
 * @param {!Object} opts Behaviour overrides.
 * @param {!Array<string>} trace Shared ordered call log.
 * @return {!Object}
 */
function makeAuth(opts, trace) {
  return {
    deleteUser: jest.fn(async () => {
      trace.push("auth.deleteUser");
      if (opts.deleteAuthError) throw new Error(opts.deleteAuthError);
    }),
  };
}

const UID = "uid-1";
const onAuthFailure = () => new Error("delete-auth-user-failed");

describe("resolveUserDocId", () => {
  test("prefers the usersByUid bridge", async () => {
    const trace = [];
    const db = makeDb({bridgeDocId: "d1"}, trace);
    expect(await resolveUserDocId(db, UID, makeLogger())).toBe("d1");
    // No fallback query needed.
    expect(trace).toEqual(["db.get:usersByUid"]);
  });

  test("falls back to a uid query when no bridge row exists", async () => {
    const trace = [];
    const db = makeDb({queryDocId: "d2"}, trace);
    expect(await resolveUserDocId(db, UID, makeLogger())).toBe("d2");
    expect(trace).toEqual(["db.get:usersByUid", "db.query:users"]);
  });

  test("a bridge read failure still falls through to the query", async () => {
    const trace = [];
    const db = makeDb({bridgeError: "unavailable", queryDocId: "d3"}, trace);
    const logger = makeLogger();

    expect(await resolveUserDocId(db, UID, logger)).toBe("d3");
    expect(logger.warn).toHaveBeenCalled();
  });

  test("returns null when neither lookup finds a doc", async () => {
    const trace = [];
    const db = makeDb({}, trace);
    expect(await resolveUserDocId(db, UID, makeLogger())).toBeNull();
  });

  test("a failed fallback query resolves null, never throws", async () => {
    const trace = [];
    const db = makeDb({queryError: "unavailable"}, trace);
    const logger = makeLogger();

    // A lookup failure must never block a deletion the user is entitled to —
    // the orphaned doc is recoverable, a blocked deletion is not.
    expect(await resolveUserDocId(db, UID, logger)).toBeNull();
    expect(logger.warn).toHaveBeenCalled();
  });
});

describe("runAccountDeletion", () => {
  const limiter = {refund: jest.fn().mockResolvedValue(undefined)};

  beforeEach(() => jest.clearAllMocks());

  test("resolves the doc BEFORE deleting anything", async () => {
    const trace = [];
    const db = makeDb({bridgeDocId: "d1"}, trace);
    const auth = makeAuth({}, trace);

    await runAccountDeletion(
        {db, auth, logger: makeLogger(), limiter, onAuthFailure}, UID);

    // Once the Auth user is gone the caller can never retry, so a doc we
    // failed to find first is stranded forever.
    expect(trace).toEqual([
      "db.get:usersByUid",
      "auth.deleteUser",
      "db.recursiveDelete",
    ]);
  });

  test("deletes Auth BEFORE the users doc", async () => {
    const trace = [];
    const db = makeDb({bridgeDocId: "d1"}, trace);
    const auth = makeAuth({}, trace);

    await runAccountDeletion(
        {db, auth, logger: makeLogger(), limiter, onAuthFailure}, UID);

    // The other order risks a live login with no profile doc.
    expect(trace.indexOf("auth.deleteUser"))
        .toBeLessThan(trace.indexOf("db.recursiveDelete"));
  });

  test("uses recursiveDelete so subcollections can't outlive the account",
      async () => {
        const trace = [];
        const db = makeDb({bridgeDocId: "d1"}, trace);

        await runAccountDeletion(
            {
              db,
              auth: makeAuth({}, trace),
              logger: makeLogger(),
              limiter,
              onAuthFailure,
            },
            UID,
        );

        // A plain doc delete would orphan fcmTokens/presence, leaving a
        // deleted account that still receives pushes.
        expect(db.recursiveDelete).toHaveBeenCalledTimes(1);
      });

  test("refunds the rate-limit slot and throws when Auth delete fails",
      async () => {
        const trace = [];
        const db = makeDb({bridgeDocId: "d1"}, trace);
        const auth = makeAuth({deleteAuthError: "auth down"}, trace);
        const logger = makeLogger();

        await expect(
            runAccountDeletion(
                {db, auth, logger, limiter, onAuthFailure}, UID),
        ).rejects.toThrow(/delete-auth-user-failed/);

        // Our failure, not the caller's — they must not lose an attempt.
        expect(limiter.refund).toHaveBeenCalledTimes(1);
        expect(logger.error).toHaveBeenCalled();
        // Nothing destructive ran on the doc.
        expect(db.recursiveDelete).not.toHaveBeenCalled();
      });

  test("reports success when the doc delete fails after Auth is gone",
      async () => {
        const trace = [];
        const db = makeDb(
            {bridgeDocId: "d1", deleteDocError: "unavailable"}, trace);
        const logger = makeLogger();

        const out = await runAccountDeletion(
            {
              db,
              auth: makeAuth({}, trace),
              logger,
              limiter,
              onAuthFailure,
            },
            UID,
        );

        // The caller's credentials no longer work either way, so telling them
        // to retry would be worse than useless.
        expect(out).toEqual({deleted: true, docId: "d1"});
        expect(logger.error).toHaveBeenCalledWith(
            expect.stringContaining("orphaned users doc"),
            expect.objectContaining({uid: UID, docId: "d1"}),
        );
      });

  test("deletes Auth even when no users doc can be found", async () => {
    const trace = [];
    const db = makeDb({}, trace);
    const auth = makeAuth({}, trace);

    const out = await runAccountDeletion(
        {db, auth, logger: makeLogger(), limiter, onAuthFailure}, UID);

    expect(auth.deleteUser).toHaveBeenCalledWith(UID);
    expect(db.recursiveDelete).not.toHaveBeenCalled();
    expect(out).toEqual({deleted: true, docId: null});
  });
});
