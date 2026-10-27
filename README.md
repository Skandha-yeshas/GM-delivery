# G.M. Delivery — Android deliveries and collections

A Flutter/Dart app for G.M. Enterprises. Both owners and the delivery person use
the same APK, with separate accounts when cloud sharing is enabled.

## Implemented

- Two owner tabs: All Shops and Assign Delivery. All Shops opens first;
  settlements and outstanding balances are available from the account avatar.
- Search shops by name, area, address, landmark or phone; filter by area and location status.
- Shop directory follows the supplied navy/white design, with live registered
  counts, A–Z groups, letter filters, reversible sorting and saved contact/call
  cards. See [directory design](docs/SHOP_DIRECTORY.md).
- Owners import 600+ shops from Excel with a preview, row errors and duplicate checks.
  Start with the Name/Location template; see [owner import instructions](docs/OWNER_IMPORT.md).
- Save Google Maps share links as delivery locations without typing coordinates.
  Pin extraction is optional; shops without a link or pin can be completed later.
- Add/edit contacts, instructions and shopfront photos.
- Shop add/edit forms follow the supplied design, with required contact/mobile,
  street address and PIN, a fixed Save/Cancel bar, GPS address lookup and no manual
  latitude/longitude fields. See
  [shop profile setup](docs/SHOP_PROFILES.md).
- Capture foreground GPS coordinates, preview in Google Maps, and explicitly
  verify the delivery entrance. A valid saved Maps link is ready directly;
  coordinate-only locations need verification.
- Owners select multiple shops, a date and a delivery person.
- Drag pending shops into delivery order, or use up/down arrows, then save the
  driver's sequence. Completed positions, visits and money records are preserved;
  stale drafts are rejected. See [delivery ordering setup](docs/DELIVERY_ORDER.md).
- Assign Delivery follows the supplied scan/dispatch design, with real driver/drop
  details, matched/unregistered shop states and Confirm Dispatch. Direct Live GPS
  opens the reviewed shop form. See [dispatch design](docs/DISPATCH_DESIGN.md).
- Owners scan a whole printed English bill; the app extracts only its customer
  shop name, finds a saved shop/GPS or offers to add a new shop without leaving
  delivery preparation. The owner confirms before adding the stop. See
  [bill-scanning instructions](docs/BILL_SCANNING.md).
- Driver opens navigation, calls shops and records delivered/failed visits.
- Driver Deliveries opens first with live progress, the owner's numbered route,
  next-stop Maps navigation and contact/collection controls adapted from the
  supplied design. See [driver interface](docs/DRIVER_DELIVERIES.md).
- The driver's Shops tab searches assigned shop names, contacts, addresses and
  phone numbers, with area/location/today filters and saved-location/call actions.
  See [driver shop search](docs/DRIVER_SHOP_SEARCH.md).
- Collections and credit ledger: integer-paise bills, partial payments, cash/UPI/
  cheque/credit, manual or Excel opening balances, owner corrections with audit
  history, outstanding filters and next-visit reminders. Financial actions save
  offline first and replay with durable IDs. See [collections setup and checks](docs/COLLECTIONS_LEDGER.md).
- SQLite stores downloaded records and queues offline visit results.
- Daily settlements: driver cash declaration, required difference reasons,
  pending-operation gate, server day locks and owner approval/reopening with audit
  history. See [settlement setup and device checklist](docs/DAILY_SETTLEMENTS.md).
- Durable operation IDs prevent retrying a visit update from applying it twice.
- Server permissions restrict drivers to assigned records. Owners share the directory.
- Optimistic versions reject edits made against an outdated record.

Bank confirmation, invoice-field extraction, route optimization and billing are future milestones. There
is no Tally integration. Navigation opens Google Maps rather than embedding a paid
map service. Offline navigation availability depends on Google Maps.

## Run on Android

To see the screens at a phone aspect ratio on your laptop, open
`preview/index.html`. See [laptop preview instructions](docs/LAPTOP_PREVIEW.md)
for the screen gallery and interactive Android emulator setup.

Install Flutter, a compatible JDK and the Android SDK. Connect a phone with USB
debugging enabled:

```powershell
flutter pub get
flutter run
```

On this Windows setup, `scripts/verify.ps1` handles spaces in the installed Flutter
SDK path. `scripts/setup_android.ps1 -AcceptLicenses` installs Google's verified
command-line build tools inside `.tooling/` without installing Android Studio.
`scripts/build_test_apk.ps1` builds a local trial APK; add `-Shared` after filling
the cloud config. Android SDK/Gradle downloads are needed on the first build.

Without cloud configuration, the app starts in **this-phone-only trial mode** with
an empty directory. All trial controls are owner controls; this is not a secure
multi-user deployment. Trial records stay separate from cloud accounts; automatic
migration is not implemented. Configure sharing before collecting the production
directory across three phones.

## Enable free sharing

Follow [Supabase setup](docs/SUPABASE_SETUP.md), then:

```powershell
Copy-Item config/cloud.example.json config/cloud.json
# Fill cloud.json with the project URL and PUBLIC publishable/anon key.
flutter run --dart-define-from-file=config/cloud.json
```

Build the same configured APK for all three phones. Each person signs in separately.
Initial infrastructure/account provisioning is a developer/admin setup task; daily
operations happen on phones. There is no public signup or client-side role picker.

Shared shop edits, assignments and route saves require internet. Driver results are saved locally
first, then synchronized while the app is open or resumes. This version has **no
closed-app background service**. Open the app and sync before relying on final results.
Pending counts and failures stay visible. Only previously synced records can be
restored after a phone is lost.

## Build test APKs

A configured test APK is built at the output path below. See
[validation results](docs/VALIDATION.md) for checks and remaining device/cloud work.

```powershell
# Uses Android's debug signing key; for testing only.
flutter build apk --debug

# Three-account shared test APK:
flutter build apk --debug --dart-define-from-file=config/cloud.json
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`. Transfer it to the phone,
allow installation from that source and install. Updates require the same app ID
and signing certificate. Install over the existing app; avoid uninstalling when
changes have not synced.

For production, follow [release signing](docs/APK_SIGNING.md). Release builds fail
when private signing configuration is missing. Keep the signing key backed up.

## Validate

```powershell
flutter analyze
flutter test
```

Tests exercise SQLite persistence, duplicate assignments, verification gates,
preservation of queued updates, local permission checks and a compact-screen owner
workflow. Cloud SQL must still be validated against your project and real accounts.
Physical-device testing is needed for GPS/camera permissions, camera recovery,
navigation, poor connectivity and APK updates.

## Structure

- `lib/domain/`: shop, delivery and queued-result models.
- `lib/data/`: SQLite and Supabase access.
- `lib/application/`: workflows and synchronization.
- `lib/presentation/`: phone screens.
- `supabase/schema.sql`: tables, server permissions, audit history and RPCs.
- `docs/IMPLEMENTATION_PROMPT.md`: reusable brief and future milestones.

Supabase starts on Free within its allowances. Monitor storage/download usage;
upgrading remains a later decision.
