---
name: mockup
description: >-
  Design-first mockup workflow — render 2-3 labeled HTML mockup options
  (A/B/C) of a proposed screen or feature as an artifact styled with this
  app's design tokens, iterate on the user's pick, then record the decision
  in docs/plans/ WITHOUT implementing. Use whenever the user wants to "see
  how it would look", asks for UI options to choose from, wants a visual
  before approving a feature, or is planning a screen/widget/notification
  layout before any code is written.
---

# Mockup Options Workflow

The user picks designs visually, and approving a mockup is NOT approval to
build — this workflow always ends at a saved plan, never at implementation.

## 1. Frame the problem

Read the real app first: the closest existing screens plus
`lib/core/theme/design_tokens.dart` (AppColors/AppSpacing/AppRadius) and the
frontend rules. Mockups must look like *this* app — Material 3, the app's
palette and spacing scale, real feature copy — not a generic dashboard.
Render each option inside a phone-width frame (~390px), and make the page
theme-aware (light + dark).

## 2. Generate options

Load the `artifact-design` skill before writing the page. Build ONE artifact
page containing 2–3 clearly labeled options (Option A / B / C), each a full
phone-frame render with a one-line caption of its tradeoff. Make the options
genuinely different approaches (layout, hierarchy, density) — not the same
screen with swapped colors.

## 3. Iterate on the pick

The user typically picks one and grafts pieces of another ("B, but with C's
needs-attention section"). Merge into a single refined design and redeploy
the SAME artifact file path (same URL). Repeat until "looks good".

## 4. Record the decision — do not build

Write or update `docs/plans/YYYY-MM-DD-<feature>.md` with: the chosen option
and what was merged in, the artifact URL, and any decisions made along the
way. Then END the turn. Do not scaffold code, do not "get a head start" —
the user gives the build go-ahead separately and explicitly. "Looks good"
approves the mockup, not the work.
