# Intelimark — Product Strategy

*Working name. See §6 for why the name should change before launch.*

This document decides **what makes the app worth choosing** in a crowded
"save anything + AI" category, and turns that into positioning, signature
features and a name. The feature list lives in `prd.md`; the technical design
lives in `architecture.md`.

---

## 1. The problem with the category

Every competitor (mymind, Raindrop, Readwise Reader, Matter, Fabric, and a
long tail of 2026 indie apps such as Tote, Aside, Save AI and Skreenly) solves
the same half of the problem:

> **Save → organize → search.**

With Apple's Foundation Models framework free to every developer, that half
is now a commodity. "AI describes your screenshot and tags it" is a weekend
project, and Apple's own iOS 27 Siri, Visual Intelligence and Photos search
already find things by their content.

The half nobody owns is the reason people save things in the first place:

> **Save → *remember why* → *come back at the right moment* → *get it done*.**

Users don't lack storage. They lack **follow-through**. The real failure mode
of every bookmark app is the *save-and-forget graveyard*: thousands of items,
no outcome. That is also why these apps churn.

## 2. Positioning

**One-liner:** *The saving app that gets things done.*

**Taglines (pick one for the App Store subtitle):**
- *Save with purpose.*
- *From saved to done.*
- *Saves that come back when they matter.*

**Category we claim:** not "bookmark manager", not "second brain", but
**"intent-driven saving"**: every saved item has a *why*, a *when* and a
*what's next*.

**We are not:** a read-later reader, a note-taking app, a public mood board, or
a team knowledge base.

## 3. Three pillars

| Pillar | Promise | Why competitors can't easily copy it |
|---|---|---|
| **1. Remember why** | Every save carries an intent (*read, buy, try, go, decide, reference, for someone*) and an optional note, set in one tap or inferred by AI. | It's a product philosophy, not a feature. It changes the data model, the UI and the notifications. Bolting it onto a tag-based app doesn't work. |
| **2. Comes back at the right moment** | Saves resurface by **time** (event dates, deadlines, sale ends), **place** (near a saved restaurant/shop), **calendar** (a trip next week → its saves), and a **weekly review**. | Needs deep, on-device Apple integration (Core Location monitoring, EventKit, notifications, App Intents). Cross-platform web apps can't do this well. |
| **3. Piles become plans** | AI groups related saves and turns each group into a **Brief**: overview, **comparison table** (hotels, products, apartments), checklist, and next actions synced to Reminders. | Structured extraction (schema.org data + guided generation) per item type is real engineering work; most competitors stop at a summary. |

Foundation for all three: **private by design.** Processing happens on-device
or in Apple Private Cloud Compute. There's no account, no server of ours, and
the App Store privacy label says *Data Not Collected*.

## 4. Signature features (the "screenshot-able" moments)

These are the features to build the App Store screenshots, the launch video
and press pitch around. Each is demonstrable in under 10 seconds.

1. **"Why did you save this?" chips** in the share sheet. One tap, then done.
   Weeks later the item opens with *"You saved this to **try** — for
   Saturday's dinner"*.
2. **Moments.** A notification as you walk past the ramen place you saved
   three months ago. A reminder the day before the concert whose screenshot
   you saved. *"Your Kyoto trip is in 5 days — 14 saves, 3 open actions."*
3. **Compare.** Save four hotel pages; the group shows a table: price, area,
   rating, cancellation policy, with a "Decide" action.
4. **Screenshot Rescue (onboarding hook).** First launch: *"You have 2,341
   screenshots. Let's sort them."* Within a minute the user sees their
   receipts, tickets, recipes, quotes and products grouped. They can file the
   keepers and delete the rest from Photos. This solves the *empty-library*
   problem every competitor has on day one and creates an immediate "wow".
5. **Highlights that live on the page.** With the Safari extension, saved
   highlights reappear on the web page when the user returns, and tapping an
   item from the app scrolls straight to the highlight (text fragments).
6. **Done.** Items and groups can be *completed*. A monthly recap shows what
   you acted on, not just what you hoarded. Unacted, unopened saves fade
   to an archive after a configurable period instead of piling up.

## 5. Go-to-market notes

- **Launch audience:** planners (trips, home projects, gifts, shopping
  decisions) and knowledge workers/students. Planning use cases demo best
  (Moments + Compare) and have obvious "done" states.
- **Displaced users:** Pocket (closed 2025) and Omnivore (closed 2024)
  refugees. Offer import from Pocket CSV, Raindrop, Netscape bookmark HTML and
  Safari Reading List export.
- **Apple-native bias:** Liquid Glass design, widgets, Control Center
  control, Action button, Shortcuts, Spotlight and Siri on day one. Apple
  features apps that adopt new platform tech, which is the cheapest marketing
  available to an indie.
- **Pricing:** free tier keeps **capture, search and the library unlimited**
  (never hold users' data hostage); **Pro** unlocks the action layer: Moments,
  Briefs and Compare, unlimited smart groups, Ask, Reminders sync and
  archiving. Indicative: $3.99/mo, $29.99/yr, lifetime option at launch. Cost
  per user is about $0 (on-device AI, PCC free below 2M first-time downloads,
  CloudKit sync).
- **Fake-door test before building:** landing page with "From saved to done"
  plus the Moments/Compare mockups; measure email sign-ups.

## 6. App name

### Why "Intelimark" should change

1. **Trademark risk.** Intel Corporation routinely opposes marks that start
   with *INTEL*: INTELCOM (2009), INTELOGIX (2011), INTELAGILE (2019),
   CHECKINTEL (2018) and FLASHINTEL (2024) are all on the USPTO TTAB docket.
   *INTELIMARK*, a software mark in a computing class, fits that pattern
   exactly. Losing the name after launch is far more expensive than changing
   it now.
2. **Spelling.** Users will type *Intelli*mark (double L) and won't find it.
3. **It describes the technology, not the benefit.** "Intelli-" reads as
   2010s marketing, and AI is no longer a differentiator; follow-through is.
4. **"-mark" says bookmark.** Bookmarks are the old mental model we're trying
   to move people away from.

### Candidates

| Name | Story | Notes |
|---|---|---|
| **Nextmark** ★ | A bookmark that knows its *next* step. Continuity with "Intelimark". | Recommended. Quick App Store search found no app with this name. Clear, easy to spell, and the subtitle can carry the meaning: *Nextmark — From saved to done.* |
| **Ripen** | Saves ripen into plans; they come back when they're ready. | Distinctive, one word, warm brand (fruit icon). No link-saving app found by that name. Less self-explanatory. |
| **Tuck** | *Tuck it away. It comes back when you need it.* | Short and friendly; likely crowded for trademarks and domains. |
| **Boomerang-style** (e.g. *Comeback*, *Returnly*) | Saves come back to you. | Strong match to Moments, weaker on "plans". *Boomerang* itself is taken (email). |
| **Purpose / Why** coinages (e.g. *Whysave*) | The intent pillar. | Memorable but awkward to say. |

### Before committing to a name
- [ ] USPTO search (classes 9 and 42) plus EUIPO and CNIPA if launching in China
- [ ] App Store Connect: reserve the name (create the app record)
- [ ] `.app` / `.com` domain and social handles
- [ ] Say it out loud: Siri must transcribe it correctly ("Hey Siri, save to Nextmark")

Until the name is decided, the code modules use neutral names with no product
name (`Capture`, `Library`, `Intelligence`…; see `architecture.md` §9), so a
rename only touches the app target, the bundle display name and the
marketing copy.
