# Add and edit shops

The two Flutter forms follow the supplied HTML reference: Plus Jakarta Sans,
navy actions, light card fields, grouped identity/contact and location sections,
and a fixed Cancel/Save bar. Editing prefills the same form and preserves the
shop ID, notes, photo and location unless the owner changes them. Saving adds
to the directory; delivery-list assignment remains a separate explicit action.

The manual Add/Edit form requires every marked field: shop name, proprietor/contact
person, 10-digit Indian mobile number, street address and a valid six-digit Indian
PIN. The mobile field has a fixed +91 prefix and saves the number with its country
code. Area, landmark, instructions, photo and location are optional when saving a
directory entry. A ready location is needed before delivery assignment.

Name/Location Excel imports still accept incomplete profiles and keep existing
shops intact. When manually editing an incomplete imported shop, the owner must
complete the required fields before saving. Search and details include contact/PIN.

## Shared database update

After the previous dated migrations, run
`supabase/migrations/20261020_shop_profiles.sql` in Supabase SQL Editor.
It adds `contact_name` and `postal_code` to shops and extends the existing owner-only,
versioned save RPC. Existing shop RLS and `shop_history` cover both fields.
Migration retry is safe. Requests from older APKs that omit the fields preserve
their stored values. An empty string from the new form intentionally clears one.
The new app checks server support before saving or starting an Excel import.

SQLite upgrades to v5 without deleting shops, delivery stops or queued operations.
The two-column Excel template stays Name/Location. Optional import columns
include Contact person / Proprietor / Contact name and PIN code / Postal code.

## Location choices

- Paste a Google Maps shop or dropped-pin link. This remains ready for delivery
  without extracting coordinates or ticking the entrance confirmation box.
- For a shop without a Maps listing, use **Shop not listed on Google Maps**
  (enabled for new shops) and tap **Detect live GPS & auto-fill address** at the entrance.
- The app displays the actual returned accuracy, then attempts reverse address
  lookup. Only empty address, area and PIN fields are filled. Existing text and
  edits made while lookup is running are retained.
- If address lookup is unavailable or times out, the GPS fix remains available;
  enter the address manually. Denied permission or disabled location services
  produce a real error and never display a simulated successful capture.
- Open the actual pin in Google Maps and confirm the entrance. Coordinate-only
  locations become ready only after confirmation. A generated coordinate link can
  be copied without a registered business listing. No embedded map, geofence or
  automatic doorstep verification is claimed.
- Capturing a replacement entrance clears the old pasted Maps link after a
  successful GPS fix so navigation uses the new pin. Cancel leaves the saved shop
  unchanged. A failed fix leaves the existing location intact.
- Manual latitude/longitude fields and raw coordinate displays have been removed.
  GPS coordinates remain stored internally for verification and navigation.
  The navigation card copies the real Maps link; the pin panel opens Google Maps.
  This form update needs no additional database migration beyond the profile one above.

Reverse lookup uses the [native geocoding plugin](https://pub.dev/packages/geocoding),
which uses platform geocoding services and does not require a paid Maps API key.
Availability and platform limits still apply. The font comes from
[Google Fonts](https://github.com/google/fonts/tree/main/ofl/plusjakartasans);
its OFL license is included in `assets/fonts/OFL.txt` and the APK.

The HTML's placeholder profile photos, simulated GPS, hardcoded accuracy/address
and success timers are replaced by the app's real data and save workflow.

## Review and checks

Open `preview/index.html` for Add shop, Edit shop and Shop location captures.
Use the updated APK in Android Studio for the interactive form.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify_maps_sql.ps1 -TestFile supabase/tests/shop_profiles.sql
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify.ps1 -Preview
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build_test_apk.ps1 -Shared -PreloadGradle
```

On real Android devices, check:

1. Apply the migration, sign in as owner, add and edit all contact/address fields,
   then confirm the other owner receives them after sync.
2. Edit an imported Maps-only shop. Confirm blank required fields block saving;
   complete them and check its original Maps link and delivery readiness are retained.
3. At an unlisted shop entrance, capture GPS, compare the reported accuracy and
   address with the surroundings, open Maps and explicitly confirm the pin.
4. Repeat with GPS denied, GPS disabled, poor reception and no address service.
   Confirm no fake address/verification appears and a successful GPS fix is kept
   when address lookup fails. Type an address during lookup and confirm it survives.
5. Edit an existing entrance, cancel, and confirm the saved record is unchanged.
   Then save and check the delivery person's navigation uses the updated location.
6. Try a stale edit from the other owner's phone. Confirm the version conflict
   requires review rather than overwriting newer data.
7. Install over the previous APK without clearing data. Check cached records and
   pending money/visit requests, the keyboard, 320-pixel width and large text.

The migration is prepared and locally tested; it has not been applied to the live
Supabase project by the agent. Native GPS/address quality requires device checks.
