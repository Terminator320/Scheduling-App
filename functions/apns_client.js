"use strict";

/**
 * @fileoverview Direct APNs HTTP/2 client for Live Activity pushes. FCM has no
 * way to set `apns-push-type: liveactivity`, so this is the ONE path in the
 * backend that talks to Apple directly; every ordinary notification still goes
 * through `notification_utils.sendToEmployee`.
 *
 * Auth is token-based: an ES256 provider JWT signed from the `.p8` key with
 * `node:crypto` (deliberately no new npm dependency). The JWT is cached and
 * re-minted at PROVIDER_TOKEN_TTL_MS — APNs rejects tokens older than one hour
 * AND rate-limits providers that re-mint more often than every 20 minutes, so
 * neither "sign per request" nor "sign once forever" is acceptable.
 *
 * Failure posture matches the design doc: a Live Activity is additive and
 * best-effort, so nothing here ever throws to the caller. Every path resolves
 * `{ok, status, reason, gone}` and a `gone` result (410 / BadDeviceToken /
 * Unregistered) tells the caller to prune that token row.
 *
 * Deps are injected (`{now, http2Impl, signer}`) so jest drives the whole
 * module with no socket.
 *
 * @module apns_client
 */

const crypto = require("node:crypto");
const http2 = require("node:http2");

// Production APNs. There is no sandbox path here: Live Activities are only
// verified on real hardware running a Release/TestFlight build.
const APNS_HOST = "https://api.push.apple.com";

const BUNDLE_ID = "net.vogas.scheduling";

// ActivityKit requires the `.push-type.liveactivity` topic suffix; the plain
// bundle id is rejected.
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

// Cached provider JWT. Keyed by keyId+teamId so a rotated secret can't serve a
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
 * Default ES256 signer: signs `input` with the `.p8` EC private key and
 * returns the raw 64-byte JOSE signature (`ieee-p1363`, NOT the DER encoding
 * `crypto` produces by default — APNs rejects DER).
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
 * signer — no caching here, see [providerToken].
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
 * Cached provider JWT, re-minted once it is older than
 * PROVIDER_TOKEN_TTL_MS or when the key/team changed under it.
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
 * Drops the cached provider JWT. For tests and for a secret rotation that
 * should not wait out the TTL.
 * @return {void}
 */
function resetProviderTokenCache() {
  _cachedToken = null;
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
 * outcome. Never rejects.
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
        // Closing a already-dead stream is not interesting.
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
 * Sends ONE Live Activity push to ONE activity token. Best-effort by
 * contract: it never throws, and a `gone: true` result means the caller
 * should delete that `liveActivityTokens` row.
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
  const host = (opts && opts.host) || APNS_HOST;
  const timeoutMs = (opts && opts.timeoutMs) || REQUEST_TIMEOUT_MS;
  if (!token || !payload || !auth || !auth.authKey) {
    return {ok: false, status: 0, reason: "missing-credentials", gone: false};
  }
  let client = null;
  try {
    const jwt = providerToken({
      authKey: auth.authKey,
      keyId: auth.keyId,
      teamId: auth.teamId,
      now: opts.now,
      signer: opts.signer,
    });
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
    client = impl.connect(host);
    if (typeof client.on === "function") {
      // A session-level error would otherwise surface as an unhandled event.
      client.on("error", () => {});
    }
    return await _request(
        client, headers, JSON.stringify(payload), timeoutMs);
  } catch (err) {
    if (logger) logger.warn("apns: live activity push failed", {err});
    return {ok: false, status: 0, reason: String(err), gone: false};
  } finally {
    try {
      if (client && typeof client.close === "function") client.close();
    } catch (err) {
      // Nothing useful to do about a failed session teardown.
    }
  }
}

module.exports = {
  APNS_HOST,
  BUNDLE_ID,
  LIVE_ACTIVITY_TOPIC,
  PROVIDER_TOKEN_TTL_MS,
  REQUEST_TIMEOUT_MS,
  signEs256,
  mintProviderToken,
  providerToken,
  resetProviderTokenCache,
  isActivityGone,
  sendLiveActivityPush,
};
