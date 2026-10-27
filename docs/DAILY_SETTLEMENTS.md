# Daily settlements — milestone 2

## Scope and setup

This milestone adds a driver’s end-of-day cash declaration and owner review.
Collections, shop import, Maps links and billing separation continue unchanged.
The plan is: calculate day totals, save drafts/submissions locally, enforce day
locks on the server, and preserve every owner decision as an immutable event.

For an existing shared project, run the following **once, in this order**, in
Supabase SQL Editor (skip migrations already applied):

1. `supabase/migrations/20261014_owner_import.sql`
2. `supabase/migrations/20261015_maps_link_delivery.sql`
3. `supabase/migrations/20261016_collections_ledger.sql`
4. `supabase/migrations/20261017_daily_settlements.sql`

For a new project, run `supabase/schema.sql` first. Do not rerun that baseline
on an existing database. No production migration is applied automatically by
this app. Use the updated APK on all three phones after the server migration.
Older APKs still have their financial writes checked by the server day lock.

Open **Daily settlements** using the receipt icon at the top of the home screen.
Owners see delivery days for their drivers; drivers see only their own days.
The current business day is also available with zero totals when there are no
deliveries or receipts, so a driver can close a day without cash activity.
Choose the delivery-list date, including an earlier unsettled day if necessary.
Use shared sign-in to exercise the separate driver and owner roles. Device-only
trial mode remains an owner workspace; it does not simulate a secure driver login.

## Amounts and dates

All monetary values are integer paise. Totals use the latest owner correction
for each original bill/payment, without counting the correction as a new receipt.
The original immutable stop receipt supplies the driver and **delivery-list
date**, not the camera timestamp or correction date. Owners recording a
collection on a driver’s stop include it in that driver’s daily settlement.
Opening balances and next-visit reminder flags do not count as daily receipts.

- Bills recorded: effective bill totals for that driver’s delivery day.
- Old-balance payments: payments entered separately against outstanding balances.
- Credit given: unpaid portion of the day’s bills, including partial payments.
- Cash / UPI / cheques: effective collected amounts by the recorded payment mode.
- Expected cash from ledger: bills + old-balance payments − credit − UPI − cheques.
- Cash physically handed over: the driver’s **cumulative total for that day**.
- Difference: handed-over cash minus recorded cash; negative means a shortage.

There is no independently planned cash-collection target in the existing model.
Expected cash therefore reconciles the recorded bills/receipts and normally
equals recorded cash. It cannot expose an unrecorded bill or cash payment.
Owner approval confirms the driver’s declared daily handover, after the owner
counts it. Resubmission replaces the current daily declaration through another
audit event; it is **not an additional cash transfer**. UPI and cheque entries
remain reported receipts, not bank clearance. No expenses or adjustments are
silently deducted from cash: explain differences explicitly.

The server rejects future-day settlement using the Asia/Kolkata business date.
The phone performs an additional local-date check. Backdated delivery lists
remain attached to their scheduled date; choose the correct list when recording.

## Driver and owner workflow

1. The driver synchronizes all delivery results and collections on their phone.
   The settlement screen lists every pending visit, ledger and settlement
   operation, including its saved ID and any failure. Submission is disabled
   until all queues are empty. The SQLite insertion transaction repeats this
   check, so bypassing a disabled button cannot skip it.
2. The driver enters counted cash handed over. A nonzero difference requires a
   reason, up to 500 characters. Amount and reason are saved as a local draft.
3. **Submit & lock day** first saves a durable request on the phone, then syncs.
   The screen says **awaiting receipt** while delivery to the server is uncertain.
   That day’s local collection additions and corrections are already blocked.
4. The server verifies the current settlement revision and day-ledger sequence,
   recalculates totals, appends a submission event, and locks the day atomically.
5. An owner syncs, reviews the amounts and explanation, physically counts the
   cash, and selects **Confirm cash received & approve**. The confirmation dialog
   repeats the amount and difference. Approval preserves the submission.
6. If a correction is necessary, an owner selects **Reopen with reason**.
   Collections unlock after the server acknowledges the reopening. The original
   submission, any approval, actor, server timestamp, reason and totals remain
   visible in history. The driver reviews and resubmits the complete day total.

## Persistence, permissions and concurrent changes

- SQLite v4 upgrades the v3 cache without replacing shops, visits, financial
  history or pending financial IDs. Drafts stay in the account’s local settings.
- `settlement_days` is an authorized server snapshot cache; `pending_settlements`
  stores the exact JSON request, durable operation ID and failure before network
  I/O. An acknowledgement must contain the request’s event before clearing it.
- A lost reply is retried with the identical payload and ID. The server returns
  the current day including the original receipt; it never duplicates that event.
  A downloaded snapshot alone does not discard a pending request.
- Network failures retain the request and local lock. Only explicit server
  `SETTLEMENT_VERSION_CONFLICT` or `SETTLEMENT_DAY_CHANGED` rejections are marked
  as rejected. They retain their details until **Remove rejected request & review**
  is selected. The user then reviews synchronized totals and submits a new request.
  Uncertain requests cannot be discarded using this control.
- Server advisory locks serialize settlement decisions with financial writes
  for that driver/day. The order is day → operation → existing shop → stop.
  Submission compares the last financial sequence; approval compares the
  submitted totals and amount. Stale submissions and stale owner decisions fail.
- `settlement_events` is the server’s append-only state and audit trail. RLS
  allows owners and the subject driver to read it; clients cannot directly insert,
  update or delete events. Only the driver submits; owners approve/reopen. RPCs
  use an empty search path. The original ledger RPC is private behind a day-lock
  wrapper, so old apps and direct RPC callers cannot bypass financial locks.
- Owners also need to reopen a locked day before financial corrections. Committed
  ledger requests can still replay while locked. New stops cannot be added to a
  locked day, and a stop with financial history cannot change driver/date/shop.
- Submission blocks unsynced actions **on this phone**. The server can check only
  committed records from other devices; it cannot discover their offline queues.
  Another phone’s delayed same-day collection is rejected while the day is locked
  and retained for owner review. Reopen and resolve it before final approval.
- Totals shown offline are labelled last synced totals. A missing settlement
  migration does not disable the existing shop directory; settlement reports
  the required migration. No new paid service or package is required.

## Automated checks

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify_maps_sql.ps1 -TestFile supabase/tests/daily_settlements.sql
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify.ps1 -Preview
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build_test_apk.ps1 -Shared -PreloadGradle
```

Flutter tests cover effective totals and date attribution, required difference
reasons, local day locking, driver/owner permissions, approval/reopening history,
both pending queue types, rejected vs uncertain requests, exact replay after a
real SQLite restart, draft persistence, the v3-to-v4 upgrade and compact UI flows.
The SQL suite runs all earlier regression checks plus real migration/RLS/RPC
checks in an isolated PostgreSQL database, never the production project.

## Manual device and shared-project checklist

1. Apply the migration in the test Supabase project; update all phones. Sign in
   as the driver and the two owners. Confirm each sees only permitted records.
2. On a delivery date record cash, partial cash, UPI, cheque, credit and a separate
   old-balance payment. Compare the day totals against manually summed receipts.
3. Deny GPS and record a valid collection. Confirm cash reconciliation still
   works, and GPS status remains explicit in its ledger entry.
4. Go offline, add a collection and a failed visit. Open settlement. Confirm both
   shop names, operation IDs and the failed-visit reason appear; submission blocks.
5. Type a draft cash amount and explanation, restart the app, and confirm the
   draft remains. Reconnect and synchronize; compare the refreshed totals.
6. Enter a cash shortage without a reason; submission must remain unavailable.
   Add the reason and submit. Disconnect immediately after the server write if
   possible, restart, reconnect, and confirm one event, not a duplicate.
7. While submitted, try adding another collection and an owner correction from
   another phone/older APK. The server must reject both. Committed operation
   retries must still return their original receipts.
8. The owner physically counts cash and approves using the confirmation dialog.
   The second owner attempts an outdated decision after the first owner updates
   the day: it must be rejected and require review of the current state.
9. Reopen with a reason, sync the driver, correct the collection as owner, and
   resubmit the full daily handover. Confirm all revisions, reasons and actors
   remain visible and amounts are counted only once.
10. Keep another device offline with an unsent same-day collection, settle on the
    first device, then reconnect the second. Confirm its money record is retained
    with a lock error; reopen the day and resolve it before approving again.
11. Install over the previous APK without clearing data. Confirm shops, financial
    history, queued IDs and navigation still work. Check at native text scaling
    and with the Android keyboard open. These physical-device checks remain
    necessary; desktop tests do not prove real cash or bank receipt.

Milestone 3 (driver experience, design system and full dark mode) requires separate
authorization. Route optimization, reports, background sync and billing are later.
