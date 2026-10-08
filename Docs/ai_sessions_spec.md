# Nextmark — AI Sessions & Work Recap

Requirement IDs continue
`prd.md` (S = sessions, R = recap). Architecture references point to
`architecture.md`.

## 1. Decision

**Yes. Support AI sessions, but sell the *Recap*, not the saving.**

People increasingly do one task across several AI tools: research in
ChatGPT or Perplexity, writing in Claude, building in Claude Code, Codex or
Cursor. Each vendor's history is a silo, and at the end of the week nobody
remembers what all those sessions added up to. Writing the weekly or monthly
report means reopening dozens of chats.

- **Saving and searching AI chats is already a commodity.** Free Chrome
  extensions (Chat Memo, ChatTrack, Echoes, LLMnesia) and the ChatsRecall
  desktop app already do it locally.
- **Nobody turns them into a record of work.** None of them group sessions
  across tools into one *task*, connect them to the pages, PDFs and actions
  the user saved for the same task, or draft a report with every line traced
  back to its source.
- **Recap brings a second persona** (knowledge workers, developers,
  consultants) with a recurring, deadline-driven need. A *weekly report every
  Friday* is the strongest retention hook in the product, and this audience
  pays.
- **It fits the positioning.** "From saved to done" gains a natural last
  step: *and a record of what you did.*

Three guardrails keep it from diluting the core product:

1. **A separate *Log* layer.** Sessions captured automatically never land in
   the Inbox, never ask "why did you save this?", and never trigger
   Moments. They feed the Timeline, search and Recap. The user can
   *promote* a session (or one answer in it) into a normal save with an
   intent.
2. **Mac first.** That's where people run several AI tools side by side and
   where capture is technically possible (§3). The iPhone gets reading,
   search, Recap review and manual capture.
3. **Ships as the 1.1 "Work" update, not in 1.0.** The 1.0 data model
   reserves the session kind, the Log status and activity spans, so 1.1 is
   purely additive.

---

## 2. Concepts

| Term | Meaning |
|---|---|
| **AI Session** | One conversation with one AI tool (chat or coding agent), identified by its tool and conversation ID or URL. It's a long-lived Item: when the same conversation continues on later days, the existing item is updated, not duplicated. |
| **Turn** | One user or assistant message (tool calls are collapsed for coding agents). |
| **Activity span** | A time interval in which a session (or any item) was actively worked on. **Reports count activity, not creation date.** A chat started in March and continued this week counts toward this week. |
| **Session Digest** | A compact, structured summary of a session: goal, outcome, status, decisions, artifacts, open questions, next steps, entities. Produced once per change and cached. It's what Recap reads, never the raw transcript. |
| **Workstream** | A Group kind for a task or project that spans sessions, tools, saved pages, files and actions ("Q4 pricing page", "Login bug #812"). |
| **Log** | The Item status for auto-captured material: searchable and reportable, but invisible in the Inbox and quiet. |
| **Recap** | A generated, editable report for a time range and template, where every bullet cites its sources. |

---

## 3. Capture: what is technically possible

| Source | iPhone / iPad | Mac | Mechanism | Pri |
|---|---|---|---|---|
| **Manual: link or selected text** from any AI app | ✅ | ✅ | Share sheet / Services (C1, C4). A text selection from a chat becomes a normal save, linked to its session when the URL is known. | P0 (1.0) |
| **Web AI apps in Safari** (chatgpt.com, claude.ai, gemini.google.com, perplexity.ai, copilot.microsoft.com, claude.ai/code) | ✅ (Safari) | ✅ | Safari Web Extension **site adapters**: a content script reads the conversation DOM, watches it with a `MutationObserver`, and sends incremental turns to the app via native messaging. **Opt-in per site.** | P1 (1.1) |
| **Data exports** (ChatGPT *Export data* `conversations.json`, Claude *Export data*, Gemini via Google Takeout) | ✅ (Files) | ✅ | Import adapters. They backfill history with real per-message timestamps, so recaps work from day one. | P1 (1.1) |
| **Coding agents' local transcripts** (Claude Code `~/.claude/projects/**/*.jsonl`, Codex CLI `~/.codex/sessions/**/*.jsonl`) | — | ✅ | User grants the folder once (`NSOpenPanel`, showing hidden files) → security-scoped bookmark → FSEvents watch → JSONL adapter. Gives the working directory/repo, timestamps, prompts, files touched, commands, and commit/PR links. | P1 (1.2) |
| **Desktop chat apps** (ChatGPT for Mac, Claude desktop) | — | ⚠️ | No API. Reading their windows would need Accessibility permission, which a sandboxed Mac App Store app can't use. Covered by share links, Services, exports and the web versions. | — |
| **Chrome / Arc / Edge** | — | ⚠️ | The same WebExtension code as a Chrome extension, talking to the app over a localhost bridge (the sandbox allows a loopback server). Distributed outside the App Store; separate review. | P2 |
| **Agents logging themselves** | — | ✅ | A local MCP server (bundled helper) with `log_work(summary, links)` and `save(url, note)` tools, so an agent writes its own end-of-task summary. Best quality and cheapest to process. | P2 (spike) |

**Share links warning:** in ChatGPT and Claude, *Share* creates a **public**
snapshot URL. The app must never push users toward making work
conversations public. Session identity uses the private conversation URL
whenever it's available.

### 3.1 Site adapters (Safari)

```
Adapter = { id, matches: [URL pattern], version,
            selectors: { conversation, turn, role, text, title, codeBlock },
            conversationID: (URL) -> String }
```

- Selectors are **data (JSON), not code**, bundled with the extension. An
  optional **signed JSON update** is fetched from a static URL so adapters
  can be fixed between App Store releases. No user data is ever sent; this
  is the only network call besides enrichment, iCloud and StoreKit.
  (Executable code isn't downloaded, per App Review Guideline 2.5.2.)
- A **health check:** if an adapter finds a conversation container but zero
  turns, it reports *"Capture paused on chatgpt.com — site changed"* in the
  app, rather than silently missing a week of work. Chat Memo's changelog
  shows breakage after the ChatGPT redesign; that will happen to us too.
- Per-site toggles; never capture in Private Browsing; a domain exclusion
  list.

### 3.2 Incremental updates

Turns are hashed (`role + normalized text`). The ingestor appends only new
turns, records an **activity span** for the observed time window (export and
JSONL timestamps when present; otherwise first-seen and last-seen times from
the content script), and re-enqueues the Digest stage, debounced by 15
minutes after the last change.

---

## 4. Processing

### 4.1 Pre-filtering (before any model sees it)

Transcripts are big and noisy, especially from coding agents. Before
digesting:

- Keep: user prompts, the assistant's final prose, titles, file paths
  touched, commands run, links, commit messages and PR URLs.
- Drop: tool output bodies, large code blocks (kept as an artifact
  reference with language and line count), repeated retries, system prompts.
- **Secret redaction at ingest** (default on): common key formats (`sk-…`,
  `sk-ant-…`, `ghp_…`, `AKIA…`, JWTs, PEM private-key blocks, `user:pass@`
  URLs) are replaced with `‹redacted:type›` **before storage**, so redacted
  text never reaches disk or iCloud.

### 4.2 Session Digest (Foundation Models, guided generation)

```swift
@Generable struct SessionDigest {
    @Guide(description: "What the user was trying to achieve, one sentence") var goal: String
    @Guide(description: "What was actually produced or learned, one or two sentences") var outcome: String
    var status: SessionStatus            // solved · partial · abandoned · exploratory
    @Guide(.maximumCount(4)) var decisions: [String]
    @Guide(.maximumCount(5)) var artifacts: [ArtifactRef]   // doc, code change, file, PR, link
    @Guide(.maximumCount(3)) var openQuestions: [String]
    @Guide(.maximumCount(3)) var nextSteps: [String]        // → suggested Actions
    @Guide(.maximumCount(6)) var entities: [String]         // project, repo, product, client, people
}
```

- **Map-reduce** for long sessions: chunks of about 5K tokens produce
  `ChunkNote`s, which are reduced into one `SessionDigest`. This keeps every
  call inside the 8,192-token on-device context. On OS 27, sessions over
  about 40K tokens may use Private Cloud Compute (32K context) for the reduce
  step.
- Digests are about 150 tokens. They're stored as derived data with
  `derivedVersion` (architecture §4.3), synced, and re-generated only when
  new turns arrive.
- Coding sessions also get deterministic facts that need no model: repo,
  branch, files touched, commands, commits, PRs, and active time.
- `nextSteps` become **suggested Actions** (A2) in the session's workstream.

### 4.3 Workstreams (grouping across tools)

Plain semantic clustering (architecture §7) isn't enough for work, because
"fix login bug" and "fix checkout bug" are similar in meaning but are
different tasks. The workstream score combines:

| Signal | Weight (initial, tuned on eval set) |
|---|---|
| Shared strong entities (repo, project/client name, ticket ID, PR, file path) | high |
| Digest embedding similarity | medium |
| Temporal proximity (activity spans within ±2 days) | medium |
| Explicit links (session URL saved into a group; agent working directory) | decisive |
| The user moved an item into or out of the workstream before | decisive (locked) |

The rules for groups apply: suggested, never forced; user moves are locked;
workstreams can mix sessions with normal saves (the spec PDF, the Figma
link, the Stack Overflow answer) and Actions. A workstream with no activity
for 14 days is offered as *done* with an outcome note, which feeds monthly
recaps.

---

## 5. Recap

### 5.1 User flow

1. **Friday 4 pm Moment** (configurable): *"Your weekly recap is ready — 23
   sessions, 4 workstreams, 6 actions done."*
2. The Recap screen shows the range (this week, last week, this month,
   custom), a template, and the scope (all work / chosen workstreams / exclude
   personal).
3. The draft is generated in sections. **Each bullet has source chips**; a
   tap opens the session at the right turn, or the item.
4. The user edits inline (it's a plain text-editing view), then exports:
   copy as Markdown or rich text, share to Mail, Notes or Pages, save as PDF,
   or send to Slack via the share sheet.

### 5.2 Templates

| Template | Sections |
|---|---|
| **Weekly report** (default) | Highlights · Done · In progress · Blockers / risks · Next week |
| **Daily standup** | Yesterday · Today · Blockers |
| **Monthly review** | Summary · Outcomes by workstream · Decisions · Lessons · Next month |
| **Brag document / performance review** | Impact statements (*did X → result Y*), grouped by quarter |
| **Client timesheet** | Workstream × day, approximate hours from activity spans (labelled *approx.*), one-line description |
| **Custom** | User-defined headings plus a style note ("concise, no jargon, for my manager") |

### 5.3 Generation pipeline: hierarchical and cached

```
digests in range ──► per-workstream rollup (cached per workstream × ISO week)
                         │
weekly rollups ──────────┴─► report sections (template schema) ──► grounding check ──► draft
```

- **Weekly workstream rollups** (`WorkstreamWeek`: ~120 tokens each) are
  computed once, when the week closes or on demand. A heavy week (50
  sessions → ~10 workstreams) becomes about 1.5K tokens of input, which fits
  comfortably on-device. **Monthly and quarterly recaps reuse the weekly
  rollups**, so they cost about the same as a weekly one.
- Evidence beyond AI sessions is included as structured facts: Actions
  completed, saves added to workstreams, plans finished, and (opt-in)
  calendar meetings per workstream. *What I did this week* is more than
  what I asked AI.
- **Grounding:** the section schema requires `sources: [ItemID]` for each
  bullet. After generation, bullets citing no valid input ID are dropped,
  and numbers, dates and names in a bullet must appear in the cited digests,
  otherwise the bullet is flagged for review. The model writes the prose; it
  doesn't invent facts.
- On OS 27, an optional **"Polish with Private Cloud Compute"** pass rewrites
  the draft for tone with a larger model, with the same grounding check
  afterwards.

### 5.4 Quality bar (go/no-go for 1.1)

Eval set: 50 real sessions (mixed chat and coding) and 4 weeks of activity
from beta testers, contributed with consent.
- Digest: goal and outcome judged *correct* in ≥ 85 % of sessions.
- Workstream assignment: ≥ 80 % agreement with the user's own grouping.
- Recap: ≥ 70 % of bullets kept without edits; **0 uncited bullets**.

If on-device quality misses the bar, Recap ships as PCC-only (OS 27) or as
"bring your own model" through the Foundation Models `LanguageModel`
protocol (the Anthropic and Google Swift packages), with an explicit privacy
note.

---

## 6. Privacy and compliance

Work transcripts are the most sensitive data the app will hold, so:

- Processing on-device by default; PCC only with an explicit per-feature
  toggle; no data of ours anywhere.
- **"Keep on this Mac" option** per source: those items are excluded from
  iCloud sync (`syncScope = .local`), for users whose employer forbids
  personal cloud storage of work data.
- Secret redaction before storage (§4.1), on by default.
- Per-site and per-folder capture toggles; a visible "Capturing" indicator
  in the menu bar while a session is being recorded; one-click "Forget this
  session" (deletes it everywhere, including the CloudKit record).
- No public share links are created by the app.
- The terms of use note that users are responsible for their employer's
  policies on storing work content.

---

## 7. Data model additions (reserved in 1.0)

- `Item.kind += .aiSession`; `Item.status += .log`; `Item.syncScope`
  (`cloud · local`).
- **`SessionMeta`** (synced, 1:1 with Item): `tool` (`chatgpt · claude ·
  gemini · perplexity · copilot · claudeCode · codex · other`),
  `conversationKey` (unique per tool), `privateURL`, `workingDirectory?`,
  `repo?`, `turnCount`, `lastTurnHash`, `adapterVersion`.
- **`Transcript`** (attachment, role `transcript`): redacted, pre-filtered
  JSON lines. Synced only if the user enables "Sync transcripts"; digests
  always sync.
- **`ActivitySpan`** (synced): `itemID`, `start`, `end`, `source`
  (`observed · exportTimestamp · agentLog`). Used for every item kind, not
  just sessions.
- `Group.kind += .workstream`.
- **`Rollup`** (synced, derived): `groupID`, `isoWeek`, `summaryJSON`,
  `inputsHash`.
- **`Recap`** (synced): `range`, `template`, `scope`, `bodyMarkdown`,
  `sourcesJSON`, `generatedAt`, `editedAt`.
- New pipeline stages: `prefilter` and `digest` (between `extract` and
  `embed`) for `.aiSession`; `rollup` runs per workstream-week.

---

## 8. UI

- **Timeline** (sidebar section *Work*): days → workstreams → sessions and
  items, with tool icons and active time; a filter by tool.
- **Session detail:** digest on top, then the transcript (collapsed tool
  calls), *Open in ChatGPT/Claude…* (private URL), and *Promote to save*
  (with intent).
- **Workstream page:** Brief (as G3) plus session list, artifacts, actions,
  and a weekly activity strip.
- **Recap screen:** range, template and scope pickers → draft with source
  chips → export.
- **Widgets:** "This week: 4 workstreams · 23 sessions · 6 done"; a Friday
  recap prompt.

---

## 9. Packaging, pricing, roadmap

- **Free:** manual capture of AI links and text, search, Timeline for the
  last 7 days, one Recap per month (a taste).
- **Pro:** auto-capture adapters, imports, coding-agent folders, unlimited
  Recaps and templates, workstreams, timesheet.

| Release | Scope |
|---|---|
| **1.0** | Data model reserved (§7); manual capture of AI links and text; ActivitySpan recorded for all items. |
| **1.1 "Work"** | Safari site adapters (ChatGPT, Claude, Gemini, Perplexity, claude.ai/code), export imports, prefilter + digest, workstreams, Timeline, Weekly report and Standup templates, Friday Moment. |
| **1.2** | Claude Code and Codex folder adapters, Monthly review, Brag doc, Timesheet, calendar evidence, PCC polish. |
| **Later** | Chrome extension + localhost bridge, MCP `log_work` server for agents, Cursor/Copilot adapters, team-shared recaps. |

**Validate before building 1.1:** add a "Weekly recap from your AI chats"
waitlist option to the fake-door page (product_strategy §5), and in the
1.0 beta ask testers to import one ChatGPT or Claude export for the
eval set.

## 10. Risks

| Risk | Mitigation |
|---|---|
| Site DOM changes break capture | Data-only selectors, signed hot updates, health check with a visible warning, exports as backfill |
| On-device model too weak for technical transcripts | Prefilter, map-reduce, deterministic facts for coding sessions, PCC / BYO model fallback, quality bar in §5.4 |
| Hallucinated report lines | Mandatory citations, grounding check, flags in the editor |
| Employer compliance / sensitive data | On-device, local-only scope, redaction, per-source toggles |
| AI vendors ship their own "weekly summary" | Single-vendor only; our value is **cross-tool and cross-source** (sessions + saves + actions + calendar) |
| Scope creep toward "record everything" (Rewind, Screenpipe) | No screen or audio recording, ever; capture only explicit AI conversations and user saves |
