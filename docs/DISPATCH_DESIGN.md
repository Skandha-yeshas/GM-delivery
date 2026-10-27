# Assign Delivery design

The owner assignment tab and bill-scanning flow follow the supplied HTML design:
navy actions, Plus Jakarta Sans, a light background, a Smart Bill Upload & Dispatch
panel, matched/unregistered shop cards, saved contact/drop-point details, driver
selection and Confirm Dispatch. The assignment tab now uses the route-planning
reference: compact numbered stops, drag handles, arrows, driver/date controls,
first-drop emphasis and a fixed save/reset bar. See `docs/DELIVERY_ORDER.md`.

- The selected day's saved stops form the assignment feed. Counts represent
  pending deliveries and completed/attempted stops, not unprocessed invoices. Each stop
  shows its actual address/contact; expanded details show driver, balance and status. Pending local
  results show Waiting to sync. Date selection, manual Add stops and refresh remain.
- Scan Next Bill opens the camera/photo-selection screen. Whole-bill English OCR
  extracts only the customer shop name. The name remains editable, and ambiguous
  branches require an explicit choice.
- A matched card uses the shop's saved Maps link or GPS entrance. Raw coordinates
  are hidden. A Maps share link is ready without extracted GPS; a GPS-only pin
  needs entrance verification. Missing/unverified locations block dispatch.
- Confirm Dispatch saves through the existing controller and shared RPC before
  showing Scheduled for dispatch. A driver is required and shop/date duplicate
  protection remains. No assignment is made from OCR or GPS capture alone.
- An unregistered result offers Add new shop or Direct Live GPS Pin. The latter
  opens the required-field shop form and starts real foreground GPS capture and
  address lookup. Review the pin and complete the profile, then save before dispatch.
  Cancel leaves the saved directory/list unchanged. Capturing does not notify drivers.
- Existing Update result, ledger, collection, reopen and remove controls remain
  accessible on saved stop cards. The driver screen and financial persistence
  rules are unchanged. Owner navigation has only All Shops and Assign Delivery.
  Settlements and outstanding balances are available from the account avatar.

There is one resumable bill-photo draft plus the saved delivery list. The design's
sample bill numbers, carton counts, vehicle/route matches, departure times and
Auto-Geocoded/OCR Active labels are not real data in this version. The app does
not claim carton OCR, address OCR, automatic geocoding, push notifications or a
persisted queue of unconfirmed invoices. Tally stays separate.

Route ordering requires `supabase/migrations/20261023_delivery_order.sql` after
the previous migrations; no new paid dependency is required. Use `preview/index.html`
for Assign Delivery, Scan a whole bill, the matched Confirm Dispatch card and
Add missing shop. Captures use controlled OCR/location services and illustrative
in-memory data. Install the updated APK in Android Studio for interaction.

Run `scripts/verify.ps1`, then `scripts/verify.ps1 -Preview` sequentially on Windows
to avoid competing for Flutter's test cache. Real camera recognition, GPS/address
accuracy, permissions and shared multi-phone updates still need Android checks.
