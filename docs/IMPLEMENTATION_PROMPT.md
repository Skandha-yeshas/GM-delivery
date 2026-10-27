# Reusable implementation prompt

Act as a senior Flutter/Dart Android engineer. Build G.M. Delivery for G.M.
Enterprises, a pen distributor with 600+ shops and roughly 30–35 daily deliveries.
Two owners and one delivery person use one Android app with separate accounts.
All daily controls work on phones. Start with free tools/services and distribute
signed APK files directly. Use Flutter/Dart, SQLite for offline data and Supabase
Free for shared PostgreSQL records, Auth and private photo storage. Keep Tally
entirely separate. A proprietary billing system is a future milestone.

Initial launch: shop locations and delivery navigation.

The owner Assign Delivery tab and scanner follow the supplied dispatch design.
Read `docs/DISPATCH_DESIGN.md`; keep name-only OCR, real saved locations and driver
choices, explicit Confirm Dispatch, duplicate protection and the reviewed GPS
shop-form flow. Preserve visit/financial actions and avoid simulated OCR metadata.

The shop directory follows the supplied navy/white reference. Read
`docs/SHOP_DIRECTORY.md`; preserve real letter/area/location/search filters,
alphabetical groups, sorting, call/details actions, Excel import, registered
versus filtered counts and lazy rendering for 600+ shops. Use only All Shops and
Assign Delivery for owner navigation, starting on All Shops. Keep settlements and
outstanding balances accessible from the account avatar.

The shop add/edit forms now follow the supplied HTML reference. Read
`docs/SHOP_PROFILES.md`: require the marked name/contact/mobile/address/PIN fields
in manual add/edit while keeping Name/Location imports compatible. Preserve
contact person/PIN persistence, optional area/landmark/instructions/photo,
the existing Maps-link readiness rule, real GPS accuracy, best-effort address
lookup that retains owner text, and explicit coordinate entrance confirmation.
This scoped shop-form work does not implement the full driver redesign milestone.

- Searchable shops with stable IDs, name, area, contact, address, landmark,
  instructions and shopfront photo.
- Capture GPS on request at the entrance, show accuracy, allow re-capture and
  map preview, and require explicit verification. Keep coordinates internal;
  show no manual latitude/longitude inputs or raw coordinate readouts.
- A saved Google Maps share link counts as a ready delivery location, including
  short links with no extracted coordinates. Open the saved link for navigation.
  Prevent assignment only when there is neither
  a valid Maps link nor verified coordinates. Keep the backend rule consistent.
- Owners select daily shops and assign the driver. Prevent duplicate shop/date
  stops. Open Google Maps one stop at a time; do not claim route optimization.
- Driver sees assigned stops, calls shops and records delivered/failed visits.
- Cache records/photos offline and persist unsent results across restarts. Use
  durable operation IDs, optimistic versions and visible synchronization status.
- Enforce roles in the backend, not only the UI. Never expose service-role keys.
- Provide empty states, permission-denial handling, Android configuration, signing
  instructions, cloud setup SQL and focused tests.
- Without cloud config, permit an explicitly labeled device-only trial. Its data
  is not shared and its controls do not provide multi-user security.
- Report actual analysis/test/build results and remaining device/cloud checks.

Collections milestone 1 is implemented. Read `docs/COLLECTIONS_LEDGER.md` before
extending it. Preserve integer paise, append-only history, durable offline IDs,
server balance calculation, assignment checks and owner-only corrections.
Milestone 2 (daily settlements) is implemented; read `docs/DAILY_SETTLEMENTS.md`.
Preserve local-first requests, the unsynced-operation gate, server day locks,
effective integer totals, owner confirmation and immutable transition history.
The supplied driver home design is implemented in `DriverDeliveryBoard`; see
`docs/DRIVER_DELIVERIES.md`. Further driver features and dark mode are separate
milestones, beyond the implemented ordered route/navigation/collection interface.
Owner manual route ordering is implemented; see `docs/DELIVERY_ORDER.md` and
`20261023_delivery_order.sql`. Later milestones include location quality, reports and release
hardening. The following notes describe optional OCR and future finance work.

- Use on-device Google ML Kit OCR and extraction rules tested on real bill samples.
  Prefill number/date, customer, printed address and total; require owner review.
  Match saved shops, ask when ambiguous and flag duplicate bills.
- Keep bill amount separate from expected collection; handle partial/unpaid amounts
  and old balances after owners verify their starting records.
- Link each cash/UPI collection to shop, reference, driver and receipt ID. Company
  UPI receipt needs verification. Cash held equals recorded cash collections minus
  confirmed handovers and separately approved adjustments.
- Only owners confirm physically counted cash. Preserve original records and use
  approved adjustments with audit history. Shopkeeper receipts help detect
  unreported cash; software alone cannot guarantee prevention of misuse.
- Add automated messaging only after its costs and authorization are agreed.

Inspect and extend the existing project, one authorized milestone at a time.
Keep billing and Tally integration separate. After each milestone report checks,
remaining device validation and ask before starting the next one.
