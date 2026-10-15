# Free backend setup

Already set up the initial database? For the owner Excel import and saved Maps
links, run `supabase/migrations/20261014_owner_import.sql` once before using the
updated app. See `docs/OWNER_IMPORT.md`. Do not rerun the initial schema.

To allow deliveries using a saved Google Maps link without coordinates, also run
`supabase/migrations/20261015_maps_link_delivery.sql` in the SQL Editor. This updates
the delivery validation function and keeps existing shops and history. Existing
links become usable immediately; they do not need to be entered again.

1. Create a Supabase account and a new **Free** project in a suitable region. Keep
   the database password private; it never goes into the APK.
2. Run `supabase/schema.sql` once in the SQL editor against this new project. This
   creates app tables and the **private** `shop-photos` bucket.
3. In Authentication → Users, create and confirm individual email/password accounts
   for the two owners. Add the delivery person's account before assigning deliveries.
   These are app logins, not separate Supabase dashboard accounts. Authentication
   identifies each person so the database can enforce their permissions and record
   who made a change. Gmail is not required; another email or a company-managed
   email works. Give each person their own account/password.
4. Run this SQL after replacing the emails with the exact ones you created:

```sql
insert into public.profiles(id, display_name, role)
select id, 'Owner 1', 'owner' from auth.users where email = 'owner1@example.com';
insert into public.profiles(id, display_name, role)
select id, 'Owner 2', 'owner' from auth.users where email = 'owner2@example.com';
select display_name, role from public.profiles;
```

Once you create the delivery person's authentication account, run:

```sql
insert into public.profiles(id, display_name, role)
select id, 'Delivery person', 'driver' from auth.users where email = 'driver@example.com';
select display_name, role from public.profiles;
```

The query must show two owner profiles initially, and three profiles after adding
the delivery person. An insert with zero rows means its email
did not match an authentication user. Roles cannot be changed from the app.

5. Find the project URL and **publishable key** in project API/connection settings.
   A legacy public `anon` key also works. Copy `config/cloud.example.json` to
   `config/cloud.json` and fill these public values.
6. Never put secret/service-role keys or database passwords into the APK. Public
   keys rely on the server policies; running the schema is essential.
7. Build/run with `--dart-define-from-file=config/cloud.json`. Install that same
   configured APK on the owners' phones and sign in separately. For the prepared
   Windows build script, use:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build_test_apk.ps1 -Shared -PreloadGradle
```

The test APK is `build/app/outputs/flutter-apk/app-debug.apk`. It should open to
email/password sign-in. Sign in as Owner 1 and add a shop while online, then check
Supabase Table Editor → `shops` for the saved record. Sign in as Owner 2 on the
second phone and refresh to confirm both owners see the same shop. A delivery
account is not needed for this directory check; add it before testing assignments.

## Verify before live use

- Owner 1 adds a verified shop; Owner 2 sees it after sync.
- Owner 2 assigns it to the driver; the driver sees it after sync.
- Driver cannot create/edit shops, assign stops or read unassigned shops/photos.
  Check these restrictions through direct API calls as well as the UI.
- After downloading a route, turn off the driver's internet. Save a visit result,
  restart the app, restore internet and sync. Owners see one event, not duplicates.
- Two edits based on the same shop version must reject the outdated edit.
- A retry using the same visit operation ID returns the original result without
  increasing the version again, even if the first response was lost.

Photos are cached for offline use. Failed photo downloads do not block route sync.
The directory and route records are paginated so the API row limit does not truncate
600+ shops. Pagination is not a transaction-wide snapshot; rerun sync if assignments
change during a download. Add incremental/date-window sync as history grows.

Conflicting visit results remain queued. An owner should review them before using
Account → Resolve a sync conflict. That action discards queued results only after
fetching server records. Normal refresh never discards them.

Trial records are separate from cloud records. Seed your shared directory by
recording verified shop entrances during normal visits. Old balances and invoices
are not imported in this location milestone.

Free resources have storage/traffic limits and inactivity pausing. Establish an
independent database and photo backup/export process before live use. Official docs:

- https://supabase.com/pricing
- https://supabase.com/docs/guides/database/secure-data
- https://supabase.com/docs/guides/platform/free-project-pausing
