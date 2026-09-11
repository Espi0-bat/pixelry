-- Campos de qualificação capturados no modal de diagnóstico.
-- Nullable: leads antigos não têm esses dados e os campos são opcionais no formulário.
alter table leads add column clinic_type text;
alter table leads add column revenue_range text;
alter table leads add column investment_range text;
