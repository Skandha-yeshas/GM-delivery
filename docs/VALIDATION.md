# Driver search/deliveries, owner dispatch and finance validation — 25 October 2026

- Static analysis: passed, no issues.
- Two-tab owner navigation: the existing owner workflow verifies exactly All Shops
  and Assign Delivery, starts on All Shops and contains no Overview destination.
  The account avatar opens both Daily settlements and Outstanding balances, and
  returning from either screen retains working shop/import/assignment controls.
  Overview was also removed from the gallery and capture runner.
- Automated tests: all 78 passed (SQLite storage, offline queue preservation,
  duplicate assignments, verification/permission checks, owner UI workflow,
  Maps pin parsing, Excel validation, a 600-shop import with duplicate/retry
  checks, a local database upgrade preserving existing shop data, bill recipient
  matching, OCR spelling errors, same-name branches, 600-shop matching, scan
  whole-bill customer-name extraction, confirmation/GPS display, persisted
  assignment, pending-camera recovery, adding an unknown shop from a scan,
  Maps-only locations and rejection of invalid links/coordinates, integer-paise
  parsing and overflow rejection, partial/credit collections, old-balance payments,
  immutable corrections, duplicate bills, financial role checks, real SQLite reopen,
  a lost server reply, successive offline stop versions, a stalled network refresh,
  transaction rollback on a failed local save, legacy delivered-result transfer,
  opening-balance Excel retries and a v2-to-v3 upgrade preserving old visit queues).
- Driver shop-search checks: passed for names/contact/address/landmark searches,
  case handling and formatted phone digits, combined today/location/area filters,
  live counts and reset, real selected-shop call/Maps targets, missing phone and
  location gates, dismissible location sheets, 606-record lazy rendering and
  320-pixel enlarged text with keyboard insets. A real SQLite/controller Home
  workflow verified that other-driver shops are excluded, historical assigned
  shops remain searchable, the query survives tab changes and owner route order
  stays unchanged. The user explicitly selected assigned-only access; no database
  policy or driver write permission was expanded.
- Driver-interface workflows: passed using real SQLite records, a sequence saved
  through the owner controller and a distinct driver account/controller. Verified
  the initial Deliveries tab, signed-in name, driver/date filtering, owner order,
  correct Maps-only next-shop target, 33%/67% progress, a saved credit collection
  advancing the next stop without changing order, enlarged text at 320 pixels,
  queued-result action gates, empty-date refresh, failed-stop handling and daily
  settlement access. Maps/dialler callbacks use controlled tests; real external
  app launches and live multi-phone updates still need Android verification.
- Owner delivery ordering: actual drag gestures, reset and arrow/save interaction
  passed at 320 pixels. The current route planner also passed at 140% text size,
  including invalidation when a visit changes during editing. SQLite restart
  preserved the driver's new sequence, completed positions, visit versions and
  unrelated-driver stops. Invalid/omitted stop lists, driver attempts and pending
  phone records were rejected. A failed SQLite update rolled back all positions;
  a lost server confirmation retained the old local order until the same request
  was safely acknowledged on retry.
- Route PostgreSQL checks: passed with the actual additive migration applied twice,
  and every prior SQL suite. Verified atomic pending-stop swaps, completed/failed
  position and version preservation, unchanged ledger count, strict complete-route
  snapshots, duplicate/omitted/completed-ID rejection, wrong-day rejection, stale
  owner/visit rejection, idempotent replay, request/actor mismatch denial, driver
  and direct-write denial, private owner history and settlement locks. A driver
  result using its pre-reorder visit version was accepted. The disposable local
  server was stopped. Reproduce with
  `scripts/verify_maps_sql.ps1 -TestFile supabase/tests/delivery_order.sql`.
- Dispatch design checks: real pending/delivered counts and scan/manual/date
  actions pass at 320 pixels with 140% text scale. Matched and unregistered scan
  flows, explicit Confirm Dispatch, Maps-only readiness, missing location and
  missing driver rejection, already-scheduled duplicate protection, resumed camera
  drafts and the return from Add shop pass. Direct Live GPS Pin opens the form,
  captures via a controlled service and fills the address; cancel saves neither
  a shop nor an assignment. The driver cannot enter the scanner. Native camera,
  GPS and geocoding quality still need real Android checks.
- Directory checks: letter ranges and alphabetical/reverse sorting, search and
  clear, combined area/location filters, Maps-only readiness, reset after no
  matches, correct call/details callbacks, absent phone numbers, hidden owner
  import actions for drivers, 606-record lazy rendering, # grouping for numeric
  and non-Latin names, and a 320-pixel screen at 140% text scale passed. The
  existing owner workflow passed after switching between All Shops and Assign
  Delivery, with consistent font styles for the changing floating action button.
  The initial parallel preview/test cache collision was resolved by sequential
  runs. The directory design adds no database migration; prior SQL results below
  cover the unchanged persistence rules.
- New shop-profile tests: passed for contact/PIN persistence across add/edit,
  Maps-only delivery readiness, real capture workflow with controlled location
  service, generated coordinate link, explicit entrance confirmation, address
  lookup failure retaining the fix, permission denial without a success claim,
  manual address edits during a delayed lookup, malformed PIN rejection and a
  v4-to-v5 SQLite upgrade preserving existing shops/stops/queued visit IDs.
- Manual shop-form rules: all marked name/contact/mobile/address/PIN fields are
  validated, including fields below the initial viewport. Invalid mobile/PIN
  blocks saving; the mobile field normalizes a pasted +91 number. Cancel keeps
  the original saved name and verified GPS pin. Manual coordinate inputs/raw
  coordinate text are absent. The 320-pixel screen at 140% text scale passes
  without clipping or overflow; the location panel grows with its contents.
- Shop-profile PostgreSQL checks: passed using the real migration and all earlier
  SQL suites, including retrying the migration, add/edit, audit snapshots, stale
  versions, invalid PINs, driver/direct-edit denial and preservation of new fields
  when older APK requests omit them. Reproduce with
  `scripts/verify_maps_sql.ps1 -TestFile supabase/tests/shop_profiles.sql`.
- Settlement tests: passed for corrected daily totals and original date attribution,
  required shortage reasons, local financial locks, driver/owner permissions,
  pending visit and money gates, durable request replay after a real SQLite restart,
  rejected versus uncertain requests, draft persistence and a v3-to-v4 upgrade.
  At 390 × 844, the widget test enters a shortage, submits, taps the owner's cash
  confirmation and approval, then reopens with a mandatory reason. Dialog tests
  initiate taps with real asynchronous I/O so their SQLite saves can finish.
- Compact financial widget checks: passed at 390 × 844 for partial cash with denied
  GPS, owner corrections retaining the original, amount/age sorting, area filtering
  and a reminder preselecting the next delivery list.
- Bill-scan widget tests use a controlled OCR service; they do not measure ML Kit
  recognition accuracy. They verify that a unique exact name opens the saved
  shop, assignment needs owner confirmation, a saved Maps link works without GPS,
  absence of both a Maps link and verified coordinates blocks assignment,
  a new shop returns to the same scan, and the driver role cannot scan.
- Owner UI test: import screen reachable at 390 × 844; a pasted short Maps link
  can be saved without pin extraction or verification, then added to the list.
  The focused workflow was rerun after shortening the empty-screen message.
- PostgreSQL 18 checks: passed against an isolated, disposable local cluster using
  the actual schema and migrations, with minimal auth/storage stand-ins. Verified
  migration retries, accepted full/short Maps links, rejected invalid links,
  link-only and verified-coordinate assignments, missing/unverified location
  rejection, duplicate protection, pending-status reset, valid driver and owner
  permission checks. The test server was stopped after the run. Reproduce with
  `scripts/verify_maps_sql.ps1` when PostgreSQL tools are on PATH. This does not
  connect to the live Supabase project.
- Collections PostgreSQL checks: passed using the real new migration. Verified
  idempotent replay, changed-request rejection, duplicate bill rejection, partial
  payments and credit, old-balance payments, UPI/cheque references, integer money,
  FIFO aging, original-record immutability, reasoned/versioned owner corrections,
  reminder versions, driver visibility including corrections to their own records,
  denial of unassigned and anonymous access, and denial of direct money edits.
  The legacy delivered endpoint cannot bypass collection entry; already committed
  old results replay and a lost old response can continue through the collection
  RPC. The test cluster was stopped after completion. Run
  `scripts/verify_maps_sql.ps1 -TestFile supabase/tests/collections_ledger.sql`.
- Settlement PostgreSQL checks: passed with the real migration, including effective
  totals, required difference/reopening reasons, integer amounts and JSON types,
  immutable event history, exact replay, changed-payload rejection, RLS, anonymous
  denial, owner/driver roles, stale settlement revisions and financial sequences,
  locked-day bill/correction/new-stop rejection, private-RPC denial and committed
  ledger replay while locked. Run
  `scripts/verify_maps_sql.ps1 -TestFile supabase/tests/daily_settlements.sql`.
  This includes both earlier SQL suites; its disposable PostgreSQL server was stopped.
  Current-day snapshots and a zero-cash submission without delivery activity also passed.
- Phone preview capture: passed at 390 × 844. The shop directory, scanner,
  matched-shop GPS, Maps-only location, missing-shop, collection-entry, credit-ledger
  and outstanding screens use real Flutter widgets with
  illustrative in-memory data and controlled OCR output. The production app
  does not receive these sample records.
- All 26 current phone captures passed, including driver shop search, a contact-name
  search result, the saved-location sheet, the driver home and stop card,
  saved route and reordered
  draft/save bar, driver settlement with a ₹10 shortage
  and owner review with cash confirmation/reopening controls. Images are captured
  at 390 × 844 logical size; scrolled examples show the relevant form/review area.
- New Add shop, Edit shop, Shop location and Delivery entrance captures use the supplied navy/white
  design and bundled Plus Jakarta Sans font. Visually checked populated contact
  fields, saved versus newly captured entrance status, editable address/PIN and
  the fixed Save/Cancel actions. GPS/address samples are controlled preview data,
  never inserted into the production directory.
- The shop-directory capture follows the supplied navy/white reference with
  contact/address/phone cards and live counts; the A–D example uses a real letter
  filter. Owner accounts still open All Shops; the gallery now opens the driver
  shop-search example. New dispatch captures show
  the route planner, saved numbered stops, a reordered draft, unregistered
  shop options and a matched shop's driver/Confirm Dispatch card. OCR and GPS in
  these captures are controlled illustrative data, not real device measurements.
- Driver captures were visually checked at 390 × 844: signed-in name, actual
  delivered/pending/failed counts, owner-sequence strip, next-shop navigation,
  saved contacts/entrance notes, calls/directions and delivery/collection actions.
  They use illustrative SQLite records and do not seed production phone data.
- Driver shop-search captures were visually checked for the assigned-shop scope,
  filter counts, contact-name result and navy/white location sheet with actual
  address, landmark, instructions, Maps and call actions. The preview uses
  controlled records; device Maps/dialler launches remain a manual check.
- Excel template generation: passed; two headers, Name and Location, no sample rows.
- Android debug APK: rebuilt successfully on 25 October 2026 from source version
  `0.6.8+15`, including assigned-shop search, the driver home and owner delivery sequencing, using
  `scripts/build_test_apk.ps1 -Shared -PreloadGradle`. It uses the replacement
  Supabase project's settings saved in `config/cloud.json`; credentials were not printed.
- APK signature: verified with Android `apksigner`; uses the Android debug certificate.
- Package: `com.gmenterprises.gm_delivery`, version `0.6.8`, build `15`.
- Declared minimum Android: API 24 (Android 7.0); target API 36.
- Included ABIs: arm64-v8a, armeabi-v7a and x86_64.
- APK: `build/app/outputs/flutter-apk/app-debug.apk`, 193,117,475 bytes (184.2 MiB).
- APK SHA-256: `3dabf308667304c6a3cb6ba79ca21398da1611465f0e38fc89306acf77cd0c3e`.
- Android build completed successfully with native geocoding and the bundled font;
  APK Signature Scheme v2 verified with one signer.
  The Gradle wrapper was restored to its official distribution URL after the build.
- Bundled English/Latin OCR: ML Kit text-recognition 16.0.1 via
  google_mlkit_text_recognition 0.17.1. Existing projects need
  `supabase/migrations/20261015_maps_link_delivery.sql` after the owner import
  migration to allow Maps-link delivery assignments on the server.
- Collections additionally require `supabase/migrations/20261016_collections_ledger.sql`.
- Daily settlements additionally require `supabase/migrations/20261017_daily_settlements.sql`.
- Shop profiles require `supabase/migrations/20261020_shop_profiles.sql`.
  The local database upgrades to v5 without replacing existing records or queue IDs.
- Shared route ordering requires `supabase/migrations/20261023_delivery_order.sql`.
  Order-only edits preserve visit versions and use a separate owner audit table.

This APK was built with the project URL and public publishable key from the
ignored `config/cloud.json` and is configured for app sign-in. The original
Supabase project was deleted and replaced. Historical endpoint probes on
13 October returned HTTP 200 for auth settings and HTTP 401 for unauthenticated
profiles; they do not validate the replacement project. On 24 October the user
reported applying the base schema and six migrations, creating two accounts and
assigning owner/driver roles in the new project. The agent checked configuration
format and rebuilt/signed the APK, but has not verified live sign-in or
authenticated database operations against this replacement project.
Android file selection, template
saving, live short-link redirects and real bill OCR accuracy need emulator/device
checks. Physical-device sign-in, shared
records, GPS, camera, navigation, offline restart and update-installation checks
remain to be performed. Structured invoice-field extraction, a shared
bill archive and billing remain future work. See `docs/BILL_SCANNING.md` for the
implemented photo-to-shop matching and delivery preparation flow.
See `docs/COLLECTIONS_LEDGER.md` for the collections plan, implementation decisions
and ten-step device/cloud checklist. Financial conflicts are retained for review;
the later reliability milestone supplies the detailed resolution workflow. UPI and
cheque clearance are not verified automatically. Settlement approval records the
owner's explicit confirmation after counting cash; it does not independently
measure physical cash or detect unrecorded receipts. Expected cash reconciles
the recorded ledger, rather than an independent collection target. See
`docs/DAILY_SETTLEMENTS.md` for setup, decisions and the eleven-step shared-device
checklist. Actual simultaneous phone requests remain part of that manual check;
the automated SQL suite verifies stale decisions and shared locking paths.

`docs/SHOP_PROFILES.md` describes the supplied-design adaptation and its device
checklist. Address lookup uses geocoding 5.0.0 / geocoding_android 5.1.0 with the
platform provider; real location accuracy and reverse-address availability still
need physical Android checks. Existing owner text is not replaced by lookup.
The bundled Plus Jakarta Sans font and OFL license support offline rendering.

The first Windows build required SDK components and a checksum-verified Gradle
download fallback. The temporary wrapper URL was restored after the build.
Use `scripts/build_test_apk.ps1 -PreloadGradle` if Java's Gradle downloader times out.
The connected rebuild also required moving previous generated build output into
`.tooling/b` after Windows prevented Gradle from clearing existing generated
folders. The backup initially had a longer timestamped name, which caused a
OneDrive path-length error. It was shortened to `b`; at that check, the longest
OneDrive-relative file paths in the backup and build were 365 and 360 characters.
The previous trial APK remains in that backup.
