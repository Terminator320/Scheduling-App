/// The shared password every employee account is created with.
///
/// **Hand-mirrored from `DEFAULT_PASSWORD` in
/// `functions/employee_accounts.js`, which is the authority.** Change one and
/// change the other, or the roster row tells an admin a password the account
/// was never given. Both sides pin the literal in a test — here in
/// `pending_invite_tile_test.dart`, there in `employee_accounts.test.js` — so a
/// one-sided rotation fails the suite instead of drifting silently.
///
/// This is only ever a DISPLAY fallback. Any surface that has just called
/// `createEmployeeAccount` shows the password the server echoed back
/// (`NewAccountCredentials.password`) instead of this, so a drift can never
/// reach the one screen where it would matter most.
///
/// It is deliberately not a secret — the admin reads it out loud. What keeps
/// the account safe is that it stays `invited`, and an invited account is
/// granted nothing by `firestore.rules` until setup replaces this password.
const String kDefaultStartingPassword = 'Welcome123!';
