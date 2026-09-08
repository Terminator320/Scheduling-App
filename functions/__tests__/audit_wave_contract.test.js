"use strict";

/**
 * Tests for `audit` — the sweep in `scripts/audit-wave-contract.js`.
 *
 * `buildCustomerPayload` beneath it was already well covered; this script's
 * own layer was not covered at all, because the file had no
 * `require.main === module` guard and no `module.exports`, so `main()` ran at
 * REQUIRE time against whatever credentials were ambient and a test could not
 * load it without running the audit. It was the only script in the directory
 * shaped that way.
 *
 * The layer is worth pinning because its numbers are a program decision: this
 * report is the gate holding the Wave rearchitecture's later phases unwritten,
 * and counting an ADVISORY problem as blocking (or missing a page of clients)
 * mis-sizes that decision rather than breaking anything visibly.
 */

const {audit, assertKnownFlags} =
  require("../scripts/audit-wave-contract");

/**
 * A client the contract accepts, so each case can break exactly one thing.
 * Mirrors the fixture in `wave_customer_contract.test.js`.
 * @param {!Object=} over Fields to override.
 * @return {!Object} Client document fields.
 */
function client(over = {}) {
  return {
    name: "Vogas Plumbing",
    firstName: "",
    lastName: "",
    email: "",
    phone: "(514) 555-1234",
    mobile: "",
    address: "4450 Prom. Paton",
    city: "Laval",
    province: "QC",
    country: "Canada",
    postalCode: "H7W 5J7",
    type: "commercial",
    ...over,
  };
}

/**
 * Mirrors `PAGE_SIZE` in the script. Not exported there — it is a round-trip
 * dial, not a rule — but the paging test needs a FULL page to prove the loop
 * continues past one, so the number has to be spelled somewhere.
 */
const PAGE_SIZE = 500;

/**
 * A Firestore double that serves `pages` one page at a time, recording the
 * cursor the script pages on.
 * @param {!Array<!Array<!Object>>} pages Documents per page, in order.
 * @param {!Array<string>=} cursors Filled with each `startAfter` doc id.
 * @return {!Object} A db handle exposing only what `audit` calls.
 */
function makeDb(pages, cursors = []) {
  let index = 0;
  const query = {
    orderBy: () => query,
    limit: () => query,
    startAfter: (doc) => {
      cursors.push(doc.id);
      return query;
    },
    get: async () => {
      const docs = pages[index] || [];
      index += 1;
      return {empty: docs.length === 0, size: docs.length, docs};
    },
  };
  return {collection: () => query};
}

/**
 * One client document double.
 * @param {string} id
 * @param {!Object} fields
 * @return {!Object}
 */
function doc(id, fields) {
  return {id, data: () => fields};
}

describe("audit severity split", () => {
  test("a BLOCKING problem counts as refused AND flagged", async () => {
    const out = await audit(makeDb([[doc("c1", client({name: ""}))]]));

    expect(out.scanned).toBe(1);
    expect(out.refused).toBe(1);
    expect(out.flagged).toBe(1);
    expect(out.offenders).toEqual([
      {
        id: "c1",
        blocked: true,
        problems: [
          {field: "name", code: "EMPTY", severity: "blocking", detail: null},
        ],
      },
    ]);
  });

  test("an ADVISORY-only problem is flagged but NEVER refused", async () => {
    // The case the audit first turned up on 2026-08-30: Wave accepts the
    // value, so blocking it would strand a client that syncs fine. Counting
    // it as refused would overstate the blocking set the program decision is
    // sized on.
    const out = await audit(
        makeDb([[doc("c2", client({phone: "Contact Person"}))]]));

    expect(out.refused).toBe(0);
    expect(out.flagged).toBe(1);
    expect(out.offenders[0].blocked).toBe(false);
  });

  test("an advisory alongside a blocking problem refuses the client ONCE",
      async () => {
        const out = await audit(makeDb([[
          doc("c3", client({name: "", phone: "Contact Person"})),
        ]]));

        expect(out.refused).toBe(1);
        expect(out.flagged).toBe(1);
        expect(out.offenders[0].problems.map((p) => p.code).sort())
            .toEqual(["EMPTY", "NOT_DIALABLE"]);
      });

  test("a clean client is neither flagged nor refused, but IS scanned",
      async () => {
        const out = await audit(makeDb([[doc("c4", client())]]));

        expect(out).toEqual({
          scanned: 1, refused: 0, flagged: 0, byCode: {}, offenders: [],
        });
      });

  test("tallies per severity+field+code, not per client", async () => {
    const out = await audit(makeDb([[
      doc("c1", client({name: ""})),
      doc("c2", client({name: ""})),
      doc("c3", client({phone: "Contact Person"})),
    ]]));

    expect(out.byCode).toEqual({
      "blocking  name:EMPTY": 2,
      "advisory  phone:NOT_DIALABLE": 1,
    });
    expect(out.refused).toBe(2);
    expect(out.flagged).toBe(3);
  });

  test("a document with no fields at all is refused, not skipped", async () => {
    // `doc.data() || {}` — a legacy row is exactly the shape the `__name__`
    // paging exists to keep reachable, so it must reach the classification.
    const out = await audit(makeDb([[{id: "c9", data: () => undefined}]]));

    expect(out.scanned).toBe(1);
    expect(out.refused).toBe(1);
  });
});

describe("audit paging", () => {
  test("walks a FULL page onto the next, paging on its last doc",
      async () => {
        // `snap.size < PAGE_SIZE` is the termination test, so only a SHORT
        // page ends the walk. A full one must continue, or the audit
        // silently reports the first 500 clients as if they were all of
        // them — the failure this script's `__name__` paging exists to
        // avoid.
        const cursors = [];
        const full = [];
        for (let i = 0; i < PAGE_SIZE; i += 1) {
          full.push(doc(`a${i}`, i === 0 ? client({name: ""}) : client()));
        }
        const short = [doc("b1", client({phone: "Contact Person"}))];

        const out = await audit(makeDb([full, short], cursors));

        expect(out.scanned).toBe(PAGE_SIZE + 1);
        expect(cursors).toEqual([`a${PAGE_SIZE - 1}`]);
        expect(out.refused).toBe(1);
        expect(out.flagged).toBe(2);
      });

  test("a short first page ends the walk without paging", async () => {
    const cursors = [];
    const out = await audit(
        makeDb([[doc("a1", client())], [doc("b1", client({name: ""}))]],
            cursors));

    expect(out.scanned).toBe(1);
    expect(cursors).toEqual([]);
  });

  test("an empty collection reports zeroes rather than throwing", async () => {
    const out = await audit(makeDb([[]]));

    expect(out).toEqual({
      scanned: 0, refused: 0, flagged: 0, byCode: {}, offenders: [],
    });
  });
});

describe("assertKnownFlags", () => {
  test("accepts the one flag this script knows", () => {
    expect(() => assertKnownFlags(["--verbose"])).not.toThrow();
    expect(() => assertKnownFlags([])).not.toThrow();
  });

  test("rejects an unknown flag, including a near-miss", () => {
    expect(() => assertKnownFlags(["--verbos"])).toThrow(/unknown argument/);
    // Read-only: `--dry-run` is deliberately NOT in the allowlist, which is
    // what makes `dryRun` structurally false for this script.
    expect(() => assertKnownFlags(["--dry-run"])).toThrow(/unknown argument/);
  });
});
