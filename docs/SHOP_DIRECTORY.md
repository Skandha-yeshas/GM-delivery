# Shop directory design

The Flutter shop directory follows the supplied 22 October HTML reference:
Plus Jakarta Sans, a navy brand header, pale background, rounded search bar,
horizontal letter chips, registered count, alphabetical section dividers,
white contact/address cards and a navy Add shop action. Records and counts come
from the controller's saved directory; the HTML's example people, photos and
28-shop count are not inserted into the app.

- Search matches name, contact, phone, address, area, landmark and PIN. Clear
  search resets only the query. Letter, area and location filters combine.
- All, A–D, E–K, L–R and S–Z filter the actual names. Non-Latin and numeric
  initials appear together under # when All is selected. Empty groups are omitted.
- Sorted toggles ascending/descending names and group order. Registered remains
  the total number of accessible shops; the shown count follows all filters.
- Tapping a card opens the existing details/edit/ledger flow. The call icon and
  phone number open the saved shop's number in the phone dialler. Missing phone
  numbers show an unavailable action rather than a made-up contact.
- Maps links still count as ready without extracted GPS. Location status remains
  visible, and the area/location filters and Import Excel action are retained.
- Owner navigation contains All Shops and Assign Delivery; All Shops opens first.
  Settlements and outstanding balances are in the account sheet. The account avatar
  uses the signed-in name's initial; sign-out appears for authenticated sessions.
  Pull to refresh and the connection/unsent-operation banner remain available.
- A lazy list builds visible cards for large directories, including 600+ shops.
  New/edit shop requirements, storage, RLS and financial operations are unchanged.

No database migration or new package is required for this design. Run
`scripts/verify.ps1` and `scripts/verify.ps1 -Preview` for automated checks and
phone captures. Open `preview/index.html` and select Shop directory or the
A–D filter example. The pictures use illustrative in-memory records; use the APK
in Android Studio for interaction. Phone dialler behavior needs an Android check.
