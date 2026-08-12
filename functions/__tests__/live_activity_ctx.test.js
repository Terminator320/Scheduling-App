"use strict";

/**
 * @fileoverview `liveActivityCtx` + `contextFor` — the two field-picked
 * payload builders that had NO coverage despite being documented owners.
 *
 * Both are consumed by code that field-picks their output a second time
 * (`buildContentState` from the ctx, `buildNotificationMessage` from the
 * message context), so a dropped key does not throw — the card silently
 * reads "Client" instead of the job's title, or a push loses its date range.
 * That is the exact failure mode the "one owner" rule was created to end, and
 * it is invisible without these assertions.
 */

const {
  liveActivityCtx,
  buildContentState,
  PHASE_TRAVEL,
} = require("../live_activity_utils");
const {contextFor} = require("../notification_policy");

const START = new Date("2026-08-12T13:00:00.000Z");
const END = new Date("2026-08-12T21:00:00.000Z");

const RECORD = {
  clientName: "Marchetti",
  title: "Water heater",
  address: "  12 Rue Principale  ",
  startTime: START,
  endTime: END,
  isAllDay: false,
  repeat: "none",
};

describe("liveActivityCtx", () => {
  test("carries every key buildContentState field-picks", () => {
    const ctx = liveActivityCtx(RECORD);

    // Named explicitly rather than snapshotted: the point is that each of
    // these survives the hand-off, so a future edit that drops one fails here
    // instead of degrading a card in production.
    expect(Object.keys(ctx).sort()).toEqual([
      "address",
      "clientName",
      "endTime",
      "leaveAt",
      "startTime",
      "title",
      "travelMinutes",
    ]);
  });

  test("normalizes the address, which the copies disagreed on", () => {
    expect(liveActivityCtx(RECORD).address).toBe("12 Rue Principale");
    expect(liveActivityCtx({}).address).toBe("");
  });

  test("a personal job's title reaches the card instead of \"Client\"", () => {
    // The whole reason `title` is in the ctx: a personal block has no client,
    // and the card read "Client" until it was threaded through.
    const personal = liveActivityCtx({
      title: "Dentist",
      startTime: START,
      endTime: END,
    });
    const state = buildContentState(personal, PHASE_TRAVEL, "en");

    expect(JSON.stringify(state)).toContain("Dentist");
    expect(JSON.stringify(state)).not.toContain("Client");
  });

  test("the travel overlay defaults to null rather than undefined", () => {
    // `undefined` drops out of JSON, so an on-site or terminal card would send
    // a payload missing the field instead of one that clears it.
    const ctx = liveActivityCtx(RECORD);
    expect(ctx.leaveAt).toBeNull();
    expect(ctx.travelMinutes).toBeNull();

    const withTravel =
      liveActivityCtx(RECORD, {leaveAt: START, travelMinutes: 20});
    expect(withTravel.travelMinutes).toBe(20);
  });

  test("a null record yields an empty ctx rather than throwing", () => {
    expect(liveActivityCtx(null)).toEqual({});
    expect(liveActivityCtx(undefined)).toEqual({});
  });
});

describe("contextFor", () => {
  test("carries every key the push and digest text reads", () => {
    expect(Object.keys(contextFor("assigned", null, RECORD)).sort()).toEqual([
      "address",
      "clientName",
      "endTime",
      "isAllDay",
      "repeat",
      "startTime",
      "title",
    ]);
  });

  test("cancelled and removed describe the job as it WAS", () => {
    const before = {...RECORD, clientName: "Before"};
    const after = {...RECORD, clientName: "After"};

    expect(contextFor("cancelled", before, after).clientName).toBe("Before");
    expect(contextFor("removed", before, after).clientName).toBe("Before");
    expect(contextFor("rescheduled", before, after).clientName).toBe("After");
  });

  test("isAllDay is a real boolean, never a truthy passthrough", () => {
    // `notification_messages` branches on it to drop the clock time, so a
    // missing field must read false rather than undefined.
    expect(contextFor("assigned", null, {}).isAllDay).toBe(false);
    expect(
        contextFor("assigned", null, {isAllDay: true}).isAllDay,
    ).toBe(true);
  });

  test("carries endTime, so a multi-day push can read a date range", () => {
    expect(contextFor("assigned", null, RECORD).endTime).toBe(END);
  });

  test("carries title, the personal-job fallback for a missing client", () => {
    expect(contextFor("assigned", null, {title: "Dentist"}).title)
        .toBe("Dentist");
  });
});
