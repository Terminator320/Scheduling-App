"use strict";

/**
 * The job time record (I18, 2026-09-01): `startedAt`/`completedAt` are stamped
 * SERVER-SIDE on the status transition, by the appointment write trigger, and
 * by nothing else.
 */

const {
  lifecycleStamps,
  isCrewCompletion,
  diffAppointmentForNotifications,
} = require("../notification_policy");
const {stampLifecycle} = require("../notification_utils");

const NOW = new Date("2026-09-01T14:00:00Z");
const LATER = new Date("2026-09-01T16:00:00Z");

const job = (over) => ({
  status: "pending",
  title: "Leak fix",
  clientName: "Acme",
  employeeIds: ["e1"],
  employeeNames: ["Marc"],
  startTime: new Date("2026-09-01T13:00:00Z"),
  endTime: new Date("2026-09-01T17:00:00Z"),
  ...over,
});

describe("lifecycleStamps", () => {
  test("pending -> in_progress stamps startedAt at now", () => {
    expect(lifecycleStamps(job(), job({status: "in_progress"}), NOW))
        .toEqual({startedAt: NOW});
  });

  test("pending -> done stamps completedAt only", () => {
    // A job closed without ever being started (the edit form's status picker, a
    // crew that never tapped Start) gets a finish and no start: inventing one
    // would put a wrong number on the record.
    expect(lifecycleStamps(job(), job({status: "done"}), NOW))
        .toEqual({completedAt: NOW});
  });

  test("the legacy completed alias is a completion", () => {
    expect(lifecycleStamps(job(), job({status: "completed"}), NOW))
        .toEqual({completedAt: NOW});
  });

  test("in_progress -> done stamps completedAt and leaves startedAt", () => {
    const before = job({status: "in_progress", startedAt: NOW});
    const after = job({status: "done", startedAt: NOW});
    expect(lifecycleStamps(before, after, LATER)).toEqual({completedAt: LATER});
  });

  test("a cancellation is never a completion", () => {
    expect(lifecycleStamps(job(), job({status: "cancelled"}), NOW))
        .toEqual({});
  });

  test("a re-save of a started job does not move its start", () => {
    const before = job({status: "in_progress", startedAt: NOW});
    const after = job({status: "in_progress", startedAt: NOW, title: "x"});
    expect(lifecycleStamps(before, after, LATER)).toEqual({});
  });

  test("a document created already in progress is stamped once", () => {
    expect(lifecycleStamps(null, job({status: "in_progress"}), NOW))
        .toEqual({startedAt: NOW});
  });

  test("a delete stamps nothing", () => {
    expect(lifecycleStamps(job({status: "done"}), null, NOW)).toEqual({});
  });

  test("a personal block and time off get no record", () => {
    expect(lifecycleStamps(
        job({isPersonal: true}),
        job({isPersonal: true, status: "in_progress"}),
        NOW,
    )).toEqual({});
    expect(lifecycleStamps(
        job({isPersonal: true, isDayOff: true}),
        job({isPersonal: true, isDayOff: true, status: "done"}),
        NOW,
    )).toEqual({});
  });

  test("a stamp already present is never overwritten", () => {
    // A console repair or an Admin-SDK backfill that set the field keeps its
    // value across the next status flip.
    const before = job();
    const after = job({status: "done", completedAt: LATER});
    expect(lifecycleStamps(before, after, NOW)).toEqual({});
  });
});

describe("the stamp-only rewrite is silent", () => {
  // What the trigger sees on its re-fire: the document the stamp just landed
  // on, differing from `before` by that field alone.
  const before = job({status: "done"});
  const after = job({status: "done", completedAt: NOW});

  test("decides no further stamp", () => {
    expect(lifecycleStamps(before, after, LATER)).toEqual({});
  });

  test("is not a completion for the office", () => {
    expect(isCrewCompletion(before, after)).toBe(false);
  });

  test("produces no crew-facing event", () => {
    expect(diffAppointmentForNotifications(before, after, NOW, "a1"))
        .toEqual([]);
  });

  test("the startedAt rewrite is silent the same way", () => {
    const b = job({status: "in_progress"});
    const a = job({status: "in_progress", startedAt: NOW});
    expect(lifecycleStamps(b, a, LATER)).toEqual({});
    expect(diffAppointmentForNotifications(b, a, NOW, "a1")).toEqual([]);
    expect(isCrewCompletion(b, a)).toBe(false);
  });
});

describe("stampLifecycle", () => {
  const makeDeps = (update) => {
    const doc = jest.fn(() => ({update}));
    return {
      deps: {
        db: {collection: jest.fn(() => ({doc}))},
        logger: {warn: jest.fn()},
        now: NOW,
      },
      doc,
    };
  };

  test("writes exactly the decided stamps to the appointment", async () => {
    const update = jest.fn(async () => {});
    const {deps, doc} = makeDeps(update);

    await stampLifecycle("a1", job(), job({status: "done"}), deps);

    expect(doc).toHaveBeenCalledWith("a1");
    expect(update).toHaveBeenCalledWith({completedAt: NOW});
  });

  test("writes nothing when there is nothing to stamp", async () => {
    const update = jest.fn(async () => {});
    const {deps} = makeDeps(update);

    await stampLifecycle("a1", job(), job({title: "renamed"}), deps);

    expect(deps.db.collection).not.toHaveBeenCalled();
    expect(update).not.toHaveBeenCalled();
  });

  test("never throws; a failed stamp is a warning", async () => {
    // The status change is already committed.
    const update = jest.fn(async () => {
      throw new Error("unavailable");
    });
    const {deps} = makeDeps(update);

    await expect(stampLifecycle("a1", job(), job({status: "done"}), deps))
        .resolves.toBeUndefined();
    expect(deps.logger.warn).toHaveBeenCalled();
  });
});
