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
  4. A screenshot: **Read Price from Screenshot…** reads its prices on the device
     and the person picks the real one.

  The first price seen is kept, so the card can say "↓ $50 since saved".
- **Check Price** on a product (or **Check Prices** on a group) reads the page again
  (a plain request first; the WebKit page, one at a time, when that shows no price)
  and records the price. Up to 60 checks are kept as its price history.
- **Target price** (free): "tell me when it's at or under ¥299". Any check that
  crosses it (Check Price, a Safari refresh, Pro's daily check) sends a notification,
  once per crossing; lists mark the product "Under target".
- **Safari refresh**: saving a product page that's already saved (Safari's Laterwise
  button, or Share) updates that product instead of saving it twice: the page as the
  person sees it, prices behind scripts or a sign-in included, is read again.
  `ProductURL.key` decides it's the same product (Amazon by its ASIN; shops by their
  product parameters, without tracking ones). A highlight or a note is a new save.
- **Pro**: prices are checked once a day while Laterwise runs, a notification says
  when one drops, and similar products are put in a **comparison group** on their
  own (free users get it as a suggestion). A group of products shows them side by
  side, cheapest first.
- Some prices are shown only to signed-in people (member prices) or only in a shop's
  app; then Check Price says it couldn't read a newer one, and a Safari refresh or a
  screenshot is the way to update it. Laterwise never signs in to a store (its WebKit
  page keeps no cookies) or sends anything but the page request. No server or
  scraping service is involved.

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
