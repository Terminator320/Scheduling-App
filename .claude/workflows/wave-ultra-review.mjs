export const meta = {
  name: 'wave-ultra-review',
  description: 'Multi-agent ultra review of the wave-integration branch diff vs main',
  phases: [
    { title: 'Review', detail: 'specialized reviewers per area (security/correctness/perf)' },
    { title: 'Verify', detail: 'adversarial refutation of every finding against real code' },
    { title: 'Critic', detail: 'completeness critic flags under-covered risk surfaces' },
  ],
}

// ----- shared context every reviewer checks the diff against -----
const REPO_CONTEXT = `
PROJECT: Flutter (Dart ^3.10.7) appointments app. Backend Firebase (Auth, Firestore,
Storage, App Check). Cloud Functions in functions/ (Node, project schedulingapp-88727,
region us-central1). Review the wave-integration branch (merge-base = main).

HOW TO SCOPE: run \`git diff main...HEAD -- <paths>\` to see EXACTLY what changed for your
area, then Read the full files for context and Grep for callers / related code. Review both
the change itself and how it interacts with existing code.

KEY INVARIANTS the change must not break:
- Secrets: server-side keys (Stripe, OpenAI, Wave Full Access Token, GOOGLE_MAP_API_KEY)
  live ONLY in Google Secret Manager, read from a Cloud Function. dev/.env holds ONLY
  Firebase client config. NEVER commit dev/.env or google-services.json. Never log secrets,
  tokens, PII.
- Callable hardening: reject oversized/malformed payloads with assertPayloadShape (non-object,
  >4KB, unexpected keys); validate strings via requireString/readSessionToken (trim, length
  cap, control-char reject). Auth-sensitive callables rate-limited via enforceDurableRateLimit
  (Firestore rateLimits/* counters clients can't read/write). Callables require App Check + auth.
- Firestore rules are the last line of defense. QUERY rules evaluate against query CONSTRAINTS
  not doc data: a list query must add .where(...) matching the rule or it's permission-denied.
  doc.get() IS evaluated against actual data. users read rule has 4 clauses (admin / active /
  own uid / own invite).
- Appointment status allowlist: pending, confirmed, in_progress, done, cancelled. New appts
  created status:'pending'.
- Role/isAdmin ALWAYS from Firestore, never SharedPreferences.
- Image upload: validate magic bytes (JPEG FF D8 FF / PNG 89 50 4E); extension insufficient.
  Two stages ImageCompressService -> ImageStorageService; temp filenames unique under Future.wait
  (static counter, not bare DateTime.now().millisecondsSinceEpoch).
- Firebase callable responses on Android return nested objects as Map<dynamic,dynamic>; cast
  loosely: (v as Map?)?.cast<String,dynamic>(). Direct as Map<String,dynamic>? throws TypeError.
- whereArrayContainsAny hard limit 30; chunk IDs into batches of 30.
- Typed failures: sealed Failure family per feature; repos throw typed failure; UI surfaces via
  noticeServiceProvider.error(failure.toLocalizedMessage(context)). Don't throw Exception(...).
- Notices via noticeServiceProvider (top overlay), never ScaffoldMessenger.showSnackBar (3
  sanctioned exceptions only). composeErrorNotice for generic catch sites with a TAG; logger.warn
  label starts with same TAG, called BEFORE any if(!mounted) return.
- Frontend tokens: never hardcode color/spacing/radius; map through Theme.of(context).colorScheme;
  never branch on isDark for styling; success surfaces use theme.statusColors (tertiary is amber
  WARNING, not success). const constructors; ListView.builder for lists.
- l10n: app_en.arb is template + app_fr.arb in lockstep; every key needs a @key metadata block
  (description + typed placeholders) or gen-l10n fails; key naming feature_keyName; use
  context.l10n (non-nullable); never import app_localizations.dart directly.
- All Firestore writes via service classes (never FirebaseFirestore.instance in UI); always set
  createdAt/updatedAt server timestamps.

WAVE CONTEXT: New Wave Accounting integration. No OAuth — a Full Access Token (Secret Manager)
only; Client ID/Secret unused. App never READS Wave (write-back only). Cloud Functions: GraphQL
transport client (functions/wave/client.js), auth helper, customer field mapper, customer
write-back (upsertCustomer) + bulk import, outbox worker (enqueueCustomerUpsert + drainQueue,
lease-based reaper for stuck inflight jobs). ClientRecord was reshaped to a Wave-aligned model
(business fields removed). Firestore rules lock down Wave fields/collections.
`.trim()

const FINDINGS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['findings', 'summary'],
  properties: {
    summary: { type: 'string', description: 'One-paragraph assessment of this area.' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['title', 'severity', 'category', 'file', 'description', 'evidence', 'suggestion'],
        properties: {
          title: { type: 'string' },
          severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low', 'nit'] },
          category: {
            type: 'string',
            enum: ['correctness', 'security', 'performance', 'race-condition', 'convention', 'test', 'maintainability', 'i18n', 'config'],
          },
          file: { type: 'string', description: 'repo-relative path' },
          line: { type: 'string', description: 'line number or range, if known' },
          description: { type: 'string', description: 'what is wrong and the concrete impact' },
          evidence: { type: 'string', description: 'the specific code / why it is a problem' },
          suggestion: { type: 'string', description: 'concrete fix' },
        },
      },
    },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['isReal', 'confidence', 'reasoning'],
  properties: {
    isReal: { type: 'boolean', description: 'true only if independently confirmed from actual code' },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
    adjustedSeverity: { type: 'string', enum: ['critical', 'high', 'medium', 'low', 'nit'] },
    reasoning: { type: 'string', description: 'what you checked and concluded' },
  },
}

const CRITIC_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['gaps'],
  properties: {
    gaps: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['area', 'risk', 'why'],
        properties: {
          area: { type: 'string' },
          risk: { type: 'string' },
          why: { type: 'string' },
          suggestedCheck: { type: 'string' },
        },
      },
    },
  },
}

// ----- review units -----
const UNITS = [
  {
    key: 'functions-security',
    agentType: 'security-reviewer',
    paths: 'functions/wave/auth.js functions/wave/client.js functions/wave/customers.js functions/wave/worker.js functions/index.js functions/wave/errors.js',
    focus: `SECURITY of the Wave Cloud Functions. Check: Full Access Token sourced ONLY from Secret
Manager and NEVER logged/returned to client; GraphQL request building is not injectable; callables
enforce App Check + auth; assertPayloadShape + requireString/readSessionToken used on every callable
input; rate limiting on auth-sensitive routes; no SSRF / unvalidated outbound URLs; errors surfaced to
client are sanitized (no token, no stack, no internal IDs); PII (client name/email/phone) not logged;
phone hashing not reversible/loggable; least-privilege on Firestore writes the function performs.`,
  },
  {
    key: 'functions-correctness',
    agentType: 'code-reviewer',
    paths: 'functions/wave/client.js functions/wave/customers.js functions/wave/worker.js functions/wave/mappers.js functions/wave/errors.js functions/index.js',
    focus: `CORRECTNESS + CONCURRENCY of the Wave Cloud Functions. Check: outbox worker transaction
correctness (claimed-flag reset on retry, lease-based reaper for stuck inflight jobs, no stale-true
bleed, no double-processing, idempotent upsert keying); drainQueue loop termination & batching;
retry/backoff on transient Wave errors vs fail-fast on auth; GraphQL response parsing (errors array,
nulls, partial data, Android-style nested maps); bulk import pagination & whereArrayContainsAny/30
limits; phone/business-name match tolerance; writeSyncSuccess guarded against deleted doc; error
mapper has no dead/unreachable branches and maps all real cases; single hash compute (no recompute).`,
  },
  {
    key: 'functions-tests',
    agentType: 'code-reviewer',
    paths: 'functions/wave/__tests__/client.test.js functions/wave/__tests__/customers.test.js functions/wave/__tests__/errors.test.js functions/wave/__tests__/mappers.test.js functions/wave/__tests__/worker.test.js functions/package.json',
    focus: `TEST QUALITY for the Wave functions. Check: tests assert BEHAVIOR/outputs not mock call
counts; mock only at boundaries (network/Firestore/clock); async throw-tests are real (await
expect().rejects, not a synchronous throw that never runs); worker race / reaper / retry paths covered;
mapper edge cases (accents, case-insensitive province/country, trimming, missing fields) covered;
no flaky/time-dependent assertions; coverage gaps for the riskiest correctness paths.`,
  },
  {
    key: 'rules-security',
    agentType: 'security-reviewer',
    paths: 'firestore.rules firestore.indexes.json',
    focus: `Firestore SECURITY RULES + indexes for the Wave change. Check: Wave sync fields on client
docs (e.g. wave sync status/customerId/hash) are NOT client-writable (only the function/admin); Wave
outbox/queue & rateLimits collections are not client-readable or writable; query-vs-get rule semantics
hold (any new client list query has matching .where constraints); no rule was loosened as a side effect;
firestore.indexes.json covers every new composite query the functions/app issue (else runtime failure);
no overly-broad allow read/write; reshaped ClientRecord fields still validated where rules validate them.`,
  },
  {
    key: 'wave-dart',
    agentType: 'code-reviewer',
    paths: 'lib/features/wave/application/wave_providers.dart lib/features/wave/data/wave_service.dart lib/features/wave/domain/models/wave_connection.dart lib/features/wave/domain/wave_error_mapper.dart lib/features/wave/domain/wave_failure.dart lib/features/wave/widgets/wave_settings_section.dart lib/features/wave/widgets/wave_sync_badge.dart',
    focus: `Wave Flutter SERVICE + UI layer. Check: callable responses cast loosely
((v as Map?)?.cast<String,dynamic>()) not direct generic cast (TypeError on Android); no Wave secret
ever in client code; typed WaveFailure thrown + surfaced via noticeServiceProvider.error(toLocalized);
error mapper maps permission-denied / not-connected correctly (recent fix: clear not-connected error,
session-free import, truthful pending badge — verify these hold); widgets use ColorScheme/statusColors
(not raw colors, not isDark branching, success != tertiary), const ctors, context.l10n, shared widgets;
provider lifecycle / autodispose correctness; no business-picker assumptions that don't exist yet.`,
  },
  {
    key: 'client-model',
    agentType: 'code-reviewer',
    paths: 'lib/features/clients/domain/models/client_record.dart lib/features/clients/domain/models/client_record.freezed.dart lib/features/clients/data/firebase_clients_repository.dart lib/features/clients/domain/policies/client_form_validator.dart',
    focus: `ClientRecord RESHAPE to the Wave-aligned model. PRIMARY RISK: backward compatibility with
EXISTING Firestore client docs written before the reshape — fromMap/fromJson must null-safely tolerate
missing new fields and removed old 'business' fields (no null-check crash, no data loss on round-trip).
Check: serialization round-trip (toMap/fromMap symmetric), freezed file matches the hand model, repo
writes still set createdAt/updatedAt server timestamps & go through the service, list queries still
satisfy rules, validator changes don't reject previously-valid data or accept invalid, no stale business
references left behind, field renames migrated everywhere they're read.`,
  },
  {
    key: 'clients-ui',
    agentType: 'code-reviewer',
    paths: 'lib/features/clients/widgets/sheets/add_client_sheet.dart lib/features/clients/widgets/views/client_edit_form.dart lib/features/clients/widgets/views/client_detail_view.dart lib/features/clients/widgets/views/client_view_body.dart lib/features/clients/widgets/views/clients_list_view.dart lib/features/clients/widgets/cards/client_contacts_cards.dart lib/features/clients/widgets/sections/additional_contacts_section.dart lib/features/clients/widgets/fields/client_search_field.dart lib/features/clients/contact_export_launcher.dart',
    focus: `Clients UI after the reshape. Check: frontend conventions (ColorScheme tokens, AppSpacing,
shared widgets reused not hand-rolled, FormSheetScaffold/DetailSheetListView/LabeledTextField, const,
ListView.builder); read-only detail bodies OMIT empty sections (no "None" placeholders); notices via
noticeServiceProvider + composeErrorNotice with proper TAG/logger.warn ordering; text caps via
TextLimits; l10n via context.l10n; accessibility (48px targets, Semantics, text scaling); no overflow;
contact export correctness after model reshape; new/edited fields are validated and bound to the model.`,
  },
  {
    key: 'core-shared',
    agentType: 'code-reviewer',
    paths: 'lib/core/images/image_compress_service.dart lib/core/images/image_picker_service.dart lib/core/images/images_providers.dart lib/core/validators/text_limits.dart lib/features/calendar/data/appointment_image_upload_service.dart lib/features/settings/screens/settings_screen.dart lib/shared/widgets/feedback/app_empty_state.dart lib/shared/widgets/sheets/sheet_widgets.dart',
    focus: `Core/shared changes. The 49-line deletion in image_compress_service.dart and changes to
appointment_image_upload_service.dart are HIGH RISK — verify the image pipeline invariants survive:
magic-byte validation still enforced, temp filenames still unique under Future.wait parallelism (static
counter NOT bare DateTime.now().millisecondsSinceEpoch), background dispatch after appointment save
intact, no resource leak (temp files cleaned). settings_screen.dart Wave section wiring correct (watches
right providers, ProviderScope/secure-storage harness needs). app_empty_state / sheet_widgets changes
don't break shared call sites. text_limits new constants used via constant not hardcoded.`,
  },
  {
    key: 'l10n',
    agentType: 'doc-reviewer',
    paths: 'lib/l10n/app_en.arb lib/l10n/app_fr.arb android/app/src/main/res/values-fr/strings.xml',
    focus: `Localization lockstep. Check: every NEW key exists in BOTH app_en.arb and app_fr.arb (no
EN/FR drift); every EN key carries a @key metadata block with description + typed placeholders (gen-l10n
fails otherwise); placeholder names/types match between EN & FR and match usage; key naming follows
feature_keyName with the right prefix bucket (wave_, settings_, clients_, error_, etc.); FR translations
are real translations (not English copies), apostrophes/accents correct; no orphaned/unused keys added;
JSON is valid. Use \`git diff main...HEAD -- lib/l10n/\` and grep code for each new key's usage.`,
  },
  {
    key: 'native-config',
    agentType: 'code-reviewer',
    paths: 'ios/Runner/Info.plist ios/Runner/AppDelegate.swift ios/Runner.xcodeproj/project.pbxproj ios/GoogleService-Info.plist macos/Podfile macos/Flutter/Flutter-Debug.xcconfig macos/Flutter/Flutter-Release.xcconfig pubspec.yaml',
    focus: `Native/build config + dependencies. Check: ios/GoogleService-Info.plist committed — is that
intended/safe (it carries the iOS API key & client config; flag if it should be gitignored like
google-services.json, and whether any restriction is applied); Info.plist has required usage strings
(NSCameraUsageDescription, NSPhotoLibraryUsageDescription, LSApplicationQueriesSchemes) and no debug/ATS
loosening; AppDelegate keeps App Check / Firebase init; iOS/macOS platform versions sane (ios 13.0);
pubspec.yaml dependency additions/bumps for the Wave work are pinned sanely and have no known-breaking
major jumps; version bump 1.16.0+27 consistent; no secret committed in any of these files.`,
  },
  {
    key: 'performance',
    agentType: 'performance-reviewer',
    paths: 'lib/features/calendar/data/appointment_image_upload_service.dart lib/features/clients/widgets/views/clients_list_view.dart functions/wave/worker.js functions/wave/customers.js',
    focus: `Performance of hot paths touched by this change. Check: outbox worker drainQueue and bulk
import for N+1 Firestore reads/writes, unbounded loops, missing batching, sequential awaits that should
be parallel (and vice-versa where parallelism overwhelms quota); client list view rebuild cost & list
virtualization; image upload concurrency/memory; any per-item GraphQL call that could be batched;
unnecessary recomputation (re-hashing, re-serializing).`,
  },
]

phase('Review')
log(`Reviewing ${UNITS.length} areas of the wave-integration diff, each adversarially verified.`)

const reviewPrompt = (u) => `You are an expert reviewer auditing ONE area of a code change.

AREA: ${u.key}
FILES IN SCOPE: ${u.paths}

${REPO_CONTEXT}

YOUR FOCUS FOR THIS AREA:
${u.focus}

INSTRUCTIONS:
1. Run \`git diff main...HEAD -- ${u.paths}\` to see exactly what changed.
2. Read the full files and Grep for callers / related code to understand context.
3. Report concrete, actionable findings. Each finding MUST cite a specific file (and line if
   possible) and explain the concrete impact, not a vague worry.
4. Be thorough about real bugs, security holes, race conditions, data-loss/back-compat issues,
   and clear convention violations from the invariants above. Do NOT pad with speculative or
   style-only nits unless they are genuinely worth fixing. Quality over quantity, but miss nothing real.
5. If the area looks correct, it is fine to return few or zero findings with a clear summary.`

const results = await pipeline(
  UNITS,
  (u) => agent(reviewPrompt(u), {
    label: `review:${u.key}`,
    phase: 'Review',
    agentType: u.agentType,
    schema: FINDINGS_SCHEMA,
    effort: 'high',
  }).then((r) => ({ unit: u, review: r })),
  (res) => {
    if (!res || !res.review || !res.review.findings || res.review.findings.length === 0) {
      return { unit: res ? res.unit : null, review: res ? res.review : null, verified: [] }
    }
    const { unit, review } = res
    return parallel(review.findings.map((f, i) => () =>
      agent(
        `You are an adversarial verifier. Your job is to REFUTE this code-review finding, not confirm it.

FINDING (area ${unit.key}):
${JSON.stringify(f, null, 2)}

PROCESS:
1. Open the cited file with Read and inspect the cited line and surrounding code.
2. Run \`git diff main...HEAD -- ${f.file}\` to confirm the change is as described.
3. Grep the repo for any existing handling (guards, validation, rules, callers) that would make
   this a NON-issue.
4. Decide: is the problem real and reachable in actual code, with the stated impact?

Default to isReal=false if you cannot independently confirm the problem from the actual code,
or if the finding is speculative, already mitigated elsewhere, or a pure style preference dressed
up as a bug. Adjust severity if the finding is real but over/under-stated.`,
        {
          label: `verify:${unit.key}#${i + 1}`,
          phase: 'Verify',
          agentType: 'code-reviewer',
          schema: VERDICT_SCHEMA,
          effort: 'high',
        },
      ).then((v) => ({ finding: f, verdict: v })),
    )).then((verified) => ({ unit, review, verified: verified.filter(Boolean) }))
  },
)

const clean = results.filter(Boolean)
const confirmed = []
const rejected = []
for (const r of clean) {
  for (const v of r.verified) {
    const row = { area: r.unit ? r.unit.key : 'unknown', ...v.finding, verdict: v.verdict }
    if (v.verdict && v.verdict.isReal) confirmed.push(row)
    else rejected.push(row)
  }
}

// completeness critic
phase('Critic')
log(`Verified findings: ${confirmed.length} confirmed, ${rejected.length} refuted. Running completeness critic.`)

const criticInput = {
  areasReviewed: UNITS.map((u) => ({ key: u.key, paths: u.paths })),
  confirmedFindings: confirmed.map((c) => ({ area: c.area, severity: c.severity, title: c.title, file: c.file })),
}

const critic = await agent(
  `You are a completeness critic for a code review of the wave-integration branch (merge-base main).

${REPO_CONTEXT}

The review covered these areas and produced these CONFIRMED findings:
${JSON.stringify(criticInput, null, 2)}

The FULL set of changed files is obtainable via \`git diff --name-only main...HEAD\`.

Your job: identify what the review may have UNDER-COVERED or MISSED — a risk surface in the diff
that no area targeted, a cross-cutting concern (e.g. a Firestore field written by a function but not
locked in rules, an l10n key used in code but absent from the ARBs, a ClientRecord field read in one
place but not migrated in another, a new function callable not guarded), or a claim that should have
been verified but wasn't. Inspect the actual diff/files to ground each gap. Return concrete gaps with
a suggested check; do not restate findings already listed. If coverage is genuinely complete, return
an empty gaps array.`,
  { label: 'completeness-critic', phase: 'Critic', agentType: 'code-reviewer', schema: CRITIC_SCHEMA, effort: 'high' },
)

const sev = { critical: 0, high: 1, medium: 2, low: 3, nit: 4 }
confirmed.sort((a, b) => (sev[a.severity] ?? 5) - (sev[b.severity] ?? 5))

return {
  stats: {
    areas: UNITS.length,
    confirmed: confirmed.length,
    refuted: rejected.length,
    bySeverity: confirmed.reduce((m, c) => ((m[c.severity] = (m[c.severity] || 0) + 1), m), {}),
  },
  summaries: clean.map((r) => ({ area: r.unit ? r.unit.key : 'unknown', summary: r.review ? r.review.summary : null })),
  confirmed,
  refuted: rejected.map((r) => ({ area: r.area, title: r.title, file: r.file, severity: r.severity, reasoning: r.verdict ? r.verdict.reasoning : null })),
  criticGaps: critic ? critic.gaps : [],
}
