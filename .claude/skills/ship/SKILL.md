---
name: ship
description: >-
  Verify-and-ship checkpoint for this repo — analyzer, targeted tests, and
  BOM scan, then commit and push to the current branch. Use whenever the user
  says "commit it", "commit and push", "push it to this branch / to moblie",
  "ship it", or asks for a final check before committing. Also use as the
  closing step after a fix or feature when the user asks to wrap it up.
---

# Ship Checkpoint

One pass that replaces the usual "final check → commit → push" exchange.
Never commit red — fix and rerun instead.

## 1. What changed

`git status` + `git diff --stat`. Bucket the changes: Dart in `lib/`/`test/`,
`functions/`, ARB files, rules, docs. The buckets decide which checks run.

## 2. Verify (scaled to the buckets)

- **BOM scan** on every changed `.dart` file — this repo has been bitten by
  editors saving UTF-8-with-BOM:
  ```bash
  git diff --name-only HEAD -- '*.dart' | while read -r f; do
    [ "$(head -c 3 "$f" | od -An -tx1 | tr -d ' \n')" = "efbbbf" ] && echo "BOM: $f"
  done
  ```
  Strip any hit with `tail -c +4 "$f" > tmp && mv tmp "$f"`.
- **Analyzer**: `flutter analyze 2>&1 | grep -E "error -|warning -"` must
  come back empty (the ~1000 info lints are known noise).
- **Tests**: run the test files that cover the changed code (match by path
  and name under `test/`). If the mapping is unclear or the change is broad,
  run the full `flutter test` — slower but safe.
- **ARB changes**: `flutter gen-l10n` succeeds and
  `lib/l10n/.gen/untranslated.json` shows no EN/FR drift.
- **functions/ changes**: `cd functions && npm run lint && npm test`.

## 3. Commit

- Stage the files belonging to this piece of work; the tree sometimes carries
  parked work, so don't blanket `git add -A` when unrelated modifications are
  present — ask only if it's genuinely ambiguous what belongs.
- Message: short imperative line matching the repo's existing style, and
  **no double quotes inside the message** (PowerShell 5.1 native-arg quoting
  mangles them).
- `dev/.env`, `google-services.json`, `ios/GoogleService-Info.plist` are
  gitignored secrets — if one ever shows as staged, stop and tell the user.

## 4. Push

Push to the **current** branch (usually `moblie`). Never push to `main`
unless explicitly asked. Finish by reporting: checks run and their results
(test counts), the commit hash, and the branch pushed.
