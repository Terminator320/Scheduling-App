/// The project's one email normalization: trim, then lowercase.
///
/// Every read and write that keys on an address goes through this — the
/// `users` uniqueness query, the callable payloads, sign-in, and the stored
/// client contact emails. The two halves must agree everywhere or a lookup
/// misses a doc that is really there: `users.email` is an employee's SIGN-IN
/// identity, so a stray " Jane@Example.com " compared against a stored
/// "jane@example.com" reads as a different person.
String normalizeEmail(String email) => email.trim().toLowerCase();
