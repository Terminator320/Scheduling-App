"use strict";

/**
 * Unit tests for the push-notification pure helpers and the injectable
 * orchestration (handleAppointmentWrite / runDailyDigest / overdue sweep).
 */

const {
  diffAppointmentForNotifications,
  buildNotificationMessage,
  buildDigestMessage,
  selectOverdueCandidates,
  groupTomorrowsJobsByEmployee,
  tomorrowWindowToronto,
  overduePromptLedgerId,
  isStaleTokenError,
  handleAppointmentWrite,
  runDailyDigest,
  runOverduePromptSweep,
  OPEN_STATUSES,
  SERIES_CLAIM_WINDOW_MS,
} = require("../notification_utils");

// Noon Toronto (EDT -4) on Wed 2026-07-08.
const NOW = new Date("2026-07-08T16:00:00.000Z");
const HOUR = 60 * 60 * 1000;
const MIN = 60 * 1000;

const future = (ms) => new Date(NOW.getTime() + ms);
const kinds = (evs) => evs.map((e) => `${e.employeeDocId}:${e.kind}`).sort();

describe("diffAppointmentForNotifications", () => {
  test("created assigns every employee", () => {
    const evs = diffAppointmentForNotifications(
        null,
        {employeeIds: ["e1", "e2"], startTime: future(3 * HOUR)},
        NOW,
    );
    expect(kinds(evs)).toEqual(["e1:assigned", "e2:assigned"]);
  });

  test("created already cancelled emits nothing", () => {
    const evs = diffAppointmentForNotifications(
        null,
        {employeeIds: ["e1"], startTime: future(3 * HOUR), status: "cancelled"},
        NOW,
    );
    expect(evs).toEqual([]);
  });

  test("cancelling a multi-day run mid-flight still tells the crew", () => {
    // The gate is the run's END, not its start. Gating on the start meant a
    // job cancelled on day 4 of 10 pushed nothing and the crew turned up.
    const run = {
      employeeIds: ["e1", "e2"],
      startTime: future(-3 * 24 * HOUR),
      endTime: future(6 * 24 * HOUR),
    };
    const evs = diffAppointmentForNotifications(
        run,
        {...run, status: "cancelled"},
        NOW,
    );
    expect(kinds(evs)).toEqual(["e1:cancelled", "e2:cancelled"]);
  });

  test("deleting a multi-day run mid-flight still tells the crew", () => {
    const evs = diffAppointmentForNotifications(
        {
          employeeIds: ["e1"],
          startTime: future(-3 * 24 * HOUR),
          endTime: future(6 * 24 * HOUR),
        },
        null,
        NOW,
    );
    expect(kinds(evs)).toEqual(["e1:cancelled"]);
  });

  test("a run that has genuinely finished still emits nothing", () => {
    const evs = diffAppointmentForNotifications(
        {
          employeeIds: ["e1"],
          startTime: future(-9 * 24 * HOUR),
          endTime: future(-2 * 24 * HOUR),
        },
        null,
        NOW,
    );
    expect(evs).toEqual([]);
  });

  test("falls back to startTime when the record carries no endTime", () => {
    const evs = diffAppointmentForNotifications(
        {employeeIds: ["e1"], startTime: future(-3 * HOUR)},
        null,
        NOW,
    );
    expect(evs).toEqual([]);
  });

  test("deleted cancels the before employees", () => {
    const evs = diffAppointmentForNotifications(
        {employeeIds: ["e1"], startTime: future(3 * HOUR)},
        null,
        NOW,
    );
    expect(kinds(evs)).toEqual(["e1:cancelled"]);
  });

  test("status -> cancelled cancels the before employees", () => {
    const evs = diffAppointmentForNotifications(
        {employeeIds: ["e1"], startTime: future(3 * HOUR), status: "pending"},
        {employeeIds: ["e1"], startTime: future(3 * HOUR), status: "cancelled"},
        NOW,
    );
    expect(kinds(evs)).toEqual(["e1:cancelled"]);
  });

  test("removed + added, same time", () => {
    const t = future(3 * HOUR);
    const evs = diffAppointmentForNotifications(
        {employeeIds: ["e1", "e2"], startTime: t},
        {employeeIds: ["e2", "e3"], startTime: t},
        NOW,
    );
    // e2 stayed with no time change -> no event.
    expect(kinds(evs)).toEqual(["e1:removed", "e3:assigned"]);
  });

  test("reschedule reschedules the ids that stayed", () => {
    const evs = diffAppointmentForNotifications(
        {employeeIds: ["e1", "e2"], startTime: future(3 * HOUR)},
        {employeeIds: ["e1", "e2"], startTime: future(4 * HOUR)},
        NOW,
    );
    expect(kinds(evs)).toEqual(["e1:rescheduled", "e2:rescheduled"]);
  });

  test("a just-added id on a reschedule is assigned, not rescheduled", () => {
    const evs = diffAppointmentForNotifications(
        {employeeIds: ["e1"], startTime: future(3 * HOUR)},
        {employeeIds: ["e1", "e2"], startTime: future(4 * HOUR)},
        NOW,
    );
    expect(kinds(evs)).toEqual(["e1:rescheduled", "e2:assigned"]);
  });

  test("a pure status change (no cancel) emits nothing", () => {
    const t = future(3 * HOUR);
    const evs = diffAppointmentForNotifications(
        {employeeIds: ["e1"], startTime: t, status: "pending"},
        {employeeIds: ["e1"], startTime: t, status: "done"},
        NOW,
    );
    expect(evs).toEqual([]);
  });

  test("past appointments are skipped", () => {
    const evs = diffAppointmentForNotifications(
        null,
        {employeeIds: ["e1"], startTime: future(-1 * HOUR)},
        NOW,
    );
    expect(evs).toEqual([]);
  });

  test("repeating series: only the anchor sends assigned", () => {
    const after = {
      employeeIds: ["e1"],
      startTime: future(3 * HOUR),
      seriesId: "s1",
      repeat: "six_months",
    };
    // The anchor occurrence (its own id === seriesId) sends one push.
    expect(kinds(diffAppointmentForNotifications(null, after, NOW, "s1")))
        .toEqual(["e1:assigned"]);
    // A pre-booked copy of the same series (id !== seriesId) is suppressed.
    expect(diffAppointmentForNotifications(null, after, NOW, "copy2"))
        .toEqual([]);
  });
});

describe("selectOverdueCandidates", () => {
  const rec = (id, endMs, status) => ({
    id,
    status,
    endTime: future(endMs),
  });

  test("keeps open statuses whose endTime has passed", () => {
    const got = selectOverdueCandidates(
        [
          rec("pend", -10 * MIN, "pending"),
          rec("prog", -1 * HOUR, "in_progress"),
          rec("legacy", -20 * MIN, "confirmed"),
          rec("edgeNow", 0, "pending"),
          rec("notEnded", 30 * MIN, "pending"),
          rec("done", -10 * MIN, "done"),
          rec("completedLegacy", -10 * MIN, "completed"),
          rec("cxl", -10 * MIN, "cancelled"),
        ],
        NOW,
    );
    expect(got.map((r) => r.id).sort())
        .toEqual(["edgeNow", "legacy", "pend", "prog"]);
  });

  test("drops a record with no endTime", () => {
    expect(selectOverdueCandidates(
        [{id: "noEnd", status: "pending"}], NOW)).toEqual([]);
  });

  test("drops a job that ended more than 24h ago", () => {
    expect(selectOverdueCandidates(
        [rec("ancient", -25 * HOUR, "pending")], NOW)).toEqual([]);
  });

  test("drops a personal block — there is no job to finish", () => {
    const personal = {...rec("personal", -10 * MIN, "pending"),
      isPersonal: true};
    expect(selectOverdueCandidates([personal], NOW)).toEqual([]);
    // The same record without the flag is still a candidate.
    expect(selectOverdueCandidates(
        [rec("personal", -10 * MIN, "pending")], NOW)).toHaveLength(1);
  });
});

describe("tomorrowWindowToronto", () => {
  test("bounds tomorrow at Toronto midnight (EDT = 04:00Z)", () => {
    const {start, end} = tomorrowWindowToronto(NOW);
    expect(start.toISOString()).toBe("2026-07-09T04:00:00.000Z");
    expect(end.toISOString()).toBe("2026-07-10T04:00:00.000Z");
  });
});

describe("groupTomorrowsJobsByEmployee", () => {
  test("groups tomorrow's jobs by employee, cancelled excluded, sorted", () => {
    const jobs = [
      {id: "j1", employeeIds: ["e1"], startTime: new Date(
          "2026-07-09T18:00:00Z")},
      {id: "j2", employeeIds: ["e1", "e2"], startTime: new Date(
          "2026-07-09T13:00:00Z")},
      {id: "today", employeeIds: ["e1"], startTime: new Date(
          "2026-07-09T02:00:00Z")}, // 22:00 Toronto today
      {id: "dayAfter", employeeIds: ["e1"], startTime: new Date(
          "2026-07-10T05:00:00Z")},
      {id: "cxl", employeeIds: ["e1"], status: "cancelled", startTime: new Date(
          "2026-07-09T15:00:00Z")},
    ];
    const grouped = groupTomorrowsJobsByEmployee(jobs, NOW);
    expect(grouped.e1.map((j) => j.id)).toEqual(["j2", "j1"]);
    expect(grouped.e2.map((j) => j.id)).toEqual(["j2"]);
  });

  test("a multi-day run started days ago still counts for tomorrow", () => {
    // The crew is on site tomorrow. Bucketing on startTime alone told them
    // "no jobs tomorrow" while they were mid-run.
    const grouped = groupTomorrowsJobsByEmployee(
        [{
          id: "run",
          employeeIds: ["e1"],
          startTime: new Date("2026-07-06T13:00:00Z"),
          endTime: new Date("2026-07-15T21:00:00Z"),
        }],
        NOW,
    );
    expect(grouped.e1.map((j) => j.id)).toEqual(["run"]);
  });

  test("a run that ended before tomorrow is still excluded", () => {
    const grouped = groupTomorrowsJobsByEmployee(
        [{
          id: "over",
          employeeIds: ["e1"],
          startTime: new Date("2026-07-01T13:00:00Z"),
          endTime: new Date("2026-07-04T21:00:00Z"),
        }],
        NOW,
    );
    expect(grouped.e1).toBeUndefined();
  });
});

describe("buildNotificationMessage", () => {
  const ctx = {
    clientName: "Alice",
    startTime: new Date("2026-07-08T18:30:00Z"),
    address: "123 Main St",
  };

  test("assigned EN/FR titles differ and body names the client", () => {
    const en = buildNotificationMessage("assigned", ctx, "en");
    const fr = buildNotificationMessage("assigned", ctx, "fr");
    expect(en.title).toBe("New job assigned");
    expect(fr.title).toBe("Nouvelle visite assignée");
    expect(en.body).toContain("Alice");
    expect(fr.body).toContain("Alice");
  });

  test("reminder appends the address; omits it when blank", () => {
    const withAddr = buildNotificationMessage("reminder", ctx, "en");
    const noAddr = buildNotificationMessage(
        "reminder",
        {...ctx, address: ""},
        "en",
    );
    expect(withAddr.body).toContain("123 Main St");
    expect(noAddr.body).not.toContain("123 Main St");
  });

  test("a personal job is named by its title, not 'Client'", () => {
    const personal = {
      clientName: "",
      title: "Dentist",
      startTime: ctx.startTime,
    };
    expect(buildNotificationMessage("assigned", personal, "en").body)
        .toContain("Dentist");
    expect(buildNotificationMessage("assigned", personal, "fr").body)
        .toContain("Dentist");
    expect(buildDigestMessage([personal], "en").body).toContain("Dentist");
    expect(buildDigestMessage([personal], "en").body)
        .not.toContain("Client");
  });

  test("an all-day block speaks the date, never 12:00 a.m.", () => {
    const allDay = {
      clientName: "",
      title: "Vacation",
      // Midnight Toronto on Wed 2026-07-08.
      startTime: new Date("2026-07-08T04:00:00Z"),
      isAllDay: true,
    };
    const en = buildNotificationMessage("assigned", allDay, "en");
    expect(en.body).toBe("Vacation · Wed, Jul 8");
    expect(en.body).not.toMatch(/12:00/);
    const fr = buildNotificationMessage("cancelled", allDay, "fr");
    expect(fr.body).not.toMatch(/00:00|0 h/);
    // A timed job is unchanged.
    expect(buildNotificationMessage("assigned", ctx, "en").body)
        .toContain("2:30");
  });

  test("a multi-day run reads as a date range, not just day one", () => {
    // Aug 1 09:00 → Aug 5 17:00 Toronto. Naming only the first morning tells a
    // tech nothing about a job they are on for the rest of the week.
    const run = {
      clientName: "Alice",
      startTime: new Date("2026-08-01T13:00:00Z"),
      endTime: new Date("2026-08-05T21:00:00Z"),
    };
    const en = buildNotificationMessage("assigned", run, "en");
    expect(en.body).toContain("Sat, Aug 1");
    expect(en.body).toContain("Wed, Aug 5");
    const fr = buildNotificationMessage("assigned", run, "fr");
    expect(fr.body).toContain("5 août");
  });

  test("a night shift's range ends on the last night, not the morning after",
      () => {
        // Aug 1 22:00 → Aug 4 06:00 = three nights, the last starting Aug 3.
        const nights = {
          clientName: "Alice",
          startTime: new Date("2026-08-02T02:00:00Z"),
          endTime: new Date("2026-08-04T10:00:00Z"),
        };
        const en = buildNotificationMessage("assigned", nights, "en");
        expect(en.body).toContain("Mon, Aug 3");
        expect(en.body).not.toContain("Aug 4");
      });

  test("a single-day job keeps its single date", () => {
    const oneDay = {
      clientName: "Alice",
      startTime: new Date("2026-07-08T18:30:00Z"),
      endTime: new Date("2026-07-08T20:30:00Z"),
    };
    expect(buildNotificationMessage("assigned", oneDay, "en").body)
        .toBe("Alice · Wed, Jul 8, 2:30 p.m.");
  });

  test("a context with no endTime is unchanged", () => {
    expect(buildNotificationMessage("assigned", ctx, "en").body)
        .toBe("Alice · Wed, Jul 8, 2:30 p.m.");
  });

  test("blank client name falls back", () => {
    const en = buildNotificationMessage(
        "assigned",
        {clientName: "", startTime: ctx.startTime},
        "en",
    );
    expect(en.body).toContain("Client");
  });

  test("leaveNow EN/FR carry the drive time and address", () => {
    const travelCtx = {...ctx, travelMinutes: 25};
    const en = buildNotificationMessage("leaveNow", travelCtx, "en");
    const fr = buildNotificationMessage("leaveNow", travelCtx, "fr");
    expect(en.title).toBe("Time to leave — Alice at 2:30 p.m.");
    expect(en.body).toBe("About 25 min drive · 123 Main St");
    expect(fr.title).toBe("C'est l'heure de partir — Alice à 14 h 30");
    expect(fr.body).toBe("Environ 25 min de route · 123 Main St");
  });

  test("leaveNow omits a blank address", () => {
    const en = buildNotificationMessage(
        "leaveNow",
        {...ctx, address: " ", travelMinutes: 25},
        "en",
    );
    expect(en.body).toBe("About 25 min drive");
  });

  test("doneCheck EN/FR nudges to update the status", () => {
    const en = buildNotificationMessage("doneCheck", ctx, "en");
    const fr = buildNotificationMessage("doneCheck", ctx, "fr");
    expect(en.title).toBe("Job finished?");
    expect(en.body).toBe(
        "Is the job for Alice done yet? Open the app to update its status.");
    expect(fr.title).toBe("Travail terminé ?");
    expect(fr.body).toBe(
        "Le travail pour Alice est-il terminé ? " +
        "Ouvrez l'application pour mettre à jour son statut.");
  });

  test("repeating assigned announces the recurrence EN/FR", () => {
    const en = buildNotificationMessage(
        "assigned", {...ctx, repeat: "six_months"}, "en");
    const fr = buildNotificationMessage(
        "assigned", {...ctx, repeat: "one_year"}, "fr");
    expect(en.title).toBe("New repeating job assigned");
    expect(en.body).toContain("repeats every 6 months");
    expect(fr.title).toBe("Nouvelle visite récurrente");
    expect(fr.body).toContain("chaque année");
  });

  test("repeat none/absent falls back to the plain assigned message", () => {
    const withNone = buildNotificationMessage(
        "assigned", {...ctx, repeat: "none"}, "en");
    const absent = buildNotificationMessage("assigned", ctx, "en");
    expect(withNone.title).toBe("New job assigned");
    expect(absent.title).toBe("New job assigned");
  });

  test("every repeat interval the app can store has a phrase", () => {
    // Mirrors RepeatInterval (repeat_interval.dart). A missing case here ships
    // a job announced as one-off when it repeats.
    for (const raw of ["four_months", "six_months", "one_year"]) {
      for (const locale of ["en", "fr"]) {
        const msg = buildNotificationMessage(
            "assigned", {...ctx, repeat: raw}, locale);
        expect(msg.title).toBe(locale === "fr" ?
          "Nouvelle visite récurrente" : "New repeating job assigned");
      }
    }
    expect(buildNotificationMessage(
        "assigned", {...ctx, repeat: "four_months"}, "en").body,
    ).toContain("repeats every 4 months");
  });

  test("an unknown kind yields empty strings rather than a blank push", () => {
    // The fan-out treats an empty title/body as nothing to send; a partial
    // message would reach a Lock Screen looking broken.
    expect(buildNotificationMessage("nope", ctx, "en"))
        .toEqual({title: "", body: ""});
  });

  test("a null context does not throw", () => {
    expect(buildNotificationMessage("assigned", null, "en").body)
        .toContain("Client");
  });

  test("an unknown locale falls back to EN, never to nothing", () => {
    expect(buildNotificationMessage("assigned", ctx, "es").title)
        .toBe("New job assigned");
  });
});

describe("buildDigestMessage", () => {
  const jobs = [
    {clientName: "Bob", startTime: new Date("2026-07-09T20:00:00Z")},
    {clientName: "Al", startTime: new Date("2026-07-09T13:00:00Z")},
  ];

  test("EN counts jobs and names the earliest first", () => {
    const en = buildDigestMessage(jobs, "en");
    expect(en.body).toContain("2 jobs tomorrow");
    expect(en.body).toContain("Al");
  });

  test("FR variant", () => {
    const fr = buildDigestMessage(jobs, "fr");
    expect(fr.body).toContain("2 visites demain");
  });

  test("singular noun for one job", () => {
    const en = buildDigestMessage([jobs[0]], "en");
    expect(en.body).toContain("1 job tomorrow");
  });

  test("an all-day first job reads 'all day', not a clock time", () => {
    const allDay = {
      clientName: "",
      title: "Vacation",
      startTime: new Date("2026-07-09T04:00:00Z"),
      isAllDay: true,
    };
    expect(buildDigestMessage([allDay], "en").body)
        .toContain("First: Vacation · all day.");
    expect(buildDigestMessage([allDay], "fr").body)
        .toContain("Première : Vacation · toute la journée.");
  });
});

describe("overduePromptLedgerId / isStaleTokenError", () => {
  test("overdue ledger id joins appointment, endTime and recipient", () => {
    expect(overduePromptLedgerId("a", 456, "e1")).toBe("a_456_e1");
  });

  test("stale-token error codes", () => {
    expect(isStaleTokenError(
        "messaging/registration-token-not-registered")).toBe(true);
    expect(isStaleTokenError(
        "messaging/invalid-registration-token")).toBe(true);
    expect(isStaleTokenError("messaging/internal-error")).toBe(false);
    // This code is generic — it could be a payload problem rather than a
    // dead token, so we don't treat it as stale.
    expect(isStaleTokenError("messaging/invalid-argument")).toBe(false);
  });
});

// ----- orchestration with mocks --------------------------------------------

/**
 * Builds a minimal Firestore mock for the orchestration tests, with
 * collection-scoped ledger ids and every appointment `where()` recorded.
 * @param {!Object} config users/tokens/appointments/ledgerExisting fixtures.
 * @return {!Object} `{db, deletedTokens, ledgerCreates, ledgerDeletes,
 *   appointmentQueries}`.
 */
function makeDb(config) {
  const deletedTokens = [];
  const ledgerCreates = [];
  const ledgerDeletes = [];
  const appointmentQueries = [];
  const seriesClaims = new Map(config.seriesClaims || []);
  const existing = new Set(config.ledgerExisting || []);
  const db = {
    collection(name) {
      if (name === "users") {
        return {
          doc(id) {
            return {
              get: async () => ({
                exists: !!config.users[id],
                data: () => config.users[id],
              }),
              collection() {
                return {
                  get: async () => ({
                    docs: (config.tokens[id] || []).map((t) => ({
                      id: t.id,
                      data: () => ({locale: t.locale}),
                      ref: {
                        delete: async () => {
                          deletedTokens.push(t.id);
                        },
                      },
                    })),
                  }),
                };
              },
            };
          },
        };
      }
      if (name === "appointments") {
        const q = {
          where(field, op, value) {
            appointmentQueries.push({field, op, value});
            return q;
          },
          orderBy() {
            return q;
          },
          limit() {
            return q;
          },
          get: async () => ({
            docs: (config.appointments || []).map((r) => ({
              id: r.id,
              data: () => r,
            })),
          }),
        };
        return q;
      }
      if (name === "appointmentReminders" ||
          name === "appointmentOverduePrompts") {
        return {
          doc(id) {
            const key = `${name}/${id}`;
            return {
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
      if (name === "appointmentSeriesNotices") {
        return {
          doc(id) {
            return {
              create: async (data) => {
                if (seriesClaims.has(id)) {
                  const e = new Error("exists");
                  e.code = 6;
                  throw e;
                }
                seriesClaims.set(id, data);
              },
              get: async () => ({
                get: (field) => (seriesClaims.get(id) || {})[field],
              }),
              set: async (data) => {
                seriesClaims.set(id, data);
              },
            };
          },
        };
      }
      return {doc: () => ({})};
    },
  };
  return {
    db, deletedTokens, ledgerCreates, ledgerDeletes, appointmentQueries,
    seriesClaims,
  };
}

/**
 * Builds a Messaging mock whose sendEach records the messages it receives.
 * @param {function(string): !Object=} resultFor Optional per-token response.
 * @return {!Object} `{sent, sendEach}`.
 */
function makeMessaging(resultFor) {
  const sent = [];
  return {
    sent,
    sendEach: async (messages) => {
      sent.push(...messages);
      return {
        responses: messages.map((m) =>
          resultFor ? resultFor(m.token) : {success: true}),
      };
    },
  };
}

const silentLogger = {warn: () => {}, info: () => {}, error: () => {}};

describe("handleAppointmentWrite repeat-series claim", () => {
  // A "this and all future" edit writes every sibling in one client batch, so
  // without a claim the tech would get one push per sibling instead of one.
  const sibling = (id) => ({
    id,
    seriesId: "series-1",
    employeeIds: ["e1"],
    startTime: future(3 * HOUR),
    status: "pending",
  });

  const runDelete = (db, messaging, id) => handleAppointmentWrite(
      id,
      sibling(id),
      null,
      {db, messaging, now: NOW, logger: silentLogger},
  );

  test("series cancel/delete notifies the employee only once", async () => {
    const {db} = makeDb({
      users: {e1: {role: "employee", status: "active"}},
      tokens: {e1: [{id: "t-en", locale: "en"}]},
    });
    const messaging = makeMessaging();
    const first = await runDelete(db, messaging, "occ-1");
    const second = await runDelete(db, messaging, "occ-2");
    const third = await runDelete(db, messaging, "occ-3");

    expect(first.sent).toBe(1);
    expect(second.sent).toBe(0);
    expect(third.sent).toBe(0);
    expect(messaging.sent).toHaveLength(1);
  });

  test("a non-series appointment is never suppressed", async () => {
    const {db} = makeDb({
      users: {e1: {role: "employee", status: "active"}},
      tokens: {e1: [{id: "t-en", locale: "en"}]},
    });
    const messaging = makeMessaging();
    const one = {
      employeeIds: ["e1"], startTime: future(3 * HOUR), status: "pending",
    };
    const a = await handleAppointmentWrite(
        "solo-1", one, null, {db, messaging, now: NOW, logger: silentLogger});
    const b = await handleAppointmentWrite(
        "solo-2", one, null, {db, messaging, now: NOW, logger: silentLogger});
    expect(a.sent).toBe(1);
    expect(b.sent).toBe(1);
  });

  test("a later separate operation on the same series notifies again",
      async () => {
        const stale = new Date(
            NOW.getTime() - SERIES_CLAIM_WINDOW_MS - 1000);
        const {db} = makeDb({
          users: {e1: {role: "employee", status: "active"}},
          tokens: {e1: [{id: "t-en", locale: "en"}]},
          seriesClaims: [["series-1_cancelled_e1", {createdAt: stale}]],
        });
        const messaging = makeMessaging();
        const res = await runDelete(db, messaging, "occ-9");
        // The existing claim predates the batch window, so it is taken over
        // rather than suppressing a genuinely new operation.
        expect(res.sent).toBe(1);
      });

  test("fails OPEN: a claim-store error still delivers the push", async () => {
    const {db} = makeDb({
      users: {e1: {role: "employee", status: "active"}},
      tokens: {e1: [{id: "t-en", locale: "en"}]},
    });
    const broken = {
      ...db,
      collection: (name) => name === "appointmentSeriesNotices" ?
        {doc: () => ({create: async () => {
          throw new Error("firestore down");
        }})} :
        db.collection(name),
    };
    const messaging = makeMessaging();
    const res = await runDelete(broken, messaging, "occ-1");
    // Degrading to today's behavior (one push per sibling) beats silently
    // dropping a cancellation for a tech already driving to the job.
    expect(res.sent).toBe(1);
  });

  // On the op-id path, a WRITE (where `after` is present) carries a fresh
  // seriesOpId that every sibling in the same batch shares and no other
  // operation reuses. So the claim is keyed on that op-id, with no time
  // window needed.
  const cancelUpdate = (db, messaging, id, opId) => {
    const before = {
      seriesId: "series-1", employeeIds: ["e1"],
      startTime: future(3 * HOUR), status: "pending",
    };
    const after = {...before, status: "cancelled", seriesOpId: opId};
    return handleAppointmentWrite(
        id, before, after, {db, messaging, now: NOW, logger: silentLogger});
  };

  test("one op-id collapses its whole batch to a single push", async () => {
    const {db} = makeDb({
      users: {e1: {role: "employee", status: "active"}},
      tokens: {e1: [{id: "t-en", locale: "en"}]},
    });
    const messaging = makeMessaging();
    const first = await cancelUpdate(db, messaging, "occ-1", "op-A");
    const second = await cancelUpdate(db, messaging, "occ-2", "op-A");
    const third = await cancelUpdate(db, messaging, "occ-3", "op-A");
    expect(first.sent).toBe(1);
    expect(second.sent).toBe(0);
    expect(third.sent).toBe(0);
    expect(messaging.sent).toHaveLength(1);
  });

  test("two separate operations each notify, even back-to-back", async () => {
    // Distinct op-ids keep separate cancellations (e.g. Tuesday's then
    // Thursday's) from suppressing each other regardless of timing.
    const {db} = makeDb({
      users: {e1: {role: "employee", status: "active"}},
      tokens: {e1: [{id: "t-en", locale: "en"}]},
    });
    const messaging = makeMessaging();
    const tuesday = await cancelUpdate(db, messaging, "tue", "op-A");
    const thursday = await cancelUpdate(db, messaging, "thu", "op-B");
    expect(tuesday.sent).toBe(1);
    expect(thursday.sent).toBe(1);
    expect(messaging.sent).toHaveLength(2);
  });

  test("op-id path suppresses without a stale-takeover read", async () => {
    // A duplicate op-id claim is definitive since it's the same batch, so
    // create() alone can resolve the collision — no need for a get()/set()
    // round-trip.
    const {db, seriesClaims} = makeDb({
      users: {e1: {role: "employee", status: "active"}},
      tokens: {e1: [{id: "t-en", locale: "en"}]},
      seriesClaims: [["op_op-A_cancelled_e1", {createdAt: NOW}]],
    });
    const messaging = makeMessaging();
    const res = await cancelUpdate(db, messaging, "occ-1", "op-A");
    expect(res.sent).toBe(0);
    // The claim doc is untouched (not overwritten by a takeover set()).
    expect(seriesClaims.get("op_op-A_cancelled_e1").createdAt).toBe(NOW);
  });
});

describe("handleAppointmentWrite", () => {
  test("sends one message per live token of an active employee", async () => {
    const {db} = makeDb({
      users: {e1: {role: "employee", status: "active"}},
      tokens: {e1: [{id: "t-en", locale: "en"}, {id: "t-fr", locale: "fr"}]},
    });
    const messaging = makeMessaging();
    const res = await handleAppointmentWrite(
        "appt1",
        null,
        {employeeIds: ["e1"], startTime: future(3 * HOUR)},
        {db, messaging, now: NOW, logger: silentLogger},
    );
    expect(res).toEqual({events: 1, sent: 2});
    expect(messaging.sent).toHaveLength(2);
    // Delivery hints are always set.
    expect(messaging.sent[0].android.priority).toBe("high");
    expect(messaging.sent[0].apns.payload.aps.sound).toBe("default");
    expect(messaging.sent[0].data.appointmentId).toBe("appt1");
    expect(messaging.sent[0].data.kind).toBe("assigned");
    // A change push carries a fresh widget payload and wakes iOS in the
    // background (content-available) to rewrite the home-screen widget.
    expect(typeof messaging.sent[0].data.widgetPayload).toBe("string");
    expect(messaging.sent[0].apns.payload.aps["content-available"]).toBe(1);
  });

  test("attaches a locale-correct widget payload with the assigned job",
      async () => {
        const {db} = makeDb({
          users: {e1: {role: "employee", status: "active"}},
          tokens: {e1: [
            {id: "t-en", locale: "en"},
            {id: "t-fr", locale: "fr"},
          ]},
          // This is the post-write state that the widget window read sees.
          appointments: [{
            id: "appt1",
            employeeIds: ["e1"],
            startTime: future(3 * HOUR),
            status: "pending",
            clientName: "Acme",
          }],
        });
        const messaging = makeMessaging();
        await handleAppointmentWrite(
            "appt1",
            null,
            {employeeIds: ["e1"], startTime: future(3 * HOUR)},
            {db, messaging, now: NOW, logger: silentLogger},
        );
        const byToken = Object.fromEntries(
            messaging.sent.map((m) => [m.token, m]));
        const en = JSON.parse(byToken["t-en"].data.widgetPayload);
        const fr = JSON.parse(byToken["t-fr"].data.widgetPayload);
        expect(en.locale).toBe("en");
        expect(fr.locale).toBe("fr");
        expect(en.todayJobs).toHaveLength(1);
        expect(en.todayJobs[0].id).toBe("appt1");
        expect(en.todayJobs[0].clientName).toBe("Acme");
        // startTime is an absolute UTC instant (…Z) for the Swift decoder.
        expect(en.todayJobs[0].startTime).toBe(future(3 * HOUR).toISOString());
      });

  test("cancelling a job yields a widget payload without it", async () => {
    const {db} = makeDb({
      users: {e1: {role: "employee", status: "active"}},
      tokens: {e1: [{id: "t-en", locale: "en"}]},
      // The cancelled doc still exists but is terminal -> filtered out.
      appointments: [{
        id: "appt1",
        employeeIds: ["e1"],
        startTime: future(3 * HOUR),
        status: "cancelled",
        clientName: "Acme",
      }],
    });
    const messaging = makeMessaging();
    await handleAppointmentWrite(
        "appt1",
        {employeeIds: ["e1"], startTime: future(3 * HOUR), status: "pending"},
        {employeeIds: ["e1"], startTime: future(3 * HOUR), status: "cancelled"},
        {db, messaging, now: NOW, logger: silentLogger},
    );
    expect(messaging.sent[0].data.kind).toBe("cancelled");
    const payload = JSON.parse(messaging.sent[0].data.widgetPayload);
    expect(payload.todayJobs).toHaveLength(0);
    expect(payload.tomorrowJobs).toHaveLength(0);
  });

  test("skips a non-active or non-employee user", async () => {
    const {db} = makeDb({
      users: {e1: {role: "employee", status: "invited"}},
      tokens: {e1: [{id: "t", locale: "en"}]},
    });
    const messaging = makeMessaging();
    const res = await handleAppointmentWrite(
        "appt1",
        null,
        {employeeIds: ["e1"], startTime: future(3 * HOUR)},
        {db, messaging, now: NOW, logger: silentLogger},
    );
    expect(res.sent).toBe(0);
    expect(messaging.sent).toHaveLength(0);
  });

  test("deletes a token doc FCM reports as stale", async () => {
    const {db, deletedTokens} = makeDb({
      users: {e1: {role: "employee", status: "active"}},
      tokens: {e1: [{id: "good", locale: "en"}, {id: "dead", locale: "en"}]},
    });
    const messaging = makeMessaging((token) =>
      token === "dead" ?
        {success: false, error: {
          code: "messaging/registration-token-not-registered",
        }} :
        {success: true});
    const res = await handleAppointmentWrite(
        "appt1",
        null,
        {employeeIds: ["e1"], startTime: future(3 * HOUR)},
        {db, messaging, now: NOW, logger: silentLogger},
    );
    expect(res.sent).toBe(1);
    expect(deletedTokens).toEqual(["dead"]);
  });

  test("no events -> no sends", async () => {
    const {db} = makeDb({users: {}, tokens: {}});
    const messaging = makeMessaging();
    const res = await handleAppointmentWrite(
        "appt1",
        null,
        {employeeIds: ["e1"], startTime: future(-1 * HOUR)},
        {db, messaging, now: NOW, logger: silentLogger},
    );
    expect(res).toEqual({events: 0, sent: 0});
  });

  test("an active admin assignee gets NO change-driven push", async () => {
    const {db} = makeDb({
      users: {a1: {role: "admin", status: "active"}},
      tokens: {a1: [{id: "t", locale: "en"}]},
    });
    const messaging = makeMessaging();
    const res = await handleAppointmentWrite(
        "appt1",
        null,
        {employeeIds: ["a1"], startTime: future(3 * HOUR)},
        {db, messaging, now: NOW, logger: silentLogger},
    );
    // Assignment/reschedule/cancel pushes are employee-only. An admin
    // usually makes those edits themselves, so we don't push back their
    // own change.
    expect(res.sent).toBe(0);
    expect(messaging.sent).toHaveLength(0);
  });
});

describe("runOverduePromptSweep", () => {
  const overdueJob = {
    id: "over",
    status: "in_progress",
    clientName: "Alice",
    employeeIds: ["e1"],
    startTime: future(-2 * HOUR),
    endTime: future(-30 * MIN),
  };
  const overdueKey = `appointmentOverduePrompts/${
    overduePromptLedgerId("over", future(-30 * MIN).getTime(), "e1")}`;

  test("writes the endTime-keyed ledger and prompts assignees", async () => {
    const {db, ledgerCreates, ledgerDeletes, appointmentQueries} = makeDb({
      users: {e1: {role: "employee", status: "active"}},
      tokens: {e1: [{id: "t", locale: "en"}]},
      appointments: [
        overdueJob,
        // Still running -> filtered out in code.
        {id: "running", status: "in_progress", employeeIds: ["e1"],
          startTime: future(-1 * HOUR), endTime: future(30 * MIN)},
        // Closed -> filtered out in code.
        {id: "closed", status: "done", employeeIds: ["e1"],
          startTime: future(-2 * HOUR), endTime: future(-30 * MIN)},
      ],
    });
    const messaging = makeMessaging();
    const res = await runOverduePromptSweep(
        {db, messaging, now: NOW, logger: silentLogger},
    );
    expect(res.prompted).toBe(1);
    expect(ledgerCreates.map((c) => c.key)).toEqual([overdueKey]);
    expect(ledgerCreates[0].data.expiresAt).toBeInstanceOf(Date);
    expect(ledgerDeletes).toEqual([]);
    // The query needs to cover open statuses across a startTime window of
    // 24h of eligibility PLUS the longest bookable span (14 days). A 48h
    // floor silently stopped matching any run longer than a day, so those
    // jobs were never prompted to close.
    expect(appointmentQueries).toEqual([
      {field: "status", op: "in",
        value: ["pending", "in_progress", "confirmed"]},
      {field: "startTime", op: ">=", value: future(-(24 + 14 * 24) * HOUR)},
      {field: "startTime", op: "<=", value: NOW},
    ]);
    expect(messaging.sent).toHaveLength(1);
    expect(messaging.sent[0].data).toEqual({
      appointmentId: "over",
      kind: "doneCheck",
    });
    expect(messaging.sent[0].notification.body).toContain("Alice");
  });

  test("an existing ledger doc suppresses a re-prompt", async () => {
    const {db} = makeDb({
      users: {e1: {role: "employee", status: "active"}},
      tokens: {e1: [{id: "t", locale: "en"}]},
      appointments: [overdueJob],
      ledgerExisting: [overdueKey],
    });
    const messaging = makeMessaging();
    const res = await runOverduePromptSweep(
        {db, messaging, now: NOW, logger: silentLogger},
    );
    expect(res.prompted).toBe(0);
    expect(messaging.sent).toHaveLength(0);
  });

  test("a zero-delivery claim is released for a later retry", async () => {
    // The assignee is active but has no fcmTokens yet, as if on a fresh
    // install.
    const {db, ledgerCreates, ledgerDeletes} = makeDb({
      users: {e1: {role: "employee", status: "active"}},
      tokens: {},
      appointments: [overdueJob],
    });
    const messaging = makeMessaging();
    const res = await runOverduePromptSweep(
        {db, messaging, now: NOW, logger: silentLogger},
    );
    expect(res.prompted).toBe(0);
    expect(ledgerCreates.map((c) => c.key)).toEqual([overdueKey]);
    expect(ledgerDeletes).toEqual([overdueKey]);
  });

  test("a thrown send releases the claim and continues", async () => {
    const other = {...overdueJob, id: "other", endTime: future(-40 * MIN)};
    const {db, ledgerCreates, ledgerDeletes} = makeDb({
      users: {e1: {role: "employee", status: "active"}},
      tokens: {e1: [{id: "t", locale: "en"}]},
      appointments: [overdueJob, other],
    });
    const messaging = {
      sendEach: async () => {
        throw new Error("transient FCM outage");
      },
    };
    const res = await runOverduePromptSweep(
        {db, messaging, now: NOW, logger: silentLogger},
    );
    // Both candidates were attempted (no sweep abort) and both claims were
    // released.
    expect(res.prompted).toBe(0);
    expect(ledgerCreates).toHaveLength(2);
    expect(ledgerDeletes).toHaveLength(2);
  });
});

describe("runDailyDigest", () => {
  test("sends one digest per employee with a job tomorrow", async () => {
    const {db} = makeDb({
      users: {
        e1: {role: "employee", status: "active"},
        e2: {role: "employee", status: "active"},
      },
      tokens: {
        e1: [{id: "t1", locale: "en"}],
        e2: [{id: "t2", locale: "fr"}],
      },
      appointments: [
        {id: "j1", status: "pending", employeeIds: ["e1"],
          startTime: new Date("2026-07-09T13:00:00Z")},
        {id: "j2", status: "pending", employeeIds: ["e2"],
          startTime: new Date("2026-07-09T18:00:00Z")},
        {id: "today", status: "pending", employeeIds: ["e1"],
          startTime: new Date("2026-07-08T18:00:00Z")},
      ],
    });
    const messaging = makeMessaging();
    const res = await runDailyDigest(
        {db, messaging, now: NOW, logger: silentLogger},
    );
    expect(res.digests).toBe(2);
    expect(messaging.sent).toHaveLength(2);
  });

  test("queries every open status, including in_progress", async () => {
    // This is a regression test: the digest's hardcoded status list used to
    // disagree with its own filter, silently dropping in_progress jobs from
    // the 18:00 digest.
    const {db, appointmentQueries} = makeDb({
      users: {e1: {role: "employee", status: "active"}},
      tokens: {e1: [{id: "t1", locale: "en"}]},
      appointments: [
        {id: "j1", status: "in_progress", employeeIds: ["e1"],
          startTime: new Date("2026-07-09T13:00:00Z")},
      ],
    });
    const messaging = makeMessaging();
    const res = await runDailyDigest(
        {db, messaging, now: NOW, logger: silentLogger},
    );

    const statusQuery = appointmentQueries.find((q) => q.field === "status");
    expect(statusQuery.value).toEqual(expect.arrayContaining(["in_progress"]));
    expect(statusQuery.value).toEqual(OPEN_STATUSES);
    expect(res.digests).toBe(1);
  });
});
