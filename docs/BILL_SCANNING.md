# Prepare deliveries by scanning bills

The owner opens **Assign Delivery → Scan Next Bill** for a selected date.
Tap **Scan whole bill** and photograph one printed
English bill, including its **Bill To / customer** section. **Choose a photo** also
reads an existing image, which is useful in an Android Studio emulator.

The app reads the photo on the Android device with ML Kit's bundled Latin
recognizer and extracts only a customer **Shop name** field. The full OCR text,
item lines, totals, tax IDs and bill address are not displayed in the name field.
Buyer/customer labels are preferred and the G.M. Enterprises supplier heading is
excluded. The name stays editable. If more than one plausible name is detected,
the owner can choose a name chip. Matching runs in a background isolate against
the downloaded directory, including directories with 600+ shops.

A unique exact name match opens a **Matched with Registered Shop** card showing
the saved address, contact and location status. Similar names and same-name
branches remain separate choices. Review the
shop and entrance, optionally preview its pin in Google Maps, choose the delivery
person and tap **Confirm Dispatch**. An assignment is never made merely
by scanning. **Scan Next Bill** continues the same date and delivery person; **View
delivery list** returns to the owner's list. Maps-link delivery requires the
database update described below for existing Supabase projects.

When the shop is missing, tap **Add new shop** directly in the scan result. The
shop form opens with the detected name filled in. Name, contact person, mobile,
street address and PIN are required; area, landmark, notes and photo are optional.
A missing area is saved as **Area not set**. Use **Save & Add to Directory** in the
fixed footer to return to the same scan/delivery flow. The new shop is selected, and any missing
location can be supplied as a Maps link or verified entrance coordinates. Cancelling the shop form leaves
the scanned name available.

**Direct Live GPS Pin** opens that same form and starts real GPS capture. Use it
at the shop entrance, review the address/contact fields and explicitly confirm the
pin. Capture alone saves neither a new shop nor an assignment. Cancel discards
the unsaved form. No driver notification is sent by capturing GPS.

The supplied dispatch design is implemented in Flutter; see
`docs/DISPATCH_DESIGN.md`. Scanning still extracts only the shop name. Carton
counts, bill numbers/amounts and addresses are not inferred or shown as OCR output.

## When the bill or shop is unclear

- Take a sharp, straight, well-lit photo. Show the customer name rather than only
  the seller heading or the item table. Handwriting and poor images need manual
  review; this version's model reads printed Latin/English text.
- Correct the single **Shop name** field to search again. The full bill text is
  intentionally kept out of this flow. **View captured photo** lets you check the
  original image if needed.
- Same-name branches remain separate choices. Confirm the actual customer and
  entrance rather than relying on the first suggestion.
- If no shop matches, use **Add new shop** in the result. You can also import a
  directory separately using Excel.
- A saved Google Maps link counts as a delivery location, including short share
  links and links whose GPS cannot be extracted. The result shows **Ready for
  delivery** and **View location in Maps**; it does not show a missing-location
  warning. Without a link, a captured GPS pin needs entrance verification.
  The shop form has no manual latitude/longitude inputs. A written address alone
  is not automatically geocoded.
- Existing Supabase projects need
  `supabase/migrations/20261015_maps_link_delivery.sql` after the owner-import
  migration to enable Maps-link deliveries on the server. Do not rerun the schema.
- If no delivery account exists yet, scanning and GPS lookup still work; creating
  the delivery assignment requires a delivery account.
- A shop already assigned on that date cannot be added again, including another
  bill for the same shop. The shared database enforces one shop stop per date.

## Storage and connection

OCR runs on the device. The app does not upload the bill photo to an OCR service
or attach it to the shared delivery record. This step identifies the destination;
invoice amounts, collections and a shared bill archive remain separate work.

One unconfirmed bill photo is copied to the signed-in account's private app
folder. Reopening the scanner re-reads this draft. If Android restarts the app
while the camera/gallery is open, reopen the scanner to recover the pending
photo. OCR corrections and the selected customer are reviewed again on resume.
After successful assignment, the draft marker and temporary photo are cleared.
This single draft is replaced when another photo is read.

Downloaded shops and saved Maps links can be viewed offline; opening Maps may need
a connection. Shared assignments require internet and retain owner checks,
coordinate verification when no Maps link is saved, and duplicate protection. An unsuccessful assignment keeps the bill
draft available for review and retry.

## Emulator check

1. Add a test shop with its real name and Google Maps share link. Alternatively,
   capture and verify its entrance location.
2. Drag a photo of a matching bill onto the emulator; it goes into Downloads.
3. In the scanner choose **Choose a photo** and select the image (use Browse /
   Files in the Android picker if needed).
4. Confirm that only the shop name appears and the saved location is ready. A
   link-only shop must not show **Needs location** or require coordinates. Confirming
   creates one stop for the selected date and driver.
5. Try an unknown customer: **Add new shop** should prefill the name and return
   to this flow after saving. A missing-location shop or duplicate bill should
   block an assignment until the relevant issue is resolved.

Automated tests use controlled OCR output to check matching, confirmation,
assignment, missing locations and Android lost-image recovery. Actual camera
capture and OCR accuracy still need testing on real bill photographs in Android.

References:
- https://developers.google.com/ml-kit/vision/text-recognition/v2/android
- https://pub.dev/packages/google_mlkit_text_recognition
