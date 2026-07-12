"use strict";

/**
 * Unit tests for the server-side widget payload builder. Mirrors the Dart
 * widget_payload_test.dart cases so the two builders (and the Swift decoder)
 * stay in lockstep, plus the Toronto day-boundary the server uses.
 */

const {
  buildWidgetPayload,
  serializeWidgetJob,
  isTerminalStatus,
  torontoDayEndMs,
} = require("../widget_payload_utils");

// Noon Toronto (EDT -4) on Wed 2026-07-08.
const NOW = new Date("2026-07-08T16:00:00.000Z");

const at = (iso) => new Date(iso);
const appt = (id, startIso, extra) => ({
  id,
  title: `Job ${id}`,
  clientName: "Client",
  startTime: at(startIso),
  status: "pending",
  ...(extra || {}),
});

describe("buildWidgetPayload", () => {
  test("today's remaining jobs are future, non-terminal, and sorted", () => {
    const payload = buildWidgetPayload([
      appt("past", "2026-07-08T13:00:00.000Z"),
      appt("later", "2026-07-08T20:00:00.000Z"),
      appt("soon", "2026-07-08T18:00:00.000Z"),
      appt("done", "2026-07-08T19:00:00.000Z", {status: "done"}),
      appt("tomorrow", "2026-07-09T13:00:00.000Z"),
    ], NOW);

    expect(payload.todayCount).toBe(2);
    expect(payload.jobs.map((j) => j.id)).toEqual(["soon", "later"]);
  });

  test("each job carries its id and a …Z startTime for the deep link", () => {
    const payload = buildWidgetPayload([
      appt("soon", "2026-07-08T18:00:00.000Z"),
    ], NOW);
    expect(payload.jobs[0].id).toBe("soon");
    expect(payload.jobs[0].startTime).toBe("2026-07-08T18:00:00.000Z");
    expect(payload.nextJob.id).toBe("soon");
  });

  test("nextJob can be on a later day when today has none left", () => {
    const payload = buildWidgetPayload([
      appt("past", "2026-07-08T13:00:00.000Z"),
      appt("tomorrow", "2026-07-09T13:00:00.000Z"),
    ], NOW);
    expect(payload.todayCount).toBe(0);
    expect(payload.jobs).toHaveLength(0);
    expect(payload.nextJob.id).toBe("tomorrow");
  });

  test("no upcoming jobs yields a null nextJob", () => {
    const payload = buildWidgetPayload([
      appt("past", "2026-07-08T13:00:00.000Z"),
    ], NOW);
    expect(payload.nextJob).toBeNull();
  });

  test("cancelled and completed jobs are excluded", () => {
    const payload = buildWidgetPayload([
      appt("cxl", "2026-07-08T18:00:00.000Z", {status: "cancelled"}),
      appt("cmp", "2026-07-08T19:00:00.000Z", {status: "completed"}),
    ], NOW);
    expect(payload.jobs).toHaveLength(0);
    expect(payload.nextJob).toBeNull();
  });

  test("the today cutoff is Toronto midnight, not UTC", () => {
    // 23:00 Toronto today (03:00Z next day) is still today; 01:00 Toronto
    // tomorrow (05:00Z) is not — it only surfaces as nextJob.
    const payload = buildWidgetPayload([
      appt("tonight", "2026-07-09T03:00:00.000Z"),
      appt("after-midnight", "2026-07-09T05:00:00.000Z"),
    ], NOW);
    expect(payload.jobs.map((j) => j.id)).toEqual(["tonight"]);
    expect(payload.todayCount).toBe(1);
    expect(payload.nextJob.id).toBe("tonight");
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

describe("isTerminalStatus / torontoDayEndMs", () => {
  test("terminal set is done/completed/cancelled", () => {
    expect(isTerminalStatus("done")).toBe(true);
    expect(isTerminalStatus("COMPLETED")).toBe(true);
    expect(isTerminalStatus("cancelled")).toBe(true);
    expect(isTerminalStatus("pending")).toBe(false);
    expect(isTerminalStatus("in_progress")).toBe(false);
  });

  test("Toronto day end for a summer (EDT) noon is next 04:00Z", () => {
    expect(new Date(torontoDayEndMs(NOW)).toISOString())
        .toBe("2026-07-09T04:00:00.000Z");
  });
});
