# Driver shop search

The driver's **Shops** tab follows the supplied directory design: a sticky search
area, filter chips, live result counts, a navy information banner, contact/address
cards and Call shop / View on map actions. Delivery accounts still open on the
Deliveries tab. Owners keep their existing All Shops directory.

The user selected **assigned shops only**. Home derives the visible shop IDs from
the signed-in driver's assignments and filters the downloaded directory against
those IDs. Assignments from earlier dates remain searchable, consistent with the
existing Supabase shop-read policy. The Today’s stops filter includes only shops
assigned to this driver on today's date. Unassigned shops and another driver's
shops are excluded. No new database migration or expanded permission is needed.

Search matches case-insensitive words across shop name, contact, area, address,
phone, PIN, landmark and instructions. Phone searches also ignore spaces, hyphens
and similar formatting. Search, area and category filters combine. Filter-chip
counts describe the available assigned directory; the live result count reflects
the current combination. Reset restores the full assigned list. Sorting toggles
A–Z/Z–A without touching delivery order. The query is retained when switching
between Shops and Deliveries.

View on map opens a dismissible sheet with the selected shop's saved location
status, address, landmark, instructions and contact. Open in Google Maps uses the
actual saved Maps link or verified entrance directions. Maps-only links work
without coordinates. Missing/unverified locations show an owner-update message
and disable external navigation. Calls use the saved phone and are disabled when
no number is present. No sample map image or coordinate-entry form is displayed.

The design's registration, unassigned-hub, carton staging and GPS distance labels
are omitted because they are not supported by this driver's permissions/data.
The filters instead use real assignments, saved location readiness and areas.
The header can scroll within a shortened keyboard viewport; cards are built
lazily so the list remains usable with hundreds of records.

## Checks

Run `scripts/verify.ps1`, then `scripts/verify.ps1 -Preview` sequentially. Tests
cover search/phone formatting, combined filters/reset, actual Maps-only targets,
missing phone/location, a dismissible location sheet, 606-record lazy rendering,
320-pixel enlarged text with keyboard insets, driver access filtering and retained
search/unchanged route order when switching tabs. The gallery includes the main
search, a contact-name result and the saved-location sheet.

On Android, sync with the owner and driver accounts, then search a known assigned
shop by name/contact/phone/address. Confirm calls and Maps open the right shop,
and an unassigned shop is absent. Search downloaded records offline and check that
changing filters does not change the driver's delivery sequence. Actual Maps and
dialler launches still require device verification; automated callbacks use
controlled targets.
