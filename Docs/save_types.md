# What people save, and what Laterwise does with each

Laterwise shows a save by **what it is**, not by its file format. Every save gets
one of seven types. Each type has a fixed set of fields, a known source for each
field, a card in lists, a Details section on its screen, and (for some) reminders.
Every save also shows when and how it was saved.

| Type | Card (lists) | Details (item screen) | Reminders |
|---|---|---|---|
| Article | Title · author · summary | Author, publisher, published or created | — |
| Receipt | Merchant · **total** · date on the receipt | Merchant, total, date on receipt | — |
| Show | Show · **date and time** · venue | Starts, doors, venue, seat, booking code | Free, on by default |
| Travel | From → To · **departure** · flight/train number | Each leg: departs, arrives, terminal, gate or platform, seat; booking code | Free, on by default |
| Product | Name · **price** (and change since saved) · store | Price, store, brand, availability, description, price history | Price drops (Pro) |
| Web link | `site › path`, title, snippet (like a search result) | Site, published | — |
| Other | Title · summary or picture description | — | — |

`ItemRecord.saveType` decides the type from what the item states about itself, in
this order: travel, show, receipt, product, article, web link, other.

## Where each field comes from

Exact sources first; the on-device model only fills what they leave empty, and
built-in rules last. Each field keeps its source, shown under it in Details.

| Source | Gives |
|---|---|
| The page's own data (schema.org JSON-LD, Open Graph and `product:price` tags) | Articles, products, events; `FlightReservation`, `TrainReservation`, `BusReservation`, `EventReservation` |
| A Wallet pass (`.pkpass`) | Boarding passes (flight, train, bus, boat) and event tickets |
| A calendar file (`.ics`) | Event or trip name, start, end, location |
| A boarding pass barcode (IATA BCBP, read from any photo or PDF) | Route, flight number, date, seat, booking code |
| Text rules (English and Chinese) | Flight and train tickets and itineraries (e.g. 12306 tickets), receipts |
| Document properties (PDF, Word) | Title, author, created |
| Apple Intelligence, when available | Type, summary, dates with their roles, places, travel route and number |

The model's dates and places are kept only when the text supports them
(`Grounding`). Dates found in text are listed apart, with the words around them
(so "Oct 21 – Oct 26" reads with its meaning). A date whose meaning isn't known
("mentioned") isn't listed.

## Lifecycle

1. **Save** from Share, Safari, + in the Inbox, Services, Quick Capture.
2. **Recognize** the type and **extract** its fields (above).
3. **Remind** (shows and travel): defaults per kind in Settings, changeable on each
   item. Reminders ignore quiet hours and the daily limit: they were asked for.
   - Show: the evening before at 18:00, and 2 hours before.
   - Flight: 24 hours and 3 hours before.
   - Train, bus or boat: 1 hour before.
4. **Upcoming** lists shows and trips by date, soonest first.
5. **Finish**: the morning after a show or a trip's last leg, it moves to Done,
   with Undo. Receipts, articles and products stay until finished by hand.

## Products and price comparison

Shopping saves (Amazon, eBay, Shopify stores, Temu, Shein, Taobao, JD…) are for
comparing before buying.

- **Where the price comes from**, most exact first:
  1. The page's data (schema.org, `product:price` and `og:price` tags, microdata).
  2. The price the page shows, read by `laterwisePrice()`
     (`Extensions/Shared/ProductPrice.js`): the shop's own price element (Amazon,
     Target, Shein, eBay, Walmart, Best Buy, AliExpress, Taobao/Tmall, JD, Zara,
     Uniqlo), else the largest currency amount near the product's name, not struck
     through. It runs in Safari (the Laterwise button and Share) on the page as the
     person sees it, and in the app's own WebKit page for Check Price and for shop
     links shared from apps. The script is copied verbatim into `PageCapture.js`
     and `content.js`; a package test keeps the three the same.
  3. The price in the text a shopping app shares.
  4. **Open Shop Page in Laterwise…**: the page in a sheet, for when the shop wants
     to check the person is a person (Shein), or the price needs a size or a sign-in.
     The person deals with the page; Laterwise reads the price it shows and records
     it as theirs with **Use $…**.
  5. A screenshot: **Read Price from Screenshot…** reads its prices on the device
     and the person picks the real one.

  The first price seen is kept, so the card can say "↓ $50 since saved".
- **Check Price** on a product (its screen, or its row in a group's Compare list)
  reads the page again and records the price. Up to 60 checks are kept as its price
  history. First a plain request (the page's tags, schema.org data, or the price Target,
  Shein and Walmart keep in their page scripts); else the WebKit page, one at a time,
  in an invisible window so the shop's scripts run as for a person. A shop link saved
  with too few words for a summary (a shopping app's share) also takes the words the
  WebKit page shows.
- **Check Prices** on a group's title line checks all its products at once (Pro; free
  users check them one by one, or get the paywall from that button).
- **Target price** (free): "tell me when it's at or under ¥299". Any check that
  crosses it (Check Price, a Safari refresh, Pro's daily check) sends a notification,
  once per crossing; lists mark the product "Under target".
- **Safari refresh**: saving a product page that's already saved (Safari's Laterwise
  button, or Share) updates that product instead of saving it twice: the page as the
  person sees it, prices behind scripts or a sign-in included, is read again.
  `ProductURL.key` decides it's the same product (Amazon by its ASIN; shops by their
  product parameters, without tracking ones). A highlight or a note is a new save.
- **Pro**: prices are checked once a day while Laterwise runs, a notification says
  when one drops, and the same product saved from several shops is put in a
  **comparison group** on its own (free users get it as a suggestion). A group's
  products are listed once, in Compare, cheapest first; its other saves under Items.
- **Same product?** (`ProductMatching.matches`): the same product link; else model
  numbers decide ("WH-1000XM5" isn't "WH-1000XM4"; sizes like "16GB" aren't model
  numbers); else two brands that differ, or prices more than 3× apart, are different
  products; else the names need two telling words in common (three character pairs
  in Chinese or Japanese), shop and marketing words not counted.
- Some prices are shown only after a check, to signed-in people (member prices) or
  only in a shop's app; then Check Price says it couldn't read a newer one, and the
  shop page sheet, a Safari refresh or a screenshot is the way to update it. The
  WebKit pages share the app's own web data (not Safari's), kept on the device, so a
  check passed once in the sheet isn't asked again by Check Price. Laterwise never
  signs in to a store for the person or sends anything but the page request. No
  server or scraping service is involved.

## Correct?

Fields read by rules or a model, rather than stated by the item, are put to the
person once on the item's screen (`ItemRecord.needsConfirmation`): a trip or show
read from text or by Apple Intelligence, any receipt, and a product price picked
out of a page's layout or a shared text.

- **Correct** marks them as the person's (`FieldOrigin.user`).
- **Edit…** (also **Edit Details…** in the item's menu, for trips, shows, receipts
  and products) opens a form; what's saved is the person's. A corrected price
  replaces the misread one rather than counting as a price change.
- **Not a Trip / Show / Receipt / Product** drops those fields and records the type
  in `TypedFields.rejected`, so reading the item again never makes the same guess.

Reading an item again (a re-save, a newer extractor) keeps the person's sections and
rejections; a product's newer page price is still recorded.
