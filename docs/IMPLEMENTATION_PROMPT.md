# Reusable implementation prompt

Act as a senior Flutter/Dart Android engineer. Build G.M. Delivery for G.M.
Enterprises, a pen distributor with 600+ shops and roughly 30–35 daily deliveries.
Two owners and one delivery person use one Android app with separate accounts.
All daily controls work on phones. Start with free tools/services and distribute
signed APK files directly. Use Flutter/Dart, SQLite for offline data and Supabase
Free for shared PostgreSQL records, Auth and private photo storage. Keep Tally
entirely separate. A proprietary billing system is a future milestone.

Initial launch: shop locations and delivery navigation.

- Searchable shops with stable IDs, name, area, contact, address, landmark,
  instructions and shopfront photo.
- Capture GPS on request at the entrance, show accuracy, allow coordinate
  correction and map preview, and require explicit verification.
- A saved Google Maps share link counts as a ready delivery location, including
  short links with no extracted coordinates. Open the saved link for navigation.
  Make manual coordinates optional; prevent assignment only when there is neither
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

Next milestone: collections and bill-photo scanning.

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

Inspect and extend the existing project. Finish and verify the location milestone
first. Keep collections and billing separate until requested.
