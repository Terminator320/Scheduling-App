const {EventEmitter} = require("node:events");

const {
  LIVE_ACTIVITY_TOPIC,
  PROVIDER_TOKEN_TTL_MS,
  mintProviderToken,
  providerToken,
  resetProviderTokenCache,
  isActivityGone,
  sendLiveActivityPush,
} = require("../apns_client");

const AUTH = {authKey: "-----PEM-----", keyId: "KID123", teamId: "TEAM99"};

let signCalls = 0;
const signer = (input) => {
  signCalls += 1;
  return Buffer.from(`sig${signCalls}`);
};

/**
 * A fake http2 session whose one request replays the given outcome.
 * @param {{status: number, body: (string|undefined),
 *   error: (Error|undefined), throwOnRequest: (boolean|undefined)}} outcome
 * @return {!Object} `{impl, sent}` — `sent` records the request headers/body.
 */
function fakeHttp2(outcome) {
  const sent = {headers: null, body: null, closed: false, host: null};
  const impl = {
    connect(host) {
      sent.host = host;
      return {
        on() {},
        close() {
          sent.closed = true;
        },
        request(headers) {
          if (outcome.throwOnRequest) throw new Error("connect refused");
          sent.headers = headers;
          const req = new EventEmitter();
          req.close = () => {};
          req.end = (body) => {
            sent.body = body;
            setImmediate(() => {
              if (outcome.error) {
                req.emit("error", outcome.error);
                return;
              }
              req.emit("response", {":status": outcome.status});
              if (outcome.body) req.emit("data", outcome.body);
              req.emit("end");
            });
          };
          return req;
        },
      };
    },
  };
  return {impl, sent};
}

const send = (outcome, extra) => {
  const {impl, sent} = fakeHttp2(outcome);
  return sendLiveActivityPush({
    token: "ACTIVITYTOKEN",
    payload: {aps: {event: "start"}},
    auth: AUTH,
    now: new Date("2026-07-20T12:00:00.000Z"),
    signer,
    http2Impl: impl,
    ...(extra || {}),
  }).then((result) => ({result, sent}));
};

beforeEach(() => {
  resetProviderTokenCache();
  signCalls = 0;
});

describe("mintProviderToken", () => {
  test("emits a three-segment ES256 JWT with the key id in the header", () => {
    const jwt = mintProviderToken({
      ...AUTH, now: new Date("2026-07-20T12:00:00.000Z"), signer,
    });
    const parts = jwt.split(".");
    expect(parts).toHaveLength(3);
    const header = JSON.parse(Buffer.from(parts[0], "base64").toString());
    const payload = JSON.parse(Buffer.from(parts[1], "base64").toString());
    expect(header).toEqual({alg: "ES256", kid: "KID123"});
    expect(payload).toEqual({
      iss: "TEAM99",
      iat: Math.floor(Date.parse("2026-07-20T12:00:00.000Z") / 1000),
    });
  });
  test("emits base64url with no padding or unsafe characters", () => {
    const jwt = mintProviderToken({...AUTH, signer});
    expect(jwt).not.toMatch(/[+/=]/);
  });
});

describe("providerToken caching", () => {
  const at = (ms) => providerToken({
    ...AUTH, now: new Date(ms), signer,
  });

  test("signs once and reuses the token inside the TTL", () => {
    const first = at(0);
    const second = at(PROVIDER_TOKEN_TTL_MS - 1);
    expect(second).toBe(first);
    expect(signCalls).toBe(1);
  });
  test("re-mints once the TTL has elapsed", () => {
    const first = at(0);
    const second = at(PROVIDER_TOKEN_TTL_MS);
    expect(second).not.toBe(first);
    expect(signCalls).toBe(2);
  });
  test("re-mints when the key id rotates under it", () => {
    at(0);
    const rotated = providerToken({
      ...AUTH, keyId: "KID999", now: new Date(1), signer,
    });
    const header = JSON.parse(
        Buffer.from(rotated.split(".")[0], "base64").toString());
    expect(header.kid).toBe("KID999");
    expect(signCalls).toBe(2);
  });
});

describe("isActivityGone", () => {
  test("treats 410 as gone", () => {
    expect(isActivityGone(410, "")).toBe(true);
  });
  test("treats BadDeviceToken as gone regardless of status", () => {
    expect(isActivityGone(400, "BadDeviceToken")).toBe(true);
  });
  test("does not treat a transient 500 as gone", () => {
    expect(isActivityGone(500, "InternalServerError")).toBe(false);
  });
});

describe("sendLiveActivityPush", () => {
  test("sets the liveactivity push type, topic and priority", async () => {
    const {result, sent} = await send({status: 200});
    expect(result).toEqual({ok: true, status: 200, reason: "", gone: false});
    expect(sent.headers["apns-push-type"]).toBe("liveactivity");
    expect(sent.headers["apns-topic"]).toBe(LIVE_ACTIVITY_TOPIC);
    expect(sent.headers["apns-topic"])
        .toBe("net.vogas.scheduling.push-type.liveactivity");
    expect(sent.headers["apns-priority"]).toBe("10");
    expect(sent.headers[":path"]).toBe("/3/device/ACTIVITYTOKEN");
    expect(sent.headers[":method"]).toBe("POST");
    expect(sent.headers["authorization"]).toMatch(/^bearer \S+\.\S+\.\S+$/);
    expect(JSON.parse(sent.body)).toEqual({aps: {event: "start"}});
    expect(sent.host).toBe("https://api.push.apple.com");
  });
  test("adds a collapse id only when one is supplied", async () => {
    const plain = await send({status: 200});
    expect(plain.sent.headers).not.toHaveProperty("apns-collapse-id");
    const tagged = await send({status: 200}, {collapseId: "appt-1"});
    expect(tagged.sent.headers["apns-collapse-id"]).toBe("appt-1");
  });
  test("closes the session after the request", async () => {
    const {sent} = await send({status: 200});
    expect(sent.closed).toBe(true);
  });
  test("flags a 410 as gone so the caller prunes the row", async () => {
    const {result} = await send({
      status: 410, body: JSON.stringify({reason: "Unregistered"}),
    });
    expect(result).toEqual({
      ok: false, status: 410, reason: "Unregistered", gone: true,
    });
  });
  test("flags a 400 BadDeviceToken as gone", async () => {
    const {result} = await send({
      status: 400, body: JSON.stringify({reason: "BadDeviceToken"}),
    });
    expect(result.gone).toBe(true);
    expect(result.ok).toBe(false);
  });
  test("does not flag a transient 503 as gone", async () => {
    const {result} = await send({
      status: 503, body: JSON.stringify({reason: "ServiceUnavailable"}),
    });
    expect(result).toEqual({
      ok: false, status: 503, reason: "ServiceUnavailable", gone: false,
    });
  });
  test("returns rather than throws on a stream error", async () => {
    const {result} = await send({status: 0, error: new Error("socket reset")});
    expect(result.ok).toBe(false);
    expect(result.gone).toBe(false);
    expect(result.reason).toContain("socket reset");
  });
  test("returns rather than throws when the session cannot open", async () => {
    const {result} = await send({status: 0, throwOnRequest: true});
    expect(result.ok).toBe(false);
    expect(result.reason).toContain("connect refused");
  });
  test("returns rather than throws on an unparseable error body", async () => {
    const {result} = await send({status: 400, body: "<html>nope</html>"});
    expect(result).toEqual({
      ok: false, status: 400, reason: "", gone: false,
    });
  });
  test("short-circuits with missing-credentials and never dials", async () => {
    const {impl, sent} = fakeHttp2({status: 200});
    const result = await sendLiveActivityPush({
      token: "T", payload: {}, auth: null, http2Impl: impl, signer,
    });
    expect(result).toEqual({
      ok: false, status: 0, reason: "missing-credentials", gone: false,
    });
    expect(sent.host).toBeNull();
  });
});
