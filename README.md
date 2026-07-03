# Stock Tracker (Pulse)

Private, local-first macOS app that reads MY portfolio (stocks, crypto,
call options) from `~/Documents/stock-tracker/portfolio.json` and shows
live value + P&L. Quotes: Yahoo Finance chart endpoint (keyless, may be
delayed — personal use). NEVER pushed to a public remote; portfolio.json
is gitignored (positions stay off git entirely).

Build & run:
  cd macos/Pulse && ./build-app.sh && open Pulse.app

Edit holdings: open portfolio.json (created from the example on first run).
