const {setGlobalOptions} = require("firebase-functions");
const {initializeApp} = require("firebase-admin/app");

setGlobalOptions({maxInstances: 10});

initializeApp();

// This file is just wiring: each function group lives in its own domain
// module, and we re-export it here under its original name so the deployed
// function set stays stable.
const bridge = require("./bridge");
const places = require("./places");
const account = require("./account");
const employeeAccounts = require("./employee_accounts");
// TODO(george): delete with the 1.37.1 shim (#compat-1.37.1)
const invites = require("./invites");
const maintenance = require("./maintenance");
const waveCallables = require("./wave/callables");
const clientPropagation = require("./client_propagation");
const clientJobCount = require("./client_job_count");
const clients = require("./clients");
const notifications = require("./notifications");

exports.syncUsersByUid = bridge.syncUsersByUid;
exports.propagateClientEdits = clientPropagation.propagateClientEdits;
exports.recountClientJobs = clientJobCount.recountClientJobs;
exports.deleteClient = clients.deleteClient;
exports.placesAutocomplete = places.placesAutocomplete;
exports.placesGetDetails = places.placesGetDetails;
exports.placesReverseGeocode = places.placesReverseGeocode;
exports.validateUploadedImage = maintenance.validateUploadedImage;
exports.deleteAccount = account.deleteAccount;
exports.createEmployeeAccount = employeeAccounts.createEmployeeAccount;
exports.completeEmployeeSetup = employeeAccounts.completeEmployeeSetup;
exports.deleteEmployeeAccount = employeeAccounts.deleteEmployeeAccount;
exports.changeEmployeeEmail = employeeAccounts.changeEmployeeEmail;
// BACKWARD-COMPAT SHIM for the 1.37.1+64 build still on the App Store, which
// calls these two from firebase_employees_repository.dart (:82 and :109). P4c
// replaced the signup-code flow with createEmployeeAccount /
// completeEmployeeSetup, but deleting these while 1.37.1 is live would break
// every invite already in flight AND the admin's "Invite employee" button.
// Retire them — with invites.js, signup_code_utils.js, the /signupCodes rules
// block, its TTL policy in firestore.indexes.json, and the fourth /users read
// clause — once no 1.37.1 build remains in the field.
// TODO(george): delete with the 1.37.1 shim (#compat-1.37.1)
exports.createEmployeeInvite = invites.createEmployeeInvite;
exports.redeemSignupCode = invites.redeemSignupCode;
exports.purgeExpiredHistory = maintenance.purgeExpiredHistory;
exports.waveBootstrap = waveCallables.waveBootstrap;
exports.waveGetConnection = waveCallables.waveGetConnection;
exports.waveSetImportSchedule = waveCallables.waveSetImportSchedule;
exports.waveImportCustomers = waveCallables.waveImportCustomers;
exports.waveScheduledImport = waveCallables.waveScheduledImport;
exports.waveUpsertCustomer = waveCallables.waveUpsertCustomer;
exports.waveSyncWorker = waveCallables.waveSyncWorker;
exports.notifyAppointmentChanges = notifications.notifyAppointmentChanges;
exports.sendUpcomingJobReminders = notifications.sendUpcomingJobReminders;
exports.sendDailyJobDigest = notifications.sendDailyJobDigest;
exports.sendOverdueJobPrompts = notifications.sendOverdueJobPrompts;
