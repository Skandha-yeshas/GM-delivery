# Owner delivery sequencing

Open **Assign Delivery**, choose the date and delivery person, then scan bills or
use **Add stops** to assign saved shops. Drag a stop's dotted handle or use its
up/down arrows. The first remaining drop is highlighted. Tap **Save delivery
order** to publish the sequence, or **Reset draft** to restore the downloaded
order. Date, driver, scan/add and tab changes are blocked while the draft is unsaved.

Completed and failed visits appear below the remaining queue. Their positions
are retained when pending stops move. Reopen a failed visit through its delivery
actions if it should return to the queue. Expand **Details & delivery actions**
for navigation, calls, results, collections, ledger and removal. Each driver/date
has its own route. Changing the sequence does not reassign shops to another driver.

## Supabase update

After the existing migrations through `20261020_shop_profiles.sql`, run
[`20261023_delivery_order.sql`](../supabase/migrations/20261023_delivery_order.sql)
in the Supabase SQL Editor. This additive migration is safe to rerun. Install the
updated APK on all phones. No paid map API or new package is required.

Shared route saves require a connection and succeed only after the server
confirms. A failed request retains the onscreen draft for retry. The retry reuses
the operation ID and cannot dispatch twice or restore an obsolete sequence. If
confirmation was lost, reset and sync to inspect the server's actual order. Drafts
are held in memory; save before closing the app. Trial mode saves to SQLite.

The driver receives the order on the next successful sync, including the existing
45-second refresh while Home is active, manual refresh or app resume. Navigation
opens the first pending stop in the saved order. This is manual sequencing;
distance estimates, shortest-path optimization and push notifications are not provided.

## Persistence and concurrent work

The owner-only `save_route_order` RPC validates the complete route snapshot and
exact pending-ID set, locks the day and stops, then updates all positions in one
transaction. Another owner's route edit, a new/removed stop or a changed visit
invalidates an older draft. Reset, sync and review before saving again. Submitted
or approved settlements lock route edits. Pending local visit/collection records
must sync before the owner can reorder.

`route_order_events` records the actor, request, before/after order and timestamp.
Drivers cannot reorder or read owner route history. Ordering preserves visit
versions so a driver's legitimate queued visit can still sync. SQLite updates
only `stop_order` in one transaction, retaining visit results and money records.

## Checks

Run `scripts/verify.ps1` and then `scripts/verify.ps1 -Preview` sequentially.
Run `scripts/verify_maps_sql.ps1 -TestFile supabase/tests/delivery_order.sql`
against its disposable local PostgreSQL cluster. No production database is used.

On two Android devices, reorder three pending stops, save, then sync the driver's
phone and check Next navigation. Repeat with one completed stop, a stale second
owner, a newly added stop, a temporarily disconnected phone and a submitted
settlement. Confirm cash/credit totals remain unchanged. Actual simultaneous
device/network behavior still requires this check.
