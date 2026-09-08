---
description: Where every piece of work actually stands — built, pushed, deployed, backfilled, shipped — and what needs a decision
argument-hint: [area] (optional; e.g. "wave", "search", "the client picker")
---

Answer "what is left / what is next" with evidence rather than recollection.
This question recurs constantly here ("what is left in the redesign", "what's
next before I deploy", "has the new UI been built?", "what do I need to pick"),
and it is hard precisely because a piece of work passes through five gates that
live in five different places — and this repo has carried work stuck between
gates across three releases at once.

Scope to `$ARGUMENTS` if given; otherwise report everything in flight.

## Gather (read all of these — do not answer from one)

1. **Working tree** — `git status`, `git --no-pager diff --stat`.
2. **Unpushed** — `git --no-pager log --oneline @{u}..HEAD` (and `HEAD..@{u}`).
3. **Version** — `pubspec.yaml` vs the top entry in `CHANGELOG.md`.
4. **Backend deploy debt** — the deploy log in `docs/DEPLOYMENT.md` gives the
   commit prod is actually running. Then:
   `git --no-pager log --oneline <that commit>..HEAD -- functions/ firestore.rules storage.rules firestore.indexes.json`
   Anything listed is written but not live. **This is the gate that is most
   often wrong, so lead with it.**
5. **Deployed function set** — `functions_list_functions` diffed by NAME against
   the 29 exports in `functions/index.js`. An unchanged count is not a
   verification; the set changed by six at an unchanged count once.
6. **Indexes** — `firestore_list_indexes` for anything `CREATING` rather than
   `READY`, for the collections the pending work queries.
7. **Prod scripts** — which `functions/scripts/` backfills the pending work
   requires, and whether the deploy log or plan doc records them as run.
8. **Plans** — `docs/plans/README.md` and the status banner at the top of each
   live plan. Trust the banner, never the checkboxes: plans here were executed
   without ticking, so an unticked box means *unknown*, not *outstanding*.
9. **Open findings** — the newest `docs/audits/*AUDIT*.md`, ids not marked done.

## Report as five gates

One table, one row per piece of work in flight, with these columns — each cell
`yes` / `no` / `n/a`, and never a guess:

| Work | Built | Pushed | Backend deployed | Prod script run | Shipped to App Store |

Under it, exactly three short sections:

**Blocked on you** — things only the owner can do: a prod script to run, a
deploy to approve, an Xcode step, a console setting, a device test.

**Needs a decision** — open questions and any options presented earlier that
were never picked. Restate the options in full; "what were the options again"
is itself one of the most repeated questions here, so never answer it with a
pointer to an earlier message.

**Next single action** — one line. Not a plan, not a menu.

## Rules

- Every claim cites where it came from (a commit, a log line, an MCP result).
  "I believe the backend is deployed" is not an answer this command may give.
- If a source disagrees with a memory note or a plan doc, **the repo and the
  live backend win** — say the doc is stale and, if it is a one-line fix, offer
  to correct it.
- If something cannot be determined without a credential or a console the
  session does not have, say so and name what would settle it. Do not deploy,
  push, or run any script from this command — it only reports.
