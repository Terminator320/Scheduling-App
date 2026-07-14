const {onCall, HttpsError} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");

const {
  assertPayloadShape,
  requireString,
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

      let response;
      try {
        response = await fetch(
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
        );
      } catch (err) {
        logger.error("placesAutocomplete: transport error", {
          uid: req.auth.uid,
          err: err.message,
        });
        throw new HttpsError("internal", "places-transport");
      }

      if (!response.ok) {
        const preview = (await response.text()).slice(0, 200);
        logger.warn("placesAutocomplete: upstream non-200", {
          status: response.status,
          body: preview,
        });
        throw new HttpsError("internal", "places-upstream");
      }

      let data;
      try {
        data = await response.json();
      } catch (err) {
        logger.warn("placesAutocomplete: invalid JSON in 200 response", {
          status: response.status,
          err: err.message,
        });
        throw new HttpsError("internal", "places-upstream");
      }
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

      let response;
      try {
        response = await fetch(url.toString(), {
          method: "GET",
          headers: {
            "X-Goog-Api-Key": GOOGLE_MAP_API_KEY.value().trim(),
            "X-Goog-FieldMask": "formattedAddress,addressComponents",
          },
        });
      } catch (err) {
        logger.error("placesGetDetails: transport error", {
          uid: req.auth.uid,
          err: err.message,
        });
        throw new HttpsError("internal", "places-transport");
      }

      if (!response.ok) {
        const preview = (await response.text()).slice(0, 200);
        logger.warn("placesGetDetails: upstream non-200", {
          status: response.status,
          body: preview,
        });
        throw new HttpsError("internal", "places-upstream");
      }

      let data;
      try {
        data = await response.json();
      } catch (err) {
        logger.warn("placesGetDetails: invalid JSON in 200 response", {
          status: response.status,
          err: err.message,
        });
        throw new HttpsError("internal", "places-upstream");
      }
      return {
        formattedAddress: typeof data.formattedAddress === "string" ?
          data.formattedAddress : "",
        addressComponents: Array.isArray(data.addressComponents) ?
          data.addressComponents : [],
      };
    },
);

module.exports = {placesAutocomplete, placesGetDetails};
