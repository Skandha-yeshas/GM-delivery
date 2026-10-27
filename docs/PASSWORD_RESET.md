# Reset an existing app user's password

`has_password = true` in the diagnostic SQL only means that a password exists. It
does not check the password typed into the app. Use the existing authentication
account so its UUID and `public.profiles` owner role stay intact.

The current app has no password-recovery screen/deep-link handler. Sending a reset
email alone therefore does not provide a complete in-app password-reset flow.
For this setup, use the local administrator helper instead:

1. In the same Supabase project used by `config/cloud.json`, open Authentication
   > Users and copy the existing owner's User UID.
2. Open Settings > API Keys and copy a **secret key** (`sb_secret_...`). A legacy
   `service_role` JWT also works. Keep this administrator credential private.
3. In your own PowerShell terminal at the project root, run:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/reset_app_password.ps1
   ```

4. Enter the User UID, then paste the secret key at the hidden prompt. The
   helper fetches and displays the existing account email. Type that email to
   select it, then enter the new password twice at hidden prompts.
5. After **Password updated**, sign in to the Android app using the displayed email
   and the new password. No APK rebuild is needed for this account-only change.

The helper sends a password-only update to the supported Supabase Auth admin API
over HTTPS. It does not create/delete users, change email confirmation, update
roles or touch delivery data. Secrets are entered interactively, are not passed
as command-line arguments and are not written to project files. Never paste the
secret/service_role key or passwords into chat, `config/cloud.json` or app code. Do not
run this helper under a terminal recorder/transcript that captures your input.

If the API returns a password-policy error, use a password meeting the project's
configured requirements. A timeout can leave the outcome uncertain; check sign-in
with the new password before repeating. If email confirmation was false, complete
confirmation separately; the helper does not bypass it.

## HTTP 401 during reset

The helper explicitly identifies itself as `GM-Delivery-Local-Admin/1.0`.
PowerShell's default User-Agent resembles a browser, while Supabase rejects secret
keys in browser requests based on that header. The original helper relied on the
default header; this was a possible cause of the reported 401, not a confirmed
diagnosis of the user's key. Rerun the updated helper first.

If 401 remains, copy a complete, active secret/service_role key from **the project
printed by the helper**. A key from the deleted project, a public publishable key
or a legacy anon key cannot authorize an admin password reset. Legacy JWTs are
now checked locally for service_role, the expected project reference and expiry;
Supabase still verifies their signatures. Opaque secret keys can only be checked
by the server. No secret-key value is printed or requested in chat.

Errors now identify **Account lookup** versus **Password update**, and give
separate guidance for 401/403, a missing user, password validation, rate limits and
uncertain network outcomes. A failed account lookup never sends a password update.

Reference: [Supabase admin password update](https://supabase.com/docs/reference/javascript/auth-admin-updateuserbyid)
and the [Auth REST specification](https://github.com/supabase/auth/blob/master/openapi.yaml).
See also [Supabase secret-key restrictions](https://supabase.com/docs/guides/getting-started/api-keys)
and [PowerShell User-Agent defaults](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-restmethod?view=powershell-5.1).

The script's syntax and 16 mock workflows are checked locally, including explicit
non-browser headers, both admin-key formats, 401/403/404/422 responses, rejection
of wrong-project/anon/expired/malformed keys, password-only payloads, cancellation
and private-output redaction. Run `scripts/tests/reset_app_password_test.ps1`.
No live password
was changed by Codex; the administrator must run the interactive helper privately.
