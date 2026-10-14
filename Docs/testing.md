# Testing Nextmark

## Package tests

`make test` runs every NextmarkKit test (Swift Testing). CI runs them on each push,
together with unsigned iOS and macOS builds and a check that our code has no warnings.

## In-app purchases (StoreKit Testing)

Nextmark Pro's products live in `App/Nextmark.storekit`: monthly and yearly
subscriptions with a one-week free trial, and a lifetime unlock. Both app schemes
use this file when you run from Xcode, so purchases work without an App Store
account or network.

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
unlocks Pro until it expires, and a refunded lifetime unlock no longer counts. CI
runs them too (the "StoreKit tests" job).

### Before release

Create the same three products, with the same IDs and the trial, in App Store
Connect, then test with a Sandbox account on a device (Settings › App Store ›
Sandbox Account). The `.storekit` file is for development only; release builds
use the App Store.

## Things CI can't test

Sync between two devices, Screenshot Rescue with a real photo library, Apple
Intelligence (needs an Apple silicon Mac or a recent iPhone; the iOS Simulator on
an Intel Mac has no on-device model, and some Vision requests fail there), and
the share and Safari extensions. Test those on devices before each release.
