-- Run in one database session with pitgo.test_appointment_id set to an unpaid,
-- unexpired Guincho test appointment. All reservations below are rolled back;
-- no Edge Function or external payment provider is called.
begin;
create temporary table guincho_payment_regression_result (result text);
do $$
declare a public.appointments%rowtype; reservation jsonb; repeated jsonb;
 commercial_amount numeric; actual_amount numeric; payment_count integer;
begin
 select * into a from public.appointments
 where id=current_setting('pitgo.test_appointment_id')::uuid and status='AWAITING_PAYMENT' for update;
 if a.id is null or a.quote_expires_at<=now() then raise exception 'An unpaid, unexpired test appointment is required'; end if;
 if exists(select 1 from public.payments where request_id=a.dispatch_search_id) then
  raise exception 'Test appointment already has a payment; do not modify it';
 end if;
 commercial_amount:=a.customer_total_amount;

 -- A real expired deadline must still reject payment.
 begin
  update public.appointments set quote_expires_at=now()-interval '1 second' where id=a.id;
  perform public.reserve_order_payment(a.client_id,a.dispatch_search_id,'GUINCHO_DIRECT',a.service_id,a.id,a.quote_version,'PIX',null,commercial_amount,true);
  raise exception 'Expired appointment incorrectly accepted';
 exception when sqlstate '22023' then
  if sqlerrm<>'QUOTE_EXPIRED' then raise; end if;
 end;
 insert into guincho_payment_regression_result values ('PASS: genuinely expired appointment is rejected');

 -- A stale quote version must not reserve a charge.
 begin
  perform public.reserve_homol_order_payment(a.client_id,a.dispatch_search_id,'GUINCHO_DIRECT',a.service_id,a.id,a.quote_version+1,'PIX',null,1.23,true);
  raise exception 'Wrong quote version incorrectly accepted';
 exception when sqlstate '22023' then
  if sqlerrm<>'INVALID_PAYMENT_CONTEXT' then raise; end if;
 end;
 insert into guincho_payment_regression_result values ('PASS: wrong quote version is rejected');

 -- After acceptance, the appointment's deadline supersedes the original quote.
 -- Production still charges the commercial amount; this nested subtransaction
 -- rolls its reservation and edited quote timestamp back before testing Homol.
 begin
  update public.guincho_quotes set expires_at=now()-interval '1 second' where id=a.guincho_quote_id;
  reservation:=public.reserve_order_payment(a.client_id,a.dispatch_search_id,'GUINCHO_DIRECT',a.service_id,a.id,a.quote_version,'PIX',null,commercial_amount,true);
  if (reservation->'payment'->>'amount')::numeric is distinct from commercial_amount then
   raise exception 'Production payment changed the commercial amount';
  end if;
  raise exception using errcode='PZ001',message='ROLLBACK_PROD_CASE';
 exception when sqlstate 'PZ001' then null;
 end;
 insert into guincho_payment_regression_result values ('PASS: accepted payment deadline is honored and Prod preserves commercial amount');

 reservation:=public.reserve_homol_order_payment(a.client_id,a.dispatch_search_id,'GUINCHO_DIRECT',a.service_id,a.id,a.quote_version,'PIX',null,1.23,true);
 if (reservation->>'created')::boolean is not true
 or (reservation->'payment'->>'amount')::numeric<>1.23
 or reservation->'payment'->>'checkout_environment'<>'homol' then raise exception 'Incorrect Homol reservation'; end if;
 select customer_total_amount,payment_amount into commercial_amount,actual_amount from public.appointments where id=a.id;
 if commercial_amount is distinct from a.customer_total_amount or actual_amount<>1.23 then
  raise exception 'Commercial quote was changed or checkout amount was lost';
 end if;
 insert into guincho_payment_regression_result values ('PASS: Homol Pix reserves 1.23 and preserves the commercial quote');

 repeated:=public.reserve_homol_order_payment(a.client_id,a.dispatch_search_id,'GUINCHO_DIRECT',a.service_id,a.id,a.quote_version,'PIX',null,1.89,true);
 select count(*) into payment_count from public.payments where request_id=a.dispatch_search_id;
 if (repeated->>'created')::boolean is not false
 or repeated->'payment'->>'id' is distinct from reservation->'payment'->>'id'
 or (repeated->'payment'->>'amount')::numeric<>1.23 or payment_count<>1 then
  raise exception 'Retry changed or duplicated payment';
 end if;
 insert into guincho_payment_regression_result values ('PASS: retry reuses the same payment and amount');
end $$;
select * from guincho_payment_regression_result;
rollback;
