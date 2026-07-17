jest.mock("firebase-admin/firestore");
jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  debug: jest.fn(),
  error: jest.fn(),
}));

const {getFirestore} = require("firebase-admin/firestore");
const {syncUsersByUid, shouldPurgePresence} = require("../bridge");

describe("shouldPurgePresence", () => {
  test("purges when the user doc is deleted", () => {
    expect(shouldPurgePresence({status: "active"}, null)).toBe(true);
  });
  test("purges when an active account is disabled", () => {
    expect(shouldPurgePresence(
        {status: "active"}, {status: "disabled"})).toBe(true);
  });
  test("does not purge on an active -> active update", () => {
    expect(shouldPurgePresence(
        {status: "active"}, {status: "active"})).toBe(false);
  });
  test("does not purge on invited -> active activation", () => {
    expect(shouldPurgePresence(
        {status: "invited"}, {status: "active"})).toBe(false);
  });
  test("does not purge on doc creation (no before)", () => {
    expect(shouldPurgePresence(null, {status: "active"})).toBe(false);
  });
});

describe("syncUsersByUid bridge/presence isolation", () => {
  const makeSnap = (data) => data === null ?
    {exists: false, data: () => null} :
    {exists: true, data: () => data};

  const makeEvent = (userId, before, after) => ({
    params: {userId},
    data: {before: makeSnap(before), after: makeSnap(after)},
  });

  let batch;
  let presenceDelete;
  let db;

  beforeEach(() => {
    jest.clearAllMocks();
    batch = {
      delete: jest.fn(),
      set: jest.fn(),
      commit: jest.fn().mockResolvedValue(undefined),
    };
    presenceDelete = jest.fn().mockRejectedValue(new Error("boom"));
    db = {
      collection: jest.fn(() => ({
        doc: jest.fn(() => ({delete: jest.fn().mockResolvedValue(undefined)})),
      })),
      batch: jest.fn(() => batch),
      doc: jest.fn(() => ({delete: presenceDelete})),
    };
    getFirestore.mockReturnValue(db);
  });

  test("bridge mirror writes even when the presence purge throws, " +
      "then the purge failure is rethrown for retry", async () => {
    const before = {uid: "auth1", status: "active", role: "employee"};
    const after = {uid: "auth1", status: "disabled", role: "employee"};

    await expect(
        syncUsersByUid.run(makeEvent("u_doc", before, after)),
    ).rejects.toThrow("boom");

    // Bridge mirror completed despite the failing purge.
    expect(batch.set).toHaveBeenCalledTimes(1);
    expect(batch.commit).toHaveBeenCalledTimes(1);
    // Purge was attempted against the correct path.
    expect(db.doc).toHaveBeenCalledWith("users/u_doc/presence/location");
    expect(presenceDelete).toHaveBeenCalledTimes(1);
    // And it ran strictly after the bridge write.
    expect(batch.commit.mock.invocationCallOrder[0])
        .toBeLessThan(presenceDelete.mock.invocationCallOrder[0]);
  });

  test("a successful presence purge resolves", async () => {
    const before = {uid: "auth1", status: "active", role: "employee"};
    const after = {uid: "auth1", status: "disabled", role: "employee"};
    presenceDelete.mockResolvedValue(undefined);

    await expect(
        syncUsersByUid.run(makeEvent("u_doc", before, after)),
    ).resolves.toBeUndefined();

    expect(batch.commit).toHaveBeenCalledTimes(1);
    expect(presenceDelete).toHaveBeenCalledTimes(1);
  });

  test("no presence purge on an active -> active update", async () => {
    const before = {uid: "auth1", status: "active", role: "employee"};
    const after = {uid: "auth1", status: "active", role: "employee"};

    await syncUsersByUid.run(makeEvent("u_doc", before, after));

    expect(batch.commit).toHaveBeenCalledTimes(1);
    expect(db.doc).not.toHaveBeenCalled();
    expect(presenceDelete).not.toHaveBeenCalled();
  });
});
