const {
  ATTRIBUTES_TYPE,
  PHASE_TRAVEL,
  PHASE_ON_SITE,
  liveActivityStrings,
  phaseFor,
  buildContentState,
  buildStartPayload,
  buildUpdatePayload,
  buildEndPayload,
} = require("../live_activity_utils");

// 2026-07-20 11:00 UTC = 07:00 America/Toronto (EDT).
const START = new Date("2026-07-20T12:00:00.000Z");
const LEAVE = new Date("2026-07-20T11:54:00.000Z");

describe("phaseFor", () => {
  test("is travel strictly before startTime", () => {
    expect(phaseFor({startTime: START, now: new Date(START.getTime() - 1)}))
        .toBe(PHASE_TRAVEL);
  });
  test("is onSite exactly at startTime", () => {
    expect(phaseFor({startTime: START, now: START})).toBe(PHASE_ON_SITE);
  });
  test("is onSite after startTime", () => {
    expect(phaseFor({startTime: START, now: new Date(START.getTime() + 1)}))
        .toBe(PHASE_ON_SITE);
  });
  test("accepts Firestore Timestamps and epoch millis", () => {
    const ts = {toMillis: () => START.getTime()};
    expect(phaseFor({startTime: ts, now: START.getTime() + 60_000}))
        .toBe(PHASE_ON_SITE);
  });
  test("falls back to travel when startTime is unreadable", () => {
    expect(phaseFor({startTime: null, now: START})).toBe(PHASE_TRAVEL);
  });
});

describe("liveActivityStrings", () => {
  test("returns the EN table for 'en'", () => {
    expect(liveActivityStrings("en").directions).toBe("Directions");
  });
  test("returns the FR table for 'fr'", () => {
    expect(liveActivityStrings("fr").directions).toBe("Itinéraire");
  });
  test("falls back to EN for an unknown locale", () => {
    expect(liveActivityStrings("de").complete).toBe("Complete");
  });
  test("EN and FR expose the same keys", () => {
    expect(Object.keys(liveActivityStrings("fr")).sort())
        .toEqual(Object.keys(liveActivityStrings("en")).sort());
  });
  test("builds a localized start alert in both languages", () => {
    const ctx = {
      clientName: "Acme",
      address: "12 Rue Principale",
      startTime: START,
      travelMinutes: 18,
    };
    const en = liveActivityStrings("en");
    const fr = liveActivityStrings("fr");
    expect(en.startAlert(ctx, en.who(ctx)).title).toContain("Time to leave");
    expect(en.startAlert(ctx, en.who(ctx)).body)
        .toBe("About 18 min drive · 12 Rue Principale");
    expect(fr.startAlert(ctx, fr.who(ctx)).title).toContain("partir");
    expect(fr.startAlert(ctx, fr.who(ctx)).body)
        .toBe("Environ 18 min de route · 12 Rue Principale");
  });
  test("start alert omits the separator when there is no address", () => {
    const ctx = {clientName: "Acme", startTime: START, travelMinutes: 5};
    const en = liveActivityStrings("en");
    expect(en.startAlert(ctx, en.who(ctx)).body).toBe("About 5 min drive");
  });
});

describe("buildContentState", () => {
  const base = {
    clientName: "Acme Plumbing",
    address: "12 Main St",
    startTime: START,
    leaveAt: LEAVE,
    travelMinutes: 18,
  };

  test("travel phase leads on the absolute leave time (EN)", () => {
    const cs = buildContentState({...base, phase: PHASE_TRAVEL, locale: "en"});
    expect(cs.phase).toBe(PHASE_TRAVEL);
    expect(cs.statusLabel).toBe("On the way");
    expect(cs.timeLabel).toBe("Leave at 7:54 a.m.");
    expect(cs.driveLabel).toBe("About 18 min drive");
    expect(cs.directionsLabel).toBe("Directions");
  });
  test("travel phase is localized in FR", () => {
    const cs = buildContentState({...base, phase: PHASE_TRAVEL, locale: "fr"});
    expect(cs.statusLabel).toBe("En route");
    expect(cs.timeLabel).toMatch(/^Départ à /);
    expect(cs.driveLabel).toBe("Environ 18 min de route");
    expect(cs.completeLabel).toBe("Terminer");
  });
  test("on-site phase switches label, chip and drops the drive line", () => {
    const cs = buildContentState({...base, phase: PHASE_ON_SITE, locale: "en"});
    expect(cs.statusLabel).toBe("On site");
    expect(cs.timeLabel).toBe("Started at 8:00 a.m.");
    expect(cs.driveLabel).toBe("");
  });
  test("emits absolute UTC ISO instants the Swift decoder can parse", () => {
    const cs = buildContentState({...base, phase: PHASE_TRAVEL});
    expect(cs.startTime).toBe("2026-07-20T12:00:00.000Z");
    expect(cs.leaveAt).toBe("2026-07-20T11:54:00.000Z");
  });
  test("falls back to a generic client name per locale", () => {
    expect(buildContentState({...base, clientName: "  ", locale: "en"})
        .clientName).toBe("Client");
    expect(buildContentState({...base, clientName: "", locale: "fr"})
        .clientName).toBe("un client");
  });
  test("a missing leaveAt never labels the start as a departure time", () => {
    // Regression: this used to render "Leave at 8:00 a.m." off `startTime`,
    // i.e. the appointment's own start presented as the leave time — which
    // sends the tech off a whole drive-time late.
    const cs = buildContentState({
      clientName: "Acme", address: "", startTime: START,
      leaveAt: null, travelMinutes: null, phase: PHASE_TRAVEL, locale: "en",
    });
    expect(cs.leaveAt).toBeNull();
    expect(cs.travelMinutes).toBeNull();
    expect(cs.driveLabel).toBe("");
    expect(cs.timeLabel).toBe("Starts at 8:00 a.m.");
  });

  test("the same fallback is localized in French", () => {
    const cs = buildContentState({
      clientName: "Acme", address: "", startTime: START,
      leaveAt: null, travelMinutes: null, phase: PHASE_TRAVEL, locale: "fr",
    });
    expect(cs.timeLabel).toBe("Débute à 8 h 00");
  });
});

describe("payload envelopes", () => {
  const cs = {phase: PHASE_TRAVEL};
  const alert = {title: "t", body: "b"};

  test("start carries attributes-type, attributes and the event", () => {
    const p = buildStartPayload({
      contentState: cs,
      attributes: {appointmentId: "a1"},
      now: START,
      alert,
      staleDate: new Date(START.getTime() + 60_000),
    });
    expect(p.aps["event"]).toBe("start");
    expect(p.aps["attributes-type"]).toBe(ATTRIBUTES_TYPE);
    expect(p.aps["attributes"]).toEqual({appointmentId: "a1"});
    expect(p.aps["content-state"]).toBe(cs);
    expect(p.aps["timestamp"]).toBe(Math.floor(START.getTime() / 1000));
    expect(p.aps["stale-date"])
        .toBe(Math.floor(START.getTime() / 1000) + 60);
    expect(p.aps["alert"]).toEqual(alert);
  });
  test("update omits attributes and the dismissal date", () => {
    const p = buildUpdatePayload({contentState: cs, now: START});
    expect(p.aps["event"]).toBe("update");
    expect(p.aps).not.toHaveProperty("attributes");
    expect(p.aps).not.toHaveProperty("attributes-type");
    expect(p.aps).not.toHaveProperty("dismissal-date");
  });
  test("omits stale-date and alert when not supplied", () => {
    const p = buildUpdatePayload({contentState: cs, now: START});
    expect(p.aps).not.toHaveProperty("stale-date");
    expect(p.aps).not.toHaveProperty("alert");
  });
  test("end carries a dismissal date and no stale date", () => {
    const p = buildEndPayload({
      contentState: cs, now: START, dismissalDate: START,
    });
    expect(p.aps["event"]).toBe("end");
    expect(p.aps["dismissal-date"]).toBe(Math.floor(START.getTime() / 1000));
    expect(p.aps).not.toHaveProperty("stale-date");
  });
});
