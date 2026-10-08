# Nextmark

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

## Getting started

Requires macOS with Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
make open          # installs XcodeGen if needed, generates Nextmark.xcodeproj, opens it
make test          # runs the NextmarkKit package tests
```

The `.xcodeproj` is generated from `project.yml` and git-ignored; change
targets and settings there. Before running on a device:

1. Set your team in `project.yml` (`DEVELOPMENT_TEAM`) if it isn't `DMY7T44MNF`.
2. Register `group.com.nextmark.app` (App Group) and `iCloud.com.nextmark.app`
   (CloudKit container) for the team; automatic signing does the rest.
3. Run the **Nextmark-iOS** or **Nextmark-macOS** scheme. To try capture, share a
   Safari page to Nextmark; it appears in the Inbox.

| Target | iOS | macOS |
|---|---|---|
| App | `Nextmark-iOS` | `Nextmark-macOS` (+ menu bar, Services menu) |
| Share extension | `ShareExtension-iOS` | `ShareExtension-macOS` |
| Safari Web Extension | `SafariExtension-iOS` | `SafariExtension-macOS` |
| Widgets | `Widgets-iOS` | `Widgets-macOS` |

Shared code lives in `Packages/NextmarkKit` (`Model`, `Capture`, `CaptureUI`,
`DesignSystem`, `Library`, `Intelligence`, `Pipeline`, `Search`, `Grouping`,
`Moments`, `Features`). See `Docs/architecture.md` §10.

## Platform

iOS / iPadOS / macOS 26+ (OS 27 features behind `#available`), Swift 6,
SwiftUI, GRDB + CloudKit (`CKSyncEngine`), Foundation Models, Vision,
NaturalLanguage, App Intents, WidgetKit.
