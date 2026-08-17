const {onCall, HttpsError} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");

const {
  assertPayloadShape,
  requireString,
  requireNumberInRange,
  readSessionToken,
  enforceDurableRateLimit,
  assertAdmin,
} = require("./security");
const {GOOGLE_MAP_API_KEY} = require("./params");

// Both callables proxy the Places API v1 so the billing-sensitive key (kept
// in Secret Manager) never ships in the Flutter binary. Clients must be
// authenticated and pass App Check.

const PLACE_ID_PATTERN = /^[A-Za-z0-9_.-]+$/;
const INPUT_MAX_LEN = 200;

// Per-uid sliding-window rate limit, in-memory per function instance — a
// cheap, latency-free guard for the high-volume autocomplete path. Set a GCP
// billing alert too — other routes use the durable Firestore limiter instead.
const RATE_LIMIT_MAX = 20;
const RATE_LIMIT_WINDOW_MS = 60_000;
const rateBuckets = new Map();

// placesGetDetails is low-volume, so it uses the durable Firestore cap rather
// than the in-memory limiter, with a limit generous enough for an admin
// entering many appointments at once.
const PLACES_DETAILS_RATE_MAX = 40;
const PLACES_DETAILS_RATE_WINDOW_MS = 15 * 60 * 1000;

// Reverse geocoding backs the live staff-location map (tap-driven, not
// keystroke-driven). A generous hourly cap via the durable Firestore limiter
// covers normal admin usage while bounding cost.
const REVERSE_GEOCODE_RATE_MAX = 120;
const REVERSE_GEOCODE_RATE_WINDOW_MS = 60 * 60 * 1000;
const REVERSE_GEOCODE_LOCALES = new Set(["en", "fr"]);

/**
 * The upstream error CODE carried by a non-200 body, or `""` when there is
 * none to read.
 *
 * Deliberately never the message, and never the body. Places API (New) and
 * the Geocoding API both echo the offending request field back in prose
 * (`Invalid value at 'input' ...`), so a rejected autocomplete request
 * carries the client street address an admin was mid-typing — into Cloud
 * Logging, where there is no retention control over it. `placesReverseGeocode`
 * opted out of body logging for exactly that reason while the two Places
 * callables opted in, which left the two paths inconsistent about the same
 * class of data.
 *
 * The codes themselves are a fixed enum vocabulary (`INVALID_ARGUMENT`,
 * `PERMISSION_DENIED`, `REQUEST_DENIED`, `RESOURCE_EXHAUSTED`) or a numeric
 * HTTP status, so they carry no caller data — and the shape test is what
 * keeps it that way if an upstream ever puts prose in the field.
 *
 * @param {string} bodyText Raw response body.
 * @return {string} An enum-shaped code, or "".
 */
function upstreamErrorCode(bodyText) {
  let parsed;
  try {
    parsed = JSON.parse(bodyText);
  } catch (err) {
    return "";
  }
  const error = (parsed && parsed.error) || {};
  const raw = error.status || error.code || (parsed && parsed.status) || "";
  const code = String(raw);
  return /^[A-Z0-9_]{1,40}$/.test(code) ? code : "";
}

/**
 * Handles the three things every Places/Geocoding proxy needs to check —
 * transport errors, non-200 responses, and JSON parse failures. Request
 * construction stays at each call site, since it differs per callable.
 * @param {string} url Fully-built request URL.
 * @param {?object} options fetch() options (method, headers, body).
 * @param {{label: string, uid: string}} opts label: log-message prefix
 *   matching the callable name. uid: caller uid, logged only on transport
 *   error.
 * @return {Promise<object>} parsed JSON body.
 */
async function fetchPlacesJson(url, options, {label, uid}) {
  let response;
  try {
    response = await fetch(url, options);
  } catch (err) {
    logger.error(`${label}: transport error`, {uid, err: err.message});
    throw new HttpsError("internal", "places-transport");
  }

  if (!response.ok) {
    // The structured code only, NEVER the body — see [upstreamErrorCode].
    let body = "";
    try {
      body = await response.text();
    } catch (err) {
      body = "";
    }
    logger.warn(`${label}: upstream non-200`, {
      status: response.status,
      code: upstreamErrorCode(body),
    });
    throw new HttpsError("internal", "places-upstream");
  }

  try {
    return await response.json();
  } catch (err) {
    logger.warn(`${label}: invalid JSON in 200 response`, {
      status: response.status,
      err: err.message,
    });
    throw new HttpsError("internal", "places-upstream");
  }
}

/**
 * Throws HttpsError("resource-exhausted") when the caller's uid exceeds
 * RATE_LIMIT_MAX requests within RATE_LIMIT_WINDOW_MS. Mutates the bucket.
 * @param {string} uid Firebase Auth uid of the caller.
 */
function enforceRateLimit(uid) {
  const now = Date.now();
  // Evict expired entries when the map grows beyond the expected user count.
  if (rateBuckets.size > 200) {
    for (const [key, val] of rateBuckets) {
      if (now - val.windowStart >= RATE_LIMIT_WINDOW_MS) {
        rateBuckets.delete(key);
      }
    }
  }
  const bucket = rateBuckets.get(uid);
  if (!bucket || now - bucket.windowStart >= RATE_LIMIT_WINDOW_MS) {
    rateBuckets.set(uid, {count: 1, windowStart: now});
    return;
  }
  bucket.count += 1;
  if (bucket.count > RATE_LIMIT_MAX) {
    throw new HttpsError(
        "resource-exhausted",
        "too-many-places-requests",
    );
  }
}

const placesAutocomplete = onCall(
    {
      enforceAppCheck: true,
      secrets: [GOOGLE_MAP_API_KEY],
    },
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      // This is admin-only — address autocomplete is only surfaced on admin
      // appointment forms. The in-memory limiter below is a cost guard, not
      // a hard cap.
      await assertAdmin(req.auth.uid);
      assertPayloadShape(req.data, new Set(["input", "sessionToken"]));
      const input = requireString(req.data, "input", INPUT_MAX_LEN);
      const sessionToken = readSessionToken(req.data);

      enforceRateLimit(req.auth.uid);

      const body = {
        input,
        includedRegionCodes: ["ca"],
        locationBias: {
          circle: {
            // Montréal
            center: {latitude: 45.5017, longitude: -73.5673},
            radius: 50000.0,
          },
        },
      };
      if (sessionToken) body.sessionToken = sessionToken;

      const data = await fetchPlacesJson(
          "https://places.googleapis.com/v1/places:autocomplete",
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "X-Goog-Api-Key": GOOGLE_MAP_API_KEY.value().trim(),
              "X-Goog-FieldMask": "suggestions.placePrediction.placeId," +
                "suggestions.placePrediction.text",
            },
            body: JSON.stringify(body),
          },
          {
            label: "placesAutocomplete",
            uid: req.auth.uid,
          },
      );
      return {suggestions: Array.isArray(data.suggestions) ?
        data.suggestions : []};
    },
);

const placesGetDetails = onCall(
    {
      enforceAppCheck: true,
      secrets: [GOOGLE_MAP_API_KEY],
    },
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      // Place details is admin-only for the same reason as autocomplete. It
      // also keeps the durable Firestore rate cap below.
      await assertAdmin(req.auth.uid);
      assertPayloadShape(req.data, new Set(["placeId", "sessionToken"]));
      const placeId = requireString(req.data, "placeId", 256);
      if (!PLACE_ID_PATTERN.test(placeId)) {
        throw new HttpsError("invalid-argument", "invalid-placeId");
      }
      const sessionToken = readSessionToken(req.data);

      await enforceDurableRateLimit(
          "placesGetDetails",
          req.auth.uid,
          PLACES_DETAILS_RATE_MAX,
          PLACES_DETAILS_RATE_WINDOW_MS,
      );

      const url = new URL(
          `https://places.googleapis.com/v1/places/${encodeURIComponent(
              placeId,
          )}`,
      );
      if (sessionToken) url.searchParams.set("sessionToken", sessionToken);

      const data = await fetchPlacesJson(
          url.toString(),
          {
            method: "GET",
            headers: {
              "X-Goog-Api-Key": GOOGLE_MAP_API_KEY.value().trim(),
              "X-Goog-FieldMask": "formattedAddress,addressComponents",
            },
          },
          {
            label: "placesGetDetails",
            uid: req.auth.uid,
          },
      );
      return {
        formattedAddress: typeof data.formattedAddress === "string" ?
          data.formattedAddress : "",
        addressComponents: Array.isArray(data.addressComponents) ?
          data.addressComponents : [],
      };
    },
);

// Reverse-geocodes a lat/lng into a human-readable address for the live
// staff-location map. Uses the classic Geocoding API, since that's the
// endpoint that offers reverse-geocode mode.
const placesReverseGeocode = onCall(
    {
      enforceAppCheck: true,
      secrets: [GOOGLE_MAP_API_KEY],
    },
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      // Only the admin-only live-location map calls this — same reasoning as
      // the other Places proxies.
      await assertAdmin(req.auth.uid);
      assertPayloadShape(req.data, new Set(["lat", "lng", "locale"]));
      const lat = requireNumberInRange(req.data && req.data.lat, "lat",
          -90, 90);
      const lng = requireNumberInRange(req.data && req.data.lng, "lng",
          -180, 180);
      const locale = requireString(req.data, "locale", 2);
      if (!REVERSE_GEOCODE_LOCALES.has(locale)) {
        throw new HttpsError("invalid-argument", "invalid-locale");
      }

      await enforceDurableRateLimit(
          "placesReverseGeocode",
          req.auth.uid,
          REVERSE_GEOCODE_RATE_MAX,
          REVERSE_GEOCODE_RATE_WINDOW_MS,
      );

      // Round before the upstream call so GPS jitter doesn't defeat
      // upstream/edge caching for what is functionally the same location.
      const roundedLat = Math.round(lat * 1e5) / 1e5;
      const roundedLng = Math.round(lng * 1e5) / 1e5;

      const url = new URL(
          "https://maps.googleapis.com/maps/api/geocode/json",
      );
      url.searchParams.set("latlng", `${roundedLat},${roundedLng}`);
      url.searchParams.set("language", locale);
      url.searchParams.set("key", GOOGLE_MAP_API_KEY.value().trim());

      // Never log lat/lng or the resolved address — staff-location PII.
      const data = await fetchPlacesJson(
          url.toString(),
          undefined,
          {
            label: "placesReverseGeocode",
            uid: req.auth.uid,
          },
      );

      if (data.status === "ZERO_RESULTS") {
        return {address: null};
      }
      if (data.status !== "OK") {
        logger.warn("placesReverseGeocode: upstream status not OK", {
          status: data.status,
        });
        throw new HttpsError("internal", "places-upstream");
      }

      const results = Array.isArray(data.results) ? data.results : [];
      const address = results.length > 0 &&
        typeof results[0].formatted_address === "string" ?
        results[0].formatted_address : null;
      return {address};
    },
);

module.exports = {
  placesAutocomplete,
  placesGetDetails,
  placesReverseGeocode,
  // Exported for jest — it is the one thing standing between a rejected
  // address lookup and the typed street address landing in Cloud Logging.
  upstreamErrorCode,
};
