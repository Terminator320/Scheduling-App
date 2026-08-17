"use strict";

// Shared "reject any argument this script doesn't recognize" rule for the
// one-off backfill scripts in this directory.
//
// Every script here reads its own flags with a bare
// `argv.includes("--dry-run")`-style check, so a typo'd flag — `--dryrun`,
// `--dry_run`, `--dry-run=true` — silently evaluates to false and sends a
// bulk write against prod data LIVE instead of failing loudly. Refusing any
// argument that isn't a flag the script explicitly knows turns every one of
// those typos into an error before a document is read.
//
// This module owns ONLY that rejection rule. The flag LISTS stay local to
// each script — they legitimately differ (some take `--since=`, most don't) —
// so each script keeps its own `EXACT_FLAGS`/`PREFIX_FLAGS` and a thin local
// `assertKnownFlags(argv)` wrapper that calls into this one.

/**
 * Throws when `argv` holds an argument not covered by `exact` or `prefixes`.
 *
 * @param {!Array<string>} argv Arguments after the node + script paths.
 * @param {{exact: !Array<string>, prefixes: (!Array<string>|undefined)}} known
 *   `exact` flags are bare switches matched VERBATIM (e.g. "--dry-run") — an
 *   exact match is what makes a typo fail instead of silently reading as
 *   false. `prefixes` flags carry a value and are matched by their
 *   "--name=" prefix (e.g. "--since=").
 */
function assertKnownFlags(argv, known) {
  const exact = known.exact;
  const prefixes = known.prefixes || [];
  for (const arg of argv) {
    if (exact.includes(arg)) continue;
    if (prefixes.some((prefix) => arg.startsWith(prefix))) continue;
    throw new Error(
        `unknown argument "${arg}" — did you mean --dry-run? Known flags: ` +
        `${[...exact, ...prefixes].join(", ")}`);
  }
}

module.exports = {assertKnownFlags};
