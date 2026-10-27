-- Run in the SQL Editor of the project used by config/cloud.json / your APK.
-- Read-only: no account, password, role or delivery records are changed.
-- Passwords and password hashes are NOT returned.
select
  u.id as user_id,
  u.email,
  u.email_confirmed_at is not null as email_confirmed,
  coalesce(length(u.encrypted_password), 0) > 0 as has_password,
  p.display_name,
  p.role
from auth.users u
left join public.profiles p on p.id = u.id
order by u.created_at;
