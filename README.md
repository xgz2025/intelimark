# Intelimark *(working name)*

**Save with purpose.** Save anything from any app on iPhone, iPad and Mac,
remember *why* you saved it, get it back at the right moment, and turn piles
of saves into plans.

- Capture from the share sheet, Safari (with highlights), the macOS
  right-click Services and Share menus, a menu-bar hotkey, Shortcuts, and
  your existing screenshots.
- On-device Apple Intelligence describes, classifies and groups everything.
  Photos and screenshots are searchable by their content.
- Smart groups become **Briefs** (overview, comparison table, next actions).
- **Moments** bring saves back by date, place, calendar and a weekly review.
- **Recap** (1.1): AI sessions from ChatGPT, Claude, Gemini and Claude Code
  are grouped into workstreams and drafted into a weekly or monthly report,
  with every line citing its source.
- Private by design: no account, no server, iCloud sync.

## Documents

| Doc | What it decides |
|---|---|
| [`Docs/market_analysis.md`](Docs/market_analysis.md) | Market and technical feasibility, competitors, risks |
| [`Docs/product_strategy.md`](Docs/product_strategy.md) | Differentiation, positioning, signature features, **app name** |
| [`Docs/prd.md`](Docs/prd.md) | Refined feature list with priorities (P0/P1/P2), MVP cut, metrics |
| [`Docs/ai_sessions_spec.md`](Docs/ai_sessions_spec.md) | AI-session capture, digests, workstreams, Recap reports |
| [`Docs/architecture.md`](Docs/architecture.md) | Targets, capture pipeline, data model, AI layer, grouping, Moments, search, sync, code layout, build order |

## Platform

iOS / iPadOS / macOS 26+ (OS 27 features behind `#available`), Swift 6,
SwiftUI, GRDB + CloudKit (`CKSyncEngine`), Foundation Models, Vision,
NaturalLanguage, App Intents, WidgetKit.
