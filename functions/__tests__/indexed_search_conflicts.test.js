"use strict";

// The conflict rule is a DAILY-window overlap, mirrored from the Dart
// `dailyWindowsOverlap`. A raw instant test reports a 9-5 run across a week as
// clashing with a 7 pm job inside it — the phantom clash an admin then has to
// force through on every evening job.

const {blocksProposedWindow} = require("../indexed_search");
const {resolveWindow} = require("../day_slice_utils");

/**
 * @param {string} iso ISO instant.
 * @return {!Date}
 */
const at = (iso) => new Date(iso);

/**
 * @param {string} startIso
 * @param {string} endIso
 * @return {!{startMs: number, endMs: number, overnight: boolean}}
 */
function proposed(startIso, endIso) {
  return resolveWindow({startTime: at(startIso), endTime: at(endIso)});
}

describe("blocksProposedWindow", () => {
  test("a week-long 9-5 run does not block a 7 pm job inside it", () => {
    const run = {
      startTime: at("2026-09-07T13:00:00Z"),
      endTime: at("2026-09-11T21:00:00Z"),
    };
    expect(blocksProposedWindow(
        run,
        proposed("2026-09-09T23:00:00Z", "2026-09-10T00:00:00Z"),
    )).toBe(false);
  });

  test("the same run blocks a job inside one of its work windows", () => {
    const run = {
      startTime: at("2026-09-07T13:00:00Z"),
      endTime: at("2026-09-11T21:00:00Z"),
    };
    expect(blocksProposedWindow(
        run,
        proposed("2026-09-09T14:00:00Z", "2026-09-09T15:00:00Z"),
    )).toBe(true);
  });

  test("a same-day job that does not overlap is free", () => {
    const job = {
      startTime: at("2026-09-09T13:00:00Z"),
      endTime: at("2026-09-09T15:00:00Z"),
    };
    expect(blocksProposedWindow(
        job,
        proposed("2026-09-09T16:00:00Z", "2026-09-09T17:00:00Z"),
    )).toBe(false);
  });

  test("a record with no usable times blocks unconditionally", () => {
    // Fail closed: a legacy or console-written row must never quietly
    // disappear from a booking check.
    expect(blocksProposedWindow(
        {startTime: null, endTime: null},
        proposed("2026-09-09T16:00:00Z", "2026-09-09T17:00:00Z"),
    )).toBe(true);
    expect(blocksProposedWindow(
        {startTime: at("2026-09-09T13:00:00Z")},
        proposed("2026-09-09T16:00:00Z", "2026-09-09T17:00:00Z"),
    )).toBe(true);
  });
});
