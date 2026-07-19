"use strict";

/**
 * Unit tests for the travel-time "leave now" pure helpers and the injectable
 * sweep orchestration (runTravelAwareReminderSweep).
 */

const {
  decideOrigin,
  selectTravelCandidates,
  computeLeadMinutes,
  isDue,
  buildRoutesRequestBody,
  parseRoutesDurationSeconds,
  computeTravelSeconds,
  travelReminderLedgerId,
  runTravelAwareReminderSweep,
} = require("../travel_utils");

// Noon Toronto (EDT -4) on Wed 2026-07-08.
const NOW = new Date("2026-07-08T16:00:00.000Z");
const HOUR = 60 * 60 * 1000;
const MIN = 60 * 1000;

const future = (ms) => new Date(NOW.getTime() + ms);

const silentLogger = {warn: () => {}, info: () => {}, error: () => {}};

// ----- decideOrigin ---------------------------------------------------------

describe("decideOrigin", () => {
  const candidate = {id: "cand", startTime: future(60 * MIN)};
  const freshPresence = {lat: 45.5, lng: -73.6, updatedAt: future(-5 * MIN)};
  const interveningJob = {
    id: "current",
    status: "in_progress",
    startTime: future(-30 * MIN),
    endTime: future(15 * MIN),
    address: "10 Current St",
  };

  test("intervening appointment beats fresh GPS", () => {
    const got = decideOrigin({
      presence: freshPresence,
      employeeAppointments: [interveningJob],
      candidate,
      now: NOW,
    });
    expect(got).toEqual({kind: "address", address: "10 Current St"});
  });

  test("an intervening job marked done is skipped (GPS takes over)", () => {
    const got = decideOrigin({
      presence: freshPresence,
      employeeAppointments: [{...interveningJob, status: "done"}],
      candidate,
      now: NOW,
    });
    expect(got).toEqual({kind: "gps", lat: 45.5, lng: -73.6});
  });

  test("a cancelled intervening job is skipped", () => {
    const got = decideOrigin({
      presence: freshPresence,
      employeeAppointments: [{...interveningJob, status: "cancelled"}],
      candidate,
      now: NOW,
    });
    expect(got.kind).toBe("gps");
  });

  test("an intervening job with an empty address is skipped", () => {
    const got = decideOrigin({
      presence: freshPresence,
      employeeAppointments: [{...interveningJob, address: "  "}],
      candidate,
      now: NOW,
    });
    expect(got.kind).toBe("gps");
  });

  test("the candidate itself never counts as intervening", () => {
    const got = decideOrigin({
      presence: freshPresence,
      employeeAppointments: [{...interveningJob, id: "cand"}],
      candidate,
      now: NOW,
    });
    expect(got.kind).toBe("gps");
  });

  test("with two intervening jobs the latest-starting wins", () => {
    const earlier = {...interveningJob, id: "a", startTime: future(-2 * HOUR),
      address: "1 Early St"};
    const later = {...interveningJob, id: "b", startTime: future(-10 * MIN),
      address: "2 Late St"};
    const got = decideOrigin({
      presence: null,
      employeeAppointments: [earlier, later],
      candidate,
      now: NOW,
    });
    expect(got).toEqual({kind: "address", address: "2 Late St"});
  });

  test("presence exactly 25 min old is still fresh", () => {
    const got = decideOrigin({
      presence: {lat: 1, lng: 2, updatedAt: future(-25 * MIN)},
      employeeAppointments: [],
      candidate,
      now: NOW,
    });
    expect(got).toEqual({kind: "gps", lat: 1, lng: 2});
  });

  test("presence older than 25 min is stale", () => {
    const got = decideOrigin({
      presence: {lat: 1, lng: 2, updatedAt: future(-26 * MIN)},
      employeeAppointments: [],
      candidate,
      now: NOW,
    });
    expect(got).toBeNull();
  });

  test("presence with non-numeric coordinates is ignored", () => {
    const got = decideOrigin({
      presence: {lat: "45.5", lng: -73.6, updatedAt: future(-5 * MIN)},
      employeeAppointments: [],
      candidate,
      now: NOW,
    });
    expect(got).toBeNull();
  });

  test("stale GPS falls back to a recently-ended previous job", () => {
    const prev = {id: "prev", status: "done", startTime: future(-3 * HOUR),
      endTime: future(-30 * MIN), address: "5 Prev Ave"};
    const got = decideOrigin({
      presence: {lat: 1, lng: 2, updatedAt: future(-2 * HOUR)},
      employeeAppointments: [prev],
      candidate,
      now: NOW,
    });
    expect(got).toEqual({kind: "address", address: "5 Prev Ave"});
  });

  test("a done previous job counts (the employee was physically there)", () => {
    const prev = {id: "prev", status: "done", endTime: future(-30 * MIN),
      startTime: future(-2 * HOUR), address: "5 Prev Ave"};
    const got = decideOrigin({
      presence: null,
      employeeAppointments: [prev],
      candidate,
      now: NOW,
    });
    expect(got).toEqual({kind: "address", address: "5 Prev Ave"});
  });

  test("a cancelled previous job never counts (visit never happened)", () => {
    const prev = {id: "prev", status: "cancelled", endTime: future(-30 * MIN),
      startTime: future(-2 * HOUR), address: "5 Prev Ave"};
    expect(decideOrigin({
      presence: null,
      employeeAppointments: [prev],
      candidate,
      now: NOW,
    })).toBeNull();
  });

  test("a previous job outside the 4-h lookback is skipped", () => {
    const prev = {id: "prev", status: "done", endTime: future(-5 * HOUR),
      startTime: future(-7 * HOUR), address: "5 Prev Ave"};
    expect(decideOrigin({
      presence: null,
      employeeAppointments: [prev],
      candidate,
      now: NOW,
    })).toBeNull();
  });

  test("a previous job with an empty address is skipped", () => {
    const prev = {id: "prev", status: "done", endTime: future(-30 * MIN),
      startTime: future(-2 * HOUR), address: ""};
    expect(decideOrigin({
      presence: null,
      employeeAppointments: [prev],
      candidate,
      now: NOW,
    })).toBeNull();
  });

  test("with two previous jobs the newest endTime wins", () => {
    const older = {id: "a", status: "done", endTime: future(-3 * HOUR),
      startTime: future(-4 * HOUR), address: "1 Old St"};
    const newer = {id: "b", status: "done", endTime: future(-20 * MIN),
      startTime: future(-1 * HOUR), address: "2 New St"};
    const got = decideOrigin({
      presence: null,
      employeeAppointments: [older, newer],
      candidate,
      now: NOW,
    });
    expect(got).toEqual({kind: "address", address: "2 New St"});
  });

  test("nothing available -> null (fixed 30-min fallback)", () => {
    expect(decideOrigin({
      presence: null,
      employeeAppointments: [],
      candidate,
      now: NOW,
    })).toBeNull();
  });
});

// ----- pure helpers ---------------------------------------------------------

describe("selectTravelCandidates", () => {
  const rec = (id, ms, status = "pending") => ({
    id,
    status,
    startTime: future(ms),
  });

  test("keeps pending-like jobs starting within (now, now+90min]", () => {
    const got = selectTravelCandidates(
        [
          rec("in20", 20 * MIN),
          rec("edge90", 90 * MIN),
          rec("out91", 91 * MIN),
          rec("started", -5 * MIN),
          rec("nowJob", 0),
          rec("inProgress", 10 * MIN, "in_progress"),
          rec("done", 10 * MIN, "done"),
          rec("cxl", 10 * MIN, "cancelled"),
          rec("legacy", 15 * MIN, "confirmed"),
        ],
        NOW,
    );
    expect(got.map((r) => r.id).sort()).toEqual(["edge90", "in20", "legacy"]);
  });
});

describe("computeLeadMinutes", () => {
  test("rounds the drive up and adds the 10-min buffer", () => {
    expect(computeLeadMinutes(601)).toBe(21);
    expect(computeLeadMinutes(600)).toBe(20);
  });

  test("caps at 90", () => {
    expect(computeLeadMinutes(2 * 60 * 60)).toBe(90);
  });

  test("null / garbage -> the fixed 30-min fallback", () => {
    expect(computeLeadMinutes(null)).toBe(30);
    expect(computeLeadMinutes(NaN)).toBe(30);
    expect(computeLeadMinutes(-5)).toBe(30);
  });
});

describe("isDue", () => {
  const startTimeMillis = NOW.getTime() + 20 * MIN;

  test("true exactly at startTime - lead", () => {
    expect(isDue({startTimeMillis, leadMinutes: 20,
      nowMillis: NOW.getTime()})).toBe(true);
  });

  test("false one ms before the leave instant", () => {
    expect(isDue({startTimeMillis, leadMinutes: 20,
      nowMillis: NOW.getTime() - 1})).toBe(false);
  });
});

describe("buildRoutesRequestBody", () => {
  test("gps origin becomes a latLng waypoint", () => {
    const body = buildRoutesRequestBody({
      origin: {kind: "gps", lat: 45.5, lng: -73.6},
      destinationAddress: "123 Main St",
      departureTimeIso: "2026-07-08T16:01:00.000Z",
    });
    expect(body).toEqual({
      origin: {location: {latLng: {latitude: 45.5, longitude: -73.6}}},
      destination: {address: "123 Main St"},
      travelMode: "DRIVE",
      routingPreference: "TRAFFIC_AWARE",
      departureTime: "2026-07-08T16:01:00.000Z",
    });
  });

  test("address origin stays a raw address string", () => {
    const body = buildRoutesRequestBody({
      origin: {kind: "address", address: "10 Current St"},
      destinationAddress: "123 Main St",
      departureTimeIso: "2026-07-08T16:01:00.000Z",
    });
    expect(body.origin).toEqual({address: "10 Current St"});
  });
});

describe("parseRoutesDurationSeconds", () => {
  test("parses the '1234s' shape", () => {
    expect(parseRoutesDurationSeconds({routes: [{duration: "1234s"}]}))
        .toBe(1234);
    expect(parseRoutesDurationSeconds({routes: [{duration: "1234.5s"}]}))
        .toBe(1235);
  });

  test("null on missing or garbage shapes", () => {
    expect(parseRoutesDurationSeconds(null)).toBeNull();
    expect(parseRoutesDurationSeconds({})).toBeNull();
    expect(parseRoutesDurationSeconds({routes: []})).toBeNull();
    expect(parseRoutesDurationSeconds({routes: [{}]})).toBeNull();
    expect(parseRoutesDurationSeconds({routes: [{duration: 1234}]}))
        .toBeNull();
    expect(parseRoutesDurationSeconds({routes: [{duration: "12m"}]}))
        .toBeNull();
  });
});

describe("computeTravelSeconds", () => {
  const args = {
    apiKey: "k",
    origin: {kind: "address", address: "A"},
    destinationAddress: "B",
    now: NOW,
    logger: silentLogger,
  };

  test("200 happy path returns parsed seconds", async () => {
    const fetchImpl = jest.fn(async () => ({
      ok: true,
      status: 200,
      json: async () => ({routes: [{duration: "900s"}]}),
    }));
    await expect(computeTravelSeconds({...args, fetchImpl})).resolves.toBe(900);
    const [url, init] = fetchImpl.mock.calls[0];
    expect(url).toContain("routes.googleapis.com");
    expect(init.headers["X-Goog-FieldMask"]).toBe("routes.duration");
  });

  test("non-200 -> null", async () => {
    const fetchImpl = async () => ({
      ok: false,
      status: 403,
      text: async () => "denied",
    });
    await expect(computeTravelSeconds({...args, fetchImpl})).resolves
        .toBeNull();
  });

  test("transport throw -> null", async () => {
    const fetchImpl = async () => {
      throw new Error("boom");
    };
    await expect(computeTravelSeconds({...args, fetchImpl})).resolves
        .toBeNull();
  });

  test("invalid JSON -> null", async () => {
    const fetchImpl = async () => ({
      ok: true,
      status: 200,
      json: async () => {
        throw new Error("bad json");
      },
    });
    await expect(computeTravelSeconds({...args, fetchImpl})).resolves
        .toBeNull();
  });
});

describe("travelReminderLedgerId", () => {
  test("matches the push plan's per-recipient reminder key shape", () => {
    expect(travelReminderLedgerId("a", 123, "e1")).toBe("a_123_e1");
  });
});

// ----- sweep orchestration with mocks ---------------------------------------

/**
 * Minimal Firestore mock for the travel sweep: candidate query vs
 * per-employee context query are told apart by their where() fields, presence
 * docs resolve through db.getAll, and the reminder ledger supports the
 * pre-check get + atomic create + release delete.
 * @param {!Object} config users/tokens/appointments/context/presence/
 *   ledgerExisting/throwLedgerGetFor fixtures.
 * @return {!Object} `{db, ledgerCreates, ledgerDeletes}`.
 */
function makeTravelDb(config) {
  const ledgerCreates = [];
  const ledgerDeletes = [];
  const existing = new Set(config.ledgerExisting || []);
  const db = {
    getAll: async (...refs) => refs.map((ref) => {
      const p = (config.presence || {})[ref._employeeId];
      return {exists: !!p, data: () => p};
    }),
    collection(name) {
      if (name === "users") {
        return {
          doc(id) {
            return {
              get: async () => ({
                exists: !!(config.users || {})[id],
                data: () => (config.users || {})[id],
              }),
              collection(sub) {
                if (sub === "presence") {
                  return {doc: () => ({_employeeId: id})};
                }
                return {
                  get: async () => ({
                    docs: ((config.tokens || {})[id] || []).map((t) => ({
                      id: t.id,
                      data: () => ({locale: t.locale}),
                      ref: {delete: async () => {}},
                    })),
                  }),
                };
              },
            };
          },
        };
      }
      if (name === "appointments") {
        const wheres = [];
        const q = {
          where(field, op, value) {
            wheres.push({field, op, value});
            return q;
          },
          orderBy() {
            return q;
          },
          limit() {
            return q;
          },
          get: async () => {
            const byEmployee = wheres.find((w) => w.field === "employeeIds");
            const rows = byEmployee ?
                ((config.context || {})[byEmployee.value] || []) :
                (config.appointments || []);
            return {docs: rows.map((r) => ({id: r.id, data: () => r}))};
          },
        };
        return q;
      }
      if (name === "appointmentReminders") {
        return {
          doc(id) {
            const key = `${name}/${id}`;
            return {
              get: async () => {
                if (config.throwLedgerGetFor === id) {
                  throw new Error("ledger get boom");
                }
                return {exists: existing.has(key)};
              },
              create: async (data) => {
                if (existing.has(key)) {
                  const e = new Error("exists");
                  e.code = 6;
                  throw e;
                }
                ledgerCreates.push({key, data});
              },
              delete: async () => {
                ledgerDeletes.push(key);
              },
            };
          },
        };
      }
      return {doc: () => ({})};
    },
  };
  return {db, ledgerCreates, ledgerDeletes};
}

/**
 * Messaging mock whose sendEach records the messages it receives.
 * @return {!Object} `{sent, sendEach}`.
 */
function makeMessaging() {
  const sent = [];
  return {
    sent,
    sendEach: async (messages) => {
      sent.push(...messages);
      return {responses: messages.map(() => ({success: true}))};
    },
  };
}

const okFetch = (seconds) => jest.fn(async () => ({
  ok: true,
  status: 200,
  json: async () => ({routes: [{duration: `${seconds}s`}]}),
}));

describe("runTravelAwareReminderSweep", () => {
  const job = {
    id: "job1",
    status: "pending",
    startTime: future(20 * MIN),
    employeeIds: ["e1"],
    clientName: "Acme",
    address: "123 Main St",
  };
  const startMs = future(20 * MIN).getTime();
  const activeE1 = {
    users: {e1: {role: "employee", status: "active"}},
    tokens: {e1: [{id: "t", locale: "en"}]},
  };

  test("fresh GPS -> Routes -> due leaveNow push, travel body", async () => {
    const {db, ledgerCreates} = makeTravelDb({
      ...activeE1,
      appointments: [job],
      presence: {e1: {lat: 45.5, lng: -73.6, updatedAt: future(-5 * MIN)}},
    });
    const messaging = makeMessaging();
    const fetchImpl = okFetch(600); // 10-min drive -> lead 20 -> due now.
    const res = await runTravelAwareReminderSweep({
      db, messaging, fetchImpl, apiKey: "k", now: NOW, logger: silentLogger,
    });
    expect(res.reminded).toBe(1);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    const body = JSON.parse(fetchImpl.mock.calls[0][1].body);
    expect(body.origin.location.latLng.latitude).toBe(45.5);
    expect(ledgerCreates.map((c) => c.key))
        .toEqual([`appointmentReminders/${
          travelReminderLedgerId("job1", startMs, "e1")}`]);
    expect(messaging.sent).toHaveLength(1);
    const msg = messaging.sent[0];
    expect(msg.data.kind).toBe("leaveNow");
    expect(msg.notification.title).toBe("Time to leave — Acme at 12:20 p.m.");
    expect(msg.notification.body).toBe("About 10 min drive · 123 Main St");
    expect(msg.apns.payload.aps["interruption-level"])
        .toBe("time-sensitive");
  });

  test("a not-yet-due job burns no ledger claim", async () => {
    const farJob = {...job, id: "far", startTime: future(80 * MIN)};
    const {db, ledgerCreates} = makeTravelDb({
      ...activeE1,
      appointments: [farJob],
      presence: {e1: {lat: 45.5, lng: -73.6, updatedAt: future(-5 * MIN)}},
    });
    const messaging = makeMessaging();
    const res = await runTravelAwareReminderSweep({
      db, messaging, fetchImpl: okFetch(600), apiKey: "k", now: NOW,
      logger: silentLogger,
    });
    expect(res.reminded).toBe(0);
    expect(ledgerCreates).toEqual([]);
    expect(messaging.sent).toEqual([]);
  });

  test("Routes failure degrades to the fixed 30-min plain reminder",
      async () => {
        const {db} = makeTravelDb({
          ...activeE1,
          appointments: [job],
          presence: {e1: {lat: 45.5, lng: -73.6,
            updatedAt: future(-5 * MIN)}},
        });
        const messaging = makeMessaging();
        const fetchImpl = async () => ({
          ok: false, status: 500, text: async () => "boom",
        });
        const res = await runTravelAwareReminderSweep({
          db, messaging, fetchImpl, apiKey: "k", now: NOW,
          logger: silentLogger,
        });
        // Job at +20 min, fallback lead 30 -> due.
        expect(res.reminded).toBe(1);
        const msg = messaging.sent[0];
        expect(msg.data.kind).toBe("reminder");
        expect(msg.notification.title).toBe("Upcoming job");
        expect(msg.apns.payload.aps["interruption-level"]).toBeUndefined();
      });

  test("no origin and no address -> plain fallback without any fetch",
      async () => {
        const bare = {...job, address: ""};
        const {db} = makeTravelDb({
          ...activeE1,
          appointments: [bare],
        });
        const messaging = makeMessaging();
        const fetchImpl = jest.fn();
        const res = await runTravelAwareReminderSweep({
          db, messaging, fetchImpl, apiKey: "k", now: NOW,
          logger: silentLogger,
        });
        expect(res.reminded).toBe(1);
        expect(fetchImpl).not.toHaveBeenCalled();
        expect(messaging.sent[0].data.kind).toBe("reminder");
      });

  test("an existing ledger doc short-circuits before any Routes spend",
      async () => {
        const {db, ledgerCreates} = makeTravelDb({
          ...activeE1,
          appointments: [job],
          presence: {e1: {lat: 45.5, lng: -73.6,
            updatedAt: future(-5 * MIN)}},
          ledgerExisting: [`appointmentReminders/${
            travelReminderLedgerId("job1", startMs, "e1")}`],
        });
        const messaging = makeMessaging();
        const fetchImpl = jest.fn();
        const res = await runTravelAwareReminderSweep({
          db, messaging, fetchImpl, apiKey: "k", now: NOW,
          logger: silentLogger,
        });
        expect(res.reminded).toBe(0);
        expect(fetchImpl).not.toHaveBeenCalled();
        expect(ledgerCreates).toEqual([]);
        expect(messaging.sent).toEqual([]);
      });

  test("an intervening job's address is the Routes origin, not GPS",
      async () => {
        const {db} = makeTravelDb({
          ...activeE1,
          appointments: [job],
          presence: {e1: {lat: 45.5, lng: -73.6,
            updatedAt: future(-5 * MIN)}},
          context: {e1: [{
            id: "current",
            status: "in_progress",
            startTime: future(-30 * MIN),
            endTime: future(10 * MIN),
            address: "10 Current St",
          }]},
        });
        const messaging = makeMessaging();
        const fetchImpl = okFetch(600);
        await runTravelAwareReminderSweep({
          db, messaging, fetchImpl, apiKey: "k", now: NOW,
          logger: silentLogger,
        });
        const body = JSON.parse(fetchImpl.mock.calls[0][1].body);
        expect(body.origin).toEqual({address: "10 Current St"});
      });

  test("one throwing pair doesn't stop the others", async () => {
    const other = {...job, id: "job2"};
    const {db} = makeTravelDb({
      ...activeE1,
      appointments: [job, other],
      presence: {e1: {lat: 45.5, lng: -73.6, updatedAt: future(-5 * MIN)}},
      throwLedgerGetFor: travelReminderLedgerId("job1", startMs, "e1"),
    });
    const messaging = makeMessaging();
    const res = await runTravelAwareReminderSweep({
      db, messaging, fetchImpl: okFetch(600), apiKey: "k", now: NOW,
      logger: silentLogger,
    });
    expect(res.reminded).toBe(1);
    expect(messaging.sent[0].data.appointmentId).toBe("job2");
  });

  test("multi-assignee job earns one per-recipient claim each", async () => {
    const shared = {...job, employeeIds: ["e1", "e2"]};
    const {db, ledgerCreates} = makeTravelDb({
      users: {
        e1: {role: "employee", status: "active"},
        e2: {role: "employee", status: "active"},
      },
      tokens: {
        e1: [{id: "t1", locale: "en"}],
        e2: [{id: "t2", locale: "fr"}],
      },
      appointments: [shared],
      presence: {e1: {lat: 45.5, lng: -73.6, updatedAt: future(-5 * MIN)}},
    });
    const messaging = makeMessaging();
    const res = await runTravelAwareReminderSweep({
      db, messaging, fetchImpl: okFetch(600), apiKey: "k", now: NOW,
      logger: silentLogger,
    });
    expect(res.reminded).toBe(2);
    expect(ledgerCreates.map((c) => c.key).sort()).toEqual([
      `appointmentReminders/${
        travelReminderLedgerId("job1", startMs, "e1")}`,
      `appointmentReminders/${
        travelReminderLedgerId("job1", startMs, "e2")}`,
    ]);
    // e2 has no fresh GPS and no context -> 30-min fallback, FR locale.
    const frMsg = messaging.sent.find((m) => m.token === "t2");
    expect(frMsg.data.kind).toBe("reminder");
    expect(frMsg.notification.title).toBe("Visite à venir");
  });
});
