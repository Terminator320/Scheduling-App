"use strict";

/**
 * Unit tests for the push-notification pure helpers and the injectable
 * orchestration (handleAppointmentWrite / runReminderSweep / runDailyDigest).
 */

const {
  diffAppointmentForNotifications,
  buildNotificationMessage,
  buildDigestMessage,
  selectReminderCandidates,
  selectOverdueCandidates,
  groupTomorrowsJobsByEmployee,
  tomorrowWindowToronto,
  reminderLedgerId,
  overduePromptLedgerId,
  isStaleTokenError,
  handleAppointmentWrite,
  runReminderSweep,
  runDailyDigest,
  runOverduePromptSweep,
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

describe("selectReminderCandidates", () => {
  const rec = (id, ms, status = "pending") => ({
    id,
    status,
    startTime: future(ms),
  });

  test("keeps pending-like jobs starting within (now, now+30min]", () => {
    const got = selectReminderCandidates(
        [
          rec("in20", 20 * MIN),
          rec("edge30", 30 * MIN),
          rec("out31", 31 * MIN),
          rec("started", -5 * MIN),
          rec("inProgress", 10 * MIN, "in_progress"),
          rec("confirmed", 15 * MIN, "confirmed"),
        ],
        NOW,
    );
    expect(got.map((r) => r.id).sort())
        .toEqual(["confirmed", "edge30", "in20"]);
  });

  test("excludes a job starting exactly now", () => {
    expect(selectReminderCandidates([rec("nowJob", 0)], NOW)).toEqual([]);
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

  test("blank client name falls back", () => {
    const en = buildNotificationMessage(
        "assigned",
        {clientName: "", startTime: ctx.startTime},
        "en",
    );
    expect(en.body).toContain("Client");
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
});

describe("reminderLedgerId / isStaleTokenError", () => {
  test("ledger id joins appointment, startTime and recipient", () => {
    expect(reminderLedgerId("a", 123, "e1")).toBe("a_123_e1");
  });

  test("overdue ledger id joins appointment, endTime and recipient", () => {
    expect(overduePromptLedgerId("a", 456, "e1")).toBe("a_456_e1");
  });

  test("stale-token error codes", () => {
    expect(isStaleTokenError(
        "messaging/registration-token-not-registered")).toBe(true);
    expect(isStaleTokenError(
        "messaging/invalid-registration-token")).toBe(true);
    expect(isStaleTokenError("messaging/internal-error")).toBe(false);
    // Generic — could be a payload problem, not a dead token; not stale.
    expect(isStaleTokenError("messaging/invalid-argument")).toBe(false);
  });
});

// ----- orchestration with mocks --------------------------------------------

/**
 * Builds a minimal Firestore mock for the orchestration tests. Ledger ids in
 * `ledgerCreates`/`ledgerDeletes`/`ledgerExisting` are collection-scoped
 * (`collection/docId`) so a sweep writing to the wrong ledger collection
 * fails the assertions; `appointmentQueries` records every `where()` so the
 * query shape itself is testable.
 * @param {!Object} config users/tokens/appointments/ledgerExisting fixtures.
 * @return {!Object} `{db, deletedTokens, ledgerCreates, ledgerDeletes,
 *   appointmentQueries}`.
 */
function makeDb(config) {
  const deletedTokens = [];
  const ledgerCreates = [];
  const ledgerDeletes = [];
  const appointmentQueries = [];
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
      return {doc: () => ({})};
    },
  };
  return {db, deletedTokens, ledgerCreates, ledgerDeletes, appointmentQueries};
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
    expect(messaging.sent[0].data).toEqual({
      appointmentId: "appt1",
      kind: "assigned",
    });
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
    // Assignment/reschedule/cancel are employee-only — an admin usually makes
    // those edits, so no push for their own change.
    expect(res.sent).toBe(0);
    expect(messaging.sent).toHaveLength(0);
  });
});

describe("runReminderSweep", () => {
  test("writes the ledger and reminds each assignee once", async () => {
    const {db, ledgerCreates} = makeDb({
      users: {e1: {role: "employee", status: "active"}},
      tokens: {e1: [{id: "t", locale: "en"}]},
      appointments: [
        {id: "soon", status: "pending", employeeIds: ["e1"],
          startTime: future(20 * MIN)},
      ],
    });
    const messaging = makeMessaging();
    const res = await runReminderSweep(
        {db, messaging, now: NOW, logger: silentLogger},
    );
    expect(res.reminded).toBe(1);
    expect(ledgerCreates.map((c) => c.key)).toEqual([
      `appointmentReminders/${
        reminderLedgerId("soon", future(20 * MIN).getTime(), "e1")}`,
    ]);
    expect(ledgerCreates[0].data.expiresAt).toBeInstanceOf(Date);
    expect(messaging.sent[0].data.kind).toBe("reminder");
  });

  test("an active admin assignee still gets the reminder", async () => {
    const {db} = makeDb({
      users: {a1: {role: "admin", status: "active"}},
      tokens: {a1: [{id: "t", locale: "en"}]},
      appointments: [
        {id: "soon", status: "pending", employeeIds: ["a1"],
          startTime: future(20 * MIN)},
      ],
    });
    const messaging = makeMessaging();
    const res = await runReminderSweep(
        {db, messaging, now: NOW, logger: silentLogger},
    );
    expect(res.reminded).toBe(1);
    expect(messaging.sent[0].data.kind).toBe("reminder");
  });

  test("an existing ledger doc suppresses a re-send", async () => {
    const startMs = future(20 * MIN).getTime();
    const {db} = makeDb({
      users: {e1: {role: "employee", status: "active"}},
      tokens: {e1: [{id: "t", locale: "en"}]},
      appointments: [
        {id: "soon", status: "pending", employeeIds: ["e1"],
          startTime: future(20 * MIN)},
      ],
      ledgerExisting: [
        `appointmentReminders/${reminderLedgerId("soon", startMs, "e1")}`,
      ],
    });
    const messaging = makeMessaging();
    const res = await runReminderSweep(
        {db, messaging, now: NOW, logger: silentLogger},
    );
    expect(res.reminded).toBe(0);
    expect(messaging.sent).toHaveLength(0);
  });

  test("a zero-delivery claim is released for a later retry", async () => {
    // Active assignee but no fcmTokens yet (fresh install) — the ledger is
    // claimed then released so the next sweep can retry while still upcoming.
    const {db, ledgerCreates, ledgerDeletes} = makeDb({
      users: {e1: {role: "employee", status: "active"}},
      tokens: {},
      appointments: [
        {id: "soon", status: "pending", employeeIds: ["e1"],
          startTime: future(20 * MIN)},
      ],
    });
    const messaging = makeMessaging();
    const res = await runReminderSweep(
        {db, messaging, now: NOW, logger: silentLogger},
    );
    expect(res.reminded).toBe(0);
    expect(ledgerCreates).toHaveLength(1);
    expect(ledgerDeletes).toEqual([
      `appointmentReminders/${
        reminderLedgerId("soon", future(20 * MIN).getTime(), "e1")}`,
    ]);
  });

  test("a token-less assignee is retried without re-sending the delivered one",
      async () => {
        // Two assignees on one job: e1 has a live token, e2 has none yet. The
        // per-recipient ledger keeps e1's claim (delivered) and releases e2's
        // (nothing delivered), so a later sweep retries ONLY e2 and never
        // re-notifies e1.
        const startMs = future(20 * MIN).getTime();
        const {db, ledgerCreates, ledgerDeletes} = makeDb({
          users: {
            e1: {role: "employee", status: "active"},
            e2: {role: "employee", status: "active"},
          },
          tokens: {e1: [{id: "t1", locale: "en"}]},
          appointments: [
            {id: "soon", status: "pending", employeeIds: ["e1", "e2"],
              startTime: future(20 * MIN)},
          ],
        });
        const messaging = makeMessaging();
        const res = await runReminderSweep(
            {db, messaging, now: NOW, logger: silentLogger},
        );
        expect(res.reminded).toBe(1);
        expect(messaging.sent).toHaveLength(1);
        // Both recipients were claimed; only the undelivered one was released.
        expect(ledgerCreates.map((c) => c.key)).toEqual([
          `appointmentReminders/${reminderLedgerId("soon", startMs, "e1")}`,
          `appointmentReminders/${reminderLedgerId("soon", startMs, "e2")}`,
        ]);
        expect(ledgerDeletes).toEqual([
          `appointmentReminders/${reminderLedgerId("soon", startMs, "e2")}`,
        ]);
      });

  test("a delivered recipient is not re-sent while a pending one still fires",
      async () => {
        // e1 already has a persisted ledger from an earlier sweep; e2 does not.
        // Only e2 should be notified this sweep.
        const startMs = future(20 * MIN).getTime();
        const {db, ledgerCreates} = makeDb({
          users: {
            e1: {role: "employee", status: "active"},
            e2: {role: "employee", status: "active"},
          },
          tokens: {
            e1: [{id: "t1", locale: "en"}],
            e2: [{id: "t2", locale: "en"}],
          },
          appointments: [
            {id: "soon", status: "pending", employeeIds: ["e1", "e2"],
              startTime: future(20 * MIN)},
          ],
          ledgerExisting: [
            `appointmentReminders/${reminderLedgerId("soon", startMs, "e1")}`,
          ],
        });
        const messaging = makeMessaging();
        const res = await runReminderSweep(
            {db, messaging, now: NOW, logger: silentLogger},
        );
        expect(res.reminded).toBe(1);
        expect(messaging.sent).toHaveLength(1);
        expect(messaging.sent[0].token).toBe("t2");
        expect(ledgerCreates.map((c) => c.key)).toEqual([
          `appointmentReminders/${reminderLedgerId("soon", startMs, "e2")}`,
        ]);
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
    // The query itself must cover open statuses over a 48h startTime window
    // (24h eligibility + the <24h max booking duration).
    expect(appointmentQueries).toEqual([
      {field: "status", op: "in",
        value: ["pending", "in_progress", "confirmed"]},
      {field: "startTime", op: ">=", value: future(-48 * HOUR)},
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
    // Active assignee but no fcmTokens yet (fresh install).
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
});
