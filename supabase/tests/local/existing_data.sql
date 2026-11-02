-- Dados que existiam antes do CRM, para a migration 4/5 ter o que carregar:
-- um cliente do portal e um lead do site. Aplicado depois da base local e
-- antes das migrations do CRM, só no ambiente local.

insert into auth.users (id, email, aud, role, raw_user_meta_data) values
  ('00000000-0000-4000-8000-0000000000c1', 'crm-seed-cliente@example.invalid',
   'authenticated', 'authenticated', '{"full_name":"Cliente Existente"}');

-- handle_new_user já criou o perfil como client.
update public.profiles
set company_name = 'Clínica Existente'
where id = '00000000-0000-4000-8000-0000000000c1';

insert into public.leads (id, name, email, whatsapp, clinic_type, revenue_range, source, created_at) values
  ('00000000-0000-4000-8000-0000000000d1', 'Lead Antigo', 'lead-antigo@example.invalid',
   '61 98888-0000', 'Estética', 'Até 20 mil', 'lp_clinicas_hero_geral',
   timestamptz '2026-10-01 12:00:00+00');
