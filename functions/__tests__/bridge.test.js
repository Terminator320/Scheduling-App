jest.mock("firebase-admin/firestore");
jest.mock("firebase-admin/auth");
jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  debug: jest.fn(),
  error: jest.fn(),
}));

const {getFirestore} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const {
  syncUsersByUid,
  shouldPurgePresence,
  authAccessChange,
  applyAuthAccess,
} = require("../bridge");

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

describe("authAccessChange", () => {
  test("revokes when an active account is disabled", () => {
    expect(authAccessChange({status: "active"}, {status: "disabled"}))
        .toBe("revoke");
  });
  test("revokes when the user doc is deleted", () => {
    expect(authAccessChange({status: "active"}, null)).toBe("revoke");
  });
  test("restores when a disabled account is reactivated", () => {
    expect(authAccessChange({status: "disabled"}, {status: "active"}))
        .toBe("restore");
  });
  test("restores on invited -> active first activation", () => {
    expect(authAccessChange({status: "invited"}, {status: "active"}))
        .toBe("restore");
  });
  test("restores on create of an active account", () => {
    expect(authAccessChange(null, {status: "active"})).toBe("restore");
  });
  test("does nothing on active -> active", () => {
    expect(authAccessChange({status: "active"}, {status: "active"}))
        .toBeNull();
  });
  test("does nothing on disabled -> disabled", () => {
    expect(authAccessChange({status: "disabled"}, {status: "disabled"}))
        .toBeNull();
  });
  test("does nothing on create of an invited account", () => {
    expect(authAccessChange(null, {status: "invited"})).toBeNull();
  });
});

describe("applyAuthAccess", () => {
  const makeAuth = () => ({
    updateUser: jest.fn().mockResolvedValue(undefined),
    revokeRefreshTokens: jest.fn().mockResolvedValue(undefined),
  });

  test("revoke disables the account AND revokes refresh tokens", async () => {
    const auth = makeAuth();
    await applyAuthAccess("uid-1", "revoke", auth);

    expect(auth.updateUser).toHaveBeenCalledWith("uid-1", {disabled: true});
    expect(auth.revokeRefreshTokens).toHaveBeenCalledWith("uid-1");
  });

  test("restore re-enables and does NOT revoke tokens", async () => {
    const auth = makeAuth();
    await applyAuthAccess("uid-1", "restore", auth);

    expect(auth.updateUser).toHaveBeenCalledWith("uid-1", {disabled: false});
    expect(auth.revokeRefreshTokens).not.toHaveBeenCalled();
  });

  test("a missing auth user is swallowed, not retried forever", async () => {
    const auth = makeAuth();
    const err = new Error("no user");
    err.code = "auth/user-not-found";
    auth.updateUser.mockRejectedValue(err);

    await expect(applyAuthAccess("gone", "revoke", auth)).resolves
        .toBeUndefined();
  });

  test("any other auth error propagates so the handler retries", async () => {
    const auth = makeAuth();
    auth.updateUser.mockRejectedValue(new Error("network"));

    await expect(applyAuthAccess("uid-1", "revoke", auth))
        .rejects.toThrow("network");
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
  let recursiveDeletes;
  let collectionDeletes;
  let auth;

  beforeEach(() => {
    jest.clearAllMocks();
    batch = {
      delete: jest.fn(),
      set: jest.fn(),
      commit: jest.fn().mockResolvedValue(undefined),
    };
    presenceDelete = jest.fn().mockRejectedValue(new Error("boom"));
    // recursiveDeletes records the collection paths passed to
    // db.recursiveDelete, and collectionDeletes records the deleted
    // doc-marker paths.
    recursiveDeletes = [];
    collectionDeletes = [];
    db = {
      collection: jest.fn((path) => ({
        path,
        doc: jest.fn((id) => ({
          delete: jest.fn(() => {
            collectionDeletes.push(`${path}/${id}`);
            return Promise.resolve(undefined);
          }),
        })),
      })),
      recursiveDelete: jest.fn((ref) => {
        recursiveDeletes.push(ref.path);
        return Promise.resolve(undefined);
      }),
      batch: jest.fn(() => batch),
      doc: jest.fn(() => ({delete: presenceDelete})),
    };
    getFirestore.mockReturnValue(db);
    auth = {
      updateUser: jest.fn().mockResolvedValue(undefined),
      revokeRefreshTokens: jest.fn().mockResolvedValue(undefined),
    };
    getAuth.mockReturnValue(auth);
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

  test("deactivation also purges push + Live Activity delivery state",
      async () => {
        const before = {uid: "auth1", status: "active", role: "employee"};
        const after = {uid: "auth1", status: "disabled", role: "employee"};
        presenceDelete.mockResolvedValue(undefined);

        await expect(
            syncUsersByUid.run(makeEvent("u_doc", before, after)),
        ).resolves.toBeUndefined();

        // Both token subcollections were recursively deleted — that's what
        // lets us paginate past the 500-write batch cap.
        expect(recursiveDeletes).toEqual([
          "users/u_doc/fcmTokens",
          "users/u_doc/liveActivityTokens",
        ]);
        // And the server-owned card marker was cleared.
        expect(collectionDeletes).toContain("liveActivityCards/u_doc");
      });

  test("deactivation disables the Auth account after the bridge write",
      async () => {
        const before = {uid: "auth1", status: "active", role: "employee"};
        const after = {uid: "auth1", status: "disabled", role: "employee"};
        presenceDelete.mockResolvedValue(undefined);

        await syncUsersByUid.run(makeEvent("u_doc", before, after));

        expect(auth.updateUser)
            .toHaveBeenCalledWith("auth1", {disabled: true});
        expect(auth.revokeRefreshTokens).toHaveBeenCalledWith("auth1");
        // Strictly after the auth-critical bridge mirror.
        expect(batch.commit.mock.invocationCallOrder[0])
            .toBeLessThan(auth.updateUser.mock.invocationCallOrder[0]);
      });

  test("reactivation re-enables the Auth account", async () => {
    const before = {uid: "auth1", status: "disabled", role: "employee"};
    const after = {uid: "auth1", status: "active", role: "employee"};

    await syncUsersByUid.run(makeEvent("u_doc", before, after));

    expect(auth.updateUser).toHaveBeenCalledWith("auth1", {disabled: false});
    expect(auth.revokeRefreshTokens).not.toHaveBeenCalled();
  });

  test("an active -> active update leaves the Auth account alone", async () => {
    const before = {uid: "auth1", status: "active", role: "employee"};
    const after = {uid: "auth1", status: "active", role: "employee"};

    await syncUsersByUid.run(makeEvent("u_doc", before, after));

    expect(auth.updateUser).not.toHaveBeenCalled();
  });

  test("a failing bridge write happens before any auth change", async () => {
    const before = {uid: "auth1", status: "active", role: "employee"};
    const after = {uid: "auth1", status: "disabled", role: "employee"};
    presenceDelete.mockRejectedValue(new Error("boom"));

    // The presence purge throws first, so the auth change never runs and the
    // retry re-runs both — neither step may be half-applied silently.
    await expect(
        syncUsersByUid.run(makeEvent("u_doc", before, after)),
    ).rejects.toThrow("boom");
    expect(auth.updateUser).not.toHaveBeenCalled();
  });

  test("no delivery-state purge on an active -> active update", async () => {
    const before = {uid: "auth1", status: "active", role: "employee"};
    const after = {uid: "auth1", status: "active", role: "employee"};

    await syncUsersByUid.run(makeEvent("u_doc", before, after));

    expect(recursiveDeletes).toEqual([]);
    expect(collectionDeletes).not.toContain("liveActivityCards/u_doc");
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
