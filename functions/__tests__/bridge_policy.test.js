"use strict";

/**
 * The `usersByUid` bridge's pure rules. `scripts/backfill.js` is the only
 * script in this repo that DELETES, and it deletes from the collection every
 * `firestore.rules` gate resolves a role through — this file is what stops
 * that decision from being untested.
 *
 * Required through the SCRIPT's surface as well as the policy module, so the
 * `require.main === module` guard and the re-export it exists for stay pinned
 * too: the script must remain requirable without prod credentials.
 */

const policy = require("../bridge_policy");
const script = require("../scripts/backfill");

const {
  shouldHaveBridge,
  bridgeBody,
  bridgeMatches,
  classifyBridgeRow,
} = policy;

describe("the script and the trigger share one owner", () => {
  test("backfill.js re-exports the policy bodies, not copies", () => {
    // They were byte-identical copies under a comment claiming the
    // duplication was deliberate. Identity is what keeps that from recurring.
    expect(script.shouldHaveBridge).toBe(policy.shouldHaveBridge);
    expect(script.bridgeBody).toBe(policy.bridgeBody);
    expect(script.bridgeMatches).toBe(policy.bridgeMatches);
    expect(script.classifyBridgeRow).toBe(policy.classifyBridgeRow);
  });

  test("bridge.js uses the same bodies", () => {
    const bridge = require("../bridge");
    // The trigger keeps its own exports; what matters is that it no longer
    // carries a private `shouldHaveBridge`.
    expect(Object.keys(bridge)).not.toContain("shouldHaveBridge");
  });
});

describe("shouldHaveBridge", () => {
  const ACTIVE = {uid: "u1", role: "employee", status: "active"};

  test("an active employee with a uid gets a row", () => {
    expect(shouldHaveBridge(ACTIVE)).toBe(true);
  });

  test("a disabled account keeps its row", () => {
    // Deliberate: `isAssignedEmployee` gates on `status == 'active'`, not on
    // the row existing, so the row is retained for a disabled user.
    expect(shouldHaveBridge({...ACTIVE, status: "disabled"})).toBe(true);
  });

  test("an invited account has no uid to key on", () => {
    expect(shouldHaveBridge({...ACTIVE, uid: "", status: "invited"}))
        .toBe(false);
  });

  test("a missing role fails CLOSED", () => {
    // `bridgeBody` writes `role` unconditionally and initializeApp() sets no
    // ignoreUndefinedProperties, so letting this through threw inside a
    // retry:true trigger and the bridge was never written at all.
    expect(shouldHaveBridge({uid: "u1", status: "active"})).toBe(false);
    expect(shouldHaveBridge({...ACTIVE, role: "superuser"})).toBe(false);
  });

  test("an unknown status is refused", () => {
    expect(shouldHaveBridge({...ACTIVE, status: ""})).toBe(false);
    expect(shouldHaveBridge({...ACTIVE, status: "archived"})).toBe(false);
  });

  test("a non-string uid is refused", () => {
    expect(shouldHaveBridge({...ACTIVE, uid: 42})).toBe(false);
    expect(shouldHaveBridge(null)).toBe(false);
  });
});

describe("bridgeBody / bridgeMatches", () => {
  test("the body is exactly the three mirrored fields", () => {
    const body = bridgeBody("doc1", {
      uid: "u1", role: "admin", status: "active", name: "ignored",
    });
    expect(body).toEqual({role: "admin", docId: "doc1", status: "active"});
  });

  test("a row matching all three fields needs no write", () => {
    const body = bridgeBody("doc1", {role: "admin", status: "active"});
    expect(bridgeMatches({...body}, body)).toBe(true);
  });

  test("any differing field means a write", () => {
    const body = bridgeBody("doc1", {role: "admin", status: "active"});
    expect(bridgeMatches({...body, role: "employee"}, body)).toBe(false);
    expect(bridgeMatches({...body, docId: "doc2"}, body)).toBe(false);
    expect(bridgeMatches({...body, status: "disabled"}, body)).toBe(false);
    expect(bridgeMatches(undefined, body)).toBe(false);
  });
});

describe("classifyBridgeRow", () => {
  /**
   * @param {!Array<string>} expected uids this run wrote or verified.
   * @param {!Array<string>} claimed uids ANY users doc carries.
   * @return {{expectedUids: !Set<string>, claimedUids: !Set<string>}}
   */
  function sets(expected, claimed) {
    return {
      expectedUids: new Set(expected),
      claimedUids: new Set(claimed),
    };
  }

  test("a uid this run wrote is current", () => {
    expect(classifyBridgeRow("u1", sets(["u1"], ["u1"]))).toBe("current");
  });

  test("a uid claimed by a SKIPPED users doc is retained, not orphaned",
      () => {
        // The whole point of the three-way split. A skipped doc (invited, or
        // a malformed role written from the console) still claims its uid —
        // deleting the row locks a live employee out of everything, and what
        // that row should say belongs to the trigger.
        expect(classifyBridgeRow("u1", sets([], ["u1"]))).toBe("retained");
      });

  test("a uid no users doc carries is an orphan", () => {
    expect(classifyBridgeRow("ghost", sets(["u1"], ["u1"]))).toBe("orphan");
  });

  test("expected wins over claimed when both hold the uid", () => {
    // `expectedUids` is a subset of `claimedUids` by construction, so the
    // order of the two tests is what makes "current" reachable at all.
    expect(classifyBridgeRow("u1", sets(["u1"], ["u1", "u2"])))
        .toBe("current");
  });

  test("empty sets orphan everything", () => {
    expect(classifyBridgeRow("anything", sets([], []))).toBe("orphan");
  });
});

describe("assertKnownFlags", () => {
  test("accepts the two documented switches", () => {
    expect(() => script.assertKnownFlags(["--dry-run", "--prune-orphans"]))
        .not.toThrow();
    expect(() => script.assertKnownFlags([])).not.toThrow();
  });

  test("a near-miss flag is a hard error, not a silent false", () => {
    // `--dryrun` reading as false takes the run LIVE; `--prune_orphans`
    // reading as false is a delete request the script silently never honours.
    expect(() => script.assertKnownFlags(["--dryrun"])).toThrow();
    expect(() => script.assertKnownFlags(["--dry_run"])).toThrow();
    expect(() => script.assertKnownFlags(["--prune_orphans"])).toThrow();
  });
});
