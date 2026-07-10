const {setGlobalOptions} = require("firebase-functions");
const {initializeApp} = require("firebase-admin/app");

setGlobalOptions({maxInstances: 10});

initializeApp();

// Thin wiring surface: each function group lives in its own module (auth/admin
// guards in security.js, the usersByUid bridge in bridge.js, Places proxies in
// places.js, account deletion in account.js, signup-code invite callables in
// invites.js, scheduled maintenance + image validation in maintenance.js, and
// the Wave orchestration callables in wave/callables.js). Re-export each
// trigger here under its original name so the deployed function set is stable.
const bridge = require("./bridge");
const places = require("./places");
const account = require("./account");
const invites = require("./invites");
const maintenance = require("./maintenance");
const waveCallables = require("./wave/callables");
const clientPropagation = require("./client_propagation");

exports.syncUsersByUid = bridge.syncUsersByUid;
exports.propagateClientEdits = clientPropagation.propagateClientEdits;
exports.placesAutocomplete = places.placesAutocomplete;
exports.placesGetDetails = places.placesGetDetails;
exports.validateUploadedImage = maintenance.validateUploadedImage;
exports.deleteAccount = account.deleteAccount;
exports.createEmployeeInvite = invites.createEmployeeInvite;
exports.redeemSignupCode = invites.redeemSignupCode;
exports.purgeExpiredHistory = maintenance.purgeExpiredHistory;
exports.waveBootstrap = waveCallables.waveBootstrap;
exports.waveGetConnection = waveCallables.waveGetConnection;
exports.waveImportCustomers = waveCallables.waveImportCustomers;
exports.waveUpsertCustomer = waveCallables.waveUpsertCustomer;
exports.waveSyncWorker = waveCallables.waveSyncWorker;
