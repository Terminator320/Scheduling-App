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
const maintenance = require("./maintenance");
const waveCallables = require("./wave/callables");
const clientPropagation = require("./client_propagation");
const clientJobCount = require("./client_job_count");
const notifications = require("./notifications");

exports.syncUsersByUid = bridge.syncUsersByUid;
exports.propagateClientEdits = clientPropagation.propagateClientEdits;
exports.recountClientJobs = clientJobCount.recountClientJobs;
exports.placesAutocomplete = places.placesAutocomplete;
exports.placesGetDetails = places.placesGetDetails;
exports.placesReverseGeocode = places.placesReverseGeocode;
exports.validateUploadedImage = maintenance.validateUploadedImage;
exports.deleteAccount = account.deleteAccount;
exports.createEmployeeAccount = employeeAccounts.createEmployeeAccount;
exports.completeEmployeeSetup = employeeAccounts.completeEmployeeSetup;
exports.deleteEmployeeAccount = employeeAccounts.deleteEmployeeAccount;
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
