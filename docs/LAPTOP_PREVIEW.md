# View the phone output on a laptop

## See the screens immediately

Open `preview/index.html` in Chrome or Edge. It displays the real Flutter screens
at the 390 × 844 phone aspect ratio. Use the screen selector to switch views.
These are static captures with illustrative data, not an interactive Android emulator.

The updated viewer includes the shop directory, whole-bill scan, shop-name result,
missing-shop addition and Maps-link-only location screens. These use the actual Flutter widgets and theme;
sample directory and OCR output are used only for the screenshots.

The collections milestone also includes illustrative **Collection entry**, **Shop
credit ledger** and **Outstanding balances** captures. These never seed phone data.

The settlement milestone adds **Driver cash settlement** and **Owner settlement
review** captures. Use the receipt icon in the actual app to open daily settlements.

**Add shop**, **Edit shop**, **Shop location & address** and **Delivery entrance &
navigation** show the new shop-form design using real Flutter widgets and
illustrative shop/GPS data. Marked fields are required; GPS and Maps links replace
manual latitude/longitude entry.

**Shop directory** uses the new navy/white contact-card design with alphabetic
groups; **Directory · A–D filter** shows a working letter filter with real Flutter
widgets and illustrative records. Owner navigation has All Shops and Assign Delivery;
settlements and outstanding balances are under the account avatar.

The viewer opens **Driver · shop search**. **Driver · search by contact** shows a
filtered result; **Driver · saved shop location** shows its location sheet.
**Driver · assigned route** shows real progress and the owner's sequence.
**Driver · shop & delivery actions** shows contact, navigation
and collection controls. Owner accounts in the Android app still open All Shops.
**Assign Delivery** shows the route-planning
controls and numbered stops. **Delivery order · drag & save** shows a reordered
draft and its fixed save/reset bar. **Matched shop · Confirm Dispatch** shows the
driver selection and real confirmation action; **Add missing shop** shows the
new-shop/GPS choices. All use actual Flutter widgets with controlled sample data.

You can also open the viewer from the project terminal:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/open_preview.ps1
```

Regenerate them after changing screens:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify.ps1 -Preview
```

Capture data is stored only in an in-memory test database. Normal test runs do not
generate these artifacts, and production app records are never seeded with samples.

## Tap through the actual Android app

1. Install Android Studio with Android Emulator.
2. On its welcome screen, choose **More Actions → Virtual Device Manager**.
   With a project open, use **View → Tool Windows → Device Manager**.
3. Choose **Create Device**, pick a Pixel phone in portrait orientation, and select
   an Android system image with API 24 or above. Android 16 / API 36 with Google
   Play and x86_64 is a suitable choice on this Windows laptop. A Google Play image
   is useful for testing Google Maps navigation. Download the image if needed,
   then finish setup. If Android Studio's initial SDK download is still running,
   let that installation finish first.
4. Start the virtual phone with its Play/Launch button.
5. Drag `build/app/outputs/flutter-apk/app-debug.apk` onto the emulator window.
6. Open **G.M. Delivery** in the emulator's app launcher.

The current APK was built with `config/cloud.json` and starts with email/password
sign-in. Use an owner account you created in Supabase. The emulator can access the
shared shop directory while online; preview samples do not appear in it. Add a shop
to test the actual application and check the saved row in Supabase's `shops` table.
A build without cloud configuration starts in device-only trial mode instead.
Camera and location behavior also need validation on a physical phone.

## OneDrive path-length popup

The project is under the OneDrive-backed Desktop. Android generates deeply nested
build files, so long backup folder names can exceed OneDrive's sync path limit.
This message comes from OneDrive rather than the app or emulator. The old build
backup was shortened to `.tooling/b` to resolve the reported path; the current
APK remains at `build/app/outputs/flutter-apk/app-debug.apk`. Click **Try again**
in the OneDrive popup after the rename.

For ongoing development, use a short project folder outside OneDrive, such as
`C:\dev\GM_Enterprises`, and back up source code separately. Git's `.gitignore`
does not control OneDrive sync. If relocating the project, update the workspace
Android SDK path in `android/local.properties`; it points inside this project.

Microsoft's explanation:
https://support.microsoft.com/en-us/onedrive/what-are-file-path-length-limits

Official instructions:

- https://developer.android.com/studio/run/managing-avds
- https://developer.android.com/studio/run/emulator-install-add-files
