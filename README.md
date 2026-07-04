<div align="center">

# Pulse

**A private, on-device portfolio companion that tells you the truth about your money.**

*Built by [sinhaankur](https://github.com/sinhaankur)*

</div>

---

Pulse reads your holdings (stocks, ETFs, crypto, options), values them live, and gives
you a blunt, numbers-first read on what's working, what's dying, and what to do —
without a single byte of your financial data ever leaving your machine.

It is **not** a trading platform and never places live orders on its own. It's an
analysis and decision companion: it explains, it flags, it scores your ideas on paper,
and it hands you a ready order ticket — but the final click stays with you, at your
broker.

## Why it exists

Most "portfolio apps" either sell your data, push you to trade, or bury the one thing
you need behind a wall of green-and-red noise. Pulse does the opposite:

- **Private by default.** Your positions, cost basis, and API keys live in local files
  that never enter git and never touch a server. Pulse talks only to public
  market-data endpoints, and it lists every domain it contacts right in the footer.
- **Direct, not hedged.** Every position gets a plain call — **HOLD**, **REVIEW**, or
  **EXIT CANDIDATE** — from countable decay markers, each with the exact rule and your
  own numbers behind it. No "it depends."
- **Honest about the future.** Nothing here predicts prices, because nothing can. It
  measures what's observably true and lets you test every instinct as a paper trade,
  scored against reality and the S&P over time, before real money moves.

## What it does

| Section | What you get |
|---|---|
| **Overview** | A health banner (am I okay?), account stats, and a ranked daily brief of your highest-dollar actions. |
| **Market** | VIX, world-index breadth, gold/oil/dollar/yields, crypto fear & greed, and per-holding news. |
| **Positions** | Every holding grouped by asset class, with since-invested timelines, income truth table, and trader-grade P/L bars. Add, edit, and sell by hand. |
| **Analysis** | Committed BUY/SELL-adjacent recommendations, verdicts with tap-to-explain rules, "why is the business doing badly" fundamentals, and a local-LLM read. |
| **Trade** | Funds-aware order drafts, a paper-trade ledger scored over time, and (optional) real paper-account execution through Interactive Brokers' API. |
| **Options** | A from-zero options course and an honest calculator — breakeven, max loss, theta — so you can learn and test-run risk-free. |
| **Agent** | An autonomous paper-trading agent that makes one disciplined call a day and keeps its own public scorecard. |

## Install & run — any OS

Pulse is one Swift package with two frontends over a shared core:

- **macOS app** (SwiftUI) — the full experience.
- **Terminal dashboard** (`pulse-tui`) — runs on **macOS and Linux**.

### Requirements
- [Swift 5.9+](https://www.swift.org/install/) (bundled with Xcode on macOS; a package
  download on Linux).

### macOS app
```bash
git clone https://github.com/sinhaankur/pulse.git
cd pulse/Pulse
./build-app.sh --install     # builds Pulse.app and copies it to /Applications
open /Applications/Pulse.app
```

### Terminal dashboard (macOS + Linux)
```bash
cd pulse/Pulse
swift run pulse-tui              # one-shot dashboard
swift run pulse-tui --watch     # refresh every 60s
swift run pulse-tui --analyze   # add a local-LLM read
swift run pulse-tui --help      # all flags
```

Verified on Linux via the official `swift:latest` Docker image.

## Your data (read this)

On first launch Pulse creates these files in `~/Documents/stock-tracker/`, **all
gitignored** — they never leave your device:

- `portfolio.json` — your positions (seeded from `portfolio.example.json`).
- `config.json` — API keys and settings (see `config.example.json`).
- `snapshots.json`, `paper-trades.json`, `watchlist.json`, `agent-state.json` — local
  history and ledgers.

Add positions in the app, or import a broker CSV (a full-account export syncs; a
partial CSV merges). Data-file permissions are locked to owner-only at every launch.
Use **Data → Export All** and **Data → Delete All** to move or wipe everything — you
own it.

## AI, on your terms

- **Local by default:** Pulse auto-starts Ollama and runs all analysis on-device.
- **Cloud is opt-in and labeled:** set an Anthropic key in `config.json` and every
  surface that uses it shows a clear "context leaves this machine" warning. Off unless
  you turn it on.

## Optional integrations (all opt-in, all keyless-or-your-key)

- **Quotes & history:** Yahoo Finance chart endpoint (keyless).
- **Options chains:** CBOE delayed quotes (keyless).
- **News & fundamentals:** Finnhub (your free key in `config.json`).
- **Execution rehearsal:** Interactive Brokers Client Portal Gateway — **paper account
  only**, enforced in code (Pulse refuses any account that isn't a paper "DU" account).

## Not financial advice

Pulse is for education and personal insight. Its automated analysis can be incomplete
or wrong, past performance doesn't predict the future, and markets are near-efficient.
Consult a licensed professional before making financial decisions. The whole point of
the paper-trade scorecard is to find out — honestly, over time — what does and doesn't
work, before it costs you anything.

---

<div align="center">

Built by **sinhaankur** · [sinhaankur.com](https://www.sinhaankur.com)

</div>
