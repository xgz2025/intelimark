# Nextmark — Product Requirements (v1)

## 1. Product summary

- **One-liner:** Save anything from any app, remember *why*, get it back at
  the right moment, and turn piles of saves into plans.
- **Platforms:** iPhone, iPad, Mac (one SwiftUI codebase, universal purchase).
- **Minimum OS:** iOS / iPadOS / macOS **26**. Features that need OS **27**
  (on-device image understanding, Private Cloud Compute model) light up
  automatically with `#available`.
- **Primary users:** planners (trips, home, gifts, shopping decisions),
  knowledge workers, students. From 1.1, also people who work across
  several AI tools and need weekly or monthly reports (see
  `ai_sessions_spec.md`).
- **Principles**
  1. **Capture in under 2 seconds.** The share sheet must never wait for AI.
  2. **Every save has a why.** Intent is first-class data, not a tag.
  3. **AI suggests, the user decides.** No silent reorganizing of anything
     the user has touched.
  4. **Works without Apple Intelligence.** It degrades to Vision OCR, labels
     and keyword grouping, and never breaks.
  5. **Private by design.** No account, no server of ours, *Data Not
     Collected*.
  6. **Finish, don't hoard.** Done states, fading, recaps.

## 2. Glossary

| Term | Meaning |
|---|---|
| **Item** | One saved thing: link, image/screenshot, text snippet, PDF/file, email reference, or quick note. |
| **Highlight** | A selected passage inside an item, with a way to return to its exact location. |
| **Intent** | Why it was saved: `read · buy · try · go · decide · reference · for someone · custom`. |
| **Group** | A set of related items. *Smart* (AI-suggested, accepted by the user), *Manual*, or a *Plan* (a group with a goal and a date). |
| **Brief** | The AI-generated page for a group: overview, key points, comparison table, checklist, suggested actions. |
| **Action** | A next step attached to an item or group. It can sync to Reminders. |
| **Moment** | A scheduled resurfacing of an item or group, triggered by time, place, calendar or review. |
| **AI Session** | One conversation with an AI tool (ChatGPT, Claude, Gemini, Claude Code…), kept as one long-lived item. |
| **Log** | Status for auto-captured material: searchable and reportable, but kept out of the Inbox and Moments. |
| **Workstream** | A group for a task or project that spans AI sessions, saves and actions. |
| **Recap** | A generated, editable weekly or monthly report in which every line cites its sources. |

## 3. Feature list

Priority: **P0** = MVP (1.0) · **P1** = 1.1–1.2 · **P2** = later / validate first.

### 3.1 Capture

| ID | Feature | Pri |
|---|---|---|
| C1 | **Share extension (iOS/iPadOS)** for URLs, images, text, PDFs and files. Shows the intent chips, an optional note, and a group picker (suggested group pre-selected when known). Saves in < 1 s; no AI in the extension. | P0 |
| C2 | **Safari page capture:** JavaScript preprocessing reads the title, canonical URL, **selected text with surrounding context**, page language and schema.org JSON-LD. Builds a **text-fragment URL** so opening the item scrolls to the highlight. | P0 |
| C3 | **Share extension (macOS)** in the right-click → *Share* menu in Safari, Finder, Photos, Preview, Notes and Mail attachments. | P0 |
| C4 | **macOS Services menu:** right-click → *Services → Save to Nextmark* for selected text in any Cocoa app (with source app name and, when available, its URL). | P0 |
| C5 | **Mac quick capture:** menu-bar icon and global hotkey (default ⌥⌘S) opens a capture panel for the clipboard, the frontmost Safari tab, or a new screenshot (ScreenCaptureKit). Drag and drop onto the menu-bar icon or the Dock. | P0 |
| C6 | **Mail on Mac:** dragging a message in stores a `message://` link (reopens the exact email), subject, sender, date and body excerpt. | P1 |
| C7 | **Safari Web Extension (iOS + macOS):** top-level *Save to Nextmark* right-click item; a floating *Mark* button on text selection; **saved highlights re-render on the page** on revisit. | P1 |
| C8 | **In-app add:** paste, photo picker, document picker, camera scan (VisionKit document scanner), quick note. | P0 |
| C9 | **Screenshot Rescue:** opt-in Photos access; bulk-import existing screenshots with progress (continued background processing); afterwards, import new screenshots when the app runs. Offers to delete imported screenshots from Photos. | P0 |
| C10 | **Shortcuts / App Intents** (*Save to Nextmark*, *Save clipboard*), Action button and a **Control Center control** for "save last screenshot". | P1 |
| C11 | **Import:** Pocket CSV, Raindrop CSV/HTML, Netscape bookmarks HTML, Safari Reading List (exported). | P1 |
| C12 | **Duplicate detection:** same canonical URL or image hash merges into the existing item and adds the new highlight or note. | P0 |

### 3.2 Understanding (AI enrichment)

| ID | Feature | Pri |
|---|---|---|
| U1 | **Content extraction:** link metadata, readable article text, PDF text, OCR for images (Vision), schema.org data. | P0 |
| U2 | **Item understanding** (Foundation Models, guided generation): a short title, a 1–2 sentence summary, **kind** (article, product, place, event, recipe, video, person/contact, receipt, ticket, quote, document, other), key entities, **dates**, **places**, keywords, and a suggested intent if the user gave none. | P0 |
| U3 | **Image description** for photos and screenshots, so they're findable by text ("red sneakers", "wifi password", "parking level 3"). iOS/macOS 27 uses the on-device model with image input; 26 and non-AI devices use Vision OCR plus classification labels. | P0 |
| U4 | **Typed fields** per kind (product → price/currency/store; place → address/coordinates; event → start/end/venue; recipe → ingredients/time). Taken from schema.org first, AI second. These feed Compare and Moments. | P0 |
| U5 | **User edits always win.** AI never overwrites a field the user has edited. | P0 |
| U6 | **Cross-device enrichment.** Results sync, so a Mac with Apple Intelligence enriches items captured on an older iPhone. | P0 |

### 3.3 Find

| ID | Feature | Pri |
|---|---|---|
| F1 | **Hybrid search:** keyword (full-text) plus meaning (semantic vectors) over titles, notes, highlights, OCR and descriptions, ranked with recency. Results in < 100 ms at 10k items. | P0 |
| F2 | **Filters:** kind, intent, status, group, source app/domain, date. Natural-language filters ("pdfs from last week about taxes") are parsed by the model when available. | P0 (filters) / P1 (NL) |
| F3 | **Spotlight and Siri:** items indexed in Core Spotlight and exposed as App Intents entities, so system search and Siri can find them. | P1 |
| F4 | **Ask:** ask questions about your saves ("what were the three hotels near Gion?"), with citations to the items. On-device, with PCC for large contexts on 27. | P1 |
| F5 | **Open in place:** every item reopens at its source: text fragment, PDF page, `message://` link, file bookmark, or the archived copy. | P0 |

### 3.4 Groups and Briefs

| ID | Feature | Pri |
|---|---|---|
| G1 | **Manual groups** with emoji/color and drag-and-drop. | P0 |
| G2 | **Smart group suggestions:** the AI clusters related items and proposes "Kyoto trip (9 items)". The user can **accept, rename, merge or dismiss**. New items are suggested into accepted groups automatically, and the user can undo. | P0 |
| G3 | **Brief:** overview, key points, open questions, and suggested actions, regenerated when membership changes (manually or automatically). | P0 |
| G4 | **Compare:** for groups of the same kind (products, places, hotels, apartments, jobs), a table of the typed fields with an editable column set and a **Decide** action. | P1 |
| G5 | **Typed group views:** a map for places, a timeline for events, an ingredient list for recipes, a checklist for to-buy. | P1 / P2 |
| G6 | **Plans:** turn a group into a plan with a goal and a date (for example "Trip, Nov 20"). This drives Moments and the "done" state. | P0 |
| G7 | **Shared groups** with family or friends (iCloud sharing). | P2 |
| G8 | **Export a group** to Markdown, PDF, Apple Notes, or a shareable page. | P1 |

### 3.5 Actions

| ID | Feature | Pri |
|---|---|---|
| A1 | **Actions** on items and groups: title, optional due date, status. | P0 |
| A2 | **Suggested actions** from intent and kind (buy → "Buy before sale ends Fri", recipe → "Cook this weekend"). The user confirms with one tap. | P0 |
| A3 | **Reminders sync** (EventKit), both ways for status. | P1 |
| A4 | **Next Actions view** and **widgets** (Home Screen, Lock Screen, macOS desktop), interactive check-off. | P0 (view) / P1 (widgets) |
| A5 | **Done:** completing all actions offers to mark the item or group done; a done group collapses into an archive with an outcome note. | P0 |

### 3.6 Moments (resurfacing)

| ID | Feature | Pri |
|---|---|---|
| M1 | **Time Moments:** notifications from extracted dates (event start, deadline, sale end, ticket date) and from plan dates (for example 5 days before a trip). | P0 |
| M2 | **Weekly Review:** a 5-minute card stack of new, stale and actionable saves: *Do · Keep · Toss*. Default Sunday evening. | P0 |
| M3 | **Place Moments:** opt-in; notify near saved places (up to 20 nearest monitored at once, refreshed as the user moves). | P1 |
| M4 | **Calendar Moments:** opt-in; an upcoming calendar event that matches a group surfaces the group ("Dentist tomorrow → insurance PDF you saved"). | P1 |
| M5 | **Notification budget:** at most N per day, quiet hours, and Moment types that keep getting dismissed are learned and muted. | P0 |
| M6 | **Fading:** items with no intent, no actions and no opens after a set period (default 90 days) move to *Faded*. They're never deleted automatically and stay searchable. | P1 |
| M7 | **Monthly recap:** "You acted on 23 saves, finished 2 plans." | P1 |

### 3.7 AI sessions and Work Recap

Full spec: `ai_sessions_spec.md`.

| ID | Feature | Pri |
|---|---|---|
| S1 | **Manual capture of AI links and selected answers** through the share sheet and Services, linked to the session when the URL is known. | P0 |
| S2 | **Safari site adapters**, opt-in per site: auto-capture conversations on ChatGPT, Claude, Gemini, Perplexity and claude.ai/code as **Log** items, updated incrementally. Includes a health check. | P1 (1.1) |
| S3 | **Import data exports** (ChatGPT, Claude, Gemini Takeout) to backfill history with timestamps. | P1 (1.1) |
| S4 | **Coding-agent transcripts on Mac** (Claude Code, Codex CLI) from user-granted folders. | P1 (1.2) |
| S5 | **Session Digest:** goal, outcome, status, decisions, artifacts, open questions, next steps (which become suggested Actions). Secrets are redacted before storage. | P1 (1.1) |
| S6 | **Workstreams:** cross-tool grouping by entities, meaning and time; suggested, never forced. | P1 (1.1) |
| S7 | **Timeline:** days → workstreams → sessions and items, with active time. | P1 (1.1) |
| R1 | **Recap:** weekly report and standup templates; every bullet cites its sources; editable; export to Markdown, Mail, Notes, Pages or PDF. Friday Moment. | P1 (1.1) |
| R2 | **Monthly review, brag document, client timesheet** templates; calendar evidence; optional PCC polish. | P1 (1.2) |
| R3 | **"Keep on this Mac"** per source (excluded from iCloud). | P1 (1.1) |
| S8 | Chrome extension (localhost bridge); MCP `log_work` server so agents log themselves. | P2 |

### 3.8 Platform, sync and account

| ID | Feature | Pri |
|---|---|---|
| P1 | **iCloud sync** across devices (private database); works fully offline. | P0 |
| P2 | **Originals storage policy:** thumbnails always sync; full originals sync by setting (to save iCloud space). | P0 |
| P3 | **Web archive** of saved pages (offline readable copy, protects against link rot). | P1 |
| P4 | **Monetization:** StoreKit 2, Free + Pro (monthly, yearly, lifetime), universal purchase. Free includes unlimited capture, search and library, 3 smart groups and Weekly Review. Pro adds Briefs, Compare, Moments (time/place/calendar), Ask, Reminders sync, archive and unlimited groups. | P0 |
| P5 | **Privacy:** no third-party SDKs, no analytics beyond App Store Connect, no account. | P0 |
| P6 | **Localization** for en, zh-Hans, zh-Hant, ja, ko, de, fr, es, it and pt-BR, following the Apple Intelligence supported languages. | P1 |
| P7 | **Accessibility:** VoiceOver, Dynamic Type, keyboard navigation on Mac and iPad. | P0 |

## 4. Non-goals for v1

- A full read-later reader (we link out, plus the archived copy).
- Android, Windows or web clients; any server of our own.
- Social or public profiles, feeds or discovery.
- Team or workspace knowledge base features.
- RSS, newsletters by email, or forwarding-email capture (needs a server).
- Screen or audio recording of any kind ("record everything" tools such as
  Rewind or Screenpipe). AI-session capture is limited to explicit
  conversations from opted-in sources.
- Third-party cloud LLMs (possible later through the Foundation Models
  `LanguageModel` protocol, but not needed for v1).

## 5. MVP cut (1.0) and success metrics

**1.0 ships:** C1–C5, C8, C9, C12, U1–U6, F1, F2 (filters), F5, G1–G3, G6,
A1, A2, A4 (view), A5, M1, M2, M5, S1, P1, P2, P4, P5, P7. The data model
reserves AI sessions, the Log status and activity spans, so the 1.1 "Work"
update (S2, S3, S5–S7, R1, R3) is purely additive.

**Measures of success (first 90 days):**
- Activation: ≥ 60 % of new users save ≥ 5 items in week 1 (Screenshot
  Rescue counts).
- Intent capture: ≥ 40 % of saves have an explicit or accepted intent.
- **Follow-through:** ≥ 25 % of weekly active users complete at least one
  action per week. This is the north-star metric.
- Retention: D30 ≥ 25 %.
- Conversion: ≥ 4 % of trial starts become paid.

Retention and conversion come from App Store Connect. Activation, intent
capture and follow-through are product-internal, so they can't be measured
in production without breaking *Data Not Collected*. They are measured in
the TestFlight beta through an **opt-in "share usage summary"** export
(aggregate counts only, shown to the tester before sending). Production
keeps the counters on-device for the user's own recap.
