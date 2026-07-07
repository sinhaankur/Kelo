# Kelo — Security & Compliance Policy

Kelo holds the most sensitive data a person has: their **DNA, health, and
money**. This policy is the guardrail that keeps it safe. It is derived from a
2026 review of the regulatory landscape (HIPAA, GDPR, GINA, PCI-DSS, SOC 2) and
privacy-expert consensus for health/finance apps. **Read this before any change
that touches how data is stored, shared, or transmitted.**

## The one rule that matters most

**Kelo is personal, on-device, no-account, no-sharing — and every major
compliance obligation is triggered the moment it stops being that.**

Privacy experts recommend exactly four controls for an app like this, and Kelo
is built on all four:

1. **Local storage by default** — the canonical copy lives on the user's device
   (plain JSON in `~/Documents/stock-tracker/`, gitignored), never a server.
2. **Auditable code** — the logic (KeloKit) is inspectable; nothing uploads
   quietly.
3. **No account required** — no login is the easiest way to keep data from
   leaving.
4. **Encrypted, user-controlled backup** — any sync must be end-to-end encrypted
   and decryptable only by the user (e.g. their own iCloud/Apple ID, never a
   third-party server).

## Why this is the shield (the trigger lines)

| Framework | Applies when… | Kelo's stance |
|---|---|---|
| **HIPAA** | data is shared with a healthcare provider / covered entity | Kelo is for the **user's own use only** → not covered. **Do not** add provider-sharing without a full HIPAA program (BAAs, Security Rule, breach rules). |
| **GINA** | genetic data used in employment / health-insurance | Doesn't bind a personal app — but genetic data is dangerous *because others discriminate with it*. **DNA stays on-device, encrypted, never leaves.** |
| **GDPR** (Art. 9) | any EU user; health + genetic = special-category (strictest) | On-device + no account minimizes exposure. A DPIA + 72-hour breach process is required **if** cloud/accounts are ever added. |
| **PCI-DSS** | the app touches card numbers | Kelo **never stores cards** — keep it that way (no full PAN/CVV, ever). |
| **State AI laws** (CA SB 243, NY) | AI companion data handling | Any in-app AI is **on-device, opt-in, off by default** ([[project_life_app_ai]]). |

**Design to the strictest common denominator.** If sync/accounts are ever added,
the GDPR 72-hour breach window and Article 9 protections govern — not the looser
HIPAA 60-day rule.

## Hard requirements for every change

- **On-device first.** No personal data leaves the device without explicit,
  per-action user consent. No telemetry. No analytics that phone home.
- **DNA is the crown jewel.** The raw genome is gitignored and stays local;
  prefer the encrypted derived form. Never commit, never upload, never log it.
- **User-action-only.** Kelo shows and correlates; it never acts, sends, or
  shares on its own ([[feedback_user_action_only]]).
- **No cards, no PII in analytics.** If a value must be shown, it's computed
  locally from the user's own files.
- **Data ownership is first-class.** Full local export and full wipe must always
  work (they do — the Data menu).
- **Honest data.** Real, cited, labelled — never a guess as fact (DNA =
  "association, not diagnosis"; BMI = "crude"; pension = "estimate").
- **When in doubt, don't transmit.** The absence of a central profile *is* the
  product. Adding cloud sync, accounts, or provider-sharing is a deliberate
  cross into the heavy regulatory regime — treat it as a policy decision, not a
  feature, and revisit this file first.

## If the AI assistant connects (backlog item)

On-device Apple Foundation Models preferred; **off by default, opt-in.** It reads
Kelo's own local data to answer questions — it never sends that data out and
never acts without the user. Cloud LLMs are only ever used if the user
explicitly switches, and the UI must say so while active.
