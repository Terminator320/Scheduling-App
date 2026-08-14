# Safe-to-auto-fix vs. report-only

The rule of thumb: **reversible + obvious + behavior-preserving → fix it now.
Semantic, security-sensitive, or judgment-requiring → report it.** When unsure
which side a finding falls on, treat it as risky and report it. A wrong
auto-edit costs more trust than a finding the user has to action themselves.

## Auto-fix now (safe)
- **Automated lint fixes** via `dart fix --apply`: unused imports, unnecessary
  `this`, `prefer_const_constructors`, `prefer_const_literals`, redundant casts,
  `unnecessary_*` lints, etc. These are tool-verified transforms.
- **Analyzer-confirmed dead code** — `unused_element`, `unused_field`,
  `unused_local_variable`, `dead_code` — once you've cleared the indirect-
  reference traps below.
- **Mechanical, behavior-preserving cleanups with one unambiguous target:**
  a hardcoded `Color(0xFF…)` or `EdgeInsets.all(16)` that maps to an existing
  `ColorScheme` token / `AppSpacing` constant; an unreachable branch; a
  duplicate import. The target must be unambiguous — if you'd have to *choose*
  which token, that's a judgment call → report instead.
- **Cloud Functions** auto-fixable ESLint rules via `npx eslint . --fix`
  (formatting, `prefer-const`, spacing). Re-run `npm run lint` after.

## Report only (risky — never auto-apply)
- **Anything that changes behavior or output.** Even an "obvious" bug fix: the
  current behavior may be load-bearing or the fix may be wrong. Describe it,
  show the fix, let the user decide.
- **Security findings** — Firestore/Storage rules, auth/App Check, secrets,
  callable payload validation, PII handling. These often need a deploy and human
  judgment; see `security-checklist.md`.
- **Anything touching a "Do not touch" invariant** (`project-map.md`). If it
  looks dead/redundant but is on that list, report it — the redundancy is usually
  intentional (e.g. the status allowlist duplicated in rules + repo).
- **Architecture / convention drift** that needs a real edit: a SnackBar that
  should be a notice, an `Exception` that should be a typed `Failure`, a direct
  `FirebaseFirestore.instance` in a widget. These are correct findings, but the
  fix reshapes code — report with a suggested approach, don't silently rewrite.
- **Performance refactors** that alter structure or semantics.
- **Unused dependencies** (`pubspec.yaml` / `functions/package.json` entries with
  no `package:<name>/` import / `require`). These are real dead weight worth
  flagging — the user asking to "find dead/unused code" means these too — but a
  pubspec/package edit needs `flutter pub get` + analyze + test to confirm and
  can have non-obvious effects, so report them, don't auto-remove. **Verify each
  candidate first** — the scan's heuristic over-reports. Expected false
  positives: codegen tooling used via `build_runner` (`freezed`,
  `json_serializable`/`json_annotation`, `riverpod_generator`/`riverpod_annotation`
  when the project uses the manual style), lint/config packages
  (`very_good_analysis`, `flutter_lints`), icon fonts (`cupertino_icons`),
  transitive interface packages (`*_platform_interface`), and native auto-init
  plugins that take effect without an import (`firebase_performance`). Confirm a
  dep is genuinely unreferenced before reporting it as removable.

## Dead code: verify before deleting
The analyzer is necessary but not sufficient, because Dart reaches a lot of code
indirectly. Before removing anything that *looks* unused, rule out:
- **l10n ARB keys** — used through generated getters (`context.l10n.key`), so a
  key can be live with zero literal `key` matches. Don't strip ARB keys as part
  of a code sweep; if a key seems orphaned, REPORT it for a deliberate l10n pass.
- **Riverpod providers** — reached via `ref.watch/read(xProvider)`; some are
  `autoDispose.family`. Confirm there is truly no `ref.*` and no override before
  deleting.
- **Route name constants** — resolved by string in `AppRoutes.onGenerateRoute`
  and pushed via `Navigator.pushNamed`. Grep the string value, not just the symbol.
- **Public API used across features**, dynamic/reflective use, JSON keys, and
  anything in `TODO(pre-ship)` scaffolding (intentional temp code — keep it).
- **Whole unused files**: a file with no inbound `import` may still be an entry
  point or referenced by path. Confirm zero `import` references across `lib/` and
  `test/` before deleting, and prefer reporting file-level deletions over silently
  removing them.

Process for a confirmed deletion: grep the symbol AND, for strings/keys/routes,
its string value across `lib/` + `test/`; confirm `flutter analyze` still flags
it as unused; remove; re-run `flutter analyze` + the touched tests. If any doubt
remains, downgrade to a report entry.
