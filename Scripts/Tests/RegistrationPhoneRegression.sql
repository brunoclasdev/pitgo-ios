-- Rollback-only integration checks. Apply the phone migration before running.
begin;
do $test$
declare fixture record; uid uuid; doc text; metadata jsonb; stored_phone text; bad_phone text;
 cpfs text[] := array['01230956468','00134224990','25038019862','78331568680','12619426634','37350307853','90235617407','38060157914','03197340728','84595548052','67318944789','57508768531'];
 cnpjs text[] := array['15351054767810','77662393996806','56258251943356','08985210015543','74425779740674','78274657326757','29848457152587','05455419483284','31754221410409','37156529209415','71137283329532','75763746368269'];
begin
 for fixture in select * from (values
  ('CLIENT', 'cpf', '+5511987654321'),
  ('CLIENT', 'cpf', '+12025550123'),
  ('CLIENT', 'cnpj', '+351912345678'),
  ('PROVIDER', 'cnpj', '+5511987654321'),
  ('CLIENT', 'cpf', '11987654321')
 ) as v(mode,kind,phone) loop
  select d into doc from unnest(case when fixture.kind='cpf' then cpfs else cnpjs end) d
  where not exists(select 1 from private.registration_identities i where i.cpf=d or i.cnpj=d)
    and not exists(select 1 from public.profiles p where p.cpf=d or p.cnpj=d)
  limit 1;
  if doc is null then raise exception 'No unused synthetic document fixture'; end if;
  uid := gen_random_uuid();
  metadata := jsonb_build_object('account_type',fixture.mode,'first_name','Regression','last_name','Phone',
    'phone',fixture.phone,fixture.kind,doc);
  insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data)
  values(uid,'authenticated','authenticated','phone-regression-'||uid||'@example.invalid',
    '{"provider":"email","providers":["email"]}'::jsonb,metadata);
  select phone into stored_phone from private.registration_identities where user_id=uid;
  if stored_phone is distinct from fixture.phone then raise exception 'Signup did not preserve phone'; end if;
  if not exists(select 1 from private.registration_cases where user_id=uid and account_type=fixture.mode) then
   raise exception 'Signup did not create registration case'; end if;
  if fixture.mode='CLIENT' then
   select phone into stored_phone from public.profiles where id=uid;
   if stored_phone is distinct from fixture.phone then raise exception 'Client profile phone mismatch'; end if;
  end if;
 end loop;
 foreach bad_phone in array array['+55','+0123456789','+5511 invalid','5511987654321','',null] loop
  if coalesce(private.is_valid_registration_phone(bad_phone),false) then
   raise exception 'Malformed phone accepted';
  end if;
 end loop;
 -- Exercise the actual Auth trigger rejection, with otherwise valid metadata.
 metadata := jsonb_set(metadata,'{phone}','"+55"'::jsonb);
 begin
  uid:=gen_random_uuid();
  insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data)
  values(uid,'authenticated','authenticated','phone-invalid-'||uid||'@example.invalid',
    '{"provider":"email","providers":["email"]}'::jsonb,metadata);
  raise exception 'Invalid signup unexpectedly succeeded';
 exception when invalid_parameter_value then
  if sqlerrm <> 'INVALID_REGISTRATION' then raise; end if;
 end;
end $test$;
select 'PASS: client CPF/CNPJ, provider CNPJ, international and legacy phone, invalid phone rejection; all test accounts rolled back' as result;
rollback;
