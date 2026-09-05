"use strict";

const {planClientSortPatch} = require("../client_sort_backfill_policy");

describe("planClientSortPatch", () => {
  const now = new Date("2026-09-05T00:00:00Z");

  it("returns null for a doc that already has both fields", () => {
    expect(planClientSortPatch({jobCount: 3, createdAt: now}, now)).toBeNull();
  });

  it("stamps jobCount 0 when it is missing", () => {
    expect(planClientSortPatch({createdAt: now}, now)).toEqual({jobCount: 0});
  });

  it("stamps jobCount 0 when it is null", () => {
    expect(planClientSortPatch({jobCount: null, createdAt: now}, now))
        .toEqual({jobCount: 0});
  });

  it("stamps createdAt from the fallback when it is missing", () => {
    expect(planClientSortPatch({jobCount: 2}, now)).toEqual({createdAt: now});
  });

  it("stamps both when both are missing", () => {
    expect(planClientSortPatch({}, now)).toEqual({jobCount: 0, createdAt: now});
  });

  // A real count must never be overwritten by the backfill - the recount
  // trigger owns that number.
  it("never rewrites an existing non-zero jobCount", () => {
    expect(planClientSortPatch({jobCount: 7, createdAt: now}, now)).toBeNull();
  });

  it("treats an existing zero jobCount as already stamped", () => {
    expect(planClientSortPatch({jobCount: 0, createdAt: now}, now)).toBeNull();
  });
});
