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

// Both callables proxy the Places API v1 so the billing-sensitive key never
// ships in the Flutter binary. The key lives in Secret Manager; clients must
// be authenticated and pass App Check.

const PLACE_ID_PATTERN = /^[A-Za-z0-9_.-]+$/;
const INPUT_MAX_LEN = 200;

// Per-uid sliding-window rate limit. In-memory, per function instance.
// IMPORTANT: Set a GCP billing alert on the Maps Platform API in the Firebase
// Console — this in-memory limit is per-instance and is not a hard billing cap.
// With maxInstances: 10, the effective ceiling is RATE_LIMIT_MAX × instance
// count requests per window. RATE_LIMIT_MAX is kept low to bound that product.
// This is a cheap, latency-free cost guard appropriate for the high-volume
// autocomplete path; auth-sensitive routes use the durable Firestore limiter
// instead (see enforceDurableRateLimit).
const RATE_LIMIT_MAX = 20;
const RATE_LIMIT_WINDOW_MS = 60_000;
const rateBuckets = new Map();

// placesGetDetails is low-volume (one billable call per address the user
// actually selects), so it gets the durable Firestore cap rather than the
// in-memory limiter — that one resets on cold start and multiplies by
// maxInstances, giving no real ceiling on the per-detail Places cost. The
// limit is generous enough for an admin entering many appointments at once.
const PLACES_DETAILS_RATE_MAX = 40;
const PLACES_DETAILS_RATE_WINDOW_MS = 15 * 60 * 1000;

// Reverse geocoding backs the live staff-location map — a tap-driven, not
// keystroke-driven, surface. A generous hourly cap comfortably covers normal
// admin usage while still bounding cost; the durable Firestore limiter is
// used (not the in-memory one) for the same cold-start/maxInstances reason as
// placesGetDetails.
const REVERSE_GEOCODE_RATE_MAX = 120;
const REVERSE_GEOCODE_RATE_WINDOW_MS = 60 * 60 * 1000;
const REVERSE_GEOCODE_LOCALES = new Set(["en", "fr"]);

/**
 * Shared response-handling triad for the three Places/Geocoding proxies:
 * transport-error catch, non-200 check, JSON-parse catch — each throwing the
 * same HttpsError codes the callables already relied on. Request
 * construction (method/headers/body) genuinely differs per callable, so that
 * stays at each call site; only the response half is deduped here.
 * @param {string} url Fully-built request URL.
 * @param {?object} options fetch() options (method, headers, body).
 * @param {{label: string, uid: string, logResponsePreview: boolean}} opts
 *   label: log-message prefix, matching the callable name (e.g.
 *     "placesAutocomplete") so each site's existing log messages/fields are
 *     preserved exactly. uid: caller uid, logged only on transport error
 *     (same as before). logResponsePreview: when true, reads and logs a
 *     200-char body preview on a non-200 response; placesReverseGeocode
 *     passes false to skip the extra read and keep its logs free of
 *     coordinate/address PII, its existing deliberate posture.
 * @return {Promise<object>} parsed JSON body.
 */
async function fetchPlacesJson(url, options, {label, uid, logResponsePreview}) {
  let response;
  try {
    response = await fetch(url, options);
  } catch (err) {
    logger.error(`${label}: transport error`, {uid, err: err.message});
    throw new HttpsError("internal", "places-transport");
  }

  if (!response.ok) {
    if (logResponsePreview) {
      const preview = (await response.text()).slice(0, 200);
      logger.warn(`${label}: upstream non-200`, {
        status: response.status,
        body: preview,
      });
    } else {
      logger.warn(`${label}: upstream non-200`, {status: response.status});
    }
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
      // Address autocomplete is only surfaced on admin-only appointment forms.
      // Gate on admin so a non-admin (or invited-but-inactive) principal can't
      // script the billable Places API — the in-memory limiter below is a
      // per-instance cost guard, not a hard ceiling.
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
            logResponsePreview: true,
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
      // Place details is admin-only for the same reason as autocomplete; it
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
            logResponsePreview: true,
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
// staff-location map. Uses the classic Geocoding API (not Places v1) since
// that's the endpoint that offers a reverse-geocode mode; the request is
// GET+query-string, so the key travels as a query param like the other
// Geocoding-family endpoints.
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

      // Round before the upstream call — high-precision jitter (e.g. from a
      // live GPS stream) would otherwise defeat any upstream/edge caching and
      // multiply the effective request volume for what is functionally the
      // same location.
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
            logResponsePreview: false,
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

module.exports = {placesAutocomplete, placesGetDetails, placesReverseGeocode};
