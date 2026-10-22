-- Send SMS hook: Supabase Auth hands each OTP to this function instead of
-- Twilio, and it asks the "SMS Gateway for Android" cloud
-- (https://api.sms-gate.app, github.com/capcom6/android-sms-gateway) to send
-- it from the gateway phone's own SIM. Test phone numbers never get here,
-- and Auth applies its SMS rate limit (Authentication -> Rate Limits) first.
--
-- Turned on in the dashboard, once:
--   1. Database -> Extensions: pg_net.
--   2. SQL Editor, with the gateway app's Cloud server credentials:
--        select vault.create_secret('<username>', 'sms_gate_username');
--        select vault.create_secret('<password>', 'sms_gate_password');
--   3. Authentication -> Auth Hooks -> Send SMS: Postgres,
--      public.send_sms_via_gateway.
-- pg_net is asynchronous: the request is queued and the hook returns at once,
-- so a gateway failure shows as "no SMS arrived", not as an error in the app
-- (net._http_response keeps the gateway's answers for checking).
create function public.send_sms_via_gateway(event jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  -- sms.phone is where Auth sends the code (the new number on a change).
  v_phone text := ltrim(coalesce(event #>> '{sms,phone}', event #>> '{user,phone}', ''), '+');
  v_otp   text := coalesce(event #>> '{sms,otp}', '');
  v_user  text;
  v_pass  text;
begin
  if v_phone !~ '^[1-9][0-9]{7,14}$' or v_otp !~ '^[0-9]{4,10}$' then
    return jsonb_build_object('error', jsonb_build_object(
      'http_code', 400, 'message', 'bad phone or code'));
  end if;
  select decrypted_secret into v_user from vault.decrypted_secrets where name = 'sms_gate_username';
  select decrypted_secret into v_pass from vault.decrypted_secrets where name = 'sms_gate_password';
  if coalesce(v_user, '') = '' or coalesce(v_pass, '') = '' then
    return jsonb_build_object('error', jsonb_build_object(
      'http_code', 500, 'message', 'SMS gateway credentials are missing from Vault'));
  end if;
  perform net.http_post(
    url := 'https://api.sms-gate.app/3rdparty/v1/message',
    body := jsonb_build_object(
      'textMessage', jsonb_build_object(
        'text', 'رمز دخول دائن: ' || v_otp || E'\n' || 'لا تعطه لأحد.'),
      'phoneNumbers', jsonb_build_array('+' || v_phone)),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Basic ' || replace(
        encode(convert_to(v_user || ':' || v_pass, 'UTF8'), 'base64'), E'\n', '')),
    timeout_milliseconds := 10000);
  return '{}'::jsonb;
end $$;

grant usage on schema public to supabase_auth_admin;
revoke execute on function public.send_sms_via_gateway(jsonb) from public, anon, authenticated, service_role;
grant execute on function public.send_sms_via_gateway(jsonb) to supabase_auth_admin;
