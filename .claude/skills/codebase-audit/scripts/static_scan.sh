#!/usr/bin/env bash
# Read-only static-analysis collector for the codebase-audit skill.
# Run from the repo root. Changes nothing — it only previews. Use the output as
# ground truth for dead code + mechanical style before reasoning further.
#
#   bash .claude/skills/codebase-audit/scripts/static_scan.sh
#
# Each section is guarded so one missing tool doesn't abort the rest.

set -uo pipefail

hr() { printf '\n========== %s ==========\n' "$1"; }

if [ ! -f pubspec.yaml ]; then
  echo "Run this from the repo root (pubspec.yaml not found here)." >&2
  exit 1
fi

hr "flutter analyze (full output; the repo baseline is: No issues found!)"
if command -v flutter >/dev/null 2>&1; then
  # Don't let a non-zero analyze exit kill the script.
  flutter analyze 2>&1 | tail -40
else
  echo "flutter not on PATH — skipped."
fi

hr "dart fix --dry-run (preview of auto-applicable lint fixes)"
if command -v dart >/dev/null 2>&1; then
  dart fix --dry-run 2>&1 || echo "(dart fix --dry-run reported nothing / not applicable)"
else
  echo "dart not on PATH — skipped."
fi

hr "Cloud Functions ESLint (functions/)"
if [ -d functions ] && [ -f functions/package.json ]; then
  ( cd functions && npm run lint 2>&1 ) || \
    echo "(functions lint reported issues above, or 'lint' script is missing)"
else
  echo "functions/ not present — skipped."
fi

hr "Heuristic: Dart files with zero inbound imports (POSSIBLE unused files)"
# A starting point only — verify against references/safe-vs-risky.md before
# deleting anything. Entry points and string/path-referenced files show up here.
if command -v grep >/dev/null 2>&1; then
  find lib -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' 2>/dev/null \
  | while read -r f; do
      base="$(basename "$f")"
      # Any other .dart file that imports this filename?
      hits="$(grep -rlF --include='*.dart' "$base" lib test 2>/dev/null | grep -vF "$f" | head -1)"
      [ -z "$hits" ] && echo "  no inbound import found: $f"
    done | sort -u || true
  echo "(heuristic — confirm before acting; main.dart and route/string-referenced files are expected here)"
else
  echo "grep not available — skipped."
fi

hr "Heuristic: pub dependencies with no package:<name>/ reference (POSSIBLE unused deps)"
# Dead-weight detector: the analyzer won't flag an unused pubspec dependency.
# For each declared dep, look for any `package:<name>/` import in lib/ or test/.
if command -v awk >/dev/null 2>&1 && command -v grep >/dev/null 2>&1; then
  awk '
    /^dependencies:/      {indep=1; indev=0; next}
    /^dev_dependencies:/  {indep=0; indev=1; next}
    /^[a-zA-Z]/           {indep=0; indev=0}
    (indep||indev) && /^  [a-z0-9_]+:/ {name=$1; sub(/:.*/,"",name); print name}
  ' pubspec.yaml | while read -r dep; do
      # Skip the SDK pseudo-deps and the lint/icon packages that are used without an import.
      case "$dep" in
        flutter|flutter_localizations|flutter_test|cupertino_icons|very_good_analysis) continue;;
      esac
      if ! grep -rqlF --include='*.dart' "package:$dep/" lib test 2>/dev/null; then
        echo "  no 'package:$dep/' reference in lib/ or test/: $dep"
      fi
    done
  echo "(heuristic — VERIFY before removing: transitive-interface, codegen-annotation"
  echo " (json_annotation/riverpod_annotation), and native auto-init deps"
  echo " (e.g. firebase_performance) are expected false positives. pubspec edits are"
  echo " report-only — confirm with flutter pub get + analyze + test.)"
else
  echo "awk/grep not available — skipped."
fi

hr "scan complete"
