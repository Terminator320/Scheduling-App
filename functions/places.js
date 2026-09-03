const {onCall, HttpsError} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");

const {
  requireString,
  requireNumberInRange,
  readSessionToken,
  enforceDurableRateLimit,
  assertAdminCall,
} = require("./security");
const {GOOGLE_MAP_API_KEY} = require("./params");

// Both callables proxy the Places API v1 so the billing-sensitive key (kept in
// Secret Manager) never ships in the Flutter binary.

const PLACE_ID_PATTERN = /^[A-Za-z0-9_.-]+$/;
const INPUT_MAX_LEN = 200;

// Per-uid sliding-window rate limit, in-memory per function instance — a cheap,
// latency-free guard for the high-volume autocomplete path, chosen over the
// durable Firestore limiter the other routes use because this one fires on a
// keystroke debounce and a round-trip per request would be felt.
const RATE_LIMIT_MAX = 20;
const RATE_LIMIT_WINDOW_MS = 60_000;
const rateBuckets = new Map();

// placesGetDetails is low-volume, so it uses the durable Firestore cap rather
// than the in-memory limiter, with a limit generous enough for an admin
// entering many appointments at once.
const UPSTREAM_TIMEOUT_MS = 8_000;

const PLACES_DETAILS_RATE_MAX = 40;
const PLACES_DETAILS_RATE_WINDOW_MS = 15 * 60 * 1000;

// Reverse geocoding backs the live staff-location map (tap-driven, not
// keystroke-driven).
const REVERSE_GEOCODE_RATE_MAX = 120;
const REVERSE_GEOCODE_RATE_WINDOW_MS = 60 * 60 * 1000;
const REVERSE_GEOCODE_LOCALES = new Set(["en", "fr"]);

/**
 * The upstream error CODE carried by a non-200 body, or `""` when there is none
 * to read.
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
 * transport errors, non-200 responses, and JSON parse failures.
 * @param {string} url Fully-built request URL.
 * @param {?object} options fetch() options (method, headers, body).
 * @param {{label: string, uid: string}} opts label: log-message prefix
 * matching the callable name. uid: caller uid, logged only on transport
 * error.
 * @return {Promise<object>} parsed JSON body.
 */
async function fetchPlacesJson(url, options, {label, uid}) {
  // `fetch()` has no default timeout in Node, so a slow upstream held the
  // function open indefinitely.
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), UPSTREAM_TIMEOUT_MS);
  try {
    return await _fetchPlacesJson(url, options, {label, uid}, controller);
  } finally {
    clearTimeout(timer);
  }
}

/**
 * [fetchPlacesJson]'s body, under an already-armed abort [controller].
 * @param {string} url Fully-built request URL.
 * @param {?object} options fetch() options (method, headers, body).
 * @param {{label: string, uid: string}} opts See [fetchPlacesJson].
 * @param {!AbortController} controller Armed by the caller's timeout.
 * @return {Promise<object>} parsed JSON body.
 */
async function _fetchPlacesJson(url, options, {label, uid}, controller) {
  let response;
  try {
    response = await fetch(url, {...options, signal: controller.signal});
  } catch (err) {
    // `timedOut` is what separates "the upstream is slow" from "the network
    // broke" in Cloud Logging; both surface as a transport error otherwise.
    logger.error(`${label}: transport error`, {
      uid,
      err: err.message,
      timedOut: controller.signal.aborted,
    });
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
 * RATE_LIMIT_MAX requests within RATE_LIMIT_WINDOW_MS.
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
      // This is admin-only — address autocomplete is only surfaced on admin
      // appointment forms.
      await assertAdminCall(req, new Set(["input", "sessionToken"]));
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
      // Place details is admin-only for the same reason as autocomplete.
      await assertAdminCall(req, new Set(["placeId", "sessionToken"]));
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
// staff-location map.
const placesReverseGeocode = onCall(
    {
      enforceAppCheck: true,
      secrets: [GOOGLE_MAP_API_KEY],
    },
    async (req) => {
      // Only the admin-only live-location map calls this — same reasoning as
      // the other Places proxies.
      await assertAdminCall(req, new Set(["lat", "lng", "locale"]));
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
  // Exported for jest — it is the one thing standing between a rejected address
  // lookup and the typed street address landing in Cloud Logging.
  upstreamErrorCode,
  // Exported for jest — the test asserts it stays under the client's own
  // callable timeout, which is the whole point of the budget.
  UPSTREAM_TIMEOUT_MS,
};
