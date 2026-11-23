-- GitHub・Google でログイン: Supabase のログイン(auth.users)と、財布番のアカウント(owners)を結びつける
create table if not exists public.owner_identities (
  auth_user uuid primary key,
  owner_id uuid not null references public.owners(id) on delete cascade,
  provider text not null,
  email text,
  created_at timestamptz not null default now(),
  last_login_at timestamptz
);
create index if not exists owner_identities_owner_idx on public.owner_identities(owner_id);
alter table public.owner_identities enable row level security;
revoke all on public.owner_identities from anon, authenticated;

-- 画面の設定に出す: このアカウントにつながっているログイン方法
CREATE OR REPLACE FUNCTION public.app_identities(p_owner_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o owners;
begin
  o := app_owner(p_owner_key);
  if o.id is null then return jsonb_build_object('error','invalid_owner_key'); end if;
  return jsonb_build_object('identities', coalesce((select jsonb_agg(jsonb_build_object('provider', provider,
    'email', case when email is null then null else left(email, 2) || '…' || substring(email from position('@' in email)) end) order by created_at)
    from owner_identities where owner_id = o.id), '[]'::jsonb));
end $function$;
revoke all on function public.app_identities(text) from public, anon, authenticated;
grant execute on function public.app_identities(text) to service_role;
