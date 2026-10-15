# Maps-link delivery and owner workspace validation — 15 October 2026

- Static analysis: passed, no issues.
- Automated tests: all 26 passed (SQLite storage, offline queue preservation,
  duplicate assignments, verification/permission checks, owner UI workflow,
  Maps pin parsing, Excel validation, a 600-shop import with duplicate/retry
  checks, a local database upgrade preserving existing shop data, bill recipient
  matching, OCR spelling errors, same-name branches, 600-shop matching, scan
  whole-bill customer-name extraction, confirmation/GPS display, persisted
  assignment, pending-camera recovery, adding an unknown shop from a scan,
  Maps-only locations and rejection of invalid links/coordinates).
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
- Phone preview capture: passed at 390 × 844. The owner overview, scanner,
  matched-shop GPS, Maps-only location and missing-shop screens use real Flutter widgets with
  illustrative in-memory data and controlled OCR output. The production app
  does not receive these sample records.
- Excel template generation: passed; two headers, Name and Location, no sample rows.
- Android debug APK: built successfully.
- APK signature: verified with Android `apksigner`; uses the Android debug certificate.
- Package: `com.gmenterprises.gm_delivery`, version `0.4.1`, build `5`.
- Declared minimum Android: API 24 (Android 7.0); target API 36.
- Included ABIs: arm64-v8a, armeabi-v7a and x86_64.
- APK: `build/app/outputs/flutter-apk/app-debug.apk`, approximately 183.7 MiB.
- APK SHA-256: `af85ca2764ee721e3c1098817b9f5eb7a42de46a3720e9b217aeff277eaa4780`.
- Bundled English/Latin OCR: ML Kit text-recognition 16.0.1 via
  google_mlkit_text_recognition 0.17.1. Existing projects need
  `supabase/migrations/20261015_maps_link_delivery.sql` after the owner import
  migration to allow Maps-link delivery assignments on the server.

This APK was rebuilt with the project URL and public publishable key from the
ignored `config/cloud.json` and opens to app sign-in. The Supabase authentication
settings endpoint responded with HTTP 200. An unauthenticated profiles request
returned HTTP 401; authenticated database operations and owner/driver permissions
have not yet been verified against this project. These endpoint probes were made
on 13 October. The owner import and Maps-link SQL migrations are prepared but have
not been executed against the live project by the agent. Android file selection, template
saving, live short-link redirects and real bill OCR accuracy need emulator/device
checks. Physical-device sign-in, shared
records, GPS, camera, navigation, offline restart and update-installation checks
remain to be performed. Collections, structured invoice-field extraction, a shared
bill archive and billing remain future work. See `docs/BILL_SCANNING.md` for the
implemented photo-to-shop matching and delivery preparation flow.

The first Windows build required SDK components and a checksum-verified Gradle
download fallback. The temporary wrapper URL was restored after the build.
Use `scripts/build_test_apk.ps1 -PreloadGradle` if Java's Gradle downloader times out.
The connected rebuild also required moving previous generated build output into
`.tooling/b` after Windows prevented Gradle from clearing existing generated
folders. The backup initially had a longer timestamped name, which caused a
OneDrive path-length error. It was shortened to `b`; at that check, the longest
OneDrive-relative file paths in the backup and build were 365 and 360 characters.
The previous trial APK remains in that backup.
