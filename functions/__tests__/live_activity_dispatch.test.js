"use strict";

/**
 * @fileoverview Exercises the dispatch orchestration alone — registry lookup
 * -> payload -> APNs -> prune — with APNs and the registry mocked. Payload
 * shapes and wire format are covered elsewhere.
 */

jest.mock("../apns_client", () => ({
  sendLiveActivityPush: jest.fn(),
}));
jest.mock("../live_activity_registry", () => ({
  listPushToStartTokens: jest.fn(),
  listUpdateTokens: jest.fn(),
  deleteActivityToken: jest.fn(),
  writeCardMarker: jest.fn(),
  readCardMarker: jest.fn(),
  setCardStart: jest.fn(),
  clearCardMarker: jest.fn(),
}));

const {sendLiveActivityPush} = require("../apns_client");
const {
  listPushToStartTokens,
  listUpdateTokens,
  deleteActivityToken,
  writeCardMarker,
  readCardMarker,
  setCardStart,
  clearCardMarker,
} = require("../live_activity_registry");
const {
  buildAttributes,
  startLiveActivity,
  updateLiveActivity,
  endLiveActivity,
} = require("../live_activity_dispatch");

const AUTH = {authKey: "-----KEY-----", keyId: "K1", teamId: "T1"};
const NOW = new Date("2026-07-19T11:30:00Z");
const START = new Date("2026-07-19T12:00:00Z");

const CTX = {
  clientName: "Ada",
  address: "14 Elm St",
  startTime: START,
  leaveAt: new Date("2026-07-19T11:32:00Z"),
  travelMinutes: 18,
  // 18 min drive + the sweep's 10-min buffer.
  leadMinutes: 28,
};

/**
 * One `liveActivityTokens` row as the registry returns it.
 * @param {!Object=} overrides
 * @return {!Object}
 */
function row(overrides) {
  return {
    token: "tok-1",
    locale: "en",
    kind: "update",
    employeeDocId: "emp1",
    ref: {id: "act1"},
    ...overrides,
  };
}

/**
 * Injected deps with a `db` stub good enough for the employee colour read.
 * @param {!Object=} overrides
 * @return {!Object}
 */
function deps(overrides) {
  const employee = {exists: true, data: () => ({colorValue: 4283215696})};
  const db = {
    collection: () => ({doc: () => ({get: async () => employee})}),
  };
  return {db, logger: {warn: jest.fn()}, apnsAuth: AUTH, ...overrides};
}

beforeEach(() => {
  jest.clearAllMocks();
  sendLiveActivityPush.mockResolvedValue({
    ok: true, status: 200, reason: "", gone: false,
  });
  listPushToStartTokens.mockResolvedValue([]);
  listUpdateTokens.mockResolvedValue([]);
  deleteActivityToken.mockResolvedValue(true);
  writeCardMarker.mockResolvedValue(true);
  setCardStart.mockResolvedValue(true);
  clearCardMarker.mockResolvedValue(true);
  readCardMarker.mockResolvedValue({
    employeeDocId: "emp1", appointmentId: "appt1", phase: "travel",
  });
});

describe("buildAttributes", () => {
  test("carries the fields the Swift ActivityAttributes declares", () => {
    expect(buildAttributes({
      appointmentId: "a", employeeDocId: "e", employeeColorValue: 42,
    })).toEqual({
      appointmentId: "a", employeeDocId: "e", employeeColorValue: 42,
    });
  });

  test("defaults a missing colour to 0 so the Swift decode can't fail", () => {
    expect(buildAttributes({appointmentId: "a", employeeDocId: "e"}))
        .toEqual({appointmentId: "a", employeeDocId: "e",
          employeeColorValue: 0});
  });
});

describe("startLiveActivity", () => {
  test("sends a start payload per push-to-start token", async () => {
    listPushToStartTokens.mockResolvedValue([row(), row({token: "tok-2"})]);

    const started = await startLiveActivity(deps(), {
      appointmentId: "appt1", employeeDocId: "emp1", ctx: CTX, nowDate: NOW,
    });

    expect(started).toBe(2);
    const {payload} = sendLiveActivityPush.mock.calls[0][0];
    expect(payload.aps.event).toBe("start");
    expect(payload.aps["attributes-type"]).toBe("LiveActivitiesAppAttributes");
    expect(payload.aps["attributes"].appointmentId).toBe("appt1");
    expect(payload.aps["attributes"].employeeColorValue).toBe(4283215696);
    expect(payload.aps["content-state"].clientName).toBe("Ada");
  });

  test("records the card marker so update/end can find the card", async () => {
    listPushToStartTokens.mockResolvedValue([row()]);

    await startLiveActivity(deps(), {
      appointmentId: "appt1", employeeDocId: "emp1", ctx: CTX, nowDate: NOW,
    });

    expect(writeCardMarker).toHaveBeenCalledWith(expect.anything(), {
      employeeDocId: "emp1",
      appointmentId: "appt1",
      startTime: START,
      phase: "travel",
      leadMinutes: CTX.leadMinutes,
      travelMinutes: CTX.travelMinutes,
    });
  });

  test("writes no marker when every start push failed", async () => {
    listPushToStartTokens.mockResolvedValue([row()]);
    sendLiveActivityPush.mockResolvedValue({
      ok: false, status: 503, reason: "TooManyRequests", gone: false,
    });

    await startLiveActivity(deps(), {
      appointmentId: "appt1", employeeDocId: "emp1", ctx: CTX, nowDate: NOW,
    });

    expect(writeCardMarker).not.toHaveBeenCalled();
  });

  test("localizes the card per the token's stored locale", async () => {
    listPushToStartTokens.mockResolvedValue([row({locale: "fr"})]);

    await startLiveActivity(deps(), {
      appointmentId: "appt1", employeeDocId: "emp1", ctx: CTX, nowDate: NOW,
    });

    const {payload} = sendLiveActivityPush.mock.calls[0][0];
    expect(payload.aps["content-state"].statusLabel).toBe("En route");
  });

  test("prunes a token APNs reports as gone", async () => {
    const dead = row();
    listPushToStartTokens.mockResolvedValue([dead]);
    sendLiveActivityPush.mockResolvedValue({
      ok: false, status: 410, reason: "BadDeviceToken", gone: true,
    });

    const started = await startLiveActivity(deps(), {
      appointmentId: "appt1", employeeDocId: "emp1", ctx: CTX, nowDate: NOW,
    });

    expect(started).toBe(0);
    expect(deleteActivityToken)
        .toHaveBeenCalledWith(expect.anything(), {ref: dead.ref});
  });

  test("no-ops without APNs credentials", async () => {
    const started = await startLiveActivity(deps({apnsAuth: null}), {
      appointmentId: "appt1", employeeDocId: "emp1", ctx: CTX, nowDate: NOW,
    });

    expect(started).toBe(0);
    expect(listPushToStartTokens).not.toHaveBeenCalled();
    expect(sendLiveActivityPush).not.toHaveBeenCalled();
  });

  test("swallows a registry failure rather than failing the sweep",
      async () => {
        listPushToStartTokens.mockRejectedValue(new Error("firestore down"));
        const d = deps();

        await expect(startLiveActivity(d, {
          appointmentId: "appt1", employeeDocId: "emp1", ctx: CTX, nowDate: NOW,
        })).resolves.toBe(0);
        expect(d.logger.warn).toHaveBeenCalled();
      });
});

describe("updateLiveActivity", () => {
  test("sends an update payload with no attributes", async () => {
    listUpdateTokens.mockResolvedValue([row()]);

    const updated = await updateLiveActivity(deps(), {
      appointmentId: "appt1", employeeDocId: "emp1", ctx: CTX, nowDate: NOW,
    });

    expect(updated).toBe(1);
    const {payload} = sendLiveActivityPush.mock.calls[0][0];
    expect(payload.aps.event).toBe("update");
    expect(payload.aps["attributes-type"]).toBeUndefined();
    // A reschedule keeps the marker's startTime authoritative so the on-site
    // backstop flips off the CURRENT start, not the stale one.
    expect(setCardStart).toHaveBeenCalledWith(
        expect.anything(),
        {employeeDocId: "emp1", startTime: START, phase: "travel"});
  });

  test("a reschedule rebuilds leaveAt from the marker's stored lead",
      async () => {
        // Regression: the reschedule hook passes leaveAt/travelMinutes null
        // (it has no Routes estimate), which used to make the card render the
        // NEW start time labelled "Leave at" — a whole drive-time late.
        listUpdateTokens.mockResolvedValue([row()]);
        readCardMarker.mockResolvedValue({
          employeeDocId: "emp1", appointmentId: "appt1", phase: "travel",
          leadMinutes: 28, travelMinutes: 18,
        });
        const movedTo = new Date("2026-07-19T14:00:00Z");

        await updateLiveActivity(deps(), {
          appointmentId: "appt1",
          employeeDocId: "emp1",
          ctx: {
            clientName: "Ada", address: "14 Elm St", startTime: movedTo,
            endTime: null, leaveAt: null, travelMinutes: null,
          },
          nowDate: NOW,
        });

        const state = sendLiveActivityPush.mock.calls[0][0]
            .payload.aps["content-state"];
        // 14:00Z minus the 28-minute lead the sweep measured.
        expect(state.leaveAt).toBe("2026-07-19T13:32:00.000Z");
        expect(state.timeLabel).toContain("Leave at");
        expect(state.timeLabel).not.toContain("Starts at");
        expect(state.driveLabel).toBe("About 18 min drive");
      });

  test("a reschedule with no recorded lead says Starts at, never Leave at",
      async () => {
        listUpdateTokens.mockResolvedValue([row()]);
        readCardMarker.mockResolvedValue({
          employeeDocId: "emp1", appointmentId: "appt1", phase: "travel",
        });

        await updateLiveActivity(deps(), {
          appointmentId: "appt1",
          employeeDocId: "emp1",
          ctx: {
            clientName: "Ada", address: "14 Elm St",
            startTime: new Date("2026-07-19T14:00:00Z"),
            endTime: null, leaveAt: null, travelMinutes: null,
          },
          nowDate: NOW,
        });

        const state = sendLiveActivityPush.mock.calls[0][0]
            .payload.aps["content-state"];
        expect(state.leaveAt).toBeNull();
        expect(state.timeLabel).toContain("Starts at");
        expect(state.timeLabel).not.toContain("Leave at");
      });

  test("flips to the on-site phase once startTime has passed", async () => {
    listUpdateTokens.mockResolvedValue([row()]);

    await updateLiveActivity(deps(), {
      appointmentId: "appt1",
      employeeDocId: "emp1",
      ctx: CTX,
      nowDate: new Date("2026-07-19T12:05:00Z"),
    });

    const {payload} = sendLiveActivityPush.mock.calls[0][0];
    expect(payload.aps["content-state"].phase).toBe("onSite");
    // Stamped so the backstop pass flips each card exactly once.
    expect(setCardStart).toHaveBeenCalledWith(
        expect.anything(),
        {employeeDocId: "emp1", startTime: START, phase: "onSite"});
  });

  test("leaves another job's live card alone", async () => {
    listUpdateTokens.mockResolvedValue([row()]);
    readCardMarker.mockResolvedValue({
      employeeDocId: "emp1", appointmentId: "someOtherJob", phase: "travel",
    });

    const updated = await updateLiveActivity(deps(), {
      appointmentId: "appt1", employeeDocId: "emp1", ctx: CTX, nowDate: NOW,
    });

    expect(updated).toBe(0);
    expect(sendLiveActivityPush).not.toHaveBeenCalled();
  });

  test("no-ops when the employee has no live card", async () => {
    listUpdateTokens.mockResolvedValue([row()]);
    readCardMarker.mockResolvedValue(null);

    const updated = await updateLiveActivity(deps(), {
      appointmentId: "appt1", employeeDocId: "emp1", ctx: CTX, nowDate: NOW,
    });

    expect(updated).toBe(0);
    expect(sendLiveActivityPush).not.toHaveBeenCalled();
  });
});

describe("endLiveActivity", () => {
  test("ends the card and drops its registry row and marker", async () => {
    const live = row();
    listUpdateTokens.mockResolvedValue([live]);

    const ended = await endLiveActivity(deps(), {
      appointmentId: "appt1", employeeDocId: "emp1", ctx: CTX, nowDate: NOW,
    });

    expect(ended).toBe(1);
    const {payload} = sendLiveActivityPush.mock.calls[0][0];
    expect(payload.aps.event).toBe("end");
    // Without a dismissal-date the card lingers up to four hours.
    expect(payload.aps["dismissal-date"])
        .toBe(Math.floor(NOW.getTime() / 1000));
    expect(deleteActivityToken)
        .toHaveBeenCalledWith(expect.anything(), {ref: live.ref});
    expect(clearCardMarker).toHaveBeenCalledWith(
        expect.anything(), {employeeDocId: "emp1"});
  });

  test("drops the row even when the end push fails", async () => {
    const live = row();
    listUpdateTokens.mockResolvedValue([live]);
    sendLiveActivityPush.mockResolvedValue({
      ok: false, status: 503, reason: "TooManyRequests", gone: false,
    });

    await endLiveActivity(deps(), {
      appointmentId: "appt1", employeeDocId: "emp1", ctx: CTX, nowDate: NOW,
    });

    expect(deleteActivityToken)
        .toHaveBeenCalledWith(expect.anything(), {ref: live.ref});
  });

  test("leaves another job's live card alone", async () => {
    listUpdateTokens.mockResolvedValue([row()]);
    readCardMarker.mockResolvedValue({
      employeeDocId: "emp1", appointmentId: "nextWeeksJob", phase: "travel",
    });

    const ended = await endLiveActivity(deps(), {
      appointmentId: "appt1", employeeDocId: "emp1", ctx: CTX, nowDate: NOW,
    });

    expect(ended).toBe(0);
    expect(sendLiveActivityPush).not.toHaveBeenCalled();
    expect(deleteActivityToken).not.toHaveBeenCalled();
  });
});
