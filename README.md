# Stock Tracker (Pulse)

Private, local-first portfolio tracker (stocks, crypto, call options) that
reads `~/Documents/stock-tracker/portfolio.json` and shows live value + P&L,
since-invested timelines, and global sentiment. Everything runs on-device:
quotes fetched directly, OCR via Apple Vision (macOS), LLM analysis via local
Ollama. NEVER pushed to a public remote; portfolio.json and config.json are
gitignored (positions and keys stay off git entirely).

Two frontends over one Swift core (`Pulse/Sources/PulseKit`):

- **macOS app** (SwiftUI): `cd Pulse && ./build-app.sh && open Pulse.app`
- **Terminal dashboard** (macOS + Linux): `cd Pulse && swift run pulse-tui`
  - `--watch` refresh every 60s · `--analyze` local-LLM read ·
    `--import file.csv` merge a broker CSV · `--no-color`
  - Linux: needs Swift ≥5.9 (verified with the official `swift` Docker image).

Data sources (all labeled in-app): Yahoo chart endpoint (delayed quotes +
history), CBOE delayed option chains, alternative.me crypto Fear & Greed,
Finnhub market headlines (key in `config.json`, see `config.example.json`).

Positions: edit portfolio.json (seeded from the example on first run) or
import a broker CSV. `acquired` dates are optional — when missing, Pulse
estimates the invested date from where price history last crossed your cost
basis and labels it `est.`; it never presents the guess as fact. The GROWTH
card reconstructs the account's value day by day from those dates (holdings
only; options have no historical marks).

Trade Draft (app): drafts a buy/sell against `cashAvailable` from
config.json — share math, post-trade concentration, realized P/L — and
copies the summary for your broker. Pulse NEVER places orders; execution
stays in the brokerage behind its own confirmations.

Learning loop: "Log paper trade" turns a draft into a scored call
(paper-trades.json, gitignored) — entry vs now, vs the S&P over the same
window, direction verdict so far, in the app and pulse-tui. Daily account
values (incl. real option marks) are recorded to snapshots.json on each
refresh, so the growth record is real going forward. Per-holding company
news (Finnhub, 7 days) shows for equity holdings and grounds the local
analysis.

Appearance follows the clock (light 07–19, dark otherwise) with a manual
override in the app header. A menu-bar pulse shows the day move; dollar
figures appear only while the app is unlocked.

Tests: `cd Pulse && swift test` (runs on macOS and Linux).
