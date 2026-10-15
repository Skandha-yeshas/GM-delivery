# Import the owner's shop directory

For an existing Supabase project, run the entire file
`supabase/migrations/20261014_owner_import.sql` in SQL Editor first. It adds the
saved Maps link column and updates the owner save function. Do not run the full
initial `schema.sql` again. New projects can use the updated initial schema.
The local phone database upgrades automatically, preserving existing records.

Use the new APK after applying the SQL. The older APK does not contain these
owner features. This database update also preserves a saved Maps link when an
older APK edits other shop fields.

## Excel file

Start with `docs/templates/GM_Shops_Template.xlsx`, or tap **Shops → Import Excel →
Save template** inside the app. Save the workbook as `.xlsx`, not legacy `.xls`.

| Name | Location |
| --- | --- |
| Example stationery shop | Google Maps share link or written address |
| Another example shop | Leave blank if unknown |

Only **Name** is required in each row. Location may be blank. Missing areas are
saved as **Area not set**, so you can fill them in later. Optional extra columns:
**Area**, **Address**, **Phone**, **Landmark**, **Delivery instructions**,
**Latitude**, **Longitude**. Use plain text for phone numbers to preserve leading
zeros and country prefixes. Paste the actual Maps URL as text, rather than a
labelled hyperlink or a HYPERLINK formula.

1. In the emulator, drag the Excel file from Windows onto the virtual phone.
   It is copied to the emulator's Download folder.
2. Sign in as an owner. Open **Shops → Import Excel → Choose Excel file**.
3. Choose the file in Downloads. Select a worksheet if it has more than one.
4. Review the new shops, possible duplicates, invalid rows and missing locations.
5. Tap **Import … new shops**. Shared imports require internet; progress appears
   as each row is processed. Keep the app open until the result appears.

The import supports up to 5 MB and 5,000 nonempty rows in a worksheet, including
a directory of 600+ shops. It does not edit existing shops or automatically mark
imported locations verified. Rows with invalid data are reported by Excel row
number. Correct the workbook and retry after resolving an error. A connection or
server failure stops further writes, while previously successful rows stay saved.

Possible duplicates match the normalized **Name + Area + Address**. Repeated
rows and known matches are skipped; existing owner notes, locations, photos and
delivery records are preserved. With only Name and Location, two shops with the
same name and no distinguishing area/address are treated as possible duplicates.
Give separate branches an Area/Address before importing, or add them manually.
Different spellings are not fuzzy-matched. Stable import IDs prevent the same
rows being inserted twice on retry or by simultaneous owner imports.

## Google Maps and missing shop locations

On **Add shop / Edit shop**, paste a Google Maps HTTPS share link and save. The
link alone is a delivery location: no coordinate entry, pin extraction or entrance
verification is required for link-based delivery. Navigation opens that saved
link in Maps. Use the actual shop or dropped-pin share link. No paid API key is needed.

Short links in an Excel import are saved without hundreds of network lookups and
are immediately ready for delivery. **Read pin from link** remains optional: long
links containing a pin are parsed on the phone; short links are resolved online
when possible. Failure to extract GPS does not block a saved Maps link. A map's
camera position or a written address is never converted into entrance coordinates.

Existing Supabase projects must run
`supabase/migrations/20261015_maps_link_delivery.sql` after the earlier
`20261014_owner_import.sql` migration. This permits link-based deliveries without
rewriting existing shops. Do not rerun `schema.sql` on an existing project.

If Google does not list the shop:

1. Use **Search Google Maps** to find its street or landmark.
2. Long-press the actual shop entrance to drop a pin, then share/copy that pin's
   link and paste it into the shop form. A Google business listing is unnecessary.
3. If the entrance is still unknown, save the address, landmark, contact and
   optional entrance photo now. During a visit, an owner can use **Capture current
   location** at the entrance.
4. A pasted Maps link is ready when saved. If using captured coordinates without
   a link, preview the pin, confirm the delivery entrance and save. Manual numeric
   entry is available under **Coordinates (optional)**.

The directory filter distinguishes **Needs location**, **Needs verification**
and **Ready for delivery**. A valid saved Maps link or owner-verified coordinates
can be assigned to a delivery list. Changing a link clears old coordinates to
avoid retaining a previous pin; the replacement Maps link is still ready.
An approximate nearby landmark should be recorded as a landmark, not verified
as the shop entrance.

## Check before importing the live directory

- Try a few rows containing a full Maps link, a short link and a blank location.
- Confirm both owners see the imported shops after sync.
- Retry the file: existing records should be skipped without edits.
- Confirm a link-only shop can be assigned and opens its saved Maps link.
- Confirm a shop with no Maps link and no verified coordinates cannot be assigned.

The Excel parser and 600-row local import are tested automatically. Live Supabase
roles, the SQL migration, the Android picker and live short-link redirects also
need checks in the emulator/project before the real directory is imported.
