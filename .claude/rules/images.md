---
paths:
  - "lib/core/images/**"
  - "lib/features/calendar/**"
  - "functions/appointment_image*.js"
  - "functions/maintenance*.js"
  - "test/core/images/**"
---

# Photos and image uploads

Loaded when working on the image pipeline. Root context: `../../CLAUDE.md`.

- **Image validation:** Reject uploads where first 4 bytes aren't JPEG
  (`FF D8 FF`) or PNG (`89 50 4E`). Extension alone is not sufficient.
- **Image upload pipeline:** Single stage — `ImagePickerService` resizes +
  JPEG-compresses at pick time (`image_picker` `maxWidth/maxHeight: 1600`,
  `imageQuality: 70`); `ImageStorageService` then validates magic bytes and
  uploads. `ImageCompressService` was removed — don't reintroduce a second
  compression pass. Background dispatch via `AppointmentImageUploadService`
  after appointment save; the picker's temp files are deleted in a `finally`.
- **Photos are RENDERED FROM BYTES held in memory. No renderable URL is ever
  produced** (owner call, 2026-08-15, which replaced the 2026-08-08
  render-from-`storagePath` scheme rather than extending it).
  `getDownloadURL()` mints a `?alt=media&token=…` URL whose
  `firebaseStorageDownloadTokens` value is **stable per object and never
  expires**, and fetching it serves the bytes over plain HTTPS with **no auth
  and no rules evaluation**. The previous scheme re-minted that URL at render
  time, which put `storage.rules` in front of the MINT — but handed back the
  same permanent string every time, so a URL rendered while an employee was
  active sat in the on-disk image cache, was trivially copyable, and kept
  working indefinitely for anyone holding it after `deactivateEmployee` had
  revoked the credential and the `status == 'active'` gate had started refusing
  *new* reads. **`AppointmentImageLoader` (`core/images/`, formerly
  `AppointmentImageUrlResolver`) calls `ref.getData()` instead** — an
  authenticated SDK fetch, so `storage.rules` is evaluated on **every fetch**,
  and nothing shareable is produced ON THE RENDER PATH or left in a cache. Be
  precise about the three halves — the written guarantee used to carry only
  the first two and was therefore an overstatement: it does **not** revoke a
  URL somebody already captured under the old build, it does **not** stop an
  entitled person screenshotting or sharing a photo they can legitimately see,
  and — the one that was missing — **`ImageStorageService.uploadImage` still
  mints and persists one such URL per upload**, into `pictures[]`, which every
  assigned employee's device receives. So the app is still MANUFACTURING a
  permanent rules-free link per photo; what ended is doing it *as a side
  effect of rendering*. That write is deliberate (builds predating this render
  from it) and goes at the CONTRACT step below. Until then the residual is
  **covered, not closed**, by `functions/appointment_image_tokens.js`
  (`rotateAssignedImageTokens`, called from `syncUsersByUid`'s deactivation
  branch): it rewrites `firebaseStorageDownloadTokens` on every photo of every
  appointment the departing employee was assigned to — newest first, bounded
  at `ROTATE_APPOINTMENT_MAX` (500) — and mints the replacement URL into
  `pictures[]` in the same pass, because rotating alone would blank those
  photos on exactly the old builds the `url` write exists for. It never throws
  (it sits inside a `retry: true` trigger) and it is defence-in-depth behind
  the rules' status gate, never the gate itself. Retire it with the `url`
  write.
  **Photos render OFFLINE again as of 2026-08-16, and this was never in
  tension with the rule above.** The render-from-bytes change was written up as
  costing the on-disk cache outright — "photos re-download once per session and
  do not render offline at all" — and that cost was paid for a day on the one
  use case the app exists for: a tech in a basement or an underground garage
  opening a job they looked at that morning. But `cached_network_image` cached
  BYTES too; what made it unacceptable was the HANDLE it cached them against, a
  permanent rules-free token URL. **`AppointmentImageDiskCache`
  (`core/images/appointment_image_disk_cache.dart`) keys on `storagePath` and
  stores nothing shareable**, so the offline win is back without the leak.
  `cached_network_image` / `flutter_cache_manager` are still not imported
  anywhere in `lib/` and must not come back — the point was never to restore
  that package, only the property it happened to provide.
  **Two caches, two distinct jobs — don't collapse them.** The session map
  (below) keeps the fetch from being paid per widget State; the disk cache keeps
  it from being paid per SESSION. `load` reads disk BEFORE the network and
  writes back after a successful fetch; the write is deliberately **not**
  awaited, so a file write and its eviction sweep never sit in front of a first
  render.
  **Be precise about the residual, which is real:** a cache HIT of either kind
  is not rules-evaluated, so bytes fetched while entitled stay renderable on
  that device until they are evicted or the session is forgotten. That is the
  accepted cost and it is bounded by three things — the entries live in the
  platform CACHE directory (iOS excludes it from device and iCloud backups, the
  same posture as the Keychain `first_unlock_this_device` rule), the folder is
  budgeted at `maxCachedBytes` (128 MB, oldest-first by INSERTION, matching the
  memory cache rather than paying a write per render to track use), and
  `clear()` wipes disk as well as memory.
  **Entries never need revalidating, and that is what makes the whole thing
  safe:** `ImageStorageService.uploadImage` composes every file name from
  `DateTime.now()`, so a `storagePath` is written exactly once and never
  overwritten. A rotated download token mints a different URL, so a legacy
  `url:`-keyed entry simply becomes unreachable and ages out. Every disk
  operation is best-effort — a failure degrades to a cache miss and a log,
  never to a photo that fails to render — and the resolved directory is
  memoized with its REJECTION explicitly forgotten, or one hiccup at launch
  would silently disable offline photos for the whole process.
  **The session cache holds the BYTES** (`Map<key, Future<Uint8List>>` keyed on
  `storagePath`, or `'url:<url>'` for a legacy entry that has no storage path —
  keying THOSE on the shared empty `storagePath` would serve one doc's bytes
  for another, but the url is already a unique handle, and the legacy branch
  bypassing the cache entirely meant re-fetching on every widget State for a
  fallback documented as permanent; the provider is a singleton) — that is what keeps the fetch from being paid
  per widget State, i.e. on every sheet open AND again on every View→Edit
  toggle, which is the whole win the URL cache was built for. It is
  **byte-budgeted** (24 MB, oldest evicted first) because bytes are far heavier
  than the strings they replaced; a session that opens fifty jobs would
  otherwise retain every photo of every one of them. `loadAll` keeps its
  concurrency bound of 4, and `appointment_image_loader_test.dart` now asserts
  that bound rather than only the ordering that survives it. **BOTH caches are
  cleared by `deregisterThisDevice`** (`core/app/device_deregistration.dart`),
  the single owner of "forget this session" — the provider is a plain
  `Provider`, so its bytes otherwise live for the whole process and one user's
  job photos stay in the heap across sign-out into the next user's session on
  a shared device, **and the DISK half outlives the process entirely**, which
  is what turns this from a memory-forensics footnote into a real leak on a
  shared handset. Not a rules bypass (serving them still needs the next
  reader to be entitled to the same `storagePath`), which is why it sits after
  the credential-dependent steps rather than before them. `clear()` is
  therefore `Future<void>` and goes through that function's isolating `step`
  like every other teardown — it touches the file system now, so it can fail.
  The memory half is emptied first and synchronously, so an awaited disk delete
  cannot delay it. A disk write whose session ended mid-flight is **dropped**
  via a generation counter that `clear()` bumps: the loader's write-back is
  unawaited, so a fetch resolving just after sign-out would otherwise re-seed
  the cache that was just emptied — on disk, where it outlives the process, for
  whoever signs in next on a shared handset.
  **The generation must be read where the FETCH starts, not inside `write`**
  (S2, 2026-08-19). `AppointmentImageDiskCache` exposes a `generation` getter
  and `write(key, bytes, {required int generation})` takes it back — **required,
  so a call site cannot silently opt out**; it defaulted to the cache's own
  current generation, which always passes the check, making the parameter that
  protects the invariant opt-in;
  `AppointmentImageLoader._resolve` reads `_disk.generation` BEFORE
  `await _fetch(...)` and passes that value to `write`, which drops the write
  when `clear()` has run since. Capturing it inside `write` was a **no-op for
  exactly the case the guard exists for**: the loader only calls `write` after
  the Storage fetch resolves, so the value captured there already equalled the
  current one and the bytes landed on disk regardless. The required parameter is what makes that unrepresentable
  at a new call site.
  Pinned by `test/core/images/appointment_image_disk_cache_test.dart` ("a write
  already in flight when the session ends is dropped" / "a write started after
  the session ended is kept").
  A doc written before `storagePath` was stored has only its `url`, so **that
  URL is unavoidably the handle** — but it is turned back into a `Reference`
  via `refFromURL` and fetched through the SDK like any other, so even the
  legacy path is rules-evaluated and the token URL never reaches the network
  stack. That fallback is why this needed no migration; keep it.
  **A RULES REJECTION MUST NOT FALL BACK** (2026-08-11, still the point): the
  old `catch` was unconditional, so the one error it existed to convert into a
  blank tile — a `permission-denied`/`unauthorized` from the `status ==
  'active'` gate — was converted straight back into a working, rules-free token
  URL. There is now no URL-shaped fallback at all, for a rejection or for
  anything else, so **EMPTY BYTES ARE A REFUSAL, not a pending load**:
  `PhotoPickerSection` renders the error tile and keeps it untappable, and
  `buildImageProviders` substitutes a 1×1 transparent image rather than dropping
  the entry — the viewer opens at an INDEX, so dropping one would shift every
  photo beside it. The rejection/transport branch survives in the loader only to
  say which happened in the log; **neither result is cached** — entitlement can
  change mid-session, and the network can come back.
  `ImageStorageService` **still writes `url`**, deliberately: builds that
  predate this render from it, so dropping the write now would blank photos on
  any phone that hasn't updated. Retire it once the fleet has moved, the way the
  1.37.1 shim was retired. `ImageStorageService.downloadUrlFor` is the ONE
  remaining URL mint and is **not** a render path — the offline queue re-links
  an already-uploaded image whose doc-link append didn't land, and that
  `pictures` entry still carries a `url` for those older builds. It lives beside
  the upload write it reproduces so nothing on the render side has a
  URL-minting method to reach for.
  **Loaded bytes are POSITIONAL, so they must be carried with the list they
  were loaded for** — `PhotoPickerSection` keys them on `_resolvedFor` and
  serves `const []` until that matches `existingImages`. A Storage round-trip
  per photo is a real window, not "a frame or two": a partial or stale list
  shifts every index beside it, so removing photo 0 rendered the *deleted*
  photo, an untapped placeholder opened a NEW photo, and the viewer's
  `initialIndex` (composed as `existingBytes.length + i`) ran past the end of
  the provider list and threw a `RangeError` out of Save/Share. Offset a
  viewer index by the entries actually handed to the viewer, never by
  `existingImages.length`; `ImageViewer.open` also clamps, as depth.
  **Decode size is now the app's problem, not the network layer's.** The strip
  decodes through `Image.memory`'s `cacheWidth`/`cacheHeight` and the carousel
  through `ResizeImage`, so a thumbnail costs ~0.3 MB decoded rather than the
  ~10 MB a full 1600×1600 frame would; only the full-screen viewer decodes at
  full size, exactly as it did before. Never render a stored photo through a
  bare `Image.memory` with no cache bound.
  **Save/Share spool to a temp file.** `ImageViewer._currentImageFile` used to
  hand `DefaultCacheManager` a URL; a `MemoryImage` has no file, so its bytes
  are written to `getTemporaryDirectory()` for the platform channel — and the
  1×1 refusal stand-in is excluded by identity, or Save/Share would hand over a
  blank pixel as if it were the job.
- **Photos are MOVING to `appointments/{id}/images`, and phase 1 writes BOTH
  stores** (2026-08-13). Every appointment document carried its whole photo
  array — a `url` alone is ~215 of a ~290-byte entry — and the calendar reads
  up to 1000 appointments at a time while only the detail sheet ever shows a
  photo. **The `pictures` array is still written and is still authoritative.**
  The shipped build (1.45.0+72) reads photos off the parent document and knows
  nothing about the subcollection, so dropping the array now blanks every photo
  on every phone until it updates; it goes at the CONTRACT step, once no device
  still runs a build that reads it — the same gate the `#compat-1.37.1` shim
  waited on. Do not "finish the migration" by deleting the array early.
  **`appendAppointmentPictures`/`removeAppointmentPictures` write both stores in
  ONE `WriteBatch`** so they cannot disagree: this path is retried by the
  offline queue, which has no way to reconcile a half-written state.
  **The subcollection document id is DERIVED from the photo —
  `appointmentImageDocId` (`calendar/domain/policies/`), hand-mirrored as
  `functions/appointment_image_ids.js`.** That is what makes the write
  idempotent, and it REPLACES the `arrayUnion` dedupe the array form depended
  on (which worked only because every image serialized its exact `uploadedAt`
  and `arrayUnion` compares maps by deep equality — one field serialized a hair
  differently and it silently stopped deduping). It keys on `storagePath`,
  falling back to `url` for the legacy docs that have no storage path, so those
  don't all collide on one id. The two implementations share worked examples in
  their tests; change them together.
  **The subcollection doc omits `url` when `storagePath` is present** — photos
  render from bytes fetched off `storagePath`, so `storage.rules` is evaluated
  on every fetch and a persisted download URL is a permanent rules-free token
  with no reader here. A LEGACY entry with only a `url` keeps it, or
  backfilling destroys the one thing that can render it.
  **Reads are "subcollection first, array fallback", and EMPTY means "use the
  array", never "this job has no photos"** — a document the backfill hasn't
  reached yet is exactly that shape. `EventDetailsController._loadStoredPictures`
  adopts the read only while the list is still what `build()` seeded, so a
  removal made during the round-trip isn't silently put back.
  **`pictureCount` is a FUNCTION-OWNED denormalized counter** (`recountAppointmentPictures`,
  an absolute `count()` aggregate — same discipline as `jobCount`), because
  `AppointmentCard` renders a photo indicator on every range-query surface and
  cannot afford a subcollection read each. `toMap()` must never emit it and the
  rules reject a client write that touches it. The card asks
  `AppointmentRecord.hasPictures`, which tests BOTH stores — during the
  migration a doc legitimately has either.
  **`cascadeDeleteAppointmentImages` is LOAD-BEARING, not cleanup: Firestore
  does NOT delete a subcollection with its parent.** Without it every
  appointment delete leaves photo documents orphaned under a parent that no
  longer exists — invisible in the console, unreachable by every query, with
  nothing reporting it. It covers all three delete paths (single, series,
  `purgeExpiredHistory`), rethrows so `retry: true` means something, and is the
  single reason a subcollection here needs a server component at all.
  Backfill: `functions/scripts/backfill-appointment-images.js` (copy-only,
  `--dry-run`, atomic per appointment so the "partially copied" state the read
  fallback can't detect is unreachable).
  **THREE THINGS THE ARRAY IS STILL DOING, which the CONTRACT step must replace
  before it is removed** — each is currently invisible because the array covers
  it, and each fails silently once it does not:
  1. **Storage cleanup on delete.** `EventDetailsController.deleteAppointment`
     enumerates `appointment.pictures` to know which Storage objects to remove.
     Empty that array and it deletes nothing, and the bytes orphan on every
     appointment delete — `cascadeDeleteAppointmentImages` removes the
     Firestore documents only. Either that trigger grows a Storage prefix
     delete (the way `purgeExpiredHistory` already does it, minding the
     load-time bucket resolution that forced `maintenance_policy.js` to split)
     or the client reads the subcollection first.
  2. **The photo-count bound.** `isValidAppointmentData` caps `pictures` at
     100; a subcollection has no such ceiling, so that guard goes with the
     array unless something replaces it. The READ is already bounded —
     `fetchAppointmentPictures` limits to the same 100 and warns at the cap,
     deliberately reusing the array's number rather than inventing a second —
     but a bounded read is not a bounded WRITE, and nothing yet stops a doc
     growing past it.
  3. **The `AppointmentImage.url` fallback.** `AppointmentImageLoader` still
     uses a stored `url` as the fetch HANDLE for legacy entries (through
     `refFromURL`), and only the backfilled subcollection docs carry one. Keep
     the fallback.
- **Offline photo-upload queue:** a failed/incomplete photo batch is persisted
  by `PendingUploadStore` (one JSON list under the SharedPreferences key
  `pending_photo_uploads`, entries pruned after 7 days) so uploads survive
  going offline. `AppointmentImageUploadService.drainPending()` retries the
  queue — it's reentrancy-guarded, re-queues the *unsent*
  paths on a transient failure (preserving `enqueuedAtMs` so a batch can't
  retry past the prune window), and `arrayUnion`-appends uploaded pictures so a
  concurrent edit or the batch's other half never clobbers them.
  **When the uploads land but the `arrayUnion` doc-link append itself throws
  transiently, the already-uploaded images are carried forward on the queue
  entry's `uploaded` field for an append-only retry — NOT re-uploaded (their
  local temp files are already gone), and NEVER dropped, or the Storage bytes
  orphan invisibly on the job.** That re-link stays idempotent because each
  carried image serializes its exact `uploadedAt` (ISO-8601 in the JSON,
  round-tripped by `AppointmentImage.fromMap`), so an append that actually
  committed server-side dedupes on the next pass. An entry with no paths AND no
  carried `uploaded` images is the only genuinely-empty one that drains away.
  **Staging and draining share ONE serialized path** (`drainPending`, guarded
  by `_draining` + `_pendingDrain`): a save that stages a batch does NOT upload
  it directly, because a listener-driven `drainPending()` firing in that window
  would load the just-added entry and upload it concurrently — and since
  `ImageStorageService` mints each file name from `DateTime.now()`, the two
  passes produce different storage paths that `arrayUnion` can't dedupe, so the
  photo lands twice. A request arriving mid-drain sets `_pendingDrain` so the
  in-flight pass repeats (coalesce, never drop).
  **`PendingUploadStore`'s mutations are serialized inside the store**
  (`_serialized`, one `_mutations` chain) — `add`/`remove`/`prune` are each
  `load()` → mutate → `_save()` over ONE SharedPreferences key, so two
  overlapping mutations both read the same list and the second save erases the
  first's change: a save staging a batch while a drain removed a finished one
  wrote `[E1, E2]` then `[]`, stranding E2's files with no queue entry and no
  failure notice. Keep new mutating methods inside `_serialized`, and never
  "simplify" it away by serializing at the call site — the requeue inside a
  drain is a caller too. `AppSyncListeners`
  (`core/app/app_sync_listeners.dart`, registered from `main.dart`)
  drives the drain on the offline→online flip AND when the account doc first
  arrives (Storage rules need an authed user — a signed-out drain just
  re-queues); both transitions are covered by
  `test/core/app/app_sync_listeners_test.dart`. Method-channel plugin —
  device-only verification of the upload itself.

## Server side

- **`cascadeDeleteAppointmentImages` + `recountAppointmentPictures`** (`appointment_images.js`, added 2026-08-13 with the photo-subcollection move; +2 exports). **The cascade is not cleanup — it is the reason this feature needs a server component at all: Firestore does NOT delete a subcollection when its parent document is deleted.** Without it every appointment delete leaves `appointments/{id}/images/*` orphaned under a parent that no longer exists: invisible in the console, unreachable by every query the app makes, and with nothing anywhere reporting it. It must cover all three delete paths — the client's single delete, its series delete, and `purgeExpiredHistory` (Admin SDK deletes fire triggers too). It uses `recursiveDelete` (the same Admin-SDK bulk writer `syncUsersByUid` already uses for `liveActivityTokens`) and **RETHROWS**, deliberately unlike the best-effort cleanup elsewhere here — a swallowed error leaves exactly the permanent invisible orphans it exists to prevent, and rethrowing is what makes `retry: true` mean anything. `recountAppointmentPictures` maintains the denormalized `pictureCount` on the parent that `AppointmentCard`'s photo indicator reads (the card renders on every range-query surface and cannot afford a subcollection read each): an **absolute `count()` aggregate, never an increment**, same rule and same reason as `recountClientJobs` under `retry: true`, written with `update()` so an appointment deleted in the window is never resurrected as a count-only stub (a `NOT_FOUND` there is the normal path, not an error — the cascade has just removed the photos). **It recounts on EVERY write, including an update that cannot have moved the count, and that is deliberate.** An `if (before.exists && after.exists) return` guard was written and then removed: the only paths it skips are the offline queue replaying `set(..., {merge: true})` on the DERIVED doc id and a backfill re-run, and those two are the ONLY self-heal this counter has — a recount whose parent `update()` keeps failing exhausts its retry window and leaves `pictureCount` wrong forever, where an idempotent replay repairs it silently. It also buys nothing against the real write amplification: `appendAppointmentPictures` writes N image docs in ONE batch, so N recounts hit the SAME parent within milliseconds (against Firestore's ~1 write/sec/document guidance), but those are genuine CREATES that any such guard must let through. **That bit, and the fix was to DEBOUNCE the recount, never to suppress the replay** (2026-08-15): `debouncedRecountPictures` claims the parent in the Admin-SDK-only `appointmentRecountClaims/{appointmentId}` ledger (`create()`-fails-if-exists, same shape as `claimSeriesNotice`), so the first trigger of a batch does the one recount and the other N−1 return having written nothing — which also collapses the second-order fan-out, since every parent write re-fires `notifyAppointmentChanges` (10 photos was 10 recounts AND 11 notification invocations for one user action). **The ORDER is the whole safety argument: the claim is released BEFORE the aggregate runs.** A suppressed sibling's photo was committed before its trigger fired, and its trigger fired before the release, so a strongly-consistent `count()` after the release necessarily sees it — nothing a debounce suppressed can be missed. Count first and release after and a photo written in that gap is both suppressed and uncounted, which is the one way this optimization could corrupt the number it maintains. **The replay self-heal survives because the claim never outlives its batch**: it is deleted on the normal path, `RECOUNT_CLAIM_STALE_MS` (15 s) takes over one abandoned by a killed invocation, and the `expiresAt` TTL policy (`firestore.indexes.json`, offset 0) is housekeeping behind both — so a later, separate write (the offline queue's replay, a backfill re-run) always claims afresh and always recounts. The claim path FAILS OPEN on any ledger error: an extra parent write is exactly the old behaviour, where a skipped recount is a wrong count with nothing left to notice it. Releasing first is also what lets a `retry: true` retry of a failed parent `update()` re-claim instead of suppressing itself. Both bodies (`purgeAppointmentImages`, `recountPictures`) take an injected `db` and are jest-tested. `IMAGES_SUBCOLLECTION` is hand-mirrored by `AppointmentImagesStore.imagesSubcollection` (`calendar/data/appointment_images_store.dart` — the phase-1 photo surface split out of `firebase_appointments_repository.dart` so the CONTRACT step is a file rather than a diff through a 900-line class) AND by the literal `match /images/{imageId}` in `firestore.rules`; renaming one alone points the trigger at a collection nothing writes and the cascade silently stops cascading. The doc-id helper lives in the dependency-free `appointment_image_ids.js`, hand-mirrored from `appointment_image_doc_id.dart` and sharing its worked examples so a divergence fails a test rather than putting one photo at two ids.
