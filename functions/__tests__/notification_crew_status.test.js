"use strict";

/**
 * The crew signal to the dispatcher (I18, 2026-09-01): "On my way" and
 * "Running late", the other operational signal that used to travel by phone
 * call. Same shape as the completion notice, and narrowed for the same
 * reasons — this reaches a Lock Screen.
 */

const {crewStatusSignal, CREW_STATUS_VALUES} =
  require("../notification_policy");
const {buildCrewStatusMessage} = require("../notification_messages");
const {notifyAdminsOfCrewStatus} = require("../notification_utils");

const job = (over) => ({
  status: "pending",
  title: "Leak fix",
  clientName: "Acme",
  employeeIds: ["e1", "e2"],
  employeeNames: ["Marc", "Nadia"],
  ...over,
});

describe("crewStatusSignal", () => {
  test("a fresh On my way is a signal", () => {
    expect(crewStatusSignal(
        job(),
        job({crewStatus: "onMyWay", crewStatusBy: "e1"}),
    )).toBe("onMyWay");
  });

  test("On my way -> Running late is a signal", () => {
    expect(crewStatusSignal(
        job({crewStatus: "onMyWay"}),
        job({crewStatus: "runningLate"}),
    )).toBe("runningLate");
  });

  test("the same value carried along by another write is silent", () => {
    // Every write to the document re-fires the trigger with the signal still
    // in `after` — a photo append, a client-edit propagation, an admin edit.
    expect(crewStatusSignal(
        job({crewStatus: "runningLate"}),
        job({crewStatus: "runningLate", title: "renamed"}),
    )).toBeNull();
  });

  test("an unknown value is not a signal", () => {
    expect(crewStatusSignal(job(), job({crewStatus: "teleporting"})))
        .toBeNull();
  });

  test("a closed job has nobody to be on the way to", () => {
    expect(crewStatusSignal(
        job({status: "done"}),
        job({status: "done", crewStatus: "onMyWay"}),
    )).toBeNull();
    expect(crewStatusSignal(
        job({status: "cancelled"}),
        job({status: "cancelled", crewStatus: "onMyWay"}),
    )).toBeNull();
  });

  test("a personal block is not work", () => {
    expect(crewStatusSignal(
        job({isPersonal: true}),
        job({isPersonal: true, crewStatus: "onMyWay"}),
    )).toBeNull();
  });

  test("a delete is silent", () => {
    expect(crewStatusSignal(job({crewStatus: "onMyWay"}), null)).toBeNull();
  });

  test("the vocabulary is exactly the two the rules admit", () => {
    expect([...CREW_STATUS_VALUES].sort()).toEqual(["onMyWay", "runningLate"]);
  });
});

describe("buildCrewStatusMessage", () => {
  test("names who and what, in both languages", () => {
    expect(buildCrewStatusMessage("onMyWay", "Marc", "Acme", "en").body)
        .toBe("Marc is on the way to Acme.");
    expect(buildCrewStatusMessage("runningLate", "Marc", "Acme", "en").body)
        .toBe("Marc is running late for Acme.");
    expect(buildCrewStatusMessage("onMyWay", "Marc", "Acme", "fr").body)
        .toBe("Marc est en route vers Acme.");
    expect(buildCrewStatusMessage("runningLate", "Marc", "Acme", "fr").body)
        .toBe("Marc est en retard pour Acme.");
  });

  test("the two kinds carry different titles", () => {
    expect(buildCrewStatusMessage("onMyWay", "M", "A", "en").title)
        .toBe("On the way");
    expect(buildCrewStatusMessage("runningLate", "M", "A", "en").title)
        .toBe("Running late");
  });

  test("falls back when the crew is unknown", () => {
    expect(buildCrewStatusMessage("runningLate", "", "Acme", "en").body)
        .toBe("Running late for Acme.");
  });

  test("falls back again when neither is known", () => {
    expect(buildCrewStatusMessage("onMyWay", "", "", "en").body)
        .toBe("A crew member is on the way.");
  });

  test("carries no address and no phone number", () => {
    const msg = buildCrewStatusMessage("onMyWay", "Marc", "Acme", "en");
    expect(JSON.stringify(msg)).not.toMatch(/\d{3}/);
  });
});

describe("notifyAdminsOfCrewStatus", () => {
  const makeDb = (admins) => ({
    collection: () => ({
      where: function where() {
        return this;
      },
      limit: function limit() {
        return this;
      },
      get: async () => ({
        size: admins.length,
        docs: admins.map((a) => ({id: a.id, data: () => a})),
      }),
    }),
  });

  test("does nothing at all when the write carries no signal", async () => {
    let queried = false;
    const deps = {
      db: {
        collection: () => {
          queried = true;
          return {where: () => ({}), limit: () => ({}), get: async () => ({})};
        },
      },
      messaging: {},
      logger: {warn: jest.fn()},
    };

    await notifyAdminsOfCrewStatus("a1", job(), job(), deps);

    expect(queried).toBe(false);
  });

  test("reads the active admin roster on a real signal", async () => {
    // The fan-out's own sendToEmployee then resolves each recipient's tokens;
    // with none registered nothing is delivered, which is the contract here.
    const admins = [{id: "admin-1", role: "admin", status: "active"}];
    const deps = {
      db: makeDb(admins),
      messaging: {},
      logger: {warn: jest.fn(), info: jest.fn()},
    };

    await expect(notifyAdminsOfCrewStatus(
        "a1",
        job(),
        job({crewStatus: "onMyWay", crewStatusBy: "e1"}),
        deps,
    )).resolves.toBeUndefined();
  });

  test("never throws, whatever the roster read does", async () => {
    const deps = {
      db: {
        collection: () => {
          throw new Error("unavailable");
        },
      },
      messaging: {},
      logger: {warn: jest.fn()},
    };

    await expect(notifyAdminsOfCrewStatus(
        "a1",
        job(),
        job({crewStatus: "runningLate", crewStatusBy: "e2"}),
        deps,
    )).resolves.toBeUndefined();
    expect(deps.logger.warn).toHaveBeenCalled();
  });
});
