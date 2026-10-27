# Driver delivery interface

The delivery account opens on **Deliveries**. The supplied navy/teal design is
adapted into a progress card, owner-sequence route card, numbered stops and large
navigation/delivery controls. The header shows the signed-in delivery person's
name. The account avatar and receipt shortcut retain sync/account and daily cash
settlement access. Owners keep their All Shops / Assign Delivery workspace.

The controller filters by signed-in driver and selected date and sorts by the
owner's saved `stop_order`. The route strip lists remaining stops in that order;
the first pending stop is highlighted. Delivered and failed stops retain their
positions in the full list. Progress measures delivered stops divided by all
assigned stops, with failed visits counted separately. A queued local result is
marked Waiting to sync. A failed visit never counts as a successful delivery.

**Navigate to next shop** and each stop's **Directions** open the actual saved
Google Maps share link or verified entrance directions. Maps-only shops work
without extracted coordinates. Google Maps supplies road directions; a place
share link may first show a place page where the driver taps Directions. The
route strip is an ordered shop sequence, not a geographic map or a calculated
shortest path. No paid map SDK, fake map image, distance or ETA is used.

**Delivered & collection** opens the existing financial form. The stop changes
only after the driver saves a valid bill/collection; closing the form changes
nothing. **Could not deliver** opens the result dialog with failure selected and
a mandatory reason. The next pending stop advances after a saved result.
Existing offline-first recording, immutable ledger and owner settlement checks
remain. Waiting-to-sync and settlement-locked stops disable result/collection
changes while leaving calls and navigation available. Other pending stops can
still be recorded when real delivery circumstances require visiting out of order;
the driver cannot reorder or reassign the route.

The reference's Add New Shop action does not appear for drivers because shop
creation remains owner-only. Carton manifests, priority/shift tracking, signature
and photo proof of delivery need separate persisted data/workflows and are not
shown as functioning features. Existing collection entry is used for confirmation.

No new database migration is needed. Existing sharing requires the migrations
through `20261023_delivery_order.sql`. Rebuild/install the current configured APK
on all phones. Sync on the driver phone after owner assignments/order changes;
the existing Home refresh runs every 45 seconds while resumed, as well as on app
resume and manual refresh. The app has no closed-app background tracking.

## Validation

Run `scripts/verify.ps1`, then `scripts/verify.ps1 -Preview` sequentially. Driver
widget workflows use a real SQLite store, an owner-saved sequence and a distinct
driver controller. They check driver/date filtering, Maps-only next-stop targets,
collection persistence/next-stop advancement, enlarged text, unsynced actions,
empty dates and failed-stop handling/settlement access.

On Android, sign in with the new project's driver account, sync owner-assigned
shops, navigate to the first saved location and verify Maps road directions.
Record a partial/credit collection and a failed visit, then check the owner's
records after syncing. Repeat offline with a restart and after an owner route
edit. Real app-to-Maps/dialler launches and simultaneous phones still need device
verification; widget callbacks do not measure road/GPS accuracy.
