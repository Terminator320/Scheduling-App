"use strict";

/**
 * Unit tests for the server-side widget payload builder. These mirror the
 * Dart widget_payload_test.dart cases (plus the Toronto day-boundary one) so
 * both builders and the Swift decoder stay in lockstep.
 */

const {
  buildWidgetPayload,
  serializeWidgetJob,
  isTerminalStatus,
} = require("../widget_payload_utils");

// Noon Toronto (EDT -4) on Wed 2026-07-08.
const NOW = new Date("2026-07-08T16:00:00.000Z");

const at = (iso) => new Date(iso);
const appt = (id, startIso, extra) => ({
  id,
  title: `Job ${id}`,
  clientName: "Client",
  startTime: at(startIso),
  endTime: at(new Date(at(startIso).getTime() + 3600000).toISOString()),
  status: "pending",
  ...(extra || {}),
});

describe("buildWidgetPayload", () => {
  test("todayJobs are future, non-terminal, and sorted", () => {
    const payload = buildWidgetPayload([
      appt("past", "2026-07-08T13:00:00.000Z"),
      appt("later", "2026-07-08T20:00:00.000Z"),
      appt("soon", "2026-07-08T18:00:00.000Z"),
      appt("done", "2026-07-08T19:00:00.000Z", {status: "done"}),
      appt("tomorrow", "2026-07-09T13:00:00.000Z"),
    ], NOW);

    expect(payload.todayJobs.map((j) => j.id)).toEqual(["soon", "later"]);
    expect(payload.tomorrowJobs.map((j) => j.id)).toEqual(["tomorrow"]);
    // an open job today means no rollover yet.
    expect(payload.rolloverAt).toBeNull();
  });

  test("each job carries its id and a …Z startTime for the deep link", () => {
    const payload = buildWidgetPayload([
      appt("soon", "2026-07-08T18:00:00.000Z"),
    ], NOW);
    expect(payload.todayJobs[0].id).toBe("soon");
    expect(payload.todayJobs[0].startTime).toBe("2026-07-08T18:00:00.000Z");
  });

  test("rolloverAt is last endTime + 1h once today is all complete", () => {
    const payload = buildWidgetPayload([
      appt("done", "2026-07-08T13:00:00.000Z", {
        status: "done",
        endTime: at("2026-07-08T14:00:00.000Z"),
      }),
      appt("tmwLater", "2026-07-09T18:00:00.000Z"),
      appt("tmwFirst", "2026-07-09T13:00:00.000Z"),
    ], NOW);
    expect(payload.rolloverAt).toBe("2026-07-08T15:00:00.000Z");
    expect(payload.todayJobs).toHaveLength(0);
    expect(payload.tomorrowJobs.map((j) => j.id)).toEqual(
        ["tmwFirst", "tmwLater"]);
    expect(payload.todayDate).toBe("2026-07-08T04:00:00.000Z");
    expect(payload.tomorrowDate).toBe("2026-07-09T04:00:00.000Z");
  });

  test("empty / all-cancelled today rolls over at start of today", () => {
    expect(buildWidgetPayload([], NOW).rolloverAt)
        .toBe("2026-07-08T04:00:00.000Z");
    const cancelled = buildWidgetPayload([
      appt("cxl", "2026-07-08T18:00:00.000Z", {status: "cancelled"}),
    ], NOW);
    expect(cancelled.rolloverAt).toBe("2026-07-08T04:00:00.000Z");
    expect(cancelled.todayJobs).toHaveLength(0);
  });

  test("the today cutoff is Toronto midnight, not UTC", () => {
    // 23:00 Toronto today (03:00Z the next day) still counts as today. 01:00
    // Toronto tomorrow (05:00Z) counts as tomorrow.
    const payload = buildWidgetPayload([
      appt("tonight", "2026-07-09T03:00:00.000Z"),
      appt("after-midnight", "2026-07-09T05:00:00.000Z"),
    ], NOW);
    expect(payload.todayJobs.map((j) => j.id)).toEqual(["tonight"]);
    expect(payload.tomorrowJobs.map((j) => j.id)).toEqual(["after-midnight"]);
  });

  test("locale is carried through", () => {
    expect(buildWidgetPayload([], NOW, "fr").locale).toBe("fr");
    expect(buildWidgetPayload([], NOW).locale).toBe("en");
  });
});

describe("serializeWidgetJob", () => {
  test("null string fields become empty strings (Swift non-optional decode)",
      () => {
        const job = serializeWidgetJob({
          id: "a1",
          startTime: at("2026-07-08T18:00:00.000Z"),
          clientName: null,
          title: null,
          address: null,
          status: null,
        });
        expect(job).toEqual({
          id: "a1",
          startTime: "2026-07-08T18:00:00.000Z",
          clientName: "",
          title: "",
          address: "",
          status: "pending",
        });
      });
});

describe("isTerminalStatus", () => {
  test("terminal set is done/completed/cancelled", () => {
    expect(isTerminalStatus("done")).toBe(true);
    expect(isTerminalStatus("COMPLETED")).toBe(true);
    expect(isTerminalStatus("cancelled")).toBe(true);
    expect(isTerminalStatus("pending")).toBe(false);
    expect(isTerminalStatus("in_progress")).toBe(false);
  });
});
