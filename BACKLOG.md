# Kelo — build backlog

The standing to-do for Kelo (the private Health & Wealth app), worked by the
**Anita** build agent one item at a time. Anita picks the top unchecked item,
builds + verifies it the way Ankur would, reports for approval, and keeps going.

Canonical taste lives in Ankur's memory (`project_life_app*`, `feedback_*`).
Hard rules: on-device, private, honest data (real/labelled, never a guess as
fact), user-action-only, mobile-first, brand = sinhaankur.com. 114 tests must
stay green; `KELO_MACOS_APP=1` for macOS builds; `xcodegen generate` for iOS/watch.

## Now

- [ ] **Facial mood detection (on-device, ARKit).** A "check in with your face"
      camera view on iOS: read expression via ARKit blendshapes on-device, map to
      a valence → set today's mood. Auto-reading per Ankur's call, BUT the written
      MoodEntry note must say "from facial expression" (honest: expression ≠ mood,
      never silently indistinguishable from a felt rating). Opt-in camera; nothing
      leaves the device. Feeds the existing mood → DayState → Discipline ring.

## Next

- [ ] **Mood + streak UI** — a mood picker (1–5 / face) + streak chips surfacing
      the Discipline data that's built but not yet tappable.
- [ ] **Own GPS activity tracker (Strava-style)** — Core Location background route
      recording + MapKit route view; session folds into TrainingSession/MovementDay.
      Ankur's own take, toward the open-source Fitness+ vision.
- [ ] **iPad multi-column layout** — right-size the dashboard for the larger canvas.
- [ ] **Bundle brand fonts** — Inter / Fraunces / JetBrains Mono into the app for
      pixel-exact type (currently system fallback).

## Later (bigger, deliberate — flag before starting)

- [ ] **iCloud sync + same-user detection** — needs a paid Apple Developer account.
- [ ] **FinanceKit auto-import** — iOS-only, special entitlement, region-gated.
- [ ] **Extract KeloKit as the open-source engine** — the open Fitness+ north star.

## Done

- [x] Rebrand Pulse → Kelo (end to end, incl. executable + logo).
- [x] Day State composite (body + money verdict), 3 surfaces.
- [x] Health domains: DNA (GWAS/ClinVar), movement (Core Motion), CrossFit.
- [x] Leak-finder + residency-honest savings benchmark.
- [x] iOS/iPad app + Apple Watch app (shared KeloKit).
- [x] Mood + discipline streaks.
- [x] Three rings (Body · Money · Discipline) on phone, watch, desktop.
