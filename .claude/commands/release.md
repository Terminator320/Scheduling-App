---
description: Bump version + CHANGELOG + CLAUDE.md + docs/ARCHITECTURE.md + docs/CLOUD_FUNCTIONS.md from the last N commits
argument-hint: [number of commits] (optional; default = commits since the last version bump)
---

You are preparing a release for this Flutter app. Update the **version**, the
**CHANGELOG**, **CLAUDE.md / rules**, and **`docs/ARCHITECTURE.md`** to reflect
recent work. Do NOT commit, push, tag, or deploy — only edit files and report
what you changed.

## Scope of work to summarize

Argument (`$ARGUMENTS`) = how many recent commits to cover.
- If a number is given, inspect exactly that many commits: `git --no-pager log -n $ARGUMENTS --stat` and `git --no-pager diff HEAD~$ARGUMENTS..HEAD`.
- If no number is given, find the last version-bump commit (search log for the previous `pubspec.yaml` version change) and cover everything since.
- Also include the **uncommitted working tree** (`git status`, `git --no-pager diff`) — staged and unstaged — so in-progress work is captured.

Read the commit messages AND the actual diffs. Commit subjects here are terse
(e.g. "bug fix", "animation"); trust the diff over the message.

## 1. Simplify and refactor changed code

Before bumping the version, invoke the `simplify` skill on the files touched in
the scope above. This cleans up the changed code for reuse, simplification,
efficiency, and altitude before the release is cut.

Use the Skill tool: `Skill({ skill: "simplify" })`.

The simplify pass must complete and its fixes applied before proceeding. The
changelog will then describe the final, cleaned-up state of the work.

## 2. Code-review changed code

After simplifying, invoke the `code-review` skill on the same scope to catch
correctness bugs, logic errors, and any remaining issues before the release.

Use the Skill tool: `Skill({ skill: "code-review" })`.

If the review surfaces real bugs, fix them before continuing. Pure style
findings already handled by the simplify pass can be skipped.

## 3. Pick the semver bump

Follow the rule in CLAUDE.md (`## Versioning & changelog`): SemVer
`MAJOR.MINOR.PATCH+BUILD` in `pubspec.yaml`.
- Any breaking/incompatible change ⇒ **MAJOR**.
- Any new backward-compatible feature (a `feat:`, new screen/capability) ⇒ **MINOR**.
- Bug fixes / refactors / docs only ⇒ **PATCH**.
- Pure internal refactors with no user-facing change get **no CHANGELOG entry**
  but may still ride along in a bump triggered by other work.

`+BUILD` always increments by **exactly one** regardless of the semver part.

Read the current version from `pubspec.yaml`, compute the next one, and confirm
your reasoning in one line before editing (e.g. "1.12.0+22 → 1.13.0+23: new
notifications feature ⇒ MINOR").

## 4. Update `pubspec.yaml`

Set `version:` to the computed value. Nothing else.

## 5. Update `CHANGELOG.md`

Prepend a new entry at the top of the list (newest first), Keep a Changelog
format, dated **today** (use the real current date). Heading build number MUST
match `pubspec.yaml` exactly:

```
## [<MAJOR.MINOR.PATCH>+<BUILD>] - YYYY-MM-DD
### Added
- ...
### Changed
- ...
### Fixed
- ...
```

Only include the sections that apply. Write entries in the **user-facing voice**
already used in this file (what the user can now do / what changed for them),
not implementation detail. One bolded lead sentence per item, like existing
entries. Never document internal-only refactors here.

## 6. Update `CLAUDE.md` and rules

Use the `claude-md-management:revise-claude-md` skill (or follow its method) to
fold any **durable** new facts from this work into the right home:
- App-logic invariants, data-layer conventions, Cloud Functions → `CLAUDE.md`.
- Naming/quality, error-handling, frontend, security, testing → the matching
  `.claude/rules/*.md` (each fact has exactly one home — don't duplicate).

Only record what is **non-obvious and lasting** (a new invariant, a gotcha, a
"must go through X" rule). Do NOT restate code structure, this release's diff,
or one-off details. Keep the existing terse, imperative style. If a change
contradicts an existing instruction, fix that instruction in place rather than
appending a second version.

## 7. Update `docs/ARCHITECTURE.md`

`docs/ARCHITECTURE.md` is the structural map — keep it true to the codebase as
of this release. Walk the diff scope and reconcile every section it touches:
- **New cross-cutting code** (a `core/` helper, a `shared/widgets/` component, a
  new responsive breakpoint/`context` getter, a new provider family) → add it to
  the Directory Map and the matching Key Patterns section.
- **New or reshaped feature flows** (routing, auth/data flow, repeating
  appointments, detail views, responsive layout) → update that section's prose
  so it describes the current behaviour, not the old one.
- **Firestore data model** changes (new field/collection) → update the model.
- **Counts and dates** drift — refresh the test-case count in *Test Strategy*
  (`grep -rE "^\s*(test|testWidgets)\(" test | wc -l`) and the "as of <date>"
  stamps to today.

Same bar as CLAUDE.md: record only **non-obvious, lasting structure**, fix
contradictions in place (never append a stale second version), and keep the
existing terse style. If the diff is a pure bug-fix/refactor with no structural
change, say "no architecture changes needed."

## 8. Update the functions docs (only if the diff touched `functions/`)

The export list in `functions/index.js` is the source of truth for both docs.
If the scope changed nothing under `functions/`, skip this step and say so.
Otherwise reconcile both:

**`docs/CLOUD_FUNCTIONS.md`** (per-function reference):
- **Added / removed / renamed function** → add or drop its Summary-table row
  AND its prose section, and update the "N functions defined / all N deployed"
  count in *Deployment status*.
- **Changed trigger, schedule, secret, or guard** (a new `assertAdmin`, a
  changed rate limit, an added `timeoutSeconds`/`maxInstances`, a new index) →
  fix both the Summary-table `Guard`/`Trigger` cell and the prose section so
  they match the source.
- **Changed call site** (who invokes a callable) → update the "Called by" cell.
- Refresh the "Generated … refreshed <date>" stamp at the top and any
  deployment-status date to today.

**`docs/cost-breakdown.html`** (backend cost analysis, an Artifact-style page):
- **Added / removed function** → add or drop its row in the "N Cloud Functions"
  table, adjust the `<h1>`/lede "N functions" count and the total-invocations
  figure.
- **Changed volume, guard, or cost lever** (a new admin gate on a billable
  callable, a changed schedule cadence, a new secret) → fix the affected row and
  any narrative (tiles, callouts, "Supporting services" / "Scenarios" tables)
  that cites it. Google Places autocomplete is the only real cost lever — keep
  its guardrail callout accurate.
- Refresh the "counts reflect the source as of <date>" line in *Basis &
  assumptions* to today.

Same bar as the other docs: match the source exactly, fix contradictions in
place, keep each file's existing style.

## 9. Verify and report

- If any `lib/l10n/*.arb` changed, run `flutter gen-l10n`.
- Run `flutter analyze` and confirm it's clean (the repo keeps 0 issues).
- Print a concise summary: chosen bump + reason, the new CHANGELOG entry, and a
  bullet list of CLAUDE.md / rules / `docs/ARCHITECTURE.md` / `docs/CLOUD_FUNCTIONS.md`
  / `docs/cost-breakdown.html` edits (or "no doc changes needed").

Do not run tests unless a change looks behavior-affecting and you want to
confirm it; mention if you skipped them.
