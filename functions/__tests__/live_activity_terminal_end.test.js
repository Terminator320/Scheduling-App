/**
 * Regression tests for a nasty edge case: a deleted, cancelled, completed, or
 * unassigned job must still END its Live Activity card even after it's
 * started. The on-site flip pass has to actually end a card whose
 * appointment is gone, not just un-mark it.
 */

jest.mock("../live_activity_dispatch", () => ({
  buildAttributes: jest.fn(() => ({})),
  startLiveActivity: jest.fn().mockResolvedValue(0),
  updateLiveActivity: jest.fn().mockResolvedValue(1),
  endLiveActivity: jest.fn().mockResolvedValue(1),
}));
jest.mock("../live_activity_registry", () => ({
  listCardsDueForOnSite: jest.fn().mockResolvedValue([]),
  clearCardMarker: jest.fn().mockResolvedValue(undefined),
  writeCardMarker: jest.fn().mockResolvedValue(undefined),
  setCardStart: jest.fn().mockResolvedValue(undefined),
  listPushToStartTokens: jest.fn().mockResolvedValue([]),
  listUpdateTokens: jest.fn().mockResolvedValue([]),
  deleteActivityToken: jest.fn().mockResolvedValue(undefined),
}));

const {
  endLiveActivity,
  updateLiveActivity,
} = require("../live_activity_dispatch");
const {
  listCardsDueForOnSite,
  clearCardMarker,
} = require("../live_activity_registry");
const {handleAppointmentWrite} = require("../notification_utils");
const {runOnSiteFlipPass} = require("../travel_utils");
const {buildContentState, PHASE_ON_SITE} = require("../live_activity_utils");

// The job STARTED an hour ago and has an hour left to run — the regression
// window this file is about. The diff no longer suppresses events here: it
// gates on the run's END, so a job cancelled mid-flight still reaches its
// crew. The push itself goes nowhere because every read below comes back
// empty; the card assertions are the point.
const NOW = new Date("2026-07-21T15:00:00.000Z");
const STARTED = new Date("2026-07-21T14:00:00.000Z");
const ENDS = new Date("2026-07-21T16:00:00.000Z");

const startedJob = (extra) => ({
  clientName: "Paul",
  address: "1 Rue A",
  startTime: STARTED,
  endTime: ENDS,
  status: "pending",
  employeeIds: ["emp-1", "emp-2"],
  ...(extra || {}),
});

// Every read resolves empty, so sendToEmployee bails at "no user doc" and
// contributes 0 sends without needing a full Firestore fake.
const emptyQuery = {
  get: async () => ({docs: [], empty: true}),
  where: () => emptyQuery,
  orderBy: () => emptyQuery,
  limit: () => emptyQuery,
};
const emptyDoc = {
  get: async () => ({exists: false, data: () => null}),
  collection: () => emptyQuery,
};

const deps = () => ({
  db: {collection: () => ({...emptyQuery, doc: () => emptyDoc})},
  messaging: {},
  now: NOW,
  logger: {warn: jest.fn()},
});

beforeEach(() => {
  jest.clearAllMocks();
});

describe("handleAppointmentWrite terminal card ends", () => {
  test("DELETING a started job ends the card for every assignee", async () => {
    const res = await handleAppointmentWrite(
        "a1", startedJob(), null, deps());
    // One cancellation event per assignee — a job deleted while the crew is
    // still on it must tell them. Nothing is delivered here (no user docs).
    expect(res).toEqual({events: 2, sent: 0});
    // ...and the card end must fire too.
    const targets = endLiveActivity.mock.calls.map((c) => c[1].employeeDocId);
    expect(targets.sort()).toEqual(["emp-1", "emp-2"]);
    expect(endLiveActivity.mock.calls[0][1].appointmentId).toBe("a1");
  });

  test("cancelling a started job ends the card", async () => {
    await handleAppointmentWrite(
        "a1", startedJob(), startedJob({status: "cancelled"}), deps());
    expect(endLiveActivity).toHaveBeenCalledTimes(2);
  });

  test("completing a started job ends the card", async () => {
    await handleAppointmentWrite(
        "a1", startedJob(), startedJob({status: "done"}), deps());
    expect(endLiveActivity).toHaveBeenCalledTimes(2);
  });

  test("unassigning one tech mid-flight ends only their card", async () => {
    await handleAppointmentWrite(
        "a1", startedJob(), startedJob({employeeIds: ["emp-2"]}), deps());
    expect(endLiveActivity).toHaveBeenCalledTimes(1);
    expect(endLiveActivity.mock.calls[0][1].employeeDocId).toBe("emp-1");
  });

  test("a plain edit with no terminal transition ends nothing", async () => {
    await handleAppointmentWrite(
        "a1", startedJob(), startedJob({clientName: "Renamed"}), deps());
    expect(endLiveActivity).not.toHaveBeenCalled();
  });
});

describe("runOnSiteFlipPass on a dead appointment", () => {
  const marker = {appointmentId: "a1", employeeDocId: "emp-1"};
  const dbWith = (snap) => ({
    collection: () => ({doc: () => ({get: async () => snap})}),
  });

  test("a DELETED appointment ends the card, not just the marker",
      async () => {
        listCardsDueForOnSite.mockResolvedValue([marker]);
        const d = {...deps(), db: dbWith({exists: false})};
        await runOnSiteFlipPass(d);
        expect(endLiveActivity).toHaveBeenCalledTimes(1);
        expect(endLiveActivity.mock.calls[0][1].appointmentId).toBe("a1");
        expect(clearCardMarker).toHaveBeenCalled();
        expect(updateLiveActivity).not.toHaveBeenCalled();
      });

  test("a terminal-status appointment ends the card too", async () => {
    listCardsDueForOnSite.mockResolvedValue([marker]);
    const d = {
      ...deps(),
      db: dbWith({exists: true, data: () => startedJob({status: "done"})}),
    };
    await runOnSiteFlipPass(d);
    expect(endLiveActivity).toHaveBeenCalledTimes(1);
    expect(clearCardMarker).toHaveBeenCalled();
  });

  test("a live appointment flips with endTime in the ctx", async () => {
    listCardsDueForOnSite.mockResolvedValue([marker]);
    const d = {
      ...deps(),
      db: dbWith({exists: true, data: () => startedJob()}),
    };
    await runOnSiteFlipPass(d);
    expect(updateLiveActivity).toHaveBeenCalledTimes(1);
    expect(updateLiveActivity.mock.calls[0][1].ctx.endTime).toEqual(ENDS);
    expect(endLiveActivity).not.toHaveBeenCalled();
  });
});

describe("buildContentState endTime (on-site countdown source)", () => {
  test("emits the scheduled end as an absolute UTC instant", () => {
    const state = buildContentState({
      clientName: "Paul",
      address: "1 Rue A",
      startTime: STARTED,
      endTime: ENDS,
      leaveAt: null,
      travelMinutes: null,
      phase: PHASE_ON_SITE,
      locale: "en",
    });
    expect(state.endTime).toBe("2026-07-21T16:00:00.000Z");
  });

  test("emits null when the record has no end", () => {
    const state = buildContentState({
      clientName: "Paul",
      address: "",
      startTime: STARTED,
      endTime: undefined,
      leaveAt: null,
      travelMinutes: null,
      phase: PHASE_ON_SITE,
      locale: "en",
    });
    expect(state.endTime).toBeNull();
  });
});
