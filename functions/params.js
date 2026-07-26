"use strict";

/**
 * @fileoverview Shared function parameters/secrets. A secret param can only
 * be `defineSecret`'d once, so its single definition lives here for every
 * consumer to import — same "shared config, not a feature dependency" rule
 * as security.js's shared guards.
 *
 * @module params
 */

const {defineSecret} = require("firebase-functions/params");

// Google Maps Platform key (Places proxy + Routes travel-time sweep), stored
// in Secret Manager and never shipped in the Flutter binary.
const GOOGLE_MAP_API_KEY = defineSecret("GOOGLE_MAP_API_KEY");

// APNs token-based auth for the direct HTTP/2 Live Activity path — FCM can't
// send `apns-push-type: liveactivity`. AUTH_KEY holds the raw `.p8` contents.
const APNS_AUTH_KEY = defineSecret("APNS_AUTH_KEY");
const APNS_KEY_ID = defineSecret("APNS_KEY_ID");
const APNS_TEAM_ID = defineSecret("APNS_TEAM_ID");

module.exports = {
  GOOGLE_MAP_API_KEY,
  APNS_AUTH_KEY,
  APNS_KEY_ID,
  APNS_TEAM_ID,
};
