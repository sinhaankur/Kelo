# Kelo — build backlog

The standing to-do for Kelo (the private Health & Wealth app), worked by the
**Anita** build agent one item at a time. Anita picks the top unchecked item,
builds + verifies it the way Ankur would, reports for approval, and keeps going.

Canonical taste lives in Ankur's memory (`project_life_app*`, `feedback_*`).
Hard rules: on-device, private, honest data (real/labelled, never a guess as
fact), user-action-only, mobile-first, brand = sinhaankur.com. 114 tests must
stay green; `KELO_MACOS_APP=1` for macOS builds; `xcodegen generate` for iOS/watch.

## Now

- [ ] **Opt-in in-app AI assistant** — let an AI assistant connect to Kelo *if
      the user allows* (explicit toggle). On-device Apple Foundation Models
      preferred (private, offline); it reads Kelo's own data to answer "how am I
      doing?" — never acts, never sends data out. Off by default.

## Next

- [ ] **Body composition** — weight / BMI / body-fat / lean mass as a domain.
      Fed by (a) a smart scale via HealthKit (bodyMass, bodyMassIndex,
      bodyFatPercentage, leanBodyMass — most scales already write these), and
      (b) an uploaded clinical report (GE/DEXA/InBody don't do consumer BLE —
      OCR the PDF/photo). Compute BMI from weight+height so Kelo never depends
      on the machine reporting it. Label BMI as the blunt measure it is; prefer
      body-fat/lean when available. Height added to Profile.
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
- [x] Facial mood detection — on-device ARKit blendshapes → valence → mood,
      labelled "from facial expression" (honest). Opt-in camera, nothing leaves
      the device. *(Anita's first task.)*
- [x] Mood + streak UI — tap-to-log mood picker (5 faces) + discipline streak
      chips on the Body tab. *(Anita's second task.)*
