# Nextmark — Market & Technical Feasibility (Oct 2026)

## Verdict

- **Technical: high.** Almost everything can be built with Apple's own
  frameworks and no server. The hard parts are email capture on iOS and the
  quality of auto-grouping.
- **Market: medium.** Demand is proven but the category is crowded and Apple
  is moving into parts of it. Winnable as a premium, Apple-native indie app
  positioned on *follow-through* ("why I saved it → what I'll do next"), not
  on "AI bookmarks". See `product_strategy.md`.

## Competitors

| App | Model | Price (2026) | Gap |
|---|---|---|---|
| mymind | AI-first "save anything", no folders | ~$7–9/mo | Cloud, pricey, no actions |
| Raindrop.io | Bookmark manager, optional AI | Free / ~$3/mo | Folder-centric, web-like, weak on images |
| Readwise Reader | Read → highlight → review | $9.99/mo | Text and reading only, power users |
| Matter | Read-later | Free / ~$8/mo | Articles only |
| Tote, Aside, Save AI, Skreenly… | Share sheet + AI auto-sort | Mostly subscriptions | iPhone-only, shallow, no "next action" |

Displaced users: Pocket (closed 2025), Omnivore (closed 2024).

## Threats

1. **Low barrier to entry.** Foundation Models give every developer free
   on-device AI.
2. **Apple building similar features.** iOS 27 Siri personal context and
   onscreen awareness, Visual Intelligence on all platforms, Safari topic
   tab groups, Photos text search. Apple covers *finding*, not
   intent → action.
3. **Save-and-forget churn.** Countered by intent, Moments, Weekly Review
   and Done states.

## Key platform facts (WWDC26)

- On-device model: **8,192-token** context; token-count APIs from 26.4.
- OS 27: **image input** to the on-device model; system **OCR, barcode and
  Spotlight search tools** callable by the model.
- **Private Cloud Compute** model: 32K context with reasoning; **free to
  developers below 2M first-time downloads**; no keys; prompts not stored.
- `LanguageModel` protocol lets the framework drive third-party models
  (Anthropic and Google publish Swift packages).
- Apple Intelligence needs iPhone 15 Pro or newer, or an M-series iPad/Mac,
  so the app needs a full fallback path (Vision OCR and labels; enrichment on
  another device).

## Feasibility by feature

| Feature | Feasibility | Notes |
|---|---|---|
| iOS share sheet capture | ✅ | Save the envelope only; no AI in the extension (memory limit) |
| Safari selected text + location | ✅ | JS preprocessing + text-fragment URLs |
| Mac right-click | ✅ | Share extension + Services menu + Safari Web Extension context menu |
| Photo/screenshot description and search | ✅ | FM image input (27), Vision fallback (26 / non-AI devices) |
| PDFs | ✅ | Page + quote anchors |
| Email | ⚠️ | Mac: `message://` links. iOS: text and attachments only |
| Auto-grouping + overview | ✅ / ⚠️ quality | Embeddings + clustering; FM names and Briefs; suggest, don't force |
| Actions / to-dos | ✅ | EventKit Reminders sync, widgets, App Intents |
| Sync | ✅ | CloudKit private DB via CKSyncEngine |

## Sources

- [What's new in the Foundation Models framework — WWDC26](https://developer.apple.com/videos/play/wwdc2026/241/)
- [All Apple Intelligence features in iOS 27 — BGR](https://bgr.com/2194403/apple-intelligence-new-features-ios-27/)
- [Best AI bookmark managers 2026 — ContextBolt](https://contextbolt.com/blog/best-ai-bookmark-managers/)
- [Bookmark manager pricing — ContextBolt](https://contextbolt.com/blog/bookmark-manager-pricing/)
- [Pocket is shutting down — TechCrunch](https://techcrunch.com/2025/05/27/read-it-later-app-pocket-is-shutting-down-here-are-the-best-alternatives)
- [Intel Corporation v. Intelagile LLC — TTAB](https://www.docketalarm.com/cases/TTAB/91245848/Intel_Corporation_v._Intelagile_LLC)
- [Intel Corporation v. Intelogix Corporation — TTAB](https://www.docketalarm.com/cases/TTAB/91200885/Intel_Corporation_v._Intelogix_Corporation)
