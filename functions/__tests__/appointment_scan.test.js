"use strict";

/**
 * @fileoverview Pins the shared appointment-window scan behind all three
 * scheduled sweeps.
 *
 * Everything here is a guard that only ever runs in production. The two throws
 * exist to stop a FUTURE call site omitting an argument — so without a test
 * they are code nobody knows is broken until a sweep quietly reads the wrong
 * jobs. The truncation warn is worse: it is the ONLY sign that a cap discarded
 * exactly the appointments the sweep exists for, and losing it fails silently
 * in the direction of doing nothing.
 *
 * `pageToCap`'s Dart suite (`test/core/data/paged_scan_test.dart`) is the twin
 * of this file; both bound helpers make their cap-reached callback required for
 * the same reason.
 */

const {scanAppointmentWindow} = require("../appointment_scan");

const LO = new Date("2026-08-01T00:00:00Z");
const HI = new Date("2026-08-08T00:00:00Z");

/**
 * Records the query chain and answers with `size` fake documents.
 * @param {{size: number}=} opts
 * @return {!Object} `{db, calls}`
 */
function makeDb({size = 0} = {}) {
  const calls = {collection: null, where: [], orderBy: null, limit: null};
  const docs = Array.from({length: size}, (_, i) => ({
    id: `a${i}`,
    data: () => ({title: `job ${i}`}),
  }));
  const query = {
    where(field, op, value) {
      calls.where.push({field, op, value});
      return query;
    },
    orderBy(field, direction) {
      calls.orderBy = {field, direction};
      return query;
    },
    limit(n) {
      calls.limit = n;
      return query;
    },
    async get() {
      return {size: docs.length, docs};
    },
  };
  const db = {
    collection(name) {
      calls.collection = name;
      return query;
    },
  };
  return {db, calls};
}

/**
 * A complete, valid options bag — each test removes or changes ONE key.
 * @param {!Object=} overrides
 * @return {!Object}
 */
function options(overrides = {}) {
  return {
    statuses: ["pending", "in_progress"],
    field: "startTime",
    lo: LO,
    loOp: ">=",
    hi: HI,
    hiOp: "<=",
    descending: false,
    cap: 3,
    logger: {warn: jest.fn()},
    label: "digest sweep",
    consequence: "some crews may not receive a digest",
    ...overrides,
  };
}

describe("the warn contract is enforced, not merely read", () => {
  // Omit `logger` and the truncation warn vanishes; omit `label` or
  // `consequence` and it prints `undefined` — both are the silent-truncation
  // failure this module exists to prevent, so it refuses to run at all.
  for (const missing of ["logger", "label", "consequence"]) {
    test(`throws when \`${missing}\` is missing`, async () => {
      const {db} = makeDb();
      await expect(
          scanAppointmentWindow(db, options({[missing]: undefined})),
      ).rejects.toThrow(/label, consequence and logger are required/);
    });
  }

  test("names itself in the message, so the caller is findable", async () => {
    const {db} = makeDb();
    await expect(
        scanAppointmentWindow(db, options({logger: undefined})),
    ).rejects.toThrow(/^scanAppointmentWindow:/);
  });

  test("refuses BEFORE reading anything", async () => {
    // A throw after the get() would still bill the read it cannot report on.
    const {db, calls} = makeDb({size: 2});
    await expect(
        scanAppointmentWindow(db, options({label: ""})),
    ).rejects.toThrow();
    expect(calls.collection).toBeNull();
  });
});

describe("the ordering contract is enforced, not defaulted", () => {
  // `descending` had a default, and getting it wrong silently spends the cap on
  // the wrong end of the window — the newest jobs when the sweep needed the
  // soonest. A default is exactly how the next call site gets it wrong without
  // saying anything.
  test("throws when `descending` is left off", async () => {
    const {db} = makeDb();
    await expect(
        scanAppointmentWindow(db, options({descending: undefined})),
    ).rejects.toThrow(/loOp, hiOp and descending are required/);
  });

  test("throws on a truthy non-boolean `descending`", async () => {
    // "desc" reads as a direction and is not one; accepting it would order
    // ascending while the caller believed otherwise.
    const {db} = makeDb();
    await expect(
        scanAppointmentWindow(db, options({descending: "desc"})),
    ).rejects.toThrow(/loOp, hiOp and descending are required/);
  });

  for (const missing of ["loOp", "hiOp"]) {
    test(`throws when \`${missing}\` is missing`, async () => {
      const {db} = makeDb();
      await expect(
          scanAppointmentWindow(db, options({[missing]: undefined})),
      ).rejects.toThrow(/loOp, hiOp and descending are required/);
    });
  }

  test("`descending: false` is a valid value, not a missing one", async () => {
    const {db, calls} = makeDb();
    await scanAppointmentWindow(db, options({descending: false}));
    expect(calls.orderBy).toEqual({field: "startTime", direction: "asc"});
  });

  test("`descending: true` orders desc", async () => {
    const {db, calls} = makeDb();
    await scanAppointmentWindow(db, options({descending: true}));
    expect(calls.orderBy).toEqual({field: "startTime", direction: "desc"});
  });
});

describe("the truncation warn", () => {
  test("fires when the snapshot fills the cap exactly", async () => {
    // size === cap is the only signal Firestore gives that a window was cut
    // short; there is no "there were more" flag.
    const warn = jest.fn();
    const {db} = makeDb({size: 3});
    await scanAppointmentWindow(db, options({cap: 3, logger: {warn}}));
    expect(warn).toHaveBeenCalledTimes(1);
    expect(warn).toHaveBeenCalledWith(
        "digest sweep: candidate cap hit; " +
          "some crews may not receive a digest",
        {cap: 3},
    );
  });

  test("stays quiet one document below the cap", async () => {
    const warn = jest.fn();
    const {db} = makeDb({size: 2});
    await scanAppointmentWindow(db, options({cap: 3, logger: {warn}}));
    expect(warn).not.toHaveBeenCalled();
  });

  test("stays quiet on an empty window", async () => {
    const warn = jest.fn();
    const {db} = makeDb({size: 0});
    await scanAppointmentWindow(db, options({cap: 3, logger: {warn}}));
    expect(warn).not.toHaveBeenCalled();
  });
});

describe("the query it builds", () => {
  test("constrains status and both ends of the window, capped", async () => {
    const {db, calls} = makeDb({size: 1});
    await scanAppointmentWindow(db, options({cap: 50}));

    expect(calls.collection).toBe("appointments");
    expect(calls.where).toEqual([
      {field: "status", op: "in", value: ["pending", "in_progress"]},
      {field: "startTime", op: ">=", value: LO},
      {field: "startTime", op: "<=", value: HI},
    ]);
    expect(calls.limit).toBe(50);
  });

  test("carries the caller's own comparison operators through", async () => {
    // The overdue sweep wants an exclusive upper bound where the digest wants
    // an inclusive one; the module must not pick for them.
    const {db, calls} = makeDb();
    await scanAppointmentWindow(db, options({loOp: ">", hiOp: "<"}));
    expect(calls.where.slice(1).map((w) => w.op)).toEqual([">", "<"]);
  });

  test("maps through recordOf, so id travels with the fields", async () => {
    // travel_utils.js re-spelled this mapper inline TWICE rather than sharing
    // it; a record that loses its id is unaddressable by every sweep.
    const {db} = makeDb({size: 2});
    await expect(scanAppointmentWindow(db, options())).resolves.toEqual([
      {id: "a0", title: "job 0"},
      {id: "a1", title: "job 1"},
    ]);
  });
});
