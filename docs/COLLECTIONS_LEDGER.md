# Milestone 1 — Collections and credit ledger

## Plan and scope

Extend the existing domain/data/application/presentation layers with an integer
paise ledger. Save financial actions and the delivered status atomically in
SQLite, then replay durable operations through a role-checked Supabase RPC.
Keep original bills and payments, append reasoned owner corrections, and expose
server-calculated outstanding balances. Preserve the location/import/scan flows.

This milestone includes collection entry, partial and credit payments, old-balance
payments, opening balances, owner corrections, outstanding sorting/filtering and
collection reminders. Settlement, cash handovers, bank verification, the wider
UI redesign, route ordering and release hardening are separate milestones.
Daily settlement and cash handover confirmation have since been implemented in
milestone 2; see [the settlement guide](DAILY_SETTLEMENTS.md) for its additional
migration, day locks and owner review workflow.

## Database setup

On an existing project, run
`supabase/migrations/20261016_collections_ledger.sql` in Supabase SQL Editor after
the previous owner import and Maps-link migrations. Do not rerun `schema.sql` on
an existing database. For a new project, run the initial schema followed by the
dated migrations in order. The agent has not applied this migration to your live
Supabase project.

The migration adds one table, `ledger_events`. It is both the financial journal
and its audit history. Original entries, correction reasons, actors, operation
IDs, revisions, device timestamps, server receipt times and captured GPS remain
immutable. Direct INSERT/UPDATE/DELETE access is not granted to app accounts;
UPDATE/DELETE is additionally blocked by a trigger. Owners use `record_ledger`
for corrections rather than overwriting original rows.

Drivers can submit bills/payments only for stops assigned to their account. They
can read their own collection records and owner corrections to those records only
while the stop is assigned to them. Owner opening balances and the full directory
are not exposed to drivers. `ledger_balances` authorizes each shop before returning
its aggregate; owners receive all shops and drivers only their assigned shops.
The private aggregate function is not callable by app accounts.

## Phone workflows

- **Deliveries → Update result → Delivered → Save result** opens the collection
  form. Enter bill number, amount, collected amount and cash/UPI/cheque/credit.
  **Save collection & mark delivered** records the bill and delivery together.
- A partial collection leaves the rest outstanding. Select **Credit — no payment**
  for a fully unpaid bill. Collection against a new bill cannot exceed that bill.
- Select **Old balance only** for a collection visit with no new bill. This also
  marks the assigned stop delivered. A standalone old-balance payment cannot
  exceed the downloaded balance plus pending local entries; the server rechecks
  the shared balance before accepting it.
- **Shops → shop → View shop ledger** shows the balance and records. Owners see
  the running balance and complete financial audit trail; drivers see their own
  collection records and the authorized server aggregate.
- Owners can **Add opening balance** once per shop. To change any posted amount,
  payment mode, reference, note or bill reference, choose **Correct entry**, enter
  the replacement values and a mandatory reason. The original stays visible.
  A zero replacement reverses the corresponding amount; payment reversals retain
  a non-credit payment mode. Corrections can create a credit balance when prior
  payments exceed a corrected debt.
- **Account avatar → Outstanding balances** opens the owner list. Sort by
  largest amount or oldest debt, filter by area, call the shop or open its ledger.
- **Collect on next visit** preselects an eligible shop in the planner for today
  or a future day, excluding shops already assigned on that day. The owner still
  confirms the list and driver. The flag stays active until an owner clears it.
- **Account → View collection sync queue** shows every pending operation, amount,
  ID and failure. Financial operations cannot be discarded through the existing
  delivery-result conflict action.

## Opening balances from Excel

Keep the existing Name/Location template. Add an optional **Opening balance**
column, in rupees, for example `1250.50`. Plain numeric/text values with at most
two decimal places are accepted; formulas and negative/over-precision amounts
are rejected. The existing import retains shop details and applies an opening
balance only when none is already recorded. It does not overwrite an existing
opening balance, including an owner-corrected one.

Each import opening request is persisted with a stable ID and its original
timestamp before queuing. A retry reuses that request. Concurrent imports that
conflict with an opening already created by another owner remain visible for
owner review rather than creating a second opening charge.

## Offline behavior and accounting choices

The local database upgrades from version 2 to 3 without replacing existing shops,
deliveries or pending visit results. A collection and its local delivered status
are committed in one SQLite transaction. Sync only removes the queued operation
after a server acknowledgement. A lost response reuses the same ID and payload;
the server serializes operations per ID and shop and rejects changed replays.
Several offline entries on one stop carry successive optimistic versions.
Phone saves use their own local write lock: an in-progress network refresh does
not hold up collection entry or failed-delivery recording. A follow-up sync picks
up operations created while a download was in progress.

Server aggregates are authoritative. While offline the screen shows the cached
server balance plus unacknowledged local effects. A record already downloaded
from the server is not counted twice if its acknowledgement was lost. A failed
operation remains queued and holds later operations for the same shop. Conflicts
require owner review; this milestone does not silently rewrite, drop or reissue
a conflicting financial record. The detailed conflict-resolution UI is planned
for the reliability milestone.

Outstanding aging applies payments to the oldest debt first (FIFO); it is a
shop-level credit ledger, not invoice-by-invoice payment allocation. Device
capture time is retained separately from server receipt time; check phone clocks
when reviewing ages. GPS is attempted automatically when the form opens, without
a geocoding service. If permission, service or a fix is unavailable, the event
records that status and still saves. Poor-location approval is a later milestone.

UPI and cheque amounts are recorded as reported payments; bank settlement and
physical cash handover are not verified here. Previously committed delivery results
can still replay safely. The old visit RPC refuses a new delivered result without
a financial entry, so older APKs cannot bypass collection entry. On an upgraded
phone, open **Record collection** on an older unsynced delivered stop: saving
atomically transfers its original visit operation ID into the financial request
and removes the superseded visit queue item. Sync this recovered collection before
adding another financial record to the same stop. Install the new APK on all
working phones before starting the ledger.
Keep Tally separate and establish a checked opening balance rather than re-entering
historical bills already included in it.

## Automated checks

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify_maps_sql.ps1 -TestFile supabase/tests/collections_ledger.sql
```

The PostgreSQL harness creates a disposable local cluster with minimal stand-ins
for Supabase Auth/Storage, uses the real schema and migrations, and stops the test
server afterward. It never connects to the live project. Flutter tests cover
integer money, ledger changes, permission guards, real SQLite restart, lost-response
retry, multiple queued stop versions and compact-screen workflows. Actual ML Kit
recognition accuracy and native GPS behavior are not simulated as proven results.

The RPC access and locking approach follows the official
[Supabase function security guidance](https://supabase.com/docs/guides/database/functions)
and [PostgreSQL transaction locking documentation](https://www.postgresql.org/docs/current/explicit-locking.html).

## Manual Android / two-owner checklist

1. Apply the new migration and update all three phones without uninstalling.
   Check that old shops, Maps links, stops and pending results remain available.
2. Owner 1 adds an opening balance; Owner 2 syncs and sees the same amount. Import
   a small Excel file with an opening balance and retry it; it must not add twice.
3. Assign a shop to the driver. Download the route and financial balance, enable
   airplane mode, record a partial cash payment and confirm the stop is delivered.
   Force-close/reopen the app. The amount and queued operation must still exist.
4. Restore connectivity. Sync both owners and the driver. Check one financial
   entry, the exact balance, payment mode, bill reference, GPS status and timestamps.
5. Test UPI, cheque, credit and an old-balance-only visit. Deny GPS once; ensure
   saving still works and the missing-GPS status is explicit.
6. Simulate a dropped response after server commit and retry. Check that the
   original operation ID is unchanged and neither balance nor payment doubles.
7. Owner 1 corrects a posted amount with a reason. Owner 2 must see the original
   and correction. Try a stale correction: it must fail without discarding it.
8. Flag a shop, open the next day's planner, confirm it is preselected, and verify
   amount/age sorting, area filtering and the call action on a real phone.
9. With separate real driver accounts, verify that direct RPC/table requests
   cannot read another driver's rows, write to an unassigned stop, alter original
   financial records, add an opening, or perform an owner correction.
10. Check disk-full/permission-denied saves, slow/offline startup and an update
    installation while operations are pending. Confirm no collected money is
    treated as physically handed over merely by recording a collection. Follow
    the milestone-2 checklist separately for driver declarations and owner approval.
