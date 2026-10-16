# Testing Laterwise

## Package tests

`make test` runs every NextmarkKit test (Swift Testing). CI runs them on each push,
together with unsigned iOS and macOS builds and a check that our code has no warnings.

## In-app purchases (StoreKit Testing)

Laterwise Pro's products live in `App/Nextmark.storekit`: monthly and yearly
subscriptions with a one-week free trial, and a lifetime unlock. Both app schemes
use this file when you run from Xcode, so purchases work without an App Store
account or network. Edit it only in Xcode's StoreKit editor: StoreKit loads no
products from a file it didn't write (it then shows an empty paywall, and the
`make test-storekit` purchases fail).

### Try it by hand

1. `make open`, pick **Nextmark-iOS** (or **Nextmark-macOS**) and run.
2. Open Settings › Upgrade to Pro and buy any product. The purchase sheet is
   Xcode's; nothing is charged.
3. In Xcode, **Debug › StoreKit › Manage Transactions…** lists the purchases. From
   there you can:
   - **Refund** a transaction: Pro turns off when the app comes back to the
     foreground.
   - **Expire** a subscription, or speed time up with **Editor › Subscription
     Renewal Rate** in `Nextmark.storekit` (a month renews every few minutes).
   - **Delete** transactions to start again as a free user.
4. In `Nextmark.storekit`, the Editor menu turns on **Ask to Buy** (the paywall
   shows "Waiting for Approval" until you approve it in Manage Transactions) and
   **Fail Transactions** (the paywall shows the error).
5. Restore Purchases reports what it found.

### Automated tests

`make test-storekit` runs `Tests/StoreKit` in the iOS Simulator against the same
file: products load with a one-week trial on the subscriptions, a subscription
unlocks Pro until it expires, and a refunded lifetime unlock no longer counts. In
Xcode, choose the Nextmark-iOS scheme and Product › Test (⌘U).

They run on a Mac, not in CI: on GitHub's macOS runners the simulator's test
store returns no products, whatever the signing.

### Before release

Create the same three products, with the same IDs and the trial, in App Store
Connect, then test with a Sandbox account on a device (Settings › App Store ›
Sandbox Account). The `.storekit` file is for development only; release builds
use the App Store.

## Save types by hand (Docs/save_types.md)

Save one of each and check its card, Details and, for shows and trips, Upcoming and
the reminders on its screen:

- **Article**: a news page from Safari; a Word document and a PDF from Files.
- **Receipt**: a photo or screenshot of a receipt (English and Chinese).
- **Show**: a Wallet event ticket, a ticket seller's `.ics`, an event page.
- **Travel**: a boarding pass screenshot (its barcode), a Wallet boarding pass, an
  airline's itinerary PDF, a 12306 train ticket screenshot, an airline's booking page.
- **Product**: the same coat from two shops (Safari share and a shopping app's Share);
  they should land in one comparison group (as a suggestion without Pro). Check Price
  on each; on a page that needs scripts, Check Price says it saw no price.

Reminders: set a show to start in under an hour and pick "30 minutes before" on its
screen (or use the Settings defaults); the notification arrives even in quiet hours.
Change the device date to the day after a show to see it move to Done with Undo.

## Things CI can't test

Sync between two devices, Screenshot Rescue with a real photo library, Apple
Intelligence (needs an Apple silicon Mac or a recent iPhone; the iOS Simulator on
an Intel Mac has no on-device model, and some Vision requests fail there), and
the share and Safari extensions. Test those on devices before each release.
