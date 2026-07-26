"use strict";

/**
 * @fileoverview Direct APNs HTTP/2 client for Live Activity pushes. This is
 * the one place that talks to Apple directly, because FCM can't set
 * `apns-push-type: liveactivity` — ordinary notifications still go through
 * `notification_utils.sendToEmployee`.
 *
 * Auth is a cached ES256 provider JWT, signed from the `.p8` key via
 * `node:crypto` and re-minted at PROVIDER_TOKEN_TTL_MS to stay ahead of
 * APNs' 1-hour expiry and 20-minute re-mint rate limit.
 *
 * Everything here is best-effort — nothing ever throws. Every path resolves
 * `{ok, status, reason, gone}`, and `gone` tells the caller to prune that
 * token row.
 *
 * Deps are injected (`{now, http2Impl, signer}`) so jest can drive the whole
 * module without opening a real socket.
 *
 * @module apns_client
 */

const crypto = require("node:crypto");
const http2 = require("node:http2");

// Production APNs, tried first — accepts tokens from a production-signed
// build (TestFlight / App Store).
const APNS_HOST = "https://api.push.apple.com";

// Sandbox APNs — we only fall back here when production returns
// `BadDeviceToken`, which is what a dev-signed build's sandbox token looks
// like when it hits the production host.
const APNS_SANDBOX_HOST = "https://api.sandbox.push.apple.com";

const BUNDLE_ID = "net.vogas.scheduling";

// ActivityKit requires the `.push-type.liveactivity` topic suffix — the
// plain bundle id gets rejected.
const LIVE_ACTIVITY_TOPIC = `${BUNDLE_ID}.push-type.liveactivity`;

// Re-mint just under the 1h APNs expiry and well over the 20-min re-mint
// throttle.
const PROVIDER_TOKEN_TTL_MS = 50 * 60 * 1000;

// A stuck socket must not hold a sweep hostage.
const REQUEST_TIMEOUT_MS = 10 * 1000;

// APNs reasons that mean the activity/token is dead and the row should go.
const GONE_REASONS = new Set([
  "BadDeviceToken",
  "Unregistered",
  "DeviceTokenNotForTopic",
  "ExpiredToken",
]);

// Checks the token shape before interpolating it into `:path`, since the
// registry rule only size-caps the field. This is really defense-in-depth —
// Node would reject bad path characters anyway — but failing here is
// cleaner and lets us mark the row prunable.
const TOKEN_SHAPE = /^[A-Za-z0-9]+$/;

// Closes a reused APNs session after this long idle. Keeping one session per
// host lets us amortize the TCP+TLS+HTTP/2 handshake across a sweep's
// pushes instead of paying for it on every push.
const SESSION_IDLE_TIMEOUT_MS = 30 * 1000;

// host -> {impl, session}. We drop an entry on transport error, close, idle
// timeout, or an impl swap (tests inject their own http2Impl).
const _sessions = new Map();

// Cached provider JWT, keyed by keyId+teamId so a rotated secret can't serve a
// stale signature.
let _cachedToken = null;

/**
 * Base64url of a Buffer or string, without padding.
 * @param {(!Buffer|string)} value
 * @return {string}
 */
function _b64url(value) {
  const buf = Buffer.isBuffer(value) ? value : Buffer.from(String(value));
  return buf.toString("base64")
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/, "");
}

/**
 * Default ES256 signer. Signs `input` with the `.p8` EC private key and
 * returns the raw 64-byte JOSE signature — that's `ieee-p1363`, not the DER
 * encoding `crypto` produces by default, since APNs rejects DER.
 * @param {string} input The `header.payload` signing input.
 * @param {string} authKey PEM contents of the APNs `.p8` auth key.
 * @return {!Buffer}
 */
function signEs256(input, authKey) {
  return crypto.sign("SHA256", Buffer.from(input), {
    key: authKey,
    dsaEncoding: "ieee-p1363",
  });
}

/**
 * Mints a fresh ES256 provider JWT. Pure apart from the injected clock and
 * signer — this function does no caching itself, see [providerToken] for that.
 * @param {{authKey: string, keyId: string, teamId: string,
 *   now: (Date|undefined), signer: (function(string, string): !Buffer|
 *   undefined)}} opts
 * @return {string}
 */
function mintProviderToken({authKey, keyId, teamId, now, signer}) {
  const iat = Math.floor((now ? now.getTime() : Date.now()) / 1000);
  const header = _b64url(JSON.stringify({alg: "ES256", kid: keyId}));
  const payload = _b64url(JSON.stringify({iss: teamId, iat}));
  const input = `${header}.${payload}`;
  const sign = signer || signEs256;
  return `${input}.${_b64url(sign(input, authKey))}`;
}

/**
 * Returns the cached provider JWT, re-minting it once it's older than
 * PROVIDER_TOKEN_TTL_MS or the key/team underneath it has changed.
 * @param {{authKey: string, keyId: string, teamId: string,
 *   now: (Date|undefined), signer: (function(string, string): !Buffer|
 *   undefined)}} opts
 * @return {string}
 */
function providerToken(opts) {
  const nowMs = opts.now ? opts.now.getTime() : Date.now();
  const fresh = _cachedToken &&
      _cachedToken.keyId === opts.keyId &&
      _cachedToken.teamId === opts.teamId &&
      nowMs - _cachedToken.mintedAtMs < PROVIDER_TOKEN_TTL_MS;
  if (fresh) return _cachedToken.token;
  const token = mintProviderToken(opts);
  _cachedToken = {
    token,
    keyId: opts.keyId,
    teamId: opts.teamId,
    mintedAtMs: nowMs,
  };
  return token;
}

/**
 * Drops the cached provider JWT, for tests or a secret rotation that
 * shouldn't wait out the TTL.
 * @return {void}
 */
function resetProviderTokenCache() {
  _cachedToken = null;
}

/**
 * The cached-or-fresh HTTP/2 session for [host], reused only while alive and
 * created by the same impl.
 * @param {!Object} impl The http2 implementation (injectable for tests).
 * @param {string} host
 * @return {!Object} A connected http2 session.
 */
function _sessionFor(impl, host) {
  const cached = _sessions.get(host);
  if (cached && cached.impl === impl &&
      !cached.session.closed && !cached.session.destroyed) {
    return cached.session;
  }
  if (cached) _dropSession(host);
  const session = impl.connect(host);
  if (typeof session.on === "function") {
    // A session-level error would otherwise surface as unhandled.
    session.on("error", () => _dropSession(host));
    session.on("close", () => {
      const entry = _sessions.get(host);
      if (entry && entry.session === session) _sessions.delete(host);
    });
  }
  if (typeof session.setTimeout === "function") {
    session.setTimeout(SESSION_IDLE_TIMEOUT_MS, () => _dropSession(host));
  }
  _sessions.set(host, {impl, session});
  return session;
}

/**
 * Closes and forgets the cached session for [host], if any.
 * @param {string} host
 * @return {void}
 */
function _dropSession(host) {
  const entry = _sessions.get(host);
  _sessions.delete(host);
  if (!entry) return;
  try {
    if (typeof entry.session.close === "function") entry.session.close();
  } catch (err) {
    // Not worth handling if closing an already-dead session fails.
  }
}

/**
 * Closes every cached APNs session. Used to isolate tests from each other,
 * and safe to call on shutdown too.
 * @return {void}
 */
function resetSessionCache() {
  for (const host of [..._sessions.keys()]) _dropSession(host);
}

/**
 * True when this APNs outcome means the token is dead and its registry row
 * should be pruned rather than retried.
 * @param {number} status
 * @param {string} reason
 * @return {boolean}
 */
function isActivityGone(status, reason) {
  return status === 410 || GONE_REASONS.has(String(reason || ""));
}

/**
 * The APNs `reason` string from a response body, or "" when the body is
 * absent/unparseable (a 200 has no body).
 * @param {string} raw
 * @return {string}
 */
function _reasonOf(raw) {
  if (!raw) return "";
  try {
    return String(JSON.parse(raw).reason || "");
  } catch (err) {
    return "";
  }
}

/**
 * Issues one HTTP/2 request on an already-connected session and resolves the
 * outcome; never rejects.
 * @param {!Object} client A connected http2 session.
 * @param {!Object} headers
 * @param {string} body
 * @param {number} timeoutMs
 * @return {!Promise<{ok: boolean, status: number, reason: string,
 *   gone: boolean}>}
 */
function _request(client, headers, body, timeoutMs) {
  return new Promise((resolve) => {
    let settled = false;
    let status = 0;
    let raw = "";
    const finish = (result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(result);
    };
    let req;
    const timer = setTimeout(() => {
      try {
        if (req && typeof req.close === "function") req.close();
      } catch (err) {
        // Not worth handling if closing an already-dead stream fails.
      }
      finish({ok: false, status: 0, reason: "timeout", gone: false});
    }, timeoutMs);
    try {
      req = client.request(headers);
    } catch (err) {
      finish({ok: false, status: 0, reason: String(err), gone: false});
      return;
    }
    req.on("response", (resHeaders) => {
      status = Number(resHeaders[":status"]) || 0;
    });
    req.on("data", (chunk) => {
      raw += chunk;
    });
    req.on("error", (err) => {
      finish({ok: false, status: 0, reason: String(err), gone: false});
    });
    req.on("end", () => {
      const reason = _reasonOf(raw);
      finish({
        ok: status === 200,
        status,
        reason,
        gone: isActivityGone(status, reason),
      });
    });
    req.end(body);
  });
}

/**
 * Sends ONE Live Activity push to ONE activity token. This never throws by
 * design — a `gone: true` result just means the caller should delete that
 * `liveActivityTokens` row.
 * @param {{token: string, payload: !Object, auth: !Object,
 *   topic: (string|undefined), pushType: (string|undefined),
 *   priority: (number|undefined), expiration: (number|undefined),
 *   collapseId: (string|undefined), now: (Date|undefined),
 *   http2Impl: (!Object|undefined),
 *   signer: (function(string, string): !Buffer|undefined),
 *   host: (string|undefined), timeoutMs: (number|undefined),
 *   logger: (!Object|undefined)}} opts `auth` is
 *   `{authKey, keyId, teamId}`; `token` is the ActivityKit push token.
 * @return {!Promise<{ok: boolean, status: number, reason: string,
 *   gone: boolean}>}
 */
async function sendLiveActivityPush(opts) {
  const {token, payload, auth, collapseId, expiration, logger} = opts || {};
  const impl = (opts && opts.http2Impl) || http2;
  const timeoutMs = (opts && opts.timeoutMs) || REQUEST_TIMEOUT_MS;
  if (!token || !payload || !auth || !auth.authKey) {
    return {ok: false, status: 0, reason: "missing-credentials", gone: false};
  }
  // A token that fails the shape check can never deliver — prune its row.
  if (!TOKEN_SHAPE.test(String(token))) {
    return {ok: false, status: 0, reason: "malformed-token", gone: true};
  }

  let jwt;
  try {
    jwt = providerToken({
      authKey: auth.authKey,
      keyId: auth.keyId,
      teamId: auth.teamId,
      now: opts.now,
      signer: opts.signer,
    });
  } catch (err) {
    if (logger) logger.warn("apns: live activity push failed", {err});
    return {ok: false, status: 0, reason: String(err), gone: false};
  }

  const headers = {
    ":method": "POST",
    ":path": `/3/device/${token}`,
    "authorization": `bearer ${jwt}`,
    "apns-push-type": opts.pushType || "liveactivity",
    "apns-topic": opts.topic || LIVE_ACTIVITY_TOPIC,
    "apns-priority": String(opts.priority || 10),
  };
  if (expiration != null) headers["apns-expiration"] = String(expiration);
  if (collapseId) headers["apns-collapse-id"] = String(collapseId);
  const body = JSON.stringify(payload);

  // One request against a per-host session, reused across this instance's
  // pushes. This never throws. A transport-level failure (status 0) drops
  // the session so the next push reconnects fresh; an HTTP-level outcome
  // just keeps the session around.
  const sendTo = async (host) => {
    try {
      const client = _sessionFor(impl, host);
      const result = await _request(client, headers, body, timeoutMs);
      if (result.status === 0) _dropSession(host);
      return result;
    } catch (err) {
      if (logger) logger.warn("apns: live activity push failed", {err, host});
      _dropSession(host);
      return {ok: false, status: 0, reason: String(err), gone: false};
    }
  };

  // An explicit host override (tests) is honoured verbatim — no dual-try.
  if (opts && opts.host) return sendTo(opts.host);

  // Try production first. `BadDeviceToken` looks like a sandbox token
  // hitting the production host, so we retry against sandbox before giving
  // up on the token. Any other outcome is returned as-is — only that
  // environment mismatch is worth a second request.
  const prod = await sendTo(APNS_HOST);
  if (prod.ok || prod.reason !== "BadDeviceToken") return prod;
  return sendTo(APNS_SANDBOX_HOST);
}

module.exports = {
  APNS_HOST,
  APNS_SANDBOX_HOST,
  BUNDLE_ID,
  LIVE_ACTIVITY_TOPIC,
  PROVIDER_TOKEN_TTL_MS,
  REQUEST_TIMEOUT_MS,
  signEs256,
  mintProviderToken,
  providerToken,
  resetProviderTokenCache,
  resetSessionCache,
  isActivityGone,
  sendLiveActivityPush,
};
