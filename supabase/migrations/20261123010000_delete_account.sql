-- 設定の「アカウントを削除」: 持ち主が自分のアカウントと関係するものを全部消す
-- (AI・予算・履歴・預かったAPIキー(保管庫の中身ごと)・通知の登録・パスキー・GitHub/Googleのつながりとログイン情報)
CREATE OR REPLACE FUNCTION public.app_delete_account(p_owner_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'vault', 'auth'
AS $function$
declare o owners; n_agents int; n_keys int; n_auth int;
begin
  o := app_owner(p_owner_key);
  if o.id is null then return jsonb_build_object('error','invalid_owner_key'); end if;
  delete from vault.secrets where id in (select secret_id from owner_provider_keys where owner_id = o.id and secret_id is not null);
  delete from owner_provider_keys where owner_id = o.id;
  get diagnostics n_keys = row_count;
  delete from auth.users where id in (select auth_user from owner_identities where owner_id = o.id);
  get diagnostics n_auth = row_count;
  delete from agents where owner_id = o.id;
  get diagnostics n_agents = row_count;
  delete from push_subs where owner_id = o.id;
  delete from owners where id = o.id;
  return jsonb_build_object('ok', true, 'agents', n_agents, 'keys', n_keys, 'logins', n_auth);
end $function$;
revoke all on function public.app_delete_account(text) from public, anon, authenticated;
grant execute on function public.app_delete_account(text) to service_role;
