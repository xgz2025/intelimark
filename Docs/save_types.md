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
(`Grounding`). Dates found in text are listed apart, with the words they came from.

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

- The price comes from the page's data when it has it, or the price in the text a
  shopping app shares. The first price seen is kept, so the card can say
  "↓ $50 since saved".
- **Check Price** on a product (or **Check Prices** on a group) fetches the page
  again and records the price. Up to 60 checks are kept as its price history.
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
- Some stores show prices only to a browser that runs their scripts, or to signed-in
  people; then Check Price says it couldn't read a newer one, and a Safari refresh
  is the way to update it. Laterwise never signs in to a store or sends anything but the
  page request.
